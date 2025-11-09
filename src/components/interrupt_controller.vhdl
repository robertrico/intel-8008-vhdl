--------------------------------------------------------------------------------
-- Generic Interrupt Controller for Intel 8008
--------------------------------------------------------------------------------
-- Multi-source priority-based interrupt controller with masking and vectoring
--
-- Features:
--   - Up to 8 interrupt sources with priority encoding (source 0 = highest)
--   - Software-controlled masking via I/O port (per-source enable/disable)
--   - Configurable RST vectors (RST 0-7) for each source
--   - Status register for software interrupt polling/debugging
--   - Edge-triggered interrupt detection with latching
--   - Optional startup interrupt (backward compatible with reset_interrupt_controller)
--   - Drop-in replacement for reset_interrupt_controller
--
-- Architecture:
--   - Priority encoder scans from source 0 (highest) to source 7 (lowest)
--   - First active & unmasked interrupt wins and is latched
--   - Generates appropriate RST vector opcode for winning source
--   - Drives interrupt data during T1I/T2 acknowledge cycle
--   - Clears after CPU acknowledges (T3 state detection)
--
-- I/O Port Integration (requires io_controller update):
--   Output Port 16 (OUT 16): Write interrupt mask register
--     Bit N = 1 enables source N, 0 disables source N
--     Default: all enabled (0xFF)
--   Input Port 1 (INP 1): Read interrupt status register
--     Bit N = 1 if source N has pending interrupt
--   Input Port 2 (INP 2): Read active interrupt vector
--     Returns which source is currently being serviced (0-7)
--
-- Generic Parameters:
--   NUM_SOURCES: Number of interrupt sources (1-8, default 8)
--   DEFAULT_VECTORS: RST vector per source (array of 0-7, default [0,1,2,3,4,5,6,7])
--   STARTUP_INT_SRC: Which source is startup interrupt (-1 = none, default 0)
--   STARTUP_ENABLE: Enable startup interrupt on reset (default true)
--
-- RST Vector Encoding:
--   RST n opcode = (n * 8) + 5
--   RST 0 = 0x05 -> jumps to address 0x000
--   RST 1 = 0x0D -> jumps to address 0x008
--   RST 2 = 0x15 -> jumps to address 0x010
--   ...
--   RST 7 = 0x3D -> jumps to address 0x038
--
-- Copyright (c) 2025 Robert Rico
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Package for interrupt controller types
package interrupt_controller_pkg is
    type int_vector_array is array (natural range <>) of integer range 0 to 7;
end package interrupt_controller_pkg;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.interrupt_controller_pkg.all;

entity interrupt_controller is
    generic (
        -- Number of interrupt sources (1-8)
        NUM_SOURCES      : integer range 1 to 8 := 8;

        -- RST vector per source (0-7 maps to RST 0-7)
        -- Default: source 0 -> RST 0, source 1 -> RST 1, etc.
        DEFAULT_VECTORS  : int_vector_array(0 to 7) := (0,1,2,3,4,5,6,7);

        -- Startup interrupt configuration
        STARTUP_INT_SRC  : integer range -1 to 7 := 0;  -- -1 = disabled
        STARTUP_ENABLE   : boolean := true
    );
    port (
        -- CPU clock (phi1) for state tracking
        phi1            : in  std_logic;
        reset_n         : in  std_logic;

        -- CPU interface (state signals)
        S2              : in  std_logic;
        S1              : in  std_logic;
        S0              : in  std_logic;
        SYNC            : in  std_logic;

        -- Interrupt sources (external, active high, edge-triggered)
        int_requests    : in  std_logic_vector(NUM_SOURCES-1 downto 0);

        -- Interrupt mask register (from I/O port write)
        -- Bit N = 1 enables source N, 0 disables source N
        int_mask        : in  std_logic_vector(7 downto 0);

        -- Status outputs (to I/O port reads)
        int_status      : out std_logic_vector(7 downto 0);  -- Pending interrupts
        int_active_src  : out std_logic_vector(7 downto 0);  -- Currently active source

        -- Bus arbiter interface
        int_data_out    : out std_logic_vector(7 downto 0);  -- RST opcode
        int_data_enable : out std_logic;                      -- High during T1I/T2

        -- Interrupt output to CPU
        INT             : out std_logic                       -- High when interrupt pending
    );
end entity interrupt_controller;

architecture rtl of interrupt_controller is
    -- State detection signals (combinatorial from CPU state)
    signal is_t1i_comb : std_logic;
    signal is_t2_comb  : std_logic;
    signal is_t3_comb  : std_logic;

    -- Registered state detection (filtered for glitches)
    signal is_t1i : std_logic;
    signal is_t2  : std_logic;
    signal is_t3  : std_logic;

    -- Interrupt request edge detection and latching
    signal int_requests_prev : std_logic_vector(NUM_SOURCES-1 downto 0);
    signal int_pending       : std_logic_vector(NUM_SOURCES-1 downto 0);

    -- Priority encoder outputs
    signal winning_source    : integer range 0 to 7;  -- Which source won arbitration
    signal any_interrupt     : std_logic;             -- At least one unmasked interrupt pending

    -- Interrupt acknowledge sequence tracking
    signal in_int_ack        : std_logic;
    signal int_asserted      : std_logic;
    signal servicing_source  : integer range 0 to 7;  -- Latched winning source

    -- Startup interrupt generation
    signal startup_done      : std_logic;
    signal startup_pending   : std_logic;

    -- RST vector opcode for current interrupt
    signal rst_opcode        : std_logic_vector(7 downto 0);

begin
    -- Detect CPU states combinatorially
    is_t1i_comb <= '1' when (S2 = '1' and S1 = '1' and S0 = '0') else '0';
    is_t2_comb  <= '1' when (S2 = '1' and S1 = '0' and S0 = '0') else '0';
    is_t3_comb  <= '1' when (S2 = '0' and S1 = '0' and S0 = '1') else '0';

    --------------------------------------------------------------------------------
    -- Priority Encoder Process
    --------------------------------------------------------------------------------
    -- Scans interrupt requests from highest priority (0) to lowest (7)
    -- Returns first active & unmasked interrupt source
    priority_encoder: process(int_pending, int_mask)
    begin
        -- Default: no interrupt
        winning_source <= 0;
        any_interrupt <= '0';

        -- Scan from highest priority (0) to lowest (NUM_SOURCES-1)
        for i in 0 to NUM_SOURCES-1 loop
            if int_pending(i) = '1' and int_mask(i) = '1' then
                winning_source <= i;
                any_interrupt <= '1';
                exit;  -- First match wins (highest priority)
            end if;
        end loop;
    end process priority_encoder;

    --------------------------------------------------------------------------------
    -- RST Vector Opcode Generation
    --------------------------------------------------------------------------------
    -- Calculate RST opcode for servicing source: RST n = (n * 8) + 5
    rst_opcode <= std_logic_vector(to_unsigned((DEFAULT_VECTORS(servicing_source) * 8) + 5, 8));

    --------------------------------------------------------------------------------
    -- Status Register Outputs
    --------------------------------------------------------------------------------
    -- Expose pending interrupts for software polling (pad to 8 bits)
    gen_status: for i in 0 to 7 generate
        gen_valid: if i < NUM_SOURCES generate
            int_status(i) <= int_pending(i);
        end generate gen_valid;
        gen_invalid: if i >= NUM_SOURCES generate
            int_status(i) <= '0';
        end generate gen_invalid;
    end generate gen_status;

    -- Active source register (one-hot encoding for I/O port read)
    int_active_src <= std_logic_vector(to_unsigned(servicing_source, 8));

    --------------------------------------------------------------------------------
    -- Interrupt Controller Main State Machine
    --------------------------------------------------------------------------------
    int_controller_proc: process(phi1, reset_n)
    begin
        if reset_n = '0' then
            -- Reset state
            is_t1i <= '0';
            is_t2 <= '0';
            is_t3 <= '0';
            in_int_ack <= '0';
            servicing_source <= 0;
            int_requests_prev <= (others => '0');
            int_pending <= (others => '0');
            startup_done <= '0';

            -- Assert INT immediately on reset for startup interrupt (like reset_interrupt_controller)
            if STARTUP_ENABLE and STARTUP_INT_SRC >= 0 and STARTUP_INT_SRC < NUM_SOURCES then
                int_asserted <= '1';
                int_pending(STARTUP_INT_SRC) <= '1';
            else
                int_asserted <= '0';
            end if;

        elsif rising_edge(phi1) then
            -- Register state detection signals to filter glitches
            is_t1i <= is_t1i_comb;
            is_t2 <= is_t2_comb;
            is_t3 <= is_t3_comb;

            --------------------------------------------------------------------------------
            -- Edge Detection and Interrupt Latching
            --------------------------------------------------------------------------------
            -- Detect rising edges on interrupt request lines
            int_requests_prev <= int_requests;

            for i in 0 to NUM_SOURCES-1 loop
                -- Latch interrupt on rising edge
                if int_requests(i) = '1' and int_requests_prev(i) = '0' then
                    int_pending(i) <= '1';
                end if;
            end loop;

            --------------------------------------------------------------------------------
            -- Interrupt Acknowledge Sequence
            --------------------------------------------------------------------------------
            if is_t1i = '1' and int_asserted = '1' then
                -- Entering interrupt acknowledge (T1I)
                -- Latch winning source for entire acknowledge sequence
                in_int_ack <= '1';
                servicing_source <= winning_source;

            elsif is_t3 = '1' and in_int_ack = '1' then
                -- Completed interrupt acknowledge sequence (T3)
                -- Clear the serviced interrupt and reset state
                in_int_ack <= '0';
                int_asserted <= '0';
                int_pending(servicing_source) <= '0';  -- Clear serviced interrupt
            end if;

            --------------------------------------------------------------------------------
            -- Interrupt Assertion Logic
            --------------------------------------------------------------------------------
            -- Assert INT when there's an unmasked pending interrupt and not currently servicing
            if any_interrupt = '1' and int_asserted = '0' and in_int_ack = '0' then
                int_asserted <= '1';
                servicing_source <= winning_source;  -- Pre-latch winning source
            end if;

        end if;
    end process int_controller_proc;

    --------------------------------------------------------------------------------
    -- Output Assignments
    --------------------------------------------------------------------------------
    -- Drive INT signal
    INT <= int_asserted;

    -- Output RST opcode (calculated from servicing source)
    int_data_out <= rst_opcode;

    -- Drive bus during T1I or during T2 that follows T1I
    int_data_enable <= is_t1i or (is_t2 and in_int_ack);

end architecture rtl;

--------------------------------------------------------------------------------
-- Generic Reset/Interrupt Controller for Intel 8008
--------------------------------------------------------------------------------
-- Reusable startup interrupt controller with configurable RST vector
--
-- Operation:
--   1. Asserts INT after reset to wake CPU from STOPPED state
--   2. When CPU acknowledges (T1I state), injects RST opcode on data bus
--   3. After acknowledge sequence completes (T3), clears INT
--   4. CPU begins execution at RST vector address
--
-- Generic Parameters:
--   RST_VECTOR: Which RST instruction to use (0-7)
--     RST 0 = 0x05 -> address 0x000
--     RST 1 = 0x0D -> address 0x008
--     RST 2 = 0x15 -> address 0x010
--     ...
--     RST 7 = 0x3D -> address 0x038
--
--   STARTUP_INT_ENABLE: Enable startup interrupt (default true)
--
-- Future expansion: Can add timer interrupts, external interrupts, etc.
--
-- Copyright (c) 2025 Robert Rico
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity reset_interrupt_controller is
    generic (
        RST_VECTOR           : integer range 0 to 7 := 0;  -- Default RST 0
        STARTUP_INT_ENABLE   : boolean := true             -- Enable startup interrupt
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

        -- Bus arbiter interface
        int_data_out    : out std_logic_vector(7 downto 0);  -- RST opcode
        int_data_enable : out std_logic;                      -- High during T1I/T2

        -- Interrupt output to CPU
        INT             : out std_logic                       -- High after reset, clears after ack
    );
end entity reset_interrupt_controller;

architecture rtl of reset_interrupt_controller is
    -- RST opcode calculation: RST n = (n * 8) | 0x05
    -- RST 0 = 0x05, RST 1 = 0x0D, RST 2 = 0x15, ..., RST 7 = 0x3D
    constant RST_OPCODE : std_logic_vector(7 downto 0) :=
        std_logic_vector(to_unsigned((RST_VECTOR * 8) + 5, 8));

    -- State detection signals (combinatorial from CPU state)
    signal is_t1i_comb : std_logic;
    signal is_t2_comb  : std_logic;
    signal is_t3_comb  : std_logic;

    -- Registered state detection (filtered for glitches)
    signal is_t1i : std_logic;
    signal is_t2  : std_logic;
    signal is_t3  : std_logic;

    -- Latch to track interrupt acknowledge sequence
    signal in_int_ack : std_logic;

    -- INT assertion control - set on reset, cleared after interrupt acknowledge
    signal int_asserted : std_logic;

begin
    -- Detect states combinatorially
    is_t1i_comb <= '1' when (S2 = '1' and S1 = '1' and S0 = '0') else '0';
    is_t2_comb  <= '1' when (S2 = '1' and S1 = '0' and S0 = '0') else '0';
    is_t3_comb  <= '1' when (S2 = '0' and S1 = '0' and S0 = '1') else '0';

    -- INT driven by int_asserted signal (conditional on startup enable)
    INT <= int_asserted when STARTUP_INT_ENABLE else '0';

    -- Output RST opcode (calculated from generic parameter)
    int_data_out <= RST_OPCODE;

    -- Track interrupt acknowledge sequence and INT state
    -- Uses phi1 clock (same as CPU) - registers state detection to filter glitches
    process(phi1, reset_n)
    begin
        if reset_n = '0' then
            is_t1i <= '0';
            is_t2 <= '0';
            is_t3 <= '0';
            in_int_ack <= '0';

            -- Assert INT on reset for startup interrupt (if enabled)
            if STARTUP_INT_ENABLE then
                int_asserted <= '1';
            else
                int_asserted <= '0';
            end if;

        elsif rising_edge(phi1) then
            -- Register state detection signals to filter glitches
            is_t1i <= is_t1i_comb;
            is_t2 <= is_t2_comb;
            is_t3 <= is_t3_comb;

            if is_t1i = '1' then
                -- Entering interrupt acknowledge
                in_int_ack <= '1';
            elsif is_t3 = '1' and in_int_ack = '1' then
                -- Completed interrupt acknowledge sequence
                in_int_ack <= '0';
                int_asserted <= '0';  -- Clear INT after startup interrupt completes
            end if;
        end if;
    end process;

    -- Drive bus during T1I or during T2 that follows T1I
    int_data_enable <= is_t1i or (is_t2 and in_int_ack);

end architecture rtl;

--------------------------------------------------------------------------------
-- b8008_top.vhdl
--------------------------------------------------------------------------------
-- Top-level system integrating b8008 CPU with ROM and RAM
--
-- Memory Map:
--   0x0000 - 0x0FFF (4KB): ROM (program code)
--   0x1000 - 0x13FF (1KB): RAM (data storage)
--   0x1400 - 0x3FFF:       Unmapped (returns 0x00)
--
-- This module connects:
--   - b8008 CPU core
--   - rom_4kx8 (4KB ROM for program storage)
--   - ram_1kx8 (1KB RAM for data storage)
--   - Address decode logic
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.b8008_types.all;

entity b8008_top is
    generic (
        -- ROM initialization file
        ROM_FILE : string := "test_programs/alu_test_as.mem"
    );
    port (
        -- External clock and reset
        clk_in      : in std_logic;
        reset       : in std_logic;
        interrupt   : in std_logic;  -- Bootstrap interrupt (tie high after reset)

        -- Debug outputs
        phi1_out    : out std_logic;
        phi2_out    : out std_logic;
        sync_out    : out std_logic;
        s0_out      : out std_logic;
        s1_out      : out std_logic;
        s2_out      : out std_logic;

        -- Address and data for debugging
        address_out : out std_logic_vector(13 downto 0);
        data_out    : out std_logic_vector(7 downto 0);

        -- RAM debug output (location 0 for verification)
        ram_byte_0  : out std_logic_vector(7 downto 0);

        -- Debug outputs: CPU state and key registers
        debug_reg_a         : out std_logic_vector(7 downto 0);  -- A register
        debug_reg_b         : out std_logic_vector(7 downto 0);  -- B register
        debug_reg_h         : out std_logic_vector(7 downto 0);  -- H register
        debug_reg_l         : out std_logic_vector(7 downto 0);  -- L register
        debug_cycle         : out integer range 1 to 3;
        debug_pc            : out std_logic_vector(13 downto 0);
        debug_ir            : out std_logic_vector(7 downto 0);
        debug_needs_address : out std_logic;
        debug_int_pending   : out std_logic
    );
end entity b8008_top;

architecture structural of b8008_top is

    -- Component: b8008 CPU
    component b8008 is
        port (
            clk_in         : in std_logic;
            reset          : in std_logic;
            phi1_out       : out std_logic;
            phi2_out       : out std_logic;
            data_bus       : inout std_logic_vector(7 downto 0);
            sync_out       : out std_logic;
            s0_out         : out std_logic;
            s1_out         : out std_logic;
            s2_out         : out std_logic;
            ready_in       : in std_logic;
            interrupt      : in std_logic;
            -- Debug
            debug_reg_a         : out std_logic_vector(7 downto 0);
            debug_reg_b         : out std_logic_vector(7 downto 0);
            debug_reg_c         : out std_logic_vector(7 downto 0);
            debug_reg_d         : out std_logic_vector(7 downto 0);
            debug_reg_e         : out std_logic_vector(7 downto 0);
            debug_reg_h         : out std_logic_vector(7 downto 0);
            debug_reg_l         : out std_logic_vector(7 downto 0);
            debug_cycle         : out integer range 1 to 3;
            debug_pc            : out std_logic_vector(13 downto 0);
            debug_ir            : out std_logic_vector(7 downto 0);
            debug_needs_address : out std_logic;
            debug_int_pending   : out std_logic;
            cycle_type          : out std_logic_vector(1 downto 0)
        );
    end component;

    -- Component: 4KB ROM
    component rom_4kx8 is
        generic (
            ROM_FILE : string := "test_programs/alu_test_as.mem"
        );
        port (
            ADDR     : in  std_logic_vector(11 downto 0);
            DATA_OUT : out std_logic_vector(7 downto 0);
            CS_N     : in  std_logic
        );
    end component;

    -- Component: 1KB RAM
    component ram_1kx8 is
        port (
            CLK          : in  std_logic;
            ADDR         : in  std_logic_vector(9 downto 0);
            DATA_IN      : in  std_logic_vector(7 downto 0);
            DATA_OUT     : out std_logic_vector(7 downto 0);
            RW_N         : in  std_logic;
            CS_N         : in  std_logic;
            DEBUG_BYTE_0 : out std_logic_vector(7 downto 0)
        );
    end component;

    -- Internal signals
    signal address_bus : std_logic_vector(13 downto 0);
    signal data_bus    : std_logic_vector(7 downto 0);
    signal phi1        : std_logic;
    signal phi2        : std_logic;

    -- Memory signals
    signal rom_cs_n    : std_logic;
    signal rom_data    : std_logic_vector(7 downto 0);
    signal ram_cs_n    : std_logic;
    signal ram_data_in : std_logic_vector(7 downto 0);
    signal ram_data_out: std_logic_vector(7 downto 0);
    signal ram_rw_n    : std_logic;

    -- Address decode
    signal rom_selected : std_logic;
    signal ram_selected : std_logic;
    signal is_write     : std_logic;
    signal cycle_type   : std_logic_vector(1 downto 0);  -- 00=PCI, 01=PCR, 10=PCC, 11=PCW

    -- Bootstrap flag: jam RST 0 only during first T1I after reset
    signal bootstrap_done : std_logic := '0';

    -- External address latches (like real 8008 external hardware)
    signal latched_address : std_logic_vector(13 downto 0) := (others => '0');

    -- T-state decode from S[2:0]
    signal is_t1  : std_logic;
    signal is_t2  : std_logic;
    signal is_t3  : std_logic;
    signal is_t4  : std_logic;
    signal is_t5  : std_logic;

begin

    -- ========================================================================
    -- EXTERNAL ADDRESS LATCHING (Real 8008 Hardware Behavior)
    -- ========================================================================
    -- In real 8008, address is output on 8 bidirectional pins during T1/T2
    -- External latches capture the address so data can use same pins during T3
    -- Here we simulate this with internal latches

    -- Decode T-states from status signals
    -- T1: S2=0, S1=1, S0=0 (binary 010)
    -- T2: S2=1, S1=0, S0=0 (binary 100)
    -- T3: S2=0, S1=0, S0=1 (binary 001)
    -- T4: S2=1, S1=1, S0=1 (binary 111)
    -- T5: S2=1, S1=0, S0=1 (binary 101)
    is_t1 <= '1' when (s2_out = '0' and s1_out = '1' and s0_out = '0') else '0';
    is_t2 <= '1' when (s2_out = '1' and s1_out = '0' and s0_out = '0') else '0';
    is_t3 <= '1' when (s2_out = '0' and s1_out = '0' and s0_out = '1') else '0';
    is_t4 <= '1' when (s2_out = '1' and s1_out = '1' and s0_out = '1') else '0';
    is_t5 <= '1' when (s2_out = '1' and s1_out = '0' and s0_out = '1') else '0';

    -- Latch address during T1 and T2 (when CPU outputs address on data bus)
    -- Real 8008 behavior: address is time-multiplexed on 8-bit data bus
    -- T1: Lower 8 bits on data bus (latch only during SYNC high - first half of T1)
    -- T2: Upper 6 bits on D[5:0], cycle type on D[7:6] (latch only during SYNC high)
    -- CRITICAL: Only latch during SYNC=1 (first half) to avoid re-latching after PC increments
    -- Hold latched address stable during T3 (when data bus used for data transfer)
    process(phi1, reset)
    begin
        if reset = '1' then
            latched_address <= (others => '0');
        elsif rising_edge(phi1) then
            if is_t1 = '1' and sync_out = '1' then
                -- T1 first half (SYNC high): Latch lower 8 bits from data bus
                latched_address(7 downto 0) <= data_bus;
                report "ADDR_LATCH: T1 lower byte = 0x" & to_hstring(unsigned(data_bus));
            elsif is_t2 = '1' and sync_out = '1' then
                -- T2 first half (SYNC high): Latch upper 6 bits from data bus D[5:0]
                latched_address(13 downto 8) <= data_bus(5 downto 0);
                report "ADDR_LATCH: T2 upper byte = 0x" & to_hstring(unsigned(data_bus(5 downto 0))) &
                       " Full address = 0x" & to_hstring(unsigned(data_bus(5 downto 0) & latched_address(7 downto 0)));
            end if;
            -- During T3+: Hold latched value stable
        end if;
    end process;

    -- ========================================================================
    -- BOOTSTRAP CONTROL
    -- ========================================================================

    -- Set bootstrap_done flag after first T1I completes
    -- We detect when we LEAVE T1I state (transition to T2)
    process(phi1, reset)
    begin
        if reset = '1' then
            bootstrap_done <= '0';
        elsif rising_edge(phi1) then
            -- When we're in T2 and bootstrap isn't done yet, T1I just completed
            if bootstrap_done = '0' and s2_out = '1' and s1_out = '0' and s0_out = '0' then
                bootstrap_done <= '1';
            end if;
        end if;
    end process;

    -- ========================================================================
    -- CPU INSTANCE
    -- ========================================================================

    u_cpu : b8008
        port map (
            clk_in      => clk_in,
            reset       => reset,
            phi1_out    => phi1,
            phi2_out    => phi2,
            data_bus    => data_bus,
            sync_out    => sync_out,
            s0_out      => s0_out,
            s1_out      => s1_out,
            s2_out      => s2_out,
            ready_in            => '1',      -- Always ready (no wait states)
            interrupt           => interrupt,
            debug_reg_a         => debug_reg_a,
            debug_reg_b         => debug_reg_b,
            debug_reg_c         => open,  -- Not used in top-level yet
            debug_reg_d         => open,  -- Not used in top-level yet
            debug_reg_e         => open,  -- Not used in top-level yet
            debug_reg_h         => debug_reg_h,
            debug_reg_l         => debug_reg_l,
            debug_cycle         => debug_cycle,
            debug_pc            => debug_pc,
            debug_ir            => debug_ir,
            debug_needs_address => debug_needs_address,
            debug_int_pending   => debug_int_pending,
            cycle_type          => cycle_type
        );

    -- ========================================================================
    -- MEMORY INSTANCES
    -- ========================================================================

    -- ROM: 4KB at 0x0000-0x0FFF
    -- Uses LATCHED address (stable during T3 data transfer)
    u_rom : rom_4kx8
        generic map (
            ROM_FILE => ROM_FILE
        )
        port map (
            ADDR     => latched_address(11 downto 0),
            DATA_OUT => rom_data,
            CS_N     => rom_cs_n
        );

    -- RAM: 1KB at 0x1000-0x13FF
    -- Uses LATCHED address (stable during T3 data transfer)
    u_ram : ram_1kx8
        port map (
            CLK          => phi1,
            ADDR         => latched_address(9 downto 0),
            DATA_IN      => ram_data_in,
            DATA_OUT     => ram_data_out,
            RW_N         => ram_rw_n,
            CS_N         => ram_cs_n,
            DEBUG_BYTE_0 => ram_byte_0
        );

    -- ========================================================================
    -- ADDRESS DECODE LOGIC
    -- ========================================================================

    -- ROM selected: address 0x0000-0x0FFF (top 2 bits = 00)
    -- Use LATCHED address for decode
    rom_selected <= '1' when latched_address(13 downto 12) = "00" else '0';

    -- RAM selected: address 0x1000-0x13FF (bits 13:12 = 01, bit 11:10 = 00)
    -- Use LATCHED address for decode
    ram_selected <= '1' when latched_address(13 downto 10) = "0100" else '0';

    -- Chip selects (active low)
    rom_cs_n <= not rom_selected;
    ram_cs_n <= not ram_selected;

    -- ========================================================================
    -- DATA BUS MULTIPLEXING
    -- ========================================================================

    -- Decode cycle type for read/write control
    -- cycle_type: 00=PCI, 01=PCR, 10=PCC, 11=PCW
    -- PCW (cycle_type = "11") indicates memory write
    is_write <= '1' when cycle_type = "11" else '0';

    -- RAM RW_N: active low write enable
    -- Write (RW_N=0) during T3/T4/T5 of PCW cycles when RAM is selected
    ram_rw_n <= '0' when (is_write = '1' and ram_selected = '1' and
                         (is_t3 = '1' or is_t4 = '1' or is_t5 = '1')) else '1';

    -- RAM always receives data from bus (but only writes when RW_N=0)
    ram_data_in <= data_bus;

    -- Connect memory data to CPU data bus
    -- Real 8008 behavior:
    --   T1: CPU outputs address lower byte on data bus (external hardware latches it)
    --   T2: CPU outputs address upper byte on data bus (external hardware latches it)
    --   T3-T5: External hardware (ROM/RAM) drives data bus for CPU to read
    -- During T1I (interrupt acknowledge), jam RST 0 instruction (0x05) for bootstrap
    -- Only jam during FIRST T1I after reset (bootstrap), then let ROM take over
    data_bus <= x"05" when (s2_out = '1' and s1_out = '1' and s0_out = '0' and bootstrap_done = '0') else  -- T1I bootstrap: jam RST 0
                rom_data when (rom_selected = '1' and (is_t3 = '1' or is_t4 = '1' or is_t5 = '1')) else  -- ROM drives bus during T3/T4/T5
                ram_data_out when (ram_selected = '1' and (is_t3 = '1' or is_t4 = '1' or is_t5 = '1')) else  -- RAM drives bus during T3/T4/T5
                (others => 'Z');  -- Tri-state during T1/T2 (CPU drives address)

    -- ========================================================================
    -- DEBUG OUTPUTS
    -- ========================================================================

    phi1_out    <= phi1;
    phi2_out    <= phi2;
    address_out <= latched_address;  -- Latched from data bus during T1/T2
    data_out    <= data_bus;  -- Debug output: pass through as-is (may contain 'Z', 'X', etc.)

end architecture structural;

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
        ROM_FILE : string := "test_programs/search_as.mem"
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

        -- Debug outputs for JMP debugging
        debug_reg_a         : out std_logic_vector(7 downto 0);
        debug_reg_b         : out std_logic_vector(7 downto 0);
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
            address_bus    : out std_logic_vector(13 downto 0);
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
            debug_cycle         : out integer range 1 to 3;
            debug_pc            : out std_logic_vector(13 downto 0);
            debug_ir            : out std_logic_vector(7 downto 0);
            debug_needs_address : out std_logic;
            debug_int_pending   : out std_logic
        );
    end component;

    -- Component: 4KB ROM
    component rom_4kx8 is
        generic (
            ROM_FILE : string := "test_programs/search_as.mem"
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

    -- Bootstrap flag: jam RST 0 only during first T1I after reset
    signal bootstrap_done : std_logic := '0';

begin

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
            address_bus => address_bus,
            data_bus    => data_bus,
            sync_out    => sync_out,
            s0_out      => s0_out,
            s1_out      => s1_out,
            s2_out      => s2_out,
            ready_in            => '1',      -- Always ready (no wait states)
            interrupt           => interrupt,
            debug_reg_a         => debug_reg_a,
            debug_reg_b         => debug_reg_b,
            debug_cycle         => debug_cycle,
            debug_pc            => debug_pc,
            debug_ir            => debug_ir,
            debug_needs_address => debug_needs_address,
            debug_int_pending   => debug_int_pending
        );

    -- ========================================================================
    -- MEMORY INSTANCES
    -- ========================================================================

    -- ROM: 4KB at 0x0000-0x0FFF
    u_rom : rom_4kx8
        generic map (
            ROM_FILE => ROM_FILE
        )
        port map (
            ADDR     => address_bus(11 downto 0),
            DATA_OUT => rom_data,
            CS_N     => rom_cs_n
        );

    -- RAM: 1KB at 0x1000-0x13FF
    u_ram : ram_1kx8
        port map (
            CLK          => phi1,
            ADDR         => address_bus(9 downto 0),
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
    rom_selected <= '1' when address_bus(13 downto 12) = "00" else '0';

    -- RAM selected: address 0x1000-0x13FF (bits 13:12 = 01, bit 11:10 = 00)
    ram_selected <= '1' when address_bus(13 downto 10) = "0100" else '0';

    -- Chip selects (active low)
    rom_cs_n <= not rom_selected;
    ram_cs_n <= not ram_selected;

    -- ========================================================================
    -- DATA BUS MULTIPLEXING
    -- ========================================================================

    -- For now, assume all accesses are reads (RAM won't write)
    -- TODO: Properly decode read/write from S0/S1/S2 state signals
    -- PCR (memory read) vs PCW (memory write) encoded in D7:D6 during T2
    is_write <= '0';  -- Simplified: treat all as reads for now
    ram_rw_n <= '1';  -- Read only for now

    -- RAM always receives data from bus (but only writes when RW_N=0)
    ram_data_in <= data_bus;

    -- Connect memory data to CPU data bus
    -- During T1I (interrupt acknowledge), jam RST 0 instruction (0x05) for bootstrap
    -- Only jam during FIRST T1I after reset (bootstrap), then let ROM take over
    -- Otherwise, ROM or RAM drives the bus, CPU io_buffer will tri-state when reading
    data_bus <= x"05" when (s2_out = '1' and s1_out = '1' and s0_out = '0' and bootstrap_done = '0') else  -- T1I bootstrap: jam RST 0
                rom_data when rom_selected = '1' else
                ram_data_out when ram_selected = '1' else
                (others => 'Z');

    -- ========================================================================
    -- DEBUG OUTPUTS
    -- ========================================================================

    phi1_out    <= phi1;
    phi2_out    <= phi2;
    address_out <= address_bus;
    data_out    <= data_bus when data_bus /= "ZZZZZZZZ" else (others => '0');

end architecture structural;

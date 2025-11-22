--------------------------------------------------------------------------------
-- Generic Memory Controller for Intel 8008
--------------------------------------------------------------------------------
-- Reusable memory management component with configurable ROM/RAM
--
-- Features:
--   - Address capture from T1/T2 cycles
--   - Tri-state bus arbitration
--   - ROM/RAM chip select generation
--   - Write control logic
--   - Generic memory sizing and addressing
--
-- Memory Map (default):
--   ROM: 0x0000 - 0x07FF (2KB)
--   RAM: 0x0800 - 0x0BFF (1KB)
--   Unmapped: Returns 0xB2 for debugging
--
-- Generic Parameters:
--   ROM_SIZE_BITS: ROM address width (11 = 2KB, 12 = 4KB, etc.)
--   RAM_SIZE_BITS: RAM address width (10 = 1KB, 11 = 2KB, etc.)
--   ROM_BASE_ADDR: ROM base address (default 0x0000)
--   RAM_BASE_ADDR: RAM base address (default 0x0800)
--
-- Copyright (c) 2025 Robert Rico
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity memory_controller is
    generic (
        ROM_SIZE_BITS : integer := 11;  -- 2^11 = 2KB (default)
        RAM_SIZE_BITS : integer := 10;  -- 2^10 = 1KB (default)
        ROM_BASE_ADDR : std_logic_vector(13 downto 0) := "00000000000000";  -- 0x0000
        RAM_BASE_ADDR : std_logic_vector(13 downto 0) := "00100000000000"   -- 0x0800
    );
    port (
        -- Clock and reset
        phi1      : in  std_logic;
        reset_n   : in  std_logic;

        -- CPU state signals
        S2        : in  std_logic;
        S1        : in  std_logic;
        S0        : in  std_logic;
        SYNC      : in  std_logic;

        -- Data bus input (for address capture and write data)
        data_bus_in : in std_logic_vector(7 downto 0);

        -- ROM interface
        rom_addr     : out std_logic_vector(ROM_SIZE_BITS - 1 downto 0);
        rom_data     : in  std_logic_vector(7 downto 0);
        rom_cs_n     : out std_logic;

        -- RAM interface
        ram_addr     : out std_logic_vector(RAM_SIZE_BITS - 1 downto 0);
        ram_data_in  : out std_logic_vector(7 downto 0);
        ram_data_out : in  std_logic_vector(7 downto 0);
        ram_rw_n     : out std_logic;
        ram_cs_n     : out std_logic;

        -- Memory bus control output (for top-level bus arbiter)
        mem_data_out    : out std_logic_vector(7 downto 0);
        mem_data_enable : out std_logic  -- High when memory should drive bus
    );
end entity memory_controller;

architecture rtl of memory_controller is
    -- Address capture signals (initialized to prevent metavalues)
    signal addr_low_capture    : std_logic_vector(7 downto 0) := (others => '0');
    signal addr_high_capture   : std_logic_vector(5 downto 0) := (others => '0');
    signal cycle_type_capture  : std_logic_vector(1 downto 0) := "00";
    signal mem_addr            : std_logic_vector(13 downto 0);

    -- State detection
    signal is_t1 : std_logic;
    signal is_t2 : std_logic;
    signal is_t3 : std_logic;
    signal is_t4 : std_logic;
    signal is_t5 : std_logic;

    -- State tracking to capture only once per T-state
    signal last_state : std_logic_vector(2 downto 0) := "000";  -- Track previous S2S1S0

    -- Memory region detection
    signal rom_selected : std_logic;
    signal ram_selected : std_logic;

    -- Cycle type detection
    signal is_read_cycle  : std_logic;  -- PCI="00" or PCR="01"
    signal is_write_cycle : std_logic;  -- PCW="10"

    -- Internal RAM control
    signal ram_rw_n_int : std_logic;

begin
    -- State detection (combinatorial)
    is_t1 <= '1' when (S2 = '0' and S1 = '1' and S0 = '0') else '0';  -- 010
    is_t2 <= '1' when (S2 = '1' and S1 = '0' and S0 = '0') else '0';  -- 100
    is_t3 <= '1' when (S2 = '0' and S1 = '0' and S0 = '1') else '0';  -- 001
    is_t4 <= '1' when (S2 = '1' and S1 = '1' and S0 = '1') else '0';  -- 111
    is_t5 <= '1' when (S2 = '1' and S1 = '0' and S0 = '1') else '0';  -- 101

    -- Cycle type detection
    is_read_cycle  <= '1' when (cycle_type_capture = "00" or cycle_type_capture = "01") else '0';
    is_write_cycle <= '1' when cycle_type_capture = "10" else '0';

    -- Build full memory address
    mem_addr <= addr_high_capture & addr_low_capture;

    -- Memory region selection (generic-based address decoding)
    -- ROM: check if address is within [ROM_BASE_ADDR, ROM_BASE_ADDR + 2^ROM_SIZE_BITS)
    rom_selected <= '1' when (unsigned(mem_addr) >= unsigned(ROM_BASE_ADDR)) and
                             (unsigned(mem_addr) < unsigned(ROM_BASE_ADDR) + (2 ** ROM_SIZE_BITS)) else '0';
    -- RAM: check if address is within [RAM_BASE_ADDR, RAM_BASE_ADDR + 2^RAM_SIZE_BITS)
    ram_selected <= '1' when (unsigned(mem_addr) >= unsigned(RAM_BASE_ADDR)) and
                             (unsigned(mem_addr) < unsigned(RAM_BASE_ADDR) + (2 ** RAM_SIZE_BITS)) else '0';

    -- ROM interface (subtract base address to get offset)
    rom_addr <= std_logic_vector(unsigned(mem_addr(ROM_SIZE_BITS - 1 downto 0)) -
                                 unsigned(ROM_BASE_ADDR(ROM_SIZE_BITS - 1 downto 0)));
    rom_cs_n <= not rom_selected;

    -- RAM interface (subtract base address to get offset)
    ram_addr <= std_logic_vector(unsigned(mem_addr(RAM_SIZE_BITS - 1 downto 0)) -
                                 unsigned(RAM_BASE_ADDR(RAM_SIZE_BITS - 1 downto 0)));
    ram_cs_n <= not ram_selected;
    ram_rw_n <= ram_rw_n_int;

    -- Memory data output - combinational (like unit tests)
    -- Data is immediately available from ROM/RAM based on captured address
    mem_data_out <= rom_data when rom_selected = '1' else
                    ram_data_out when ram_selected = '1' else
                    (others => '0');

    -- Memory drives bus during T3 of read cycles
    mem_data_enable <= '1' when (is_t3 = '1' and is_read_cycle = '1') else '0';

    -- Debug process to monitor memory accesses
    process(is_t3, is_read_cycle, mem_addr, rom_data, ram_data_out, rom_selected, ram_selected)
    begin
        if is_t3 = '1' and is_read_cycle = '1' then
            report "MEM: T3 READ addr=0x" & to_hstring(unsigned(mem_addr)) &
                   " rom_sel=" & std_logic'image(rom_selected)(2) &
                   " ram_sel=" & std_logic'image(ram_selected)(2) &
                   " rom_data=0x" & to_hstring(unsigned(rom_data)) &
                   " ram_data=0x" & to_hstring(unsigned(ram_data_out)) &
                   " output=0x" & to_hstring(unsigned(mem_data_out));
        end if;
    end process;

    -- Address capture process
    -- PROPER 8008 BUS PROTOCOL:
    -- External hardware watches SYNC transitions along with S0/S1/S2
    -- Capture on state transitions (when S2S1S0 changes)
    addr_capture: process(SYNC, reset_n)
        variable current_state : std_logic_vector(2 downto 0);
    begin
        if reset_n = '0' then
            addr_low_capture <= (others => '0');
            addr_high_capture <= (others => '0');
            cycle_type_capture <= "00";  -- Default to PCI (instruction fetch)
            last_state <= "000";

        elsif rising_edge(SYNC) then
            -- Build current state from S signals
            current_state := S2 & S1 & S0;

            -- Only capture when state has changed (entering new T-state)
            if current_state /= last_state then
                last_state <= current_state;

                -- T1 state: Capture low address byte
                -- Per datasheet: "PCL is sent out, then PC lower byte is incremented"
                -- We capture PCL while it's stable on the bus during T1
                if is_t1 = '1' then
                    addr_low_capture <= data_bus_in;
                    report "MEM_CTRL: SYNC rising, T1 CAPTURE addr_low=0x" & to_hstring(unsigned(data_bus_in));
                end if;

                -- T2 state: Capture high address and cycle type
                -- Per datasheet: "PCH is sent out, then incremented if carry"
                if is_t2 = '1' then
                    addr_high_capture <= data_bus_in(5 downto 0);
                    cycle_type_capture <= data_bus_in(7 downto 6);
                    report "MEM_CTRL: SYNC rising, T2 CAPTURE addr_high=0x" & to_hstring(unsigned(data_bus_in(5 downto 0))) &
                           " cycle_type=" & to_string(data_bus_in(7 downto 6));
                end if;
            end if;
        end if;
    end process;

    -- RAM write control process
    ram_control: process(phi1, reset_n)
        variable prev_rw_n : std_logic := '1';
    begin
        if reset_n = '0' then
            ram_rw_n_int <= '1';  -- Default to read
            ram_data_in <= (others => '0');
            prev_rw_n := '1';

        elsif rising_edge(phi1) then
            -- T3/T4/T5 states with write cycle (PCW = "10")
            if ((is_t3 = '1' or is_t4 = '1' or is_t5 = '1') and is_write_cycle = '1') then
                ram_rw_n_int <= '0';  -- Write enable
                -- Only capture data when transitioning FROM read TO write
                -- This prevents capturing Z values on subsequent cycles
                if prev_rw_n = '1' then
                    ram_data_in <= data_bus_in;
                end if;
            else
                ram_rw_n_int <= '1';  -- Read mode
            end if;
            prev_rw_n := ram_rw_n_int;
        end if;
    end process;

end architecture rtl;

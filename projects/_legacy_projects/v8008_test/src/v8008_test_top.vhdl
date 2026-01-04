--------------------------------------------------------------------------------
-- v8008_test Top Level - Intel 8008 FPGA Implementation
--------------------------------------------------------------------------------
-- Runs the search.asm test program to search for period character in string
-- Demonstrates complete Intel 8008 system with ROM/RAM
--
-- Memory Map:
--   ROM: 0x0000-0x07FF (2KB) - Program storage
--   RAM: 0x0800-0x0BFF (1KB) - Stack and data
--
-- Expected Behavior:
--   - CPU boots with RST 0 interrupt
--   - Searches string at address 200 (0xC8) for period '.'
--   - When found at position 213 (0xD5), copies to H and halts
--   - LEDs show accumulator value
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity v8008_test_top is
    port (
        -- System clock and reset
        clk         : in  std_logic;                      -- 100 MHz FPGA clock
        rst         : in  std_logic;                      -- Reset button (active high)

        -- Board LEDs (8 LEDs showing accumulator, active low)
        led_E16     : out std_logic;  -- LED0 (bit 0)
        led_D17     : out std_logic;  -- LED1 (bit 1)
        led_D18     : out std_logic;  -- LED2 (bit 2)
        led_E18     : out std_logic;  -- LED3 (bit 3)
        led_D19     : out std_logic;  -- LED4 (bit 4)
        led_E19     : out std_logic;  -- LED5 (bit 5)
        led_A20     : out std_logic;  -- LED6 (bit 6)
        led_B20     : out std_logic;  -- LED7 (bit 7)

        -- CPU debug signals (16 signals to PMOD J39 header)
        cpu_d       : out std_logic_vector(7 downto 0);  -- Data bus [0-7]
        cpu_phi1    : out std_logic;                      -- phi1 clock [8]
        cpu_phi2    : out std_logic;                      -- phi2 clock [9]
        cpu_sync    : out std_logic;                      -- SYNC signal [10]
        cpu_s0      : out std_logic;                      -- State S0 [11]
        cpu_s1      : out std_logic;                      -- State S1 [12]
        cpu_s2      : out std_logic;                      -- State S2 [13]
        cpu_int     : out std_logic;                      -- INT signal [14]
        cpu_ready   : out std_logic                       -- READY signal [15]
    );
end entity v8008_test_top;

architecture rtl of v8008_test_top is

    --------------------------------------------------------------------------------
    -- Component Declarations
    --------------------------------------------------------------------------------
    component v8008 is
        port (
            phi1            : in    std_logic;
            phi2            : in    std_logic;
            data_bus_in     : in    std_logic_vector(7 downto 0);
            data_bus_out    : out   std_logic_vector(7 downto 0);
            data_bus_enable : out   std_logic;
            S0              : out   std_logic;
            S1              : out   std_logic;
            S2              : out   std_logic;
            SYNC            : out   std_logic;
            READY           : in    std_logic;
            INT             : in    std_logic;
            debug_reg_A     : out   std_logic_vector(7 downto 0);
            debug_reg_B     : out   std_logic_vector(7 downto 0);
            debug_reg_C     : out   std_logic_vector(7 downto 0);
            debug_reg_D     : out   std_logic_vector(7 downto 0);
            debug_reg_E     : out   std_logic_vector(7 downto 0);
            debug_reg_H     : out   std_logic_vector(7 downto 0);
            debug_reg_L     : out   std_logic_vector(7 downto 0);
            debug_pc        : out   std_logic_vector(13 downto 0);
            debug_flags     : out   std_logic_vector(3 downto 0);
            debug_instruction : out std_logic_vector(7 downto 0);
            debug_stack_pointer : out std_logic_vector(2 downto 0);
            debug_hl_address : out std_logic_vector(13 downto 0)
        );
    end component;

    component phase_clocks is
        port (
            clk_in  : in  std_logic;
            reset   : in  std_logic;
            phi1    : out std_logic;
            phi2    : out std_logic
        );
    end component;

    component rom_2kx8 is
        generic (
            ROM_FILE : string := "test_programs/simple_add.mem"
        );
        port (
            ADDR     : in  std_logic_vector(10 downto 0);
            DATA_OUT : out std_logic_vector(7 downto 0);
            CS_N     : in  std_logic
        );
    end component;

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

    component reset_interrupt_controller is
        generic (
            RST_VECTOR           : integer range 0 to 7 := 0;
            STARTUP_INT_ENABLE   : boolean := true
        );
        port (
            phi1            : in  std_logic;
            reset_n         : in  std_logic;
            S2              : in  std_logic;
            S1              : in  std_logic;
            S0              : in  std_logic;
            SYNC            : in  std_logic;
            int_data_out    : out std_logic_vector(7 downto 0);
            int_data_enable : out std_logic;
            INT             : out std_logic
        );
    end component;

    component memory_controller is
        generic (
            ROM_SIZE_BITS : integer := 11;
            RAM_SIZE_BITS : integer := 10;
            ROM_BASE_ADDR : std_logic_vector(13 downto 0) := "00000000000000";
            RAM_BASE_ADDR : std_logic_vector(13 downto 0) := "00100000000000"
        );
        port (
            phi1            : in  std_logic;
            reset_n         : in  std_logic;
            S2              : in  std_logic;
            S1              : in  std_logic;
            S0              : in  std_logic;
            SYNC            : in  std_logic;
            data_bus_in     : in  std_logic_vector(7 downto 0);
            rom_addr        : out std_logic_vector(ROM_SIZE_BITS - 1 downto 0);
            rom_data        : in  std_logic_vector(7 downto 0);
            rom_cs_n        : out std_logic;
            ram_addr        : out std_logic_vector(RAM_SIZE_BITS - 1 downto 0);
            ram_data_in     : out std_logic_vector(7 downto 0);
            ram_data_out    : in  std_logic_vector(7 downto 0);
            ram_rw_n        : out std_logic;
            ram_cs_n        : out std_logic;
            mem_data_out    : out std_logic_vector(7 downto 0);
            mem_data_enable : out std_logic
        );
    end component;

    --------------------------------------------------------------------------------
    -- Internal Signals
    --------------------------------------------------------------------------------
    -- Synthesis attributes for generated clocks
    attribute syn_keep : boolean;
    attribute syn_preserve : boolean;

    -- Clock signals
    signal phi1         : std_logic;
    signal phi2         : std_logic;

    -- Mark phi1 and phi2 as clocks to preserve routing
    attribute syn_keep of phi1 : signal is true;
    attribute syn_keep of phi2 : signal is true;
    attribute syn_preserve of phi1 : signal is true;
    attribute syn_preserve of phi2 : signal is true;

    -- CPU interface signals
    signal data_bus         : std_logic_vector(7 downto 0);
    signal cpu_data_out     : std_logic_vector(7 downto 0);
    signal cpu_data_enable  : std_logic;
    signal S0, S1, S2       : std_logic;
    signal SYNC             : std_logic;
    signal READY            : std_logic;
    signal INT              : std_logic;

    -- Interrupt controller bus arbiter interface
    signal int_data_out     : std_logic_vector(7 downto 0);
    signal int_data_enable  : std_logic;

    -- Memory controller interface
    signal mem_data_out     : std_logic_vector(7 downto 0);
    signal mem_data_enable  : std_logic;

    -- ROM signals
    signal rom_addr : std_logic_vector(10 downto 0);
    signal rom_data : std_logic_vector(7 downto 0);
    signal rom_cs_n : std_logic;

    -- RAM signals
    signal ram_addr     : std_logic_vector(9 downto 0);
    signal ram_data_in  : std_logic_vector(7 downto 0);
    signal ram_data_out : std_logic_vector(7 downto 0);
    signal ram_rw_n     : std_logic;
    signal ram_cs_n     : std_logic;

    -- Debug signals
    signal debug_reg_A, debug_reg_B, debug_reg_C, debug_reg_D : std_logic_vector(7 downto 0);
    signal debug_reg_E, debug_reg_H, debug_reg_L : std_logic_vector(7 downto 0);
    signal debug_pc_int    : std_logic_vector(13 downto 0);
    signal debug_flags_int : std_logic_vector(3 downto 0);
    signal debug_byte_0    : std_logic_vector(7 downto 0);

    -- Synchronized reset to avoid metastability
    signal rst_sync : std_logic_vector(1 downto 0) := (others => '1');
    signal reset_n  : std_logic;

begin

    --------------------------------------------------------------------------------
    -- Reset Synchronization
    --------------------------------------------------------------------------------
    -- Synchronize external reset to avoid metastability
    process(clk)
    begin
        if rising_edge(clk) then
            rst_sync <= rst_sync(0) & rst;
        end if;
    end process;

    reset_n <= not rst_sync(1);

    --------------------------------------------------------------------------------
    -- Control Signals
    --------------------------------------------------------------------------------
    READY <= '1';  -- Always ready (no wait states)

    -- Phase Clock Generator (non-overlapping phi1 and phi2 for Intel 8008)
    u_phase_clocks : phase_clocks
        port map (
            clk_in  => clk,
            reset   => rst_sync(1),
            phi1    => phi1,
            phi2    => phi2
        );

    --------------------------------------------------------------------------------
    -- Intel 8008 CPU Core (v8008)
    --------------------------------------------------------------------------------
    u_cpu : v8008
        port map (
            phi1            => phi1,
            phi2            => phi2,
            data_bus_in     => data_bus,
            data_bus_out    => cpu_data_out,
            data_bus_enable => cpu_data_enable,
            S0              => S0,
            S1              => S1,
            S2              => S2,
            SYNC            => SYNC,
            READY           => READY,
            INT             => INT,
            debug_reg_A     => debug_reg_A,
            debug_reg_B     => debug_reg_B,
            debug_reg_C     => debug_reg_C,
            debug_reg_D     => debug_reg_D,
            debug_reg_E     => debug_reg_E,
            debug_reg_H     => debug_reg_H,
            debug_reg_L     => debug_reg_L,
            debug_pc        => debug_pc_int,
            debug_flags     => debug_flags_int,
            debug_instruction => open,
            debug_stack_pointer => open,
            debug_hl_address => open
        );

    --------------------------------------------------------------------------------
    -- Tri-State Bus Arbiter
    --------------------------------------------------------------------------------
    -- Centralized bus arbiter - single point of control for data_bus
    -- Priority-based arbitration:
    -- 1. Interrupt controller (highest priority during T1I/T2)
    -- 2. CPU drives during T1, T2, and write cycles
    -- 3. Memory controller drives during memory read cycles
    -- 4. Default: Hi-Z
    process(int_data_enable, int_data_out, cpu_data_enable, cpu_data_out, mem_data_enable, mem_data_out)
        variable enable_count : integer;
    begin
        -- Count how many drivers are active (for contention detection)
        enable_count := 0;
        if int_data_enable = '1' then
            enable_count := enable_count + 1;
        end if;
        if cpu_data_enable = '1' then
            enable_count := enable_count + 1;
        end if;
        if mem_data_enable = '1' then
            enable_count := enable_count + 1;
        end if;

        -- Report bus contention
        if enable_count > 1 then
            report "BUS CONTENTION: " & integer'image(enable_count) & " drivers active! " &
                   "int_en=" & std_logic'image(int_data_enable) & " " &
                   "cpu_en=" & std_logic'image(cpu_data_enable) & " " &
                   "mem_en=" & std_logic'image(mem_data_enable)
                   severity warning;
        end if;

        -- Default: tri-state
        data_bus <= (others => 'Z');

        -- Priority 1: Interrupt controller (highest - during T1I/T2)
        if int_data_enable = '1' then
            data_bus <= int_data_out;
        -- Priority 2: CPU (during T1/T2 address output)
        elsif cpu_data_enable = '1' then
            data_bus <= cpu_data_out;

            -- Debug: Report PC vs bus output during T1
            if S2 = '0' and S1 = '1' and S0 = '0' then  -- T1 state
                report "DEBUG T1: debug_pc=0x" & to_hstring(unsigned(debug_pc_int)) &
                       " cpu_data_out(bus)=0x" & to_hstring(unsigned(cpu_data_out)) &
                       " MISMATCH=" & boolean'image(debug_pc_int(7 downto 0) /= cpu_data_out);
            end if;
        -- Priority 3: Memory controller (during T3 read)
        elsif mem_data_enable = '1' then
            data_bus <= mem_data_out;
        end if;
    end process;

    --------------------------------------------------------------------------------
    -- Memory Subsystem
    --------------------------------------------------------------------------------
    -- ROM: 2KB at 0x0000-0x07FF (loaded with search_as.mem)
    u_rom : rom_2kx8
        generic map (
            ROM_FILE => "../../test_programs/search_as.mem"
        )
        port map (
            ADDR     => rom_addr,
            DATA_OUT => rom_data,
            CS_N     => rom_cs_n
        );

    -- RAM: 1KB at 0x0800-0x0BFF (for stack and data)
    u_ram : ram_1kx8
        port map (
            CLK          => phi1,
            ADDR         => ram_addr,
            DATA_IN      => ram_data_in,
            DATA_OUT     => ram_data_out,
            RW_N         => ram_rw_n,
            CS_N         => ram_cs_n,
            DEBUG_BYTE_0 => debug_byte_0
        );

    -- Memory Controller (handles ROM/RAM address decoding)
    u_memory_controller : memory_controller
        generic map (
            ROM_SIZE_BITS => 11,  -- 2KB ROM
            RAM_SIZE_BITS => 10,  -- 1KB RAM
            ROM_BASE_ADDR => "00000000000000",  -- 0x0000
            RAM_BASE_ADDR => "00100000000000"   -- 0x0800
        )
        port map (
            phi1            => phi1,
            reset_n         => reset_n,
            S2              => S2,
            S1              => S1,
            S0              => S0,
            SYNC            => SYNC,
            data_bus_in     => data_bus,
            rom_addr        => rom_addr,
            rom_data        => rom_data,
            rom_cs_n        => rom_cs_n,
            ram_addr        => ram_addr,
            ram_data_in     => ram_data_in,
            ram_data_out    => ram_data_out,
            ram_rw_n        => ram_rw_n,
            ram_cs_n        => ram_cs_n,
            mem_data_out    => mem_data_out,
            mem_data_enable => mem_data_enable
        );

    --------------------------------------------------------------------------------
    -- Interrupt Controller (boots CPU with RST 0)
    --------------------------------------------------------------------------------
    u_interrupt_controller : reset_interrupt_controller
        generic map (
            RST_VECTOR         => 0,     -- RST 0 (jump to 0x0000)
            STARTUP_INT_ENABLE => true   -- Generate interrupt on startup
        )
        port map (
            phi1            => phi1,
            reset_n         => reset_n,
            S2              => S2,
            S1              => S1,
            S0              => S0,
            SYNC            => SYNC,
            int_data_out    => int_data_out,
            int_data_enable => int_data_enable,
            INT             => INT
        );

    --------------------------------------------------------------------------------
    -- LED Output (show accumulator register on LEDs)
    --------------------------------------------------------------------------------
    -- LEDs are active-low on ECP5-5G Versa board
    led_E16 <= not debug_reg_A(0);
    led_D17 <= not debug_reg_A(1);
    led_D18 <= not debug_reg_A(2);
    led_E18 <= not debug_reg_A(3);
    led_D19 <= not debug_reg_A(4);
    led_E19 <= not debug_reg_A(5);
    led_A20 <= not debug_reg_A(6);
    led_B20 <= not debug_reg_A(7);

    --------------------------------------------------------------------------------
    -- Debug Header Output (PMOD J39 - 16 pins)
    --------------------------------------------------------------------------------
    cpu_d     <= data_bus;     -- [0-7] Data bus
    cpu_phi1  <= phi1;         -- [8] phi1 clock
    cpu_phi2  <= phi2;         -- [9] phi2 clock
    cpu_sync  <= SYNC;         -- [10] SYNC signal
    cpu_s0    <= S0;           -- [11] State S0
    cpu_s1    <= S1;           -- [12] State S1
    cpu_s2    <= S2;           -- [13] State S2
    cpu_int   <= INT;          -- [14] INT signal
    cpu_ready <= READY;        -- [15] READY signal

end architecture rtl;

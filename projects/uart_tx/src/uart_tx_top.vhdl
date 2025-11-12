--------------------------------------------------------------------------------
-- UART TX Top Level - Intel 8008 FPGA Implementation
--------------------------------------------------------------------------------
-- UART transmitter demonstration using Intel 8008 CPU
-- Demonstrates generic uart_tx component for serial communication
--
-- Features:
--   - Generic UART transmitter at 9600 baud, 8N1
--   - Simple I/O interface for transmitting characters
--   - Status register to check transmission busy state
--   - Memory-mapped I/O for UART control
--
-- I/O Ports:
--   OUT 10: UART TX data register (write byte to transmit)
--   INP 10: UART TX status register (bit 0 = tx_busy)
--
-- Memory Map:
--   ROM: 0x0000-0x07FF (2KB)
--   RAM: 0x0800-0x0BFF (1KB)
--
-- Copyright (c) 2025 Robert Rico
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_tx_top is
    port (
        -- System clock and reset
        clk         : in  std_logic;
        rst         : in  std_logic;

        -- UART TX output
        uart_tx     : out std_logic;

        -- Board LEDs (status indicators)
        led_E16     : out std_logic;  -- LED0 - TX busy indicator
        led_D17     : out std_logic;  -- LED1 - unused
        led_D18     : out std_logic;  -- LED2 - unused
        led_E18     : out std_logic;  -- LED3 - unused
        led_F17     : out std_logic;  -- LED4 - unused
        led_F18     : out std_logic;  -- LED5 - unused
        led_E17     : out std_logic;  -- LED6 - unused
        led_F16     : out std_logic;  -- LED7 - unused
        led_M20     : out std_logic;  -- Status: phi1 clock indicator
        led_L18     : out std_logic;  -- Status: always-on reference

        -- CPU debug signals (16 signals to PMOD header)
        cpu_d       : out std_logic_vector(7 downto 0);  -- Data bus
        cpu_s0      : out std_logic;                      -- State outputs
        cpu_s1      : out std_logic;
        cpu_s2      : out std_logic;
        cpu_sync    : out std_logic;                      -- Control signals
        cpu_phi1    : out std_logic;
        cpu_phi2    : out std_logic;
        cpu_ready   : out std_logic;
        cpu_int     : out std_logic;
        cpu_data_en : out std_logic                       -- CPU data bus enable
    );
end entity uart_tx_top;

architecture rtl of uart_tx_top is

    --------------------------------------------------------------------------------
    -- Component Declarations
    --------------------------------------------------------------------------------
    component s8008 is
        port (
            phi1            : in    std_logic;
            phi2            : in    std_logic;
            reset_n         : in    std_logic;
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
            debug_flags     : out   std_logic_vector(3 downto 0)
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

    component io_controller is
        generic (
            NUM_OUTPUT_PORTS : integer := 24;
            NUM_INPUT_PORTS  : integer := 8
        );
        port (
            phi1            : in  std_logic;
            reset_n         : in  std_logic;
            S2              : in  std_logic;
            S1              : in  std_logic;
            S0              : in  std_logic;
            data_bus_in     : in  std_logic_vector(7 downto 0);
            data_bus_out    : out std_logic_vector(7 downto 0);
            data_bus_enable : out std_logic;
            port_out        : out std_logic_vector((NUM_OUTPUT_PORTS * 8) - 1 downto 0);
            port_in         : in  std_logic_vector((NUM_INPUT_PORTS * 8) - 1 downto 0);
            int_mask_out    : out std_logic_vector(7 downto 0);
            int_status_in   : in  std_logic_vector(7 downto 0);
            int_active_in   : in  std_logic_vector(7 downto 0)
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

    -- Clock and reset
    signal reset_n      : std_logic;
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

    -- Memory controller interface
    signal mem_data_out     : std_logic_vector(7 downto 0);
    signal mem_data_enable  : std_logic;

    -- I/O controller interface
    signal io_data_out      : std_logic_vector(7 downto 0);
    signal io_data_enable   : std_logic;
    signal io_port_out      : std_logic_vector(23 downto 0);  -- 3 ports * 8 bits (port 8 LEDs, port 9 unused, port 10 UART data)
    signal io_port_in       : std_logic_vector(7 downto 0);   -- 1 port * 8 bits (port 0 UART status)

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

    -- UART signals (simplified - i8008_uart handles cycle detection internally)
    signal uart_tx_data_from_port : std_logic_vector(7 downto 0);
    signal uart_status_to_port    : std_logic_vector(7 downto 0);

    -- LED output register
    signal led_out : std_logic_vector(7 downto 0);

    -- Debug signals (unused)
    signal debug_reg_A, debug_reg_B, debug_reg_C, debug_reg_D : std_logic_vector(7 downto 0);
    signal debug_reg_E, debug_reg_H, debug_reg_L : std_logic_vector(7 downto 0);
    signal debug_pc_int    : std_logic_vector(13 downto 0);
    signal debug_flags_int : std_logic_vector(3 downto 0);
    signal debug_byte_0    : std_logic_vector(7 downto 0);

    -- Synchronized reset to avoid metastability
    signal rst_sync : std_logic_vector(1 downto 0) := (others => '1');

    -- Interrupt controller signals
    signal int_data_out : std_logic_vector(7 downto 0);
    signal int_data_enable : std_logic;
    signal int_status : std_logic_vector(7 downto 0);
    signal int_active_src : std_logic_vector(7 downto 0);
    signal int_mask : std_logic_vector(7 downto 0) := (others => '1');  -- All enabled

begin

    --------------------------------------------------------------------------------
    -- Reset Synchronization
    --------------------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            rst_sync <= rst_sync(0) & rst;
        end if;
    end process;

    --------------------------------------------------------------------------------
    -- Reset and Clock Generation & Startup
    --------------------------------------------------------------------------------
    reset_n <= not rst_sync(1);  -- Invert synchronized reset for CPU/peripherals
    READY <= '1';  -- Always ready

    -- Phase Clock Generator (non-overlapping phi1 and phi2 for Intel 8008)
    u_phase_clocks : phase_clocks
        port map (
            clk_in  => clk,
            reset   => rst_sync(1),
            phi1    => phi1,
            phi2    => phi2
        );

    --------------------------------------------------------------------------------
    -- Interrupt Controller
    --------------------------------------------------------------------------------
    -- Single-source controller for startup interrupt only (RST 0 -> 0x000)
    u_interrupt_controller : entity work.interrupt_controller
        generic map (
            NUM_SOURCES     => 1,              -- Only startup interrupt
            DEFAULT_VECTORS => (0,1,2,3,4,5,6,7),  -- Source 0 -> RST 0
            STARTUP_INT_SRC => 0,              -- Source 0 is startup
            STARTUP_ENABLE  => true            -- Enable startup interrupt
        )
        port map (
            phi1            => phi1,
            reset_n         => reset_n,
            S2              => S2,
            S1              => S1,
            S0              => S0,
            SYNC            => SYNC,
            int_requests    => (others => '0'),  -- No external interrupts
            int_mask        => int_mask,
            int_status      => int_status,
            int_active_src  => int_active_src,
            int_data_out    => int_data_out,
            int_data_enable => int_data_enable,
            INT             => INT
        );

    --------------------------------------------------------------------------------
    -- Intel 8008 CPU Core
    --------------------------------------------------------------------------------
    u_cpu : s8008
        port map (
            phi1            => phi1,
            phi2            => phi2,
            reset_n         => reset_n,
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
            debug_flags     => debug_flags_int
        );

    --------------------------------------------------------------------------------
    -- Tri-State Bus Arbiter
    --------------------------------------------------------------------------------
    process(int_data_enable, int_data_out, cpu_data_enable, cpu_data_out,
            mem_data_enable, mem_data_out, io_data_enable, io_data_out)
    begin
        -- Default: tri-state
        data_bus <= (others => 'Z');

        -- Priority 0: Interrupt controller (provides RST instruction during T1I/T2)
        if int_data_enable = '1' then
            data_bus <= int_data_out;
        -- Priority 1: CPU
        elsif cpu_data_enable = '1' then
            data_bus <= cpu_data_out;
        -- Priority 2: Memory controller
        elsif mem_data_enable = '1' then
            data_bus <= mem_data_out;
        -- Priority 3: I/O controller
        elsif io_data_enable = '1' then
            data_bus <= io_data_out;
        end if;
    end process;

    --------------------------------------------------------------------------------
    -- Memory Subsystem
    --------------------------------------------------------------------------------
    -- ROM: 2KB at 0x0000-0x07FF
    u_rom : rom_2kx8
        generic map (
            ROM_FILE => "test_programs/uart_tx.mem"
        )
        port map (
            ADDR     => rom_addr,
            DATA_OUT => rom_data,
            CS_N     => rom_cs_n
        );

    -- RAM: 1KB at 0x0800-0x0BFF
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

    -- Memory Controller
    u_memory_controller : memory_controller
        generic map (
            ROM_SIZE_BITS => 11,  -- 2KB
            RAM_SIZE_BITS => 10   -- 1KB
        )
        port map (
            phi1            => phi1,
            reset_n         => reset_n,
            S2              => S2,
            S1              => S1,
            S0              => S0,
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
    -- I/O Controller
    --------------------------------------------------------------------------------
    u_io_controller : io_controller
        generic map (
            NUM_OUTPUT_PORTS => 3,   -- Port 8 (LEDs), Port 9 (unused), Port 10 (UART data)
            NUM_INPUT_PORTS  => 1    -- Port 0 (UART status)
        )
        port map (
            phi1            => phi1,
            reset_n         => reset_n,
            S2              => S2,
            S1              => S1,
            S0              => S0,
            data_bus_in     => data_bus,
            data_bus_out    => io_data_out,
            data_bus_enable => io_data_enable,
            port_out        => io_port_out,
            port_in         => io_port_in,
            int_mask_out    => int_mask,
            int_status_in   => int_status,
            int_active_in   => int_active_src
        );

    -- Map port 8 (first output port, index 0) to LEDs
    led_out <= io_port_out(7 downto 0);

    -- Map port 10 (third output port, index 2) to UART TX data input
    uart_tx_data_from_port <= io_port_out(23 downto 16);

    -- Map port 0 (first input port) to UART status output
    io_port_in <= uart_status_to_port;

    --------------------------------------------------------------------------------
    -- UART Component with 8008 Interface
    --------------------------------------------------------------------------------
    -- This component encapsulates both the UART TX engine and the 8008-specific
    -- I/O cycle detection logic, making it reusable across projects
    --------------------------------------------------------------------------------
    u_uart : entity work.s8008_uart(rtl)
        generic map (
            CLK_FREQ_HZ    => 100_000_000,  -- 100 MHz system clock
            BAUD_RATE      => 9600,          -- 9600 baud
            TX_DATA_PORT   => 10,            -- OUT 10 for TX data
            TX_STATUS_PORT => 0              -- IN 0 for status
        )
        port map (
            clk            => clk,
            rst            => rst_sync(1),
            phi1           => phi1,
            reset_n        => reset_n,
            S2             => S2,
            S1             => S1,
            S0             => S0,
            data_bus       => data_bus,
            tx_status_out  => uart_status_to_port,
            uart_tx        => UART_TX
        );

    --------------------------------------------------------------------------------
    -- CPU Debug Output Assignments
    --------------------------------------------------------------------------------
    cpu_d       <= data_bus;
    cpu_s0      <= S0;
    cpu_s1      <= S1;
    cpu_s2      <= S2;
    cpu_sync    <= SYNC;
    cpu_phi1    <= phi1;
    cpu_phi2    <= phi2;
    cpu_ready   <= READY;
    cpu_int     <= INT;
    cpu_data_en <= cpu_data_enable;

    --------------------------------------------------------------------------------
    -- LED Outputs (all active low)
    --------------------------------------------------------------------------------
    -- LED0: UART TX busy indicator
    led_E16 <= not uart_status_to_port(0);  -- Invert tx_busy bit

    -- Remaining LEDs: unused (all off)
    led_D17 <= led_out(1);
    led_D18 <= led_out(2);
    led_E18 <= led_out(3);
    led_F17 <= led_out(4);
    led_F18 <= led_out(5);
    led_E17 <= led_out(6);
    led_F16 <= led_out(7);

    -- Status LEDs
    led_M20 <= not phi1;     -- phi1 clock indicator (dim = rapid toggle)
    led_L18 <= reset_n;      -- Always-on reference (on when running)

end architecture rtl;

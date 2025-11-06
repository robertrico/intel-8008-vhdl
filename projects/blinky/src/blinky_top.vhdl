--------------------------------------------------------------------------------
-- Blinky Top Level - Intel 8008 FPGA Implementation
--------------------------------------------------------------------------------
-- First hardware validation program for the Intel 8008 CPU
--
-- Based on the working monitor_8008 testbench architecture
--
-- Copyright (c) 2025 Robert Rico
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity blinky_top is
    port (
        -- System clock and reset
        clk         : in  std_logic;
        rst         : in  std_logic;

        -- KEEP - Main program LED
        debug_led   : out std_logic;  -- B16 - blinky program output

        -- KEEP - Phase clock LEDs (divided for visibility)
        led_phi1    : out std_logic;  -- D17 - phi1 clock divided
        led_phi2    : out std_logic;  -- D18 - phi2 clock divided

        -- RECYCLE + NEW - Diagnostic LEDs (5 total)
        led_test1   : out std_logic;  -- E18 - RECYCLE: ROM chip select
        led_test2   : out std_logic;  -- F17 - RECYCLE: CPU SYNC signal
        led_test3   : out std_logic;  -- F18 - NEW: RAM write strobe
        led_test4   : out std_logic;  -- E17 - NEW: I/O write strobe
        led_test5   : out std_logic;  -- F16 - NEW: Interrupt pending

        -- Raw phi1 diagnostic (M20 - free LED)
        led_phi1_raw : out std_logic;  -- M20 - Direct phi1 signal (not divided)

        -- Reference LED for brightness comparison (L18 - always on)
        led_ref_on   : out std_logic;  -- L18 - Always ON for brightness reference

        -- Single button input (B19 - speed_btn)
        speed_btn   : in  std_logic;

        -- 16 CPU debug signals
        cpu_d       : out std_logic_vector(7 downto 0);  -- Data bus
        cpu_s0      : out std_logic;                      -- State outputs
        cpu_s1      : out std_logic;
        cpu_s2      : out std_logic;
        cpu_sync    : out std_logic;                      -- Control signals
        cpu_phi1    : out std_logic;
        cpu_phi2    : out std_logic;
        cpu_ready   : out std_logic;
        cpu_int     : out std_logic
    );
end entity blinky_top;

architecture rtl of blinky_top is

    --------------------------------------------------------------------------------
    -- Component Declarations
    --------------------------------------------------------------------------------
    component s8008 is
        port (
            phi1        : in    std_logic;
            phi2        : in    std_logic;
            reset_n     : in    std_logic;
            data_bus    : inout std_logic_vector(7 downto 0);
            S0          : out   std_logic;
            S1          : out   std_logic;
            S2          : out   std_logic;
            SYNC        : out   std_logic;
            READY       : in    std_logic;
            INT         : in    std_logic;
            debug_reg_A : out   std_logic_vector(7 downto 0);
            debug_reg_B : out   std_logic_vector(7 downto 0);
            debug_reg_C : out   std_logic_vector(7 downto 0);
            debug_reg_D : out   std_logic_vector(7 downto 0);
            debug_reg_E : out   std_logic_vector(7 downto 0);
            debug_reg_H : out   std_logic_vector(7 downto 0);
            debug_reg_L : out   std_logic_vector(7 downto 0);
            debug_pc    : out   std_logic_vector(13 downto 0);
            debug_flags : out   std_logic_vector(3 downto 0)
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
        port (
            clk       : in  std_logic;
            reset_n   : in  std_logic;
            S2        : in  std_logic;
            S1        : in  std_logic;
            S0        : in  std_logic;
            SYNC      : in  std_logic;
            data_bus  : inout std_logic_vector(7 downto 0);
            leds      : out std_logic_vector(7 downto 0);
            buttons   : in  std_logic_vector(7 downto 0)
        );
    end component;

    component interrupt_controller is
        generic (
            CLK_FREQ_HZ : integer := 100_000_000;
            DEBOUNCE_MS : integer := 50
        );
        port (
            clk        : in    std_logic;
            reset_n    : in    std_logic;
            S2         : in    std_logic;
            S1         : in    std_logic;
            S0         : in    std_logic;
            SYNC       : in    std_logic;
            button_raw : in    std_logic;
            INT        : out   std_logic;
            data_bus   : inout std_logic_vector(7 downto 0)
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
    signal data_bus     : std_logic_vector(7 downto 0);
    signal S0, S1, S2   : std_logic;
    signal SYNC         : std_logic;
    signal READY        : std_logic;
    signal INT          : std_logic;

    -- Memory address capture (captured from data bus during T1/T2)
    signal addr_low_capture  : std_logic_vector(7 downto 0);
    signal addr_high_capture : std_logic_vector(5 downto 0);
    signal cycle_type_capture : std_logic_vector(1 downto 0);
    signal mem_addr          : std_logic_vector(13 downto 0);

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

    -- I/O signals
    signal led_out   : std_logic_vector(7 downto 0);
    signal button_in : std_logic_vector(7 downto 0);

    -- Debug signals (unused)
    signal debug_reg_A, debug_reg_B, debug_reg_C, debug_reg_D : std_logic_vector(7 downto 0);
    signal debug_reg_E, debug_reg_H, debug_reg_L : std_logic_vector(7 downto 0);
    signal debug_pc_int    : std_logic_vector(13 downto 0);
    signal debug_flags_int : std_logic_vector(3 downto 0);
    signal debug_byte_0    : std_logic_vector(7 downto 0);

    -- Clock dividers for phi LEDs
    signal phi1_div_counter : unsigned(23 downto 0) := (others => '0');
    signal phi2_div_counter : unsigned(23 downto 0) := (others => '0');
    signal phi1_divided     : std_logic := '0';
    signal phi2_divided     : std_logic := '0';
    signal phi1_prev        : std_logic := '0';
    signal phi2_prev        : std_logic := '0';

    -- I/O write detection
    signal io_write_active  : std_logic := '0';

    -- Synchronized reset to avoid metastability
    signal rst_sync : std_logic_vector(1 downto 0) := (others => '1');

begin

    --------------------------------------------------------------------------------
    -- Reset Synchronization
    --------------------------------------------------------------------------------
    -- Synchronize the external reset to avoid metastability
    process(clk)
    begin
        if rising_edge(clk) then
            rst_sync <= rst_sync(0) & rst;
        end if;
    end process;

    --------------------------------------------------------------------------------
    -- Reset and Clock Generation
    --------------------------------------------------------------------------------
    -- SW3 switches are active-low (logic 0 when ON)
    -- We want: SW3-1 ON = running, SW3-1 OFF = reset
    -- rst input '0' (ON) = normal operation, rst input '1' (OFF) = reset
    reset_n <= not rst_sync(1);  -- Invert synchronized reset for CPU/peripherals
    READY <= '1';  -- Always ready

    -- Phase Clock Generator (non-overlapping phi1 and phi2 for Intel 8008)
    -- Note: phi1/phi2 outputs will be used as clocks, so they need proper routing
    u_phase_clocks : phase_clocks
        port map (
            clk_in  => clk,
            reset   => rst_sync(1),  -- Use synchronized reset: '1'=reset, '0'=run
            phi1    => phi1,
            phi2    => phi2
        );

    -- WORKAROUND: Add synthesis directive to route phi1/phi2 as clocks
    -- synthesis translate_off
    -- pragma translate_off
    -- synthesis translate_on
    -- pragma translate_on

    --------------------------------------------------------------------------------
    -- Intel 8008 CPU Core
    --------------------------------------------------------------------------------
    u_cpu : s8008
        port map (
            phi1        => phi1,
            phi2        => phi2,
            reset_n     => reset_n,
            data_bus    => data_bus,
            S0          => S0,
            S1          => S1,
            S2          => S2,
            SYNC        => SYNC,
            READY       => READY,
            INT         => INT,
            debug_reg_A => debug_reg_A,
            debug_reg_B => debug_reg_B,
            debug_reg_C => debug_reg_C,
            debug_reg_D => debug_reg_D,
            debug_reg_E => debug_reg_E,
            debug_reg_H => debug_reg_H,
            debug_reg_L => debug_reg_L,
            debug_pc    => debug_pc_int,
            debug_flags => debug_flags_int
        );

    --------------------------------------------------------------------------------
    -- Memory Subsystem
    --------------------------------------------------------------------------------
    -- ROM: 2KB at 0x0000-0x07FF
    u_rom : rom_2kx8
        generic map (
            ROM_FILE => "blinky_simple.mem"
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

    --------------------------------------------------------------------------------
    -- Memory Address Decode (based on monitor_8008 testbench)
    --------------------------------------------------------------------------------
    mem_addr <= addr_high_capture & addr_low_capture;

    -- ROM: addresses 0x0000 - 0x07FF (bits 13-11 = "000")
    rom_addr <= mem_addr(10 downto 0);
    rom_cs_n <= '0' when mem_addr(13 downto 11) = "000" else '1';

    -- RAM: addresses 0x0800 - 0x0BFF (bits 13-10 = "0010")
    ram_addr <= mem_addr(9 downto 0);
    ram_cs_n <= '0' when mem_addr(13 downto 10) = "0010" else '1';

    --------------------------------------------------------------------------------
    -- Memory Controller (based on monitor_8008 testbench)
    --------------------------------------------------------------------------------
    -- Address capture process (synchronous on phi1)
    addr_capture: process(phi1)
    begin
        if rising_edge(phi1) then
            -- T1 state: Capture low address byte (S2 S1 S0 = 0 0 0)
            if S2 = '0' and S1 = '0' and S0 = '0' then
                if data_bus /= "ZZZZZZZZ" then
                    addr_low_capture <= data_bus;
                end if;
            end if;

            -- T2 state: Capture high address and cycle type (S2 S1 S0 = 0 1 0)
            if S2 = '0' and S1 = '1' and S0 = '0' then
                if data_bus /= "ZZZZZZZZ" then
                    addr_high_capture <= data_bus(5 downto 0);
                    cycle_type_capture <= data_bus(7 downto 6);
                end if;
            end if;
        end if;
    end process;

    -- RAM control process (synchronous writes)
    ram_control: process(phi1)
    begin
        if rising_edge(phi1) then
            -- T3/T4/T5 states with write cycle (PCW = "11")
            if ((S2 = '1' and S1 = '0' and S0 = '0') or  -- T3
                (S2 = '0' and S1 = '1' and S0 = '1') or  -- T4
                (S2 = '1' and S1 = '1' and S0 = '1')) and -- T5
               cycle_type_capture = "11" then
                -- PCW = memory write cycle
                ram_rw_n <= '0';
                if data_bus /= "ZZZZZZZZ" then
                    ram_data_in <= data_bus;
                end if;
            else
                ram_rw_n <= '1';
            end if;
        end if;
    end process;

    -- Bus multiplexer (combinational) - EXACTLY like monitor_8008
    bus_mux: process(S2, S1, S0, cycle_type_capture, mem_addr, rom_data, ram_data_out)
    begin
        -- Default: tri-state
        data_bus <= (others => 'Z');

        -- T3/T4/T5 states with memory read cycle (PCI="00" or PCR="01")
        -- Do NOT drive during I/O cycles (PCC="10") - let I/O controllers drive
        if ((S2 = '1' and S1 = '0' and S0 = '0') or  -- T3
            (S2 = '0' and S1 = '1' and S0 = '1') or  -- T4
            (S2 = '1' and S1 = '1' and S0 = '1')) and -- T5
           (cycle_type_capture = "00" or cycle_type_capture = "01") then

            -- Select memory source based on address
            if mem_addr(13 downto 11) = "000" then
                -- ROM space (0x0000 - 0x07FF)
                data_bus <= rom_data;
            elsif mem_addr(13 downto 10) = "0010" then
                -- RAM space (0x0800 - 0x0BFF)
                data_bus <= ram_data_out;
            else
                -- Unmapped
                data_bus <= x"FF";
            end if;
        end if;
    end process;

    --------------------------------------------------------------------------------
    -- I/O Controller
    --------------------------------------------------------------------------------
    button_in <= "0000000" & speed_btn;

    u_io_controller : io_controller
        port map (
            clk      => phi2,
            reset_n  => reset_n,
            S2       => S2,
            S1       => S1,
            S0       => S0,
            SYNC     => SYNC,
            data_bus => data_bus,
            leds     => led_out,
            buttons  => button_in
        );

    debug_led <= led_out(0);  -- Use only LED0

    --------------------------------------------------------------------------------
    -- Interrupt Controller
    --------------------------------------------------------------------------------
    u_interrupt_controller : interrupt_controller
        generic map (
            CLK_FREQ_HZ => 100_000_000,
            DEBOUNCE_MS => 50
        )
        port map (
            clk        => phi2,
            reset_n    => reset_n,
            S2         => S2,
            S1         => S1,
            S0         => S0,
            SYNC       => SYNC,
            button_raw => speed_btn,
            INT        => INT,
            data_bus   => data_bus
        );

    --------------------------------------------------------------------------------
    -- CPU Debug Output Assignments (16 signals)
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

    --------------------------------------------------------------------------------
    -- Phase Clock Divider for Visible LED Display
    --------------------------------------------------------------------------------
    -- Divide phi1/phi2 by large factor to make blinking visible to human eye
    -- Target: ~10 Hz blink rate (100ms period)
    -- Phi1 runs at ~455 kHz, so divide by ~45,000 for ~10 Hz
    phi_divider: process(clk, reset_n)
    begin
        if reset_n = '0' then
            phi1_div_counter <= (others => '0');
            phi2_div_counter <= (others => '0');
            phi1_divided     <= '0';
            phi2_divided     <= '0';
            phi1_prev        <= '0';
            phi2_prev        <= '0';
        elsif rising_edge(clk) then
            -- Store previous phi1/phi2 values for edge detection
            phi1_prev <= phi1;
            phi2_prev <= phi2;

            -- Phi1 divider: count rising edges of phi1
            if phi1 = '1' and phi1_prev = '0' then
                if phi1_div_counter < 45000 then
                    phi1_div_counter <= phi1_div_counter + 1;
                else
                    phi1_div_counter <= (others => '0');
                    phi1_divided <= not phi1_divided;
                end if;
            end if;

            -- Phi2 divider: count rising edges of phi2
            if phi2 = '1' and phi2_prev = '0' then
                if phi2_div_counter < 45000 then
                    phi2_div_counter <= phi2_div_counter + 1;
                else
                    phi2_div_counter <= (others => '0');
                    phi2_divided <= not phi2_divided;
                end if;
            end if;
        end if;
    end process;

    --------------------------------------------------------------------------------
    -- I/O Write Detection
    --------------------------------------------------------------------------------
    -- Detect when an I/O write operation is occurring (S2,S1,S0 = 010 during I/O cycle)
    -- This happens during the T2 state of an OUT instruction
    process(clk, reset_n)
    begin
        if reset_n = '0' then
            io_write_active <= '0';
        elsif rising_edge(clk) then
            -- I/O write occurs when S2='0', S1='1', S0='0' (state 010)
            if S2 = '0' and S1 = '1' and S0 = '0' then
                io_write_active <= '1';
            else
                io_write_active <= '0';
            end if;
        end if;
    end process;

    --------------------------------------------------------------------------------
    -- LED Outputs (all active low)
    --------------------------------------------------------------------------------
    -- KEEP - Phase clock LEDs (divided for visibility)
    led_phi1   <= not phi1_divided;   -- D17: Phi1 clock divided
    led_phi2   <= not phi2_divided;   -- D18: Phi2 clock divided

    -- Diagnostic LEDs
    led_test1  <= rom_cs_n;           -- E18: ROM chip select (active low, so LED on when ROM active)
    led_test2  <= not SYNC;           -- F17: CPU SYNC signal (LED on during SYNC)
    led_test3  <= ram_rw_n;           -- F18: RAM write strobe (active low, so LED on when writing)
    led_test4  <= not io_write_active;-- E17: I/O write strobe (LED on when I/O write)
    led_test5  <= not INT;            -- F16: Interrupt signal (LED on when interrupt pending)

    -- Raw phi1 signal (should be ~455kHz, will appear dim if oscillating)
    led_phi1_raw <= not phi1;         -- M20: Direct phi1 (active low LED)

    -- Reference LED (always on for brightness comparison)
    led_ref_on <= reset_n;                -- L18: Always ON (active low)

end architecture rtl;

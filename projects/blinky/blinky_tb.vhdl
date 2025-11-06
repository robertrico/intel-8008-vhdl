--------------------------------------------------------------------------------
-- Blinky Testbench - Intel 8008 Hardware Validation
--------------------------------------------------------------------------------
-- Simulates the complete blinky system including:
--   - Intel 8008 CPU
--   - ROM (with blinky program)
--   - RAM (for variables)
--   - I/O controller (LEDs and buttons)
--   - Interrupt controller
--
-- Test scenarios:
--   1. System initialization and reset
--   2. LED blinking at default rate
--   3. Button press triggers interrupt
--   4. Blink rate changes
--   5. Button release restores original rate
--
-- Copyright (c) 2025 Robert Rico
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity blinky_tb is
end entity blinky_tb;

architecture sim of blinky_tb is

    --------------------------------------------------------------------------------
    -- Component Declaration
    --------------------------------------------------------------------------------
    component blinky_top is
        port (
            clk         : in  std_logic;
            rst         : in  std_logic;
            debug_led   : out std_logic;
            speed_btn   : in  std_logic;
            cpu_d       : out std_logic_vector(7 downto 0);
            cpu_s0      : out std_logic;
            cpu_s1      : out std_logic;
            cpu_s2      : out std_logic;
            cpu_sync    : out std_logic;
            cpu_phi1    : out std_logic;
            cpu_phi2    : out std_logic;
            cpu_ready   : out std_logic;
            cpu_int     : out std_logic
        );
    end component;

    --------------------------------------------------------------------------------
    -- Constants
    --------------------------------------------------------------------------------
    constant CLK_PERIOD : time := 10 ns;  -- 100 MHz clock

    --------------------------------------------------------------------------------
    -- Signals
    --------------------------------------------------------------------------------
    signal clk         : std_logic := '0';
    signal rst         : std_logic := '1';
    signal debug_led   : std_logic;
    signal speed_btn   : std_logic := '0';

    -- CPU debug signals
    signal cpu_d       : std_logic_vector(7 downto 0);
    signal cpu_s0      : std_logic;
    signal cpu_s1      : std_logic;
    signal cpu_s2      : std_logic;
    signal cpu_sync    : std_logic;
    signal cpu_phi1    : std_logic;
    signal cpu_phi2    : std_logic;
    signal cpu_ready   : std_logic;
    signal cpu_int     : std_logic;

    -- Test control
    signal sim_done : boolean := false;

    -- LED change detection
    signal led_changed : boolean := false;
    signal led_prev    : std_logic := '1';

begin

    --------------------------------------------------------------------------------
    -- Clock Generation
    --------------------------------------------------------------------------------
    clk_proc: process
    begin
        while not sim_done loop
            clk <= '0';
            wait for CLK_PERIOD / 2;
            clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process clk_proc;

    --------------------------------------------------------------------------------
    -- Device Under Test (DUT)
    --------------------------------------------------------------------------------
    dut: blinky_top
        port map (
            clk         => clk,
            rst         => rst,
            debug_led   => debug_led,
            speed_btn   => speed_btn,
            cpu_d       => cpu_d,
            cpu_s0      => cpu_s0,
            cpu_s1      => cpu_s1,
            cpu_s2      => cpu_s2,
            cpu_sync    => cpu_sync,
            cpu_phi1    => cpu_phi1,
            cpu_phi2    => cpu_phi2,
            cpu_ready   => cpu_ready,
            cpu_int     => cpu_int
        );

    --------------------------------------------------------------------------------
    -- LED Change Monitor
    --------------------------------------------------------------------------------
    led_monitor: process(clk)
    begin
        if rising_edge(clk) then
            if debug_led /= led_prev then
                led_changed <= true;
                led_prev    <= debug_led;
                report "LED changed to: " & std_logic'image(debug_led)
                       severity note;
            else
                led_changed <= false;
            end if;
        end if;
    end process led_monitor;

    --------------------------------------------------------------------------------
    -- Stimulus Process
    --------------------------------------------------------------------------------
    stim_proc: process
    begin
        report "========================================" severity note;
        report "Blinky Testbench - Starting Simulation" severity note;
        report "========================================" severity note;

        -- Initial reset
        rst <= '1';
        speed_btn <= '0';
        wait for 100 ns;

        report "Releasing reset..." severity note;
        rst <= '0';
        wait for 1 us;

        -- Test 1: Let CPU boot and start executing
        report "Test 1: CPU initialization and boot" severity note;
        wait for 50 us;

        -- Test 2: Observe LED blinking at default rate
        report "Test 2: Observing LED blink at default (fast) rate" severity note;
        report "Waiting for LED transitions..." severity note;
        wait for 500 us;

        -- Test 3: Press button to trigger interrupt
        report "Test 3: Pressing speed button" severity note;
        speed_btn <= '1';  -- Press button
        wait for 100 us;

        -- Test 4: Observe slower blink rate
        report "Test 4: LED should now blink at slower rate" severity note;
        wait for 800 us;

        -- Test 5: Release button
        report "Test 5: Releasing speed button" severity note;
        speed_btn <= '0';  -- Release button
        wait for 100 us;

        -- Test 6: Verify return to fast blink
        report "Test 6: LED should return to fast blink rate" severity note;
        wait for 500 us;

        -- End simulation
        report "========================================" severity note;
        report "Simulation Complete" severity note;
        report "========================================" severity note;
        report "Expected behavior:" severity note;
        report "  1. LED0 toggles at ~10ms intervals initially" severity note;
        report "  2. Button press triggers interrupt" severity note;
        report "  3. LED0 toggles at ~100ms intervals (slower)" severity note;
        report "  4. Button release triggers interrupt" severity note;
        report "  5. LED0 returns to ~10ms intervals (fast)" severity note;
        report "========================================" severity note;

        sim_done <= true;
        wait;
    end process stim_proc;

    --------------------------------------------------------------------------------
    -- Assertions and Checks
    --------------------------------------------------------------------------------
    check_proc: process
    begin
        -- Wait for reset to complete
        wait until rst = '0';
        wait for 1 us;

        -- Wait for first clock edge (should happen within a few microseconds)
        wait until rising_edge(cpu_phi1) for 10 us;
        assert cpu_phi1 = '1'
            report "ERROR: Phase clocks not toggling - phi1 never went high!"
            severity error;

        -- Check for non-overlapping clocks
        wait until rising_edge(cpu_phi1);
        assert cpu_phi2 = '0'
            report "ERROR: Clock overlap detected (phi1 rising while phi2 high)!"
            severity error;

        wait until rising_edge(cpu_phi2);
        assert cpu_phi1 = '0'
            report "ERROR: Clock overlap detected (phi2 rising while phi1 high)!"
            severity error;

        report "Clock generation verified (non-overlapping)" severity note;

        wait;
    end process check_proc;

end architecture sim;

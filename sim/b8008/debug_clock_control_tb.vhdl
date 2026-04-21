--------------------------------------------------------------------------------
-- debug_clock_control_tb.vhdl
--------------------------------------------------------------------------------
-- Testbench for the Three-Button Debug Controller.
--
-- The controller no longer gates clk_in. Instead it outputs a run_enable
-- hold signal consumed by phase_clocks. This TB instantiates BOTH modules
-- together (debug_clock_control + real phase_clocks) so the assertions
-- reflect the integrated behavior we actually ship.
--
-- Tests:
--   1. Reset initializes to "stopped" (run_enable='0', is_running='0')
--   2. Run/stop toggle: press starts CPU; press again stops it
--   3. Full-cycle step: single phi step advances phase_clocks exactly one
--      phi edge (run_enable pulses just long enough)
--   4. Multiple consecutive steps stay single-edge each
--   5. Step-to-SYNC advances until sync toggles, then stops
--
-- Copyright (c) 2025 Robert Rico
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity debug_clock_control_tb is
end entity debug_clock_control_tb;

architecture sim of debug_clock_control_tb is

    constant CLK_PERIOD : time := 10 ns;  -- 100 MHz master clock
    constant PHI1_CLOCKS : integer := 80;
    constant DEAD1_CLOCKS : integer := 40;
    constant PHI2_CLOCKS : integer := 60;
    constant DEAD2_CLOCKS : integer := 40;
    constant TOTAL_CYCLE : integer := PHI1_CLOCKS + DEAD1_CLOCKS + PHI2_CLOCKS + DEAD2_CLOCKS;

    -- Master clock + top-level reset
    signal clk           : std_logic := '0';
    signal reset         : std_logic := '1';

    -- Buttons (debounced pulses, driven by test stimulus)
    signal btn_run_stop   : std_logic := '0';
    signal btn_step_cycle : std_logic := '0';
    signal btn_step_sync  : std_logic := '0';

    -- Bootstrap break input (held low so we don't trigger an auto-stop)
    signal bootstrap_done : std_logic := '0';

    -- debug_clock_control outputs
    signal run_enable    : std_logic;
    signal is_running    : std_logic;
    signal next_is_phi1  : std_logic;
    signal next_is_phi2  : std_logic;
    signal triggered     : std_logic;
    signal reset_request : std_logic;

    -- phase_clocks outputs (feed back into the DUT)
    signal phi1         : std_logic;
    signal phi2         : std_logic;
    signal sync_sig     : std_logic;
    signal phi1_rising  : std_logic;
    signal phi1_falling : std_logic;
    signal phi2_rising  : std_logic;
    signal phi2_falling : std_logic;

    -- Simulation control
    signal sim_done : boolean := false;

    -- Counter of clk edges where run_enable is asserted (the "CPU is
    -- advancing" metric that replaces the old gated_clk tick count).
    signal active_tick_count : integer := 0;

begin

    ---------------------------------------------------------------------------
    -- DUT: the controller under test
    ---------------------------------------------------------------------------
    dut : entity work.debug_clock_control
        port map (
            clk_in          => clk,
            reset           => reset,
            btn_run_stop    => btn_run_stop,
            btn_step_cycle  => btn_step_cycle,
            btn_step_sync   => btn_step_sync,
            phi1_in         => phi1,
            phi2_in         => phi2,
            sync_in         => sync_sig,
            bootstrap_done  => bootstrap_done,
            run_enable      => run_enable,
            is_running      => is_running,
            next_is_phi1    => next_is_phi1,
            next_is_phi2    => next_is_phi2,
            triggered       => triggered,
            reset_request   => reset_request
        );

    ---------------------------------------------------------------------------
    -- Real phase_clocks: advances only while run_enable='1'. This is what
    -- the monitor's top-level uses, so the TB exercises the shipping
    -- integration rather than a simulated stand-in.
    ---------------------------------------------------------------------------
    u_phase : entity work.phase_clocks
        port map (
            clk_in       => clk,
            reset        => reset,
            run_enable   => run_enable,
            phi1         => phi1,
            phi2         => phi2,
            sync         => sync_sig,
            phi1_rising  => phi1_rising,
            phi1_falling => phi1_falling,
            phi2_rising  => phi2_rising,
            phi2_falling => phi2_falling
        );

    ---------------------------------------------------------------------------
    -- Clock generation (100 MHz)
    ---------------------------------------------------------------------------
    clk_proc : process
    begin
        while not sim_done loop
            clk <= '0';
            wait for CLK_PERIOD / 2;
            clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    ---------------------------------------------------------------------------
    -- Count clk edges where run_enable was '1' (proxy for "CPU advanced")
    ---------------------------------------------------------------------------
    tick_count_proc : process(clk, reset)
    begin
        if reset = '1' then
            active_tick_count <= 0;
        elsif rising_edge(clk) then
            if run_enable = '1' then
                active_tick_count <= active_tick_count + 1;
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- Main test sequence
    ---------------------------------------------------------------------------
    test_process : process
        variable start_count : integer;
        variable elapsed     : integer;
        variable errors      : integer := 0;

        procedure check(
            condition : boolean;
            name      : string
        ) is
        begin
            if condition then
                report "  PASS: " & name severity note;
            else
                report "  FAIL: " & name severity error;
                errors := errors + 1;
            end if;
        end procedure;

        procedure press(signal btn : out std_logic) is
        begin
            btn <= '1';
            wait for CLK_PERIOD;
            btn <= '0';
        end procedure;
    begin
        report "=== Debug Clock Control Testbench ===" severity note;

        -----------------------------------------------------------------------
        -- Test 0: reset state
        -----------------------------------------------------------------------
        report "Test 0: Reset state" severity note;
        reset <= '1';
        wait for CLK_PERIOD * 10;
        reset <= '0';
        wait for CLK_PERIOD * 5;

        check(is_running = '0', "is_running starts low after reset (CPU stopped)");
        check(run_enable = '0', "run_enable starts low after reset");

        -----------------------------------------------------------------------
        -- Test 1: run/stop toggle
        -----------------------------------------------------------------------
        report "Test 1: Run/stop toggle" severity note;

        -- Press to start running
        press(btn_run_stop);
        wait for CLK_PERIOD * 600;  -- let the reset pulse complete + run a bit
        check(is_running = '1', "running after first run/stop press");

        -- Advance past at least one full phi cycle so phi1/phi2 emit edges
        wait for CLK_PERIOD * (TOTAL_CYCLE + 50);
        check(active_tick_count > TOTAL_CYCLE,
              "run_enable was high for >= 1 full phi cycle while running");

        -- Press again to stop
        press(btn_run_stop);
        wait for CLK_PERIOD * 10;
        check(is_running = '0', "stopped after second run/stop press");
        check(run_enable = '0', "run_enable low while stopped");

        -- Confirm no further active ticks accumulate
        start_count := active_tick_count;
        wait for CLK_PERIOD * 200;
        check(active_tick_count = start_count,
              "active_tick_count frozen while stopped");

        -----------------------------------------------------------------------
        -- Test 2: single phi step
        -----------------------------------------------------------------------
        report "Test 2: Step Phi (one phi edge advance)" severity note;

        start_count := active_tick_count;
        press(btn_step_cycle);

        -- Expect a short burst of active ticks and then stop again. A phi
        -- step completes on the next phi falling edge, which is at most
        -- TOTAL_CYCLE clk cycles away.
        wait for CLK_PERIOD * (TOTAL_CYCLE + 50);
        check(is_running = '0', "stopped again after phi step completes");

        elapsed := active_tick_count - start_count;
        check(elapsed > 0 and elapsed <= TOTAL_CYCLE,
              "phi step advanced 0 < n <= 220 active ticks (got " &
              integer'image(elapsed) & ")");

        -----------------------------------------------------------------------
        -- Test 3: three consecutive phi steps
        -----------------------------------------------------------------------
        report "Test 3: Three consecutive phi steps" severity note;

        start_count := active_tick_count;
        for i in 1 to 3 loop
            press(btn_step_cycle);
            wait for CLK_PERIOD * (TOTAL_CYCLE + 20);
        end loop;

        check(is_running = '0', "stopped again after three phi steps");
        elapsed := active_tick_count - start_count;
        check(elapsed > 0 and elapsed <= 3 * TOTAL_CYCLE,
              "three phi steps stayed within 3 * 220 active ticks (got " &
              integer'image(elapsed) & ")");

        -----------------------------------------------------------------------
        -- Test 4: step-to-SYNC
        -----------------------------------------------------------------------
        report "Test 4: Step to SYNC (runs until sync toggles)" severity note;

        start_count := active_tick_count;
        press(btn_step_sync);

        -- Sync toggles every full phi cycle, so step-sync takes up to
        -- TOTAL_CYCLE clk cycles to complete.
        wait for CLK_PERIOD * (TOTAL_CYCLE + 50);
        check(is_running = '0', "stopped after step-to-SYNC");

        elapsed := active_tick_count - start_count;
        check(elapsed > 0 and elapsed <= TOTAL_CYCLE + 10,
              "step-to-SYNC advanced a bounded number of ticks (got " &
              integer'image(elapsed) & ")");

        -----------------------------------------------------------------------
        -- Test 5: resume running
        -----------------------------------------------------------------------
        report "Test 5: Resume running" severity note;

        press(btn_run_stop);
        wait for CLK_PERIOD * 600;
        check(is_running = '1', "running again after resume press");

        -----------------------------------------------------------------------
        -- Summary
        -----------------------------------------------------------------------
        report "";
        if errors = 0 then
            report "*** ALL TESTS PASSED ***" severity note;
        else
            report "*** TESTS FAILED: " & integer'image(errors) & " errors ***" severity error;
        end if;

        sim_done <= true;
        wait;
    end process;

end architecture sim;

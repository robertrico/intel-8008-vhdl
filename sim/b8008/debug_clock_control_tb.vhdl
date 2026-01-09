--------------------------------------------------------------------------------
-- debug_clock_control_tb.vhdl
--------------------------------------------------------------------------------
-- Testbench for Three-Button Debug Controller
--
-- Tests:
--   1. Run/stop toggle functionality
--   2. Full cycle stepping (220 clocks)
--   3. Step-to-SYNC functionality
--   4. Multiple consecutive steps
--   5. Phase tracking accuracy
--
-- Copyright (c) 2025 Robert Rico
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity debug_clock_control_tb is
end entity debug_clock_control_tb;

architecture sim of debug_clock_control_tb is

    -- Clock period (100 MHz = 10 ns)
    constant CLK_PERIOD : time := 10 ns;

    -- Phase timing constants (must match debug_clock_control.vhdl)
    constant PHI1_CLOCKS : integer := 80;
    constant DEAD1_CLOCKS : integer := 40;
    constant PHI2_CLOCKS : integer := 60;
    constant DEAD2_CLOCKS : integer := 40;
    constant TOTAL_CYCLE : integer := 220;

    -- DUT signals
    signal clk_in : std_logic := '0';
    signal reset : std_logic := '1';
    signal btn_run_stop : std_logic := '0';
    signal btn_step_cycle : std_logic := '0';
    signal btn_step_sync : std_logic := '0';
    signal phi1_in : std_logic := '0';
    signal phi2_in : std_logic := '0';
    signal sync_in : std_logic := '0';
    signal clk_out : std_logic;
    signal is_running : std_logic;
    signal next_is_phi1 : std_logic;
    signal next_is_phi2 : std_logic;
    signal triggered : std_logic;

    -- Simulation control
    signal sim_done : boolean := false;

    -- Test counters
    signal gated_clk_count : integer := 0;
    signal test_phase : integer := 0;

    -- Simulated phase_clocks signals (generated from gated clock)
    signal sim_phi1 : std_logic := '0';
    signal sim_phi2 : std_logic := '0';
    signal sim_sync : std_logic := '0';
    signal sim_phase_counter : integer := 0;

begin

    ---------------------------------------------------------------------------
    -- DUT Instantiation
    ---------------------------------------------------------------------------
    dut : entity work.debug_clock_control
        port map (
            clk_in          => clk_in,
            reset           => reset,
            btn_run_stop    => btn_run_stop,
            btn_step_cycle  => btn_step_cycle,
            btn_step_sync   => btn_step_sync,
            phi1_in         => phi1_in,
            phi2_in         => phi2_in,
            sync_in         => sync_in,
            clk_out         => clk_out,
            is_running      => is_running,
            next_is_phi1    => next_is_phi1,
            next_is_phi2    => next_is_phi2,
            triggered       => triggered
        );

    ---------------------------------------------------------------------------
    -- Clock Generation (100 MHz)
    ---------------------------------------------------------------------------
    clk_process : process
    begin
        while not sim_done loop
            clk_in <= '0';
            wait for CLK_PERIOD / 2;
            clk_in <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    ---------------------------------------------------------------------------
    -- Simulated Phase Clocks (driven by gated clock output)
    ---------------------------------------------------------------------------
    -- This simulates what phase_clocks inside b8008 would do
    phase_sim : process(clk_out, reset)
    begin
        if reset = '1' then
            sim_phi1 <= '1';
            sim_phi2 <= '0';
            sim_sync <= '1';
            sim_phase_counter <= 0;
        elsif rising_edge(clk_out) then
            sim_phase_counter <= sim_phase_counter + 1;

            -- Generate phi1/phi2/sync based on counter
            if sim_phase_counter < PHI1_CLOCKS then
                -- PHI1 active
                sim_phi1 <= '1';
                sim_phi2 <= '0';
            elsif sim_phase_counter < PHI1_CLOCKS + DEAD1_CLOCKS then
                -- Dead time 1
                sim_phi1 <= '0';
                sim_phi2 <= '0';
            elsif sim_phase_counter < PHI1_CLOCKS + DEAD1_CLOCKS + PHI2_CLOCKS then
                -- PHI2 active
                sim_phi1 <= '0';
                sim_phi2 <= '1';
            elsif sim_phase_counter < TOTAL_CYCLE - 1 then
                -- Dead time 2
                sim_phi1 <= '0';
                sim_phi2 <= '0';
            else
                -- End of cycle, wrap around
                sim_phase_counter <= 0;
                sim_phi1 <= '1';
                sim_phi2 <= '0';
                sim_sync <= not sim_sync;  -- Toggle sync every full cycle
            end if;
        end if;
    end process;

    -- Connect simulated phase clocks to DUT feedback inputs
    phi1_in <= sim_phi1;
    phi2_in <= sim_phi2;
    sync_in <= sim_sync;

    ---------------------------------------------------------------------------
    -- Gated Clock Counter
    ---------------------------------------------------------------------------
    count_gated : process(clk_out, reset)
    begin
        if reset = '1' then
            gated_clk_count <= 0;
        elsif rising_edge(clk_out) then
            gated_clk_count <= gated_clk_count + 1;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- Main Test Process
    ---------------------------------------------------------------------------
    test_process : process
        variable start_count : integer;
        variable elapsed : integer;
    begin
        report "=== Debug Clock Control Testbench ===" severity note;

        -----------------------------------------------------------------------
        -- Test 0: Reset
        -----------------------------------------------------------------------
        test_phase <= 0;
        report "Test 0: Reset" severity note;
        reset <= '1';
        wait for CLK_PERIOD * 10;
        reset <= '0';
        wait for CLK_PERIOD * 5;

        -- After reset, should be running
        assert is_running = '1'
            report "FAIL: Should be running after reset" severity error;
        report "PASS: Running after reset" severity note;

        -----------------------------------------------------------------------
        -- Test 1: Run/Stop Toggle
        -----------------------------------------------------------------------
        test_phase <= 1;
        report "Test 1: Run/Stop Toggle" severity note;

        -- Let it run for a bit
        wait for CLK_PERIOD * 500;
        assert is_running = '1'
            report "FAIL: Should still be running" severity error;

        -- Press run/stop to stop
        btn_run_stop <= '1';
        wait for CLK_PERIOD;
        btn_run_stop <= '0';

        -- Wait for clean stop (should stop at end of DEAD_2)
        wait for CLK_PERIOD * 300;  -- Enough time to reach stop point

        assert is_running = '0'
            report "FAIL: Should be stopped after run/stop press" severity error;
        report "PASS: Stopped after run/stop press" severity note;

        -- Verify stopped at clean point (phi1 is next)
        wait for CLK_PERIOD * 10;
        assert next_is_phi1 = '1'
            report "FAIL: Should stop with phi1 as next phase" severity error;
        report "PASS: Stopped with phi1 as next phase" severity note;

        -----------------------------------------------------------------------
        -- Test 2: Step Full Cycle
        -----------------------------------------------------------------------
        test_phase <= 2;
        report "Test 2: Step Full Cycle" severity note;

        -- Record starting count
        start_count := gated_clk_count;

        -- Press step cycle
        btn_step_cycle <= '1';
        wait for CLK_PERIOD;
        btn_step_cycle <= '0';

        -- Wait for step to complete
        wait for CLK_PERIOD * 250;  -- 220 clocks + margin

        -- Check stopped again
        assert is_running = '0'
            report "FAIL: Should be stopped after cycle step" severity error;

        -- Check we advanced by exactly 220 clocks (full cycle)
        elapsed := gated_clk_count - start_count;
        assert elapsed >= 218 and elapsed <= 222
            report "FAIL: Step cycle should advance ~220 clocks, got " &
                   integer'image(elapsed) severity error;
        report "PASS: Step cycle advanced " & integer'image(elapsed) & " clocks" severity note;

        -----------------------------------------------------------------------
        -- Test 3: Multiple Consecutive Steps
        -----------------------------------------------------------------------
        test_phase <= 3;
        report "Test 3: Multiple Consecutive Steps" severity note;

        start_count := gated_clk_count;

        -- Do 3 consecutive steps
        for i in 1 to 3 loop
            btn_step_cycle <= '1';
            wait for CLK_PERIOD;
            btn_step_cycle <= '0';
            wait for CLK_PERIOD * 250;  -- Wait for step to complete
        end loop;

        -- Check stopped
        assert is_running = '0'
            report "FAIL: Should be stopped after multiple steps" severity error;

        -- Check we advanced by approximately 3 * 220 = 660 clocks
        elapsed := gated_clk_count - start_count;
        assert elapsed >= 655 and elapsed <= 665
            report "FAIL: 3 steps should advance ~660 clocks, got " &
                   integer'image(elapsed) severity error;
        report "PASS: 3 consecutive steps advanced " & integer'image(elapsed) & " clocks" severity note;

        -----------------------------------------------------------------------
        -- Test 4: Resume Running
        -----------------------------------------------------------------------
        test_phase <= 4;
        report "Test 4: Resume Running" severity note;

        -- Press run/stop to resume
        btn_run_stop <= '1';
        wait for CLK_PERIOD;
        btn_run_stop <= '0';
        wait for CLK_PERIOD * 10;

        assert is_running = '1'
            report "FAIL: Should be running after resume" severity error;
        report "PASS: Running after resume" severity note;

        -- Let it run for a while
        wait for CLK_PERIOD * 500;

        -----------------------------------------------------------------------
        -- Test 5: Step to SYNC
        -----------------------------------------------------------------------
        test_phase <= 5;
        report "Test 5: Step to SYNC" severity note;

        -- First stop the CPU
        btn_run_stop <= '1';
        wait for CLK_PERIOD;
        btn_run_stop <= '0';
        wait for CLK_PERIOD * 300;

        assert is_running = '0'
            report "FAIL: Should be stopped before step-sync test" severity error;

        start_count := gated_clk_count;

        -- Press step sync
        btn_step_sync <= '1';
        wait for CLK_PERIOD;
        btn_step_sync <= '0';

        -- Wait for SYNC to be detected (might take up to 2 full cycles)
        wait for CLK_PERIOD * 500;

        -- Should have stopped
        assert is_running = '0'
            report "FAIL: Should have stopped after step-sync" severity error;

        elapsed := gated_clk_count - start_count;
        report "Step-to-SYNC advanced " & integer'image(elapsed) & " clocks" severity note;

        -- Should have stopped at SYNC boundary (phi1 next)
        assert next_is_phi1 = '1'
            report "FAIL: Step-sync should stop with phi1 next" severity error;
        report "PASS: Step-to-SYNC completed correctly" severity note;

        -----------------------------------------------------------------------
        -- Test Complete
        -----------------------------------------------------------------------
        report "=== All Tests Completed ===" severity note;
        sim_done <= true;
        wait;
    end process;

end architecture sim;

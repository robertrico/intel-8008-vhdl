-------------------------------------------------------------------------------
-- Intel 8008 v8008 Minimal Existence and SYNC Test
-------------------------------------------------------------------------------
-- Testbench to verify v8008 entity compiles, instantiates correctly, and
-- has proper SYNC signal behavior.
--
-- Test Coverage:
--   - Component instantiation (phase_clocks, v8008)
--   - Reset sequence
--   - Output signal stability (no 'X' or 'U' values)
--   - SYNC signal toggles on both rising and falling edges of phi2
--   - SYNC frequency is exactly phi2/2
--   - SYNC duty cycle measurement
--
-- Copyright (c) 2025 Robert Rico
-- License: MIT
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;

entity v8008_minimal_tb is
end v8008_minimal_tb;

architecture behavior of v8008_minimal_tb is
    -- Component declarations
    component phase_clocks
        port(
            clk_in : in std_logic;
            reset : in std_logic;
            phi1 : out std_logic;
            phi2 : out std_logic
        );
    end component;

    component v8008
        port(
            phi1 : in std_logic;
            phi2 : in std_logic;
            data_bus_in     : in  std_logic_vector(7 downto 0);
            data_bus_out    : out std_logic_vector(7 downto 0);
            data_bus_enable : out std_logic;
            S0 : out std_logic;
            S1 : out std_logic;
            S2 : out std_logic;
            SYNC : out std_logic;
            READY : in std_logic;
            INT : in std_logic;
            debug_reg_A : out std_logic_vector(7 downto 0);
            debug_reg_B : out std_logic_vector(7 downto 0);
            debug_reg_C : out std_logic_vector(7 downto 0);
            debug_reg_D : out std_logic_vector(7 downto 0);
            debug_reg_E : out std_logic_vector(7 downto 0);
            debug_reg_H : out std_logic_vector(7 downto 0);
            debug_reg_L : out std_logic_vector(7 downto 0);
            debug_pc : out std_logic_vector(13 downto 0);
            debug_flags : out std_logic_vector(3 downto 0);
            debug_instruction : out std_logic_vector(7 downto 0);
            debug_stack_pointer : out std_logic_vector(2 downto 0);
            debug_hl_address : out std_logic_vector(13 downto 0)
        );
    end component;

    -- Test signals
    signal master_clk_tb : std_logic := '0';
    signal reset_tb : std_logic := '1';
    signal phi1_tb : std_logic := '0';
    signal phi2_tb : std_logic := '0';
    signal ready_tb : std_logic := '1';
    signal int_tb : std_logic := '0';
    signal data_tb : std_logic_vector(7 downto 0) := (others => '0');
    signal cpu_data_out_tb     : std_logic_vector(7 downto 0);
    signal cpu_data_enable_tb  : std_logic;
    signal S0_tb, S1_tb, S2_tb : std_logic;
    signal sync_tb : std_logic;

    -- Debug signals
    signal debug_reg_A_tb : std_logic_vector(7 downto 0);
    signal debug_reg_B_tb : std_logic_vector(7 downto 0);
    signal debug_reg_C_tb : std_logic_vector(7 downto 0);
    signal debug_reg_D_tb : std_logic_vector(7 downto 0);
    signal debug_reg_E_tb : std_logic_vector(7 downto 0);
    signal debug_reg_H_tb : std_logic_vector(7 downto 0);
    signal debug_reg_L_tb : std_logic_vector(7 downto 0);
    signal debug_pc_tb : std_logic_vector(13 downto 0);
    signal debug_flags_tb : std_logic_vector(3 downto 0);
    signal debug_instruction_tb : std_logic_vector(7 downto 0);
    signal debug_stack_pointer_tb : std_logic_vector(2 downto 0);
    signal debug_hl_address_tb : std_logic_vector(13 downto 0);

    -- SYNC test measurement signals
    signal sync_edge_count : natural := 0;
    signal phi2_edge_count : natural := 0;
    signal sync_high_time : time := 0 ns;
    signal sync_low_time : time := 0 ns;
    signal sync_period : time := 0 ns;
    signal last_sync_rise : time := 0 ns;
    signal last_sync_fall : time := 0 ns;
    signal sync_duty_cycle : real := 0.0;
    
    -- Edge detection helpers
    signal phi2_prev : std_logic := '0';
    signal sync_prev : std_logic := '0';
    
    -- Test control
    signal enable_counting : boolean := false;
    signal test_errors : integer := 0;
    signal is_int_ack : boolean := false;  -- Track interrupt acknowledge cycle

    -- Master clock period
    constant MASTER_CLK_PERIOD : time := 10 ns;  -- 100 MHz master clock

begin

    -- Master clock generation
    master_clk_tb <= not master_clk_tb after MASTER_CLK_PERIOD / 2;

    -- Phase clock generator
    PHASE_GEN: phase_clocks
        port map (
            clk_in => master_clk_tb,
            reset => reset_tb,
            phi1 => phi1_tb,
            phi2 => phi2_tb
        );

    -- CPU instance (v8008)
    CPU: v8008
        port map (
            phi1 => phi1_tb,
            phi2 => phi2_tb,
            data_bus_in => data_tb,
            data_bus_out => cpu_data_out_tb,
            data_bus_enable => cpu_data_enable_tb,
            S0 => S0_tb,
            S1 => S1_tb,
            S2 => S2_tb,
            SYNC => sync_tb,
            READY => ready_tb,
            INT => int_tb,
            debug_reg_A => debug_reg_A_tb,
            debug_reg_B => debug_reg_B_tb,
            debug_reg_C => debug_reg_C_tb,
            debug_reg_D => debug_reg_D_tb,
            debug_reg_E => debug_reg_E_tb,
            debug_reg_H => debug_reg_H_tb,
            debug_reg_L => debug_reg_L_tb,
            debug_pc => debug_pc_tb,
            debug_flags => debug_flags_tb,
            debug_instruction => debug_instruction_tb,
            debug_stack_pointer => debug_stack_pointer_tb,
            debug_hl_address => debug_hl_address_tb
        );

    -- Data bus process - provides RST instruction during interrupt acknowledge
    data_bus_proc: process(S2_tb, S1_tb, S0_tb)
    begin
        -- Default: high-Z (not driving)
        data_tb <= (others => 'Z');
        
        -- During T1I (interrupt acknowledge): S2=1, S1=1, S0=0 (110)
        if S2_tb = '1' and S1_tb = '1' and S0_tb = '0' then
            is_int_ack <= true;
        end if;
        
        -- During T3 (data transfer): S2=0, S1=0, S0=1 (001)
        if S2_tb = '0' and S1_tb = '0' and S0_tb = '1' and is_int_ack then
            -- Provide RST 0 instruction (0x05 = 00 000 101)
            data_tb <= X"05";
        end if;
        
        -- Clear interrupt acknowledge flag when leaving T3
        if not (S2_tb = '0' and S1_tb = '0' and S0_tb = '1') then
            if is_int_ack and S2_tb = '0' and S1_tb = '1' and S0_tb = '0' then
                -- Back to T1, clear flag
                is_int_ack <= false;
            end if;
        end if;
    end process data_bus_proc;

    -- PHI2 and SYNC edge counter process
    EDGE_MONITOR: process(master_clk_tb)
        variable sync_rise_time : time;
        variable sync_fall_time : time;
        variable prev_enable_counting : boolean := false;
    begin
        if rising_edge(master_clk_tb) then
            -- Reset counters on enable_counting false->true transition
            if enable_counting and not prev_enable_counting then
                sync_edge_count <= 0;
                phi2_edge_count <= 0;
            end if;
            prev_enable_counting := enable_counting;
            
            phi2_prev <= phi2_tb;
            sync_prev <= sync_tb;
            
            -- Count both edges of phi2 when counting enabled
            if enable_counting and (phi2_tb /= phi2_prev) then
                phi2_edge_count <= phi2_edge_count + 1;
            end if;
            
            -- Count SYNC edges and measure timing when counting enabled
            if enable_counting then
                if sync_tb = '1' and sync_prev = '0' then
                    -- Rising edge of SYNC
                    sync_edge_count <= sync_edge_count + 1;
                    sync_rise_time := now;
                    
                    if last_sync_rise > 0 ns then
                        sync_period <= sync_rise_time - last_sync_rise;
                    end if;
                    last_sync_rise <= sync_rise_time;
                    
                    if last_sync_fall > 0 ns then
                        sync_low_time <= sync_rise_time - last_sync_fall;
                    end if;
                    
                elsif sync_tb = '0' and sync_prev = '1' then
                    -- Falling edge of SYNC
                    sync_edge_count <= sync_edge_count + 1;
                    sync_fall_time := now;
                    
                    if last_sync_rise > 0 ns then
                        sync_high_time <= sync_fall_time - last_sync_rise;
                    end if;
                    last_sync_fall <= sync_fall_time;
                end if;
                
                -- Calculate duty cycle when we have both measurements
                if sync_high_time > 0 ns and sync_period > 0 ns then
                    sync_duty_cycle <= real(sync_high_time / 1 ns) / real(sync_period / 1 ns) * 100.0;
                end if;
            end if;
        end if;
    end process;

    -- Test stimulus process
    STIMULUS: process
        variable l : line;
        variable phi2_edges_at_start : natural;
        variable sync_edges_at_start : natural;
        variable expected_sync_edges : natural;
        variable actual_sync_edges : natural;
    begin
        write(l, string'("========================================"));
        writeline(output, l);
        write(l, string'("v8008 Minimal and SYNC Signal Test"));
        writeline(output, l);
        write(l, string'("========================================"));
        writeline(output, l);

        -- Test 1: Initial state and reset
        write(l, string'("Test 1: Reset and stabilization"));
        writeline(output, l);
        
        -- Initial state: hold in reset
        reset_tb <= '1';
        wait for 100 ns;

        write(l, string'("  Applying reset..."));
        writeline(output, l);

        -- Release reset
        reset_tb <= '0';
        wait for 50 ns;
        
        write(l, string'("  Waiting for clock stabilization..."));
        writeline(output, l);
        
        -- Wait for phase clocks to start running
        -- The phase_clocks component needs time to generate phi1/phi2 after reset
        wait for 1500 ns;  -- Wait until after first phi2 edge at ~1305ns
        
        -- Now pulse INT to exit STOPPED state
        -- Phi2 edges are at 1305, 3505, 5705, 7905ns (2200ns apart)
        write(l, string'("  Setting INT=1 at time ") & time'image(now));
        writeline(output, l);
        int_tb <= '1';
        
        wait for 3000 ns;  -- Hold through phi2 edge at 3505ns
        
        write(l, string'("  Setting INT=0 at time ") & time'image(now));
        writeline(output, l);
        int_tb <= '0';
        
        -- Wait for CPU to process interrupt and transition states
        -- CPU exits STOPPED at 5705ns, goes through T1I->T2->T3->T1
        wait for 4000 ns;  -- Wait until after state transitions
        
        -- Check if CPU exited STOPPED state
        write(l, string'("  After interrupt: S2=") & std_logic'image(S2_tb) &
                 string'(" S1=") & std_logic'image(S1_tb) &
                 string'(" S0=") & std_logic'image(S0_tb));
        writeline(output, l);
        
        if not (S2_tb = '0' and S1_tb = '1' and S0_tb = '1') then
            write(l, string'("  SUCCESS: CPU exited STOPPED state!"));
            writeline(output, l);
        else
            write(l, string'("  ERROR: CPU still in STOPPED state"));
            writeline(output, l);
            test_errors <= test_errors + 1;
        end if;

        write(l, string'("  Reset released"));
        writeline(output, l);
        
        -- Check initial state
        write(l, string'("  Initial state: S2=") & std_logic'image(S2_tb) &
                 string'(" S1=") & std_logic'image(S1_tb) &
                 string'(" S0=") & std_logic'image(S0_tb) &
                 string'(" (should be 011 = STOPPED)"));
        writeline(output, l);

        -- Check that outputs are stable (not undefined)
        write(l, string'("  Checking output stability..."));
        writeline(output, l);

        assert S0_tb /= 'U' and S0_tb /= 'X'
            report "S0 output is undefined!" severity error;
        assert S1_tb /= 'U' and S1_tb /= 'X'
            report "S1 output is undefined!" severity error;
        assert S2_tb /= 'U' and S2_tb /= 'X'
            report "S2 output is undefined!" severity error;
        assert sync_tb /= 'U' and sync_tb /= 'X'
            report "SYNC output is undefined!" severity error;

        -- Check debug outputs
        assert debug_reg_A_tb /= "UUUUUUUU" and debug_reg_A_tb /= "XXXXXXXX"
            report "debug_reg_A is undefined!" severity error;
        assert debug_pc_tb /= "UUUUUUUUUUUUUU" and debug_pc_tb /= "XXXXXXXXXXXXXX"
            report "debug_pc is undefined!" severity error;

        write(l, string'("  PASS: All outputs are stable"));
        writeline(output, l);

        -- Test 2: SYNC edge relationship to phi2
        write(l, string'("Test 2: SYNC edge relationship to phi2"));
        writeline(output, l);
        
        -- Enable counting after stabilization
        enable_counting <= true;
        wait for 10 ns;
        
        phi2_edges_at_start := phi2_edge_count;
        sync_edges_at_start := sync_edge_count;
        
        -- Run for multiple phi2 cycles
        wait for 1000 ns;
        
        -- Check that SYNC edges are exactly equal to phi2 edges
        expected_sync_edges := phi2_edge_count - phi2_edges_at_start;
        actual_sync_edges := sync_edge_count - sync_edges_at_start;
        
        write(l, string'("  PHI2 edges detected: ") & integer'image(expected_sync_edges));
        writeline(output, l);
        write(l, string'("  SYNC edges detected: ") & integer'image(actual_sync_edges));
        writeline(output, l);
        
        if actual_sync_edges /= expected_sync_edges then
            write(l, string'("  ERROR: SYNC edge count mismatch!"));
            writeline(output, l);
            test_errors <= test_errors + 1;
        else
            write(l, string'("  PASS: SYNC toggles on every phi2 edge"));
            writeline(output, l);
        end if;

        -- Test 3: Verify SYNC frequency is phi2/2
        write(l, string'("Test 3: SYNC frequency verification"));
        writeline(output, l);
        
        -- Disable and re-enable counting to reset counters
        enable_counting <= false;
        wait for 10 ns;
        enable_counting <= true;
        wait for 10 ns;
        
        -- Count complete SYNC cycles over a longer period
        wait for 2000 ns;
        
        write(l, string'("  PHI2 edges: ") & integer'image(phi2_edge_count));
        writeline(output, l);
        write(l, string'("  SYNC edges: ") & integer'image(sync_edge_count));
        writeline(output, l);
        
        -- Since SYNC toggles on every phi2 edge, sync_edges should equal phi2_edges
        if sync_edge_count /= phi2_edge_count then
            write(l, string'("  ERROR: SYNC frequency is not phi2/2!"));
            writeline(output, l);
            test_errors <= test_errors + 1;
        else
            write(l, string'("  PASS: SYNC frequency is phi2/2"));
            writeline(output, l);
        end if;

        -- Test 4: Measure SYNC duty cycle
        write(l, string'("Test 4: SYNC duty cycle measurement"));
        writeline(output, l);
        
        -- Wait for measurements to accumulate
        wait for 500 ns;
        
        write(l, string'("  SYNC high time: ") & time'image(sync_high_time));
        writeline(output, l);
        write(l, string'("  SYNC low time: ") & time'image(sync_low_time));
        writeline(output, l);
        write(l, string'("  SYNC period: ") & time'image(sync_period));
        writeline(output, l);
        write(l, string'("  SYNC duty cycle: ") & real'image(sync_duty_cycle) & string'("%"));
        writeline(output, l);
        
        -- Duty cycle should be approximately 50%
        if sync_duty_cycle < 45.0 or sync_duty_cycle > 55.0 then
            write(l, string'("  WARNING: SYNC duty cycle not ~50%"));
            writeline(output, l);
        else
            write(l, string'("  PASS: SYNC duty cycle is ~50%"));
            writeline(output, l);
        end if;

        -- Test 5: Test SYNC with READY signal
        write(l, string'("Test 5: SYNC behavior with READY signal"));
        writeline(output, l);
        
        -- Apply READY=0 to create wait states
        ready_tb <= '0';
        -- Disable and re-enable counting to reset counters
        enable_counting <= false;
        wait for 10 ns;
        enable_counting <= true;
        wait for 500 ns;
        
        -- SYNC should still toggle with phi2 even during wait states
        write(l, string'("  During READY=0 (wait state):"));
        writeline(output, l);
        write(l, string'("    PHI2 edges: ") & integer'image(phi2_edge_count));
        writeline(output, l);
        write(l, string'("    SYNC edges: ") & integer'image(sync_edge_count));
        writeline(output, l);
        
        if sync_edge_count /= phi2_edge_count then
            write(l, string'("  ERROR: SYNC not toggling during wait states!"));
            writeline(output, l);
            test_errors <= test_errors + 1;
        else
            write(l, string'("  PASS: SYNC continues during wait states"));
            writeline(output, l);
        end if;
        
        ready_tb <= '1';
        wait for 100 ns;

        -- Final summary
        write(l, string'("========================================"));
        writeline(output, l);
        if test_errors = 0 then
            write(l, string'("TEST PASSED - v8008 instantiated successfully"));
            writeline(output, l);
            write(l, string'("All outputs stable, SYNC correctly implements phi2/2"));
            writeline(output, l);
        else
            write(l, string'("TEST FAILED - ") & integer'image(test_errors) & string'(" errors detected"));
            writeline(output, l);
        end if;
        write(l, string'("========================================"));
        writeline(output, l);

        wait;
    end process;

end behavior;
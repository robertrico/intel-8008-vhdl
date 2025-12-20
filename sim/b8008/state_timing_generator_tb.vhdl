--------------------------------------------------------------------------------
-- state_timing_generator_tb.vhdl
--------------------------------------------------------------------------------
-- Testbench for state_timing_generator
-- Tests: T1-T5 progression, T1I interrupt handling, state skipping
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.b8008_types.all;

entity state_timing_generator_tb is
end entity state_timing_generator_tb;

architecture test of state_timing_generator_tb is

    component state_timing_generator is
        port (
            phi1                  : in  std_logic;
            phi2                  : in  std_logic;
            advance_state         : in  std_logic;
            interrupt_pending     : in  std_logic;
            ready                 : in  std_logic;
            instr_is_hlt_flag     : in  std_logic;
            transition_to_stopped : in  std_logic;
            state_t1              : out std_logic;
            state_t2              : out std_logic;
            state_t3              : out std_logic;
            state_t4              : out std_logic;
            state_t5              : out std_logic;
            state_t1i             : out std_logic;
            state_stopped         : out std_logic;
            state_half            : out std_logic;
            status_s0             : out std_logic;
            status_s1             : out std_logic;
            status_s2             : out std_logic
        );
    end component;

    signal phi1                  : std_logic := '0';
    signal phi2                  : std_logic := '0';
    signal advance_state         : std_logic := '0';
    signal interrupt_pending     : std_logic := '0';
    signal ready                 : std_logic := '1';
    signal instr_is_hlt_flag     : std_logic := '0';
    signal transition_to_stopped : std_logic := '0';
    signal state_t1              : std_logic;
    signal state_t2              : std_logic;
    signal state_t3              : std_logic;
    signal state_t4              : std_logic;
    signal state_t5              : std_logic;
    signal state_t1i             : std_logic;
    signal state_stopped         : std_logic;
    signal state_half            : std_logic;
    signal status_s0             : std_logic;
    signal status_s1             : std_logic;
    signal status_s2             : std_logic;

    constant CLK_PERIOD : time := 10 ns;
    constant PHI1_WIDTH : time := 80 ns;
    constant PHI2_WIDTH : time := 60 ns;
    constant DEAD_TIME : time := 40 ns;

    signal done : boolean := false;

begin

    uut : state_timing_generator
        port map (
            phi1                  => phi1,
            phi2                  => phi2,
            advance_state         => advance_state,
            interrupt_pending     => interrupt_pending,
            ready                 => ready,
            instr_is_hlt_flag     => instr_is_hlt_flag,
            transition_to_stopped => transition_to_stopped,
            state_t1              => state_t1,
            state_t2              => state_t2,
            state_t3              => state_t3,
            state_t4              => state_t4,
            state_t5              => state_t5,
            state_t1i             => state_t1i,
            state_stopped         => state_stopped,
            state_half            => state_half,
            status_s0             => status_s0,
            status_s1             => status_s1,
            status_s2             => status_s2
        );

    -- Clock generation process (generates phi1 and phi2 non-overlapping clocks)
    process
    begin
        while not done loop
            -- PHI1 pulse
            phi1 <= '1';
            wait for PHI1_WIDTH;
            phi1 <= '0';
            wait for DEAD_TIME;

            -- PHI2 pulse
            phi2 <= '1';
            wait for PHI2_WIDTH;
            phi2 <= '0';
            wait for DEAD_TIME;
        end loop;
        wait;
    end process;

    -- Test stimulus
    process
        variable errors : integer := 0;
        constant T_CY : time := PHI1_WIDTH + DEAD_TIME + PHI2_WIDTH + DEAD_TIME;  -- One complete clock cycle
    begin
        report "========================================";
        report "State Timing Generator Test";
        report "========================================";

        wait for T_CY / 2;

        -- Test 0: Verify initial STOPPED state
        report "Test 0: Initial STOPPED state";
        if state_stopped /= '1' then
            report "  ERROR: Should start in STOPPED" severity error;
            errors := errors + 1;
        else
            report "  PASS: Started in STOPPED state";
        end if;

        -- Test 1: Exit STOPPED via interrupt, then T1I->T2->T3->T4->T5->T1
        report "";
        report "Test 1: Exit STOPPED via interrupt, full cycle";

        -- Trigger interrupt to exit STOPPED
        interrupt_pending <= '1';
        wait for T_CY * 2;  -- Should transition to T1I

        if state_t1i /= '1' then
            report "  ERROR: Should enter T1I from STOPPED" severity error;
            errors := errors + 1;
        else
            report "  PASS: Entered T1I from STOPPED";
        end if;

        interrupt_pending <= '0';

        -- T1I -> T2
        wait for T_CY * 2;
        if state_t2 /= '1' then
            report "  ERROR: Should advance to T2" severity error;
            errors := errors + 1;
        else
            report "  PASS: Advanced to T2";
        end if;

        -- T2 -> T3
        wait for T_CY * 2;
        if state_t3 /= '1' then
            report "  ERROR: Should advance to T3" severity error;
            errors := errors + 1;
        else
            report "  PASS: Advanced to T3";
        end if;

        -- T3 -> T4 (no advance_state, so continue to T4)
        wait for T_CY * 2;
        if state_t4 /= '1' then
            report "  ERROR: Should advance to T4" severity error;
            errors := errors + 1;
        else
            report "  PASS: Advanced to T4";
        end if;

        -- T4 -> T5 (no advance_state, so continue to T5)
        wait for T_CY * 2;
        if state_t5 /= '1' then
            report "  ERROR: Should advance to T5" severity error;
            errors := errors + 1;
        else
            report "  PASS: Advanced to T5";
        end if;

        -- T5 -> T1 (no interrupt pending)
        wait for T_CY * 2;
        if state_t1 /= '1' then
            report "  ERROR: Should return to T1" severity error;
            errors := errors + 1;
        else
            report "  PASS: Returned to T1";
        end if;

        -- Test 2: Skip from T3 to T1 (short instruction)
        report "";
        report "Test 2: Skip from T3 to T1 (short instruction)";

        -- T1 -> T2
        wait for T_CY * 2;
        -- T2 -> T3
        wait for T_CY * 2;

        -- At T3, signal advance_state to skip to T1
        advance_state <= '1';
        wait for T_CY * 2;  -- Should go to T1

        if state_t1 /= '1' then
            report "  ERROR: Should skip to T1 after T3" severity error;
            errors := errors + 1;
        else
            report "  PASS: Skipped from T3 to T1";
        end if;

        advance_state <= '0';

        -- Test 3: Interrupt after T5 (go to T1I instead of T1)
        report "";
        report "Test 3: Interrupt after T5 (go to T1I)";

        -- Go through full cycle: T1->T2->T3->T4->T5
        wait for T_CY * 2;  -- T2
        wait for T_CY * 2;  -- T3
        wait for T_CY * 2;  -- T4
        wait for T_CY * 2;  -- T5

        -- Set interrupt pending before T5 ends
        interrupt_pending <= '1';
        wait for T_CY * 2;

        if state_t1i /= '1' then
            report "  ERROR: Should go to T1I when interrupt pending" severity error;
            errors := errors + 1;
        else
            report "  PASS: Entered T1I state";
        end if;

        interrupt_pending <= '0';

        -- T1I should proceed to T2
        wait for T_CY * 2;

        if state_t2 /= '1' then
            report "  ERROR: T1I should advance to T2" severity error;
            errors := errors + 1;
        else
            report "  PASS: T1I advanced to T2";
        end if;

        -- Test 4: HLT instruction (transition_to_stopped at T3)
        report "";
        report "Test 4: HLT instruction (STOPPED at T3)";

        -- Complete current instruction: T2->T3
        wait for T_CY * 2;  -- T3

        -- At T3, signal HLT
        transition_to_stopped <= '1';
        wait for T_CY * 2;  -- Should go to STOPPED

        if state_stopped /= '1' then
            report "  ERROR: Should enter STOPPED after HLT at T3" severity error;
            errors := errors + 1;
        else
            report "  PASS: Entered STOPPED state (HLT)";
        end if;

        transition_to_stopped <= '0';

        -- Test 5: Wake from STOPPED via interrupt
        report "";
        report "Test 5: Wake from STOPPED via interrupt";

        -- Should still be in STOPPED
        wait for T_CY * 2;
        if state_stopped /= '1' then
            report "  ERROR: Should remain in STOPPED without interrupt" severity error;
            errors := errors + 1;
        else
            report "  PASS: Remained in STOPPED";
        end if;

        -- Trigger interrupt to wake
        interrupt_pending <= '1';
        wait for T_CY * 2;

        if state_t1i /= '1' then
            report "  ERROR: Should wake to T1I on interrupt" severity error;
            errors := errors + 1;
        else
            report "  PASS: Woke to T1I from STOPPED";
        end if;

        interrupt_pending <= '0';

        -- Summary
        report "";
        report "========================================";
        if errors = 0 then
            report "*** ALL TESTS PASSED ***";
        else
            report "*** TESTS FAILED: " & integer'image(errors) & " errors ***" severity error;
        end if;
        report "========================================";

        done <= true;
        wait;
    end process;

end architecture test;

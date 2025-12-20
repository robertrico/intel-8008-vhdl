--------------------------------------------------------------------------------
-- machine_cycle_control_tb.vhdl
--------------------------------------------------------------------------------
-- Testbench for machine_cycle_control
-- Tests: Cycle sequencing, D6/D7 output during T2, advance_state signaling
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.b8008_types.all;

entity machine_cycle_control_tb is
end entity machine_cycle_control_tb;

architecture test of machine_cycle_control_tb is

    component machine_cycle_control is
        port (
            -- State inputs from State Timing Generator
            state_t1  : in std_logic;
            state_t2  : in std_logic;
            state_t3  : in std_logic;
            state_t4  : in std_logic;
            state_t5  : in std_logic;
            state_t1i : in std_logic;

            -- Instruction decoder inputs
            instr_needs_immediate : in std_logic;  -- Instruction needs 2nd byte
            instr_needs_address   : in std_logic;  -- Instruction needs 14-bit address (2 bytes)
            instr_is_io           : in std_logic;  -- I/O operation
            instr_is_write        : in std_logic;  -- Memory write operation
            instr_is_hlt          : in std_logic;  -- HLT (halt) instruction
            instr_needs_t4t5      : in std_logic;  -- Instruction needs T4/T5 extended states
            eval_condition        : in std_logic;  -- Conditional instruction
            condition_met         : in std_logic;  -- Condition result

            -- Outputs to State Timing Generator
            advance_state     : out std_logic;  -- Signal to skip to next instruction
            instr_is_hlt_flag : out std_logic;  -- Latched HLT flag for state machine

            -- Outputs to Memory & I/O Control (cycle type)
            cycle_type : out std_logic_vector(1 downto 0);  -- D6, D7 (only valid during T2)

            -- Cycle tracking (for observation/debug)
            current_cycle : out integer range 1 to 3  -- Which cycle of instruction (1, 2, or 3)
        );
    end component;

    -- Inputs
    signal state_t1  : std_logic := '0';
    signal state_t2  : std_logic := '0';
    signal state_t3  : std_logic := '0';
    signal state_t4  : std_logic := '0';
    signal state_t5  : std_logic := '0';
    signal state_t1i : std_logic := '0';

    signal instr_needs_immediate : std_logic := '0';
    signal instr_needs_address   : std_logic := '0';
    signal instr_is_io           : std_logic := '0';
    signal instr_is_write        : std_logic := '0';
    signal instr_is_hlt          : std_logic := '0';
    signal instr_needs_t4t5      : std_logic := '0';
    signal eval_condition        : std_logic := '0';
    signal condition_met         : std_logic := '0';

    -- Outputs
    signal advance_state     : std_logic;
    signal instr_is_hlt_flag : std_logic;
    signal cycle_type        : std_logic_vector(1 downto 0);
    signal current_cycle     : integer range 1 to 3;

    -- Test control
    signal done : boolean := false;

    -- Helper procedure to simulate one complete state
    -- Returns state high, then caller checks, then we drop state
    procedure enter_state(signal st: out std_logic) is
    begin
        st <= '1';
        wait for 50 ns;  -- Wait for rising edge to be processed
    end procedure;

    procedure exit_state(signal st: out std_logic) is
    begin
        wait for 50 ns;  -- Finish state duration
        st <= '0';
        wait for 10 ns;  -- Gap between states
    end procedure;

    -- Legacy procedure for compatibility
    procedure simulate_state(signal st: out std_logic) is
    begin
        st <= '1';
        wait for 100 ns;  -- State duration
        st <= '0';
        wait for 10 ns;   -- Gap between states
    end procedure;

begin

    uut : machine_cycle_control
        port map (
            state_t1              => state_t1,
            state_t2              => state_t2,
            state_t3              => state_t3,
            state_t4              => state_t4,
            state_t5              => state_t5,
            state_t1i             => state_t1i,
            instr_needs_immediate => instr_needs_immediate,
            instr_needs_address   => instr_needs_address,
            instr_is_io           => instr_is_io,
            instr_is_write        => instr_is_write,
            instr_is_hlt          => instr_is_hlt,
            instr_needs_t4t5      => instr_needs_t4t5,
            eval_condition        => eval_condition,
            condition_met         => condition_met,
            advance_state         => advance_state,
            instr_is_hlt_flag     => instr_is_hlt_flag,
            cycle_type            => cycle_type,
            current_cycle         => current_cycle
        );

    -- Test stimulus
    process
        variable errors : integer := 0;
    begin
        report "========================================";
        report "Machine Cycle Control Test";
        report "========================================";

        wait for 50 ns;

        -- Test 1: Single-cycle instruction (T1-T2-T3-T4)
        report "";
        report "Test 1: Single-cycle instruction (e.g., MOV A,B)";
        report "  Should: Cycle 1 (PCI), advance_state during T4 (short cycle)";

        -- Setup: instruction needs nothing extra, no T4/T5 extended
        instr_needs_immediate <= '0';
        instr_needs_address <= '0';
        instr_is_io <= '0';
        instr_is_write <= '0';
        instr_is_hlt <= '0';
        instr_needs_t4t5 <= '0';

        -- Simulate Cycle 1: PCI
        simulate_state(state_t1);
        if current_cycle /= 1 then
            report "  ERROR: Should be in cycle 1" severity error;
            errors := errors + 1;
        end if;

        simulate_state(state_t2);
        if cycle_type /= "00" then  -- PCI = 00
            report "  ERROR: T2 of cycle 1 should output PCI (00), got " &
                   std_logic'image(cycle_type(1)) & std_logic'image(cycle_type(0)) severity error;
            errors := errors + 1;
        else
            report "  PASS: T2 outputs PCI (00)";
        end if;

        simulate_state(state_t3);
        -- advance_state should NOT be set yet for cycle 1 (waits for T4)
        if advance_state = '1' then
            report "  ERROR: advance_state should not be set at T3 for cycle 1" severity error;
            errors := errors + 1;
        else
            report "  PASS: advance_state not set at T3 (cycle 1 continues to T4)";
        end if;

        -- Use enter/exit to check DURING T4
        enter_state(state_t4);
        -- Check during T4 (after rising edge has been processed)
        if advance_state /= '1' then
            report "  ERROR: Should signal advance_state during T4, got " &
                   std_logic'image(advance_state) severity error;
            errors := errors + 1;
        else
            report "  PASS: advance_state signaled during T4";
        end if;
        exit_state(state_t4);

        -- Test 2: Two-cycle instruction (8 states: needs immediate byte)
        report "";
        report "Test 2: Two-cycle instruction (e.g., MVI A, data)";
        report "  Should: Cycle 1 (PCI), Cycle 2 (PCR), then advance";

        -- Reset for new instruction
        wait for 50 ns;
        instr_needs_immediate <= '1';
        instr_needs_address <= '0';

        -- Cycle 1: PCI (fetch instruction)
        simulate_state(state_t1);
        simulate_state(state_t2);
        if cycle_type /= "00" then
            report "  ERROR: Cycle 1 T2 should be PCI (00)" severity error;
            errors := errors + 1;
        end if;

        simulate_state(state_t3);
        if advance_state = '1' then
            report "  ERROR: Should NOT advance after T3 (needs 2nd cycle)" severity error;
            errors := errors + 1;
        end if;

        simulate_state(state_t4);
        simulate_state(state_t5);

        -- Cycle 2: PCR (fetch immediate data)
        simulate_state(state_t1);
        if current_cycle /= 2 then
            report "  ERROR: Should be in cycle 2" severity error;
            errors := errors + 1;
        else
            report "  PASS: Entered cycle 2";
        end if;

        simulate_state(state_t2);
        if cycle_type /= "01" then  -- PCR = 01
            report "  ERROR: Cycle 2 T2 should be PCR (01), got " &
                   std_logic'image(cycle_type(1)) & std_logic'image(cycle_type(0)) severity error;
            errors := errors + 1;
        else
            report "  PASS: T2 outputs PCR (01)";
        end if;

        simulate_state(state_t3);
        if advance_state /= '1' then
            report "  ERROR: Should advance after cycle 2 T3" severity error;
            errors := errors + 1;
        else
            report "  PASS: advance_state signaled after cycle 2";
        end if;

        -- Test 3: Three-cycle instruction (11 states: needs 14-bit address)
        report "";
        report "Test 3: Three-cycle instruction (e.g., JMP addr)";
        report "  Should: Cycle 1 (PCI), Cycle 2 (PCR), Cycle 3 (PCR)";

        wait for 50 ns;
        instr_needs_immediate <= '0';
        instr_needs_address <= '1';

        -- Cycle 1: PCI
        simulate_state(state_t1);
        simulate_state(state_t2);
        if cycle_type /= "00" then
            report "  ERROR: Cycle 1 should be PCI" severity error;
            errors := errors + 1;
        end if;
        simulate_state(state_t3);
        simulate_state(state_t4);
        simulate_state(state_t5);

        -- Cycle 2: PCR (low byte of address)
        simulate_state(state_t1);
        simulate_state(state_t2);
        if cycle_type /= "01" then
            report "  ERROR: Cycle 2 should be PCR" severity error;
            errors := errors + 1;
        end if;
        simulate_state(state_t3);
        if advance_state = '1' then
            report "  ERROR: Should NOT advance after cycle 2 (needs cycle 3)" severity error;
            errors := errors + 1;
        end if;
        simulate_state(state_t4);
        simulate_state(state_t5);

        -- Cycle 3: PCR (high byte of address)
        simulate_state(state_t1);
        if current_cycle /= 3 then
            report "  ERROR: Should be in cycle 3" severity error;
            errors := errors + 1;
        else
            report "  PASS: Entered cycle 3";
        end if;

        simulate_state(state_t2);
        if cycle_type /= "01" then
            report "  ERROR: Cycle 3 should be PCR" severity error;
            errors := errors + 1;
        else
            report "  PASS: Cycle 3 T2 outputs PCR";
        end if;

        simulate_state(state_t3);
        if advance_state /= '1' then
            report "  ERROR: Should advance after cycle 3" severity error;
            errors := errors + 1;
        else
            report "  PASS: advance_state signaled after cycle 3";
        end if;

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

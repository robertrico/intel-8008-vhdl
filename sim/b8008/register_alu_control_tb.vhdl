--------------------------------------------------------------------------------
-- register_alu_control_tb.vhdl
--------------------------------------------------------------------------------
-- Testbench for Register and ALU Control
-- Tests: Control signal generation for Reg.a, Reg.b, ALU, and Flags
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.b8008_types.all;

entity register_alu_control_tb is
end entity register_alu_control_tb;

architecture test of register_alu_control_tb is

    -- Component declaration
    component register_alu_control is
        port (
            -- Clock input from Clock Generator
            phi2 : in std_logic;

            -- Status signals from State Timing Generator (encode T1-T5)
            status_s0 : in std_logic;
            status_s1 : in std_logic;
            status_s2 : in std_logic;

            -- Instruction decoder inputs
            instr_is_alu_op       : in std_logic;
            instr_uses_temp_regs  : in std_logic;
            instr_needs_immediate : in std_logic;
            instr_writes_reg      : in std_logic;

            -- Machine cycle control input
            current_cycle : in integer range 1 to 3;

            -- Interrupt input
            interrupt : in std_logic;

            -- Control outputs (load signals)
            load_reg_a   : out std_logic;
            load_reg_b   : out std_logic;
            alu_enable   : out std_logic;
            update_flags : out std_logic;

            -- Output enable signals
            output_reg_a  : out std_logic;
            output_reg_b  : out std_logic;
            output_result : out std_logic;
            output_flags  : out std_logic
        );
    end component;

    -- Clock signal
    signal phi2 : std_logic := '0';
    constant phi2_period : time := 500 ns;

    -- Inputs
    signal status_s0 : std_logic := '0';
    signal status_s1 : std_logic := '0';
    signal status_s2 : std_logic := '0';
    signal instr_is_alu_op       : std_logic := '0';
    signal instr_uses_temp_regs  : std_logic := '0';
    signal instr_needs_immediate : std_logic := '0';
    signal instr_writes_reg      : std_logic := '0';
    signal current_cycle : integer range 1 to 3 := 1;
    signal interrupt : std_logic := '0';

    -- Outputs
    signal load_reg_a   : std_logic;
    signal load_reg_b   : std_logic;
    signal alu_enable   : std_logic;
    signal update_flags : std_logic;
    signal output_reg_a  : std_logic;
    signal output_reg_b  : std_logic;
    signal output_result : std_logic;
    signal output_flags  : std_logic;

    -- Test control
    signal done : boolean := false;

    -- Helper procedure to set status signals for a given T-state
    -- Status signal encoding (S2, S1, S0) from state_timing_generator.vhdl:
    -- STOPPED: 011, T1:  010, T2:  100, T3:  001
    -- T4:  111, T5:  101, T1I: 110
    procedure set_state(
        signal s0, s1, s2 : out std_logic;
        constant state : in string(1 to 3)
    ) is
    begin
        case state is
            when "T1 " =>
                s2 <= '0'; s1 <= '1'; s0 <= '0';  -- 010
            when "T2 " =>
                s2 <= '1'; s1 <= '0'; s0 <= '0';  -- 100
            when "T3 " =>
                s2 <= '0'; s1 <= '0'; s0 <= '1';  -- 001
            when "T4 " =>
                s2 <= '1'; s1 <= '1'; s0 <= '1';  -- 111 (was 011, wrong!)
            when "T5 " =>
                s2 <= '1'; s1 <= '0'; s0 <= '1';  -- 101
            when "T1I" =>
                s2 <= '1'; s1 <= '1'; s0 <= '0';  -- 110
            when others =>
                s2 <= '0'; s1 <= '0'; s0 <= '0';
        end case;
    end procedure;

begin

    uut : register_alu_control
        port map (
            phi2                  => phi2,
            status_s0             => status_s0,
            status_s1             => status_s1,
            status_s2             => status_s2,
            instr_is_alu_op       => instr_is_alu_op,
            instr_uses_temp_regs  => instr_uses_temp_regs,
            instr_needs_immediate => instr_needs_immediate,
            instr_writes_reg      => instr_writes_reg,
            current_cycle         => current_cycle,
            interrupt             => interrupt,
            load_reg_a            => load_reg_a,
            load_reg_b            => load_reg_b,
            alu_enable            => alu_enable,
            update_flags          => update_flags,
            output_reg_a          => output_reg_a,
            output_reg_b          => output_reg_b,
            output_result         => output_result,
            output_flags          => output_flags
        );

    -- Clock generation
    phi2_process : process
    begin
        while not done loop
            phi2 <= '0';
            wait for phi2_period / 2;
            phi2 <= '1';
            wait for phi2_period / 2;
        end loop;
        wait;
    end process;

    -- Test stimulus
    test_process : process
        variable errors : integer := 0;
    begin
        report "========================================";
        report "Register and ALU Control Test";
        report "========================================";

        wait for 100 ns;

        -- Test 1: ALU OP r (single cycle, register operand)
        -- Pattern: C1 T4 (load operands), T5 (execute)
        report "";
        report "Test 1: ALU OP r (single cycle)";
        report "  Expected: Load Reg.a and Reg.b at T4, execute at T5";

        instr_is_alu_op <= '1';
        instr_uses_temp_regs <= '1';
        instr_needs_immediate <= '0';
        current_cycle <= 1;
        interrupt <= '0';

        -- T1: Address output (not relevant to ALU)
        set_state(status_s0, status_s1, status_s2, "T1 ");
        wait for phi2_period;

        -- T2: Address output (not relevant to ALU)
        set_state(status_s0, status_s1, status_s2, "T2 ");
        wait for phi2_period;

        -- T3: For register ALU ops, no temp reg loading at T3 (that's for immediate ops)
        set_state(status_s0, status_s1, status_s2, "T3 ");
        wait until phi2 = '1';  -- Wait for phi2 high
        wait for 10 ns;  -- Small delay for signals to settle
        if load_reg_b = '1' then
            report "  ERROR: load_reg_b should NOT be high at T3 for register ALU op" severity error;
            errors := errors + 1;
        else
            report "  PASS: load_reg_b not asserted at T3 (register ALU ops load at T4)";
        end if;
        wait until phi2 = '0';  -- Wait for phi2 to go low
        wait for phi2_period / 2;  -- Wait for next state

        -- T4: Load SSS to Reg.b, load accumulator to Reg.a
        set_state(status_s0, status_s1, status_s2, "T4 ");
        wait until phi2 = '1';
        wait for 10 ns;
        if load_reg_a /= '1' then
            report "  ERROR: load_reg_a should be high at T4" severity error;
            errors := errors + 1;
        end if;
        if load_reg_b /= '1' then
            report "  ERROR: load_reg_b should be high at T4" severity error;
            errors := errors + 1;
        end if;
        if load_reg_a = '1' and load_reg_b = '1' then
            report "  PASS: Both load_reg_a and load_reg_b asserted at T4";
        end if;
        wait until phi2 = '0';
        wait for phi2_period / 2;

        -- T5: Execute ALU operation
        set_state(status_s0, status_s1, status_s2, "T5 ");
        wait until phi2 = '1';
        wait for 10 ns;
        if alu_enable /= '1' then
            report "  ERROR: alu_enable should be high at T5" severity error;
            errors := errors + 1;
        else
            report "  PASS: alu_enable asserted at T5";
        end if;
        if update_flags /= '1' then
            report "  ERROR: update_flags should be high at T5" severity error;
            errors := errors + 1;
        else
            report "  PASS: update_flags asserted at T5";
        end if;
        wait until phi2 = '0';
        wait for phi2_period / 2;

        -- Test 2: ALU OP I (two cycles, immediate operand)
        -- Pattern: C2 T3 (load immediate to Reg.b), C2 T4 (load A to Reg.a), C2 T5 (execute)
        report "";
        report "Test 2: ALU OP I (two cycles, immediate)";
        report "  Expected: Load Reg.b at C2 T3, load Reg.a at C2 T4, execute at C2 T5";

        instr_is_alu_op <= '1';
        instr_uses_temp_regs <= '0';  -- Immediate ops don't use temp_regs at C1 T4
        instr_needs_immediate <= '1';
        current_cycle <= 1;
        wait for 100 ns;

        -- Cycle 1, T3: Fetch instruction (no temp reg loading for immediate ops at C1)
        set_state(status_s0, status_s1, status_s2, "T3 ");
        wait until phi2 = '1';
        wait for 10 ns;
        if load_reg_b = '1' then
            report "  ERROR: load_reg_b should NOT be high at C1 T3 for immediate ALU op" severity error;
            errors := errors + 1;
        else
            report "  PASS: load_reg_b not asserted at C1 T3";
        end if;
        wait until phi2 = '0';
        wait for phi2_period / 2;

        -- Move to Cycle 2
        current_cycle <= 2;
        wait for 100 ns;

        -- Cycle 2, T3: Fetch immediate data into Reg.b
        set_state(status_s0, status_s1, status_s2, "T3 ");
        wait until phi2 = '1';
        wait for 10 ns;
        if load_reg_b /= '1' then
            report "  ERROR: load_reg_b should be high at C2 T3" severity error;
            errors := errors + 1;
        else
            report "  PASS: load_reg_b asserted at C2 T3";
        end if;
        -- Reg.a is loaded at T4 for immediate ops, not T3
        if load_reg_a = '1' then
            report "  ERROR: load_reg_a should NOT be high at C2 T3 (loads at T4)" severity error;
            errors := errors + 1;
        else
            report "  PASS: load_reg_a not asserted at C2 T3 (will load at T4)";
        end if;
        wait until phi2 = '0';
        wait for phi2_period / 2;

        -- Cycle 2, T4: Load accumulator to Reg.a
        set_state(status_s0, status_s1, status_s2, "T4 ");
        wait until phi2 = '1';
        wait for 10 ns;
        if load_reg_a /= '1' then
            report "  ERROR: load_reg_a should be high at C2 T4" severity error;
            errors := errors + 1;
        else
            report "  PASS: load_reg_a asserted at C2 T4";
        end if;
        wait until phi2 = '0';
        wait for phi2_period / 2;

        -- Cycle 2, T5: Execute ALU
        set_state(status_s0, status_s1, status_s2, "T5 ");
        wait until phi2 = '1';
        wait for 10 ns;
        if alu_enable /= '1' then
            report "  ERROR: alu_enable should be high at C2 T5" severity error;
            errors := errors + 1;
        else
            report "  PASS: alu_enable asserted at C2 T5";
        end if;
        wait until phi2 = '0';
        wait for phi2_period / 2;

        -- Test 3: Non-ALU instruction (should not trigger ALU signals)
        report "";
        report "Test 3: Non-ALU instruction (e.g., MOV)";
        report "  Expected: No ALU control signals";

        instr_is_alu_op <= '0';  -- Not an ALU operation
        instr_uses_temp_regs <= '1';  -- MOV uses temp regs
        instr_needs_immediate <= '0';
        current_cycle <= 1;
        wait for 100 ns;

        set_state(status_s0, status_s1, status_s2, "T5 ");
        wait for phi2_period;
        if alu_enable = '1' then
            report "  ERROR: alu_enable should not be high for non-ALU instruction" severity error;
            errors := errors + 1;
        else
            report "  PASS: alu_enable not asserted for non-ALU instruction";
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

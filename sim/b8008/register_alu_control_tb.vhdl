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

            -- Instruction decoder input
            instr_is_alu_op : in std_logic;

            -- Machine cycle control input
            cycle_is_2 : in std_logic;  -- 0=cycle 1, 1=cycle 2

            -- Interrupt input
            interrupt : in std_logic;

            -- Control outputs
            load_reg_a   : out std_logic;  -- Latch data into temp Reg.a
            load_reg_b   : out std_logic;  -- Latch data into temp Reg.b
            alu_enable   : out std_logic;  -- Enable ALU execution
            update_flags : out std_logic   -- Latch condition flags
        );
    end component;

    -- Clock signal
    signal phi2 : std_logic := '0';
    constant phi2_period : time := 500 ns;

    -- Inputs
    signal status_s0 : std_logic := '0';
    signal status_s1 : std_logic := '0';
    signal status_s2 : std_logic := '0';
    signal instr_is_alu_op : std_logic := '0';
    signal cycle_is_2 : std_logic := '0';
    signal interrupt : std_logic := '0';

    -- Outputs
    signal load_reg_a   : std_logic;
    signal load_reg_b   : std_logic;
    signal alu_enable   : std_logic;
    signal update_flags : std_logic;

    -- Test control
    signal done : boolean := false;

    -- Helper procedure to set status signals for a given T-state
    -- Status signal encoding (S2, S1, S0):
    -- T1:  010, T2:  100, T3:  001
    -- T4:  011, T5:  101, T1I: 110
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
                s2 <= '0'; s1 <= '1'; s0 <= '1';  -- 011
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
            phi2              => phi2,
            status_s0         => status_s0,
            status_s1         => status_s1,
            status_s2         => status_s2,
            instr_is_alu_op   => instr_is_alu_op,
            cycle_is_2        => cycle_is_2,
            interrupt         => interrupt,
            load_reg_a        => load_reg_a,
            load_reg_b        => load_reg_b,
            alu_enable        => alu_enable,
            update_flags      => update_flags
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
        -- Pattern: C1 T3 (load IR), T4 (load operands), T5 (execute)
        report "";
        report "Test 1: ALU OP r (single cycle)";
        report "  Expected: Load Reg.b at T3 and T4, execute at T5";

        instr_is_alu_op <= '1';
        cycle_is_2 <= '0';  -- Cycle 1
        interrupt <= '0';

        -- T1: Address output (not relevant to ALU)
        set_state(status_s0, status_s1, status_s2, "T1 ");
        wait for phi2_period;

        -- T2: Address output (not relevant to ALU)
        set_state(status_s0, status_s1, status_s2, "T2 ");
        wait for phi2_period;

        -- T3: Fetch instruction to IR and Reg.b
        set_state(status_s0, status_s1, status_s2, "T3 ");
        wait until phi2 = '1';  -- Wait for phi2 high
        wait for 10 ns;  -- Small delay for signals to settle
        if load_reg_b /= '1' then
            report "  ERROR: load_reg_b should be high at T3" severity error;
            errors := errors + 1;
        else
            report "  PASS: load_reg_b asserted at T3";
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
        -- Pattern: C1 T3 (load IR), C2 T3 (load immediate), C2 T5 (execute)
        report "";
        report "Test 2: ALU OP I (two cycles, immediate)";
        report "  Expected: Load Reg.b at C1 T3 and C2 T3, execute at C2 T5";

        instr_is_alu_op <= '1';
        cycle_is_2 <= '0';  -- Start with Cycle 1
        wait for 100 ns;

        -- Cycle 1, T3: Fetch instruction
        set_state(status_s0, status_s1, status_s2, "T3 ");
        wait until phi2 = '1';
        wait for 10 ns;
        if load_reg_b /= '1' then
            report "  ERROR: load_reg_b should be high at C1 T3" severity error;
            errors := errors + 1;
        else
            report "  PASS: load_reg_b asserted at C1 T3";
        end if;
        wait until phi2 = '0';
        wait for phi2_period / 2;

        -- Move to Cycle 2
        cycle_is_2 <= '1';
        wait for 100 ns;

        -- Cycle 2, T3: Fetch immediate data
        set_state(status_s0, status_s1, status_s2, "T3 ");
        wait until phi2 = '1';
        wait for 10 ns;
        if load_reg_b /= '1' then
            report "  ERROR: load_reg_b should be high at C2 T3" severity error;
            errors := errors + 1;
        end if;
        if load_reg_a /= '1' then
            report "  ERROR: load_reg_a should be high at C2 T3" severity error;
            errors := errors + 1;
        end if;
        if load_reg_a = '1' and load_reg_b = '1' then
            report "  PASS: Both load_reg_a and load_reg_b asserted at C2 T3";
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
        cycle_is_2 <= '0';
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

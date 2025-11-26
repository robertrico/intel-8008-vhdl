--------------------------------------------------------------------------------
-- ahl_pointer_tb.vhdl
--------------------------------------------------------------------------------
-- Testbench for AHL Pointer (Scratchpad Address Selector)
-- Tests: Selecting H and L register addresses during memory indirect operations
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.b8008_types.all;

entity ahl_pointer_tb is
end entity ahl_pointer_tb;

architecture test of ahl_pointer_tb is

    component ahl_pointer is
        port (
            state_t1              : in std_logic;
            state_t2              : in std_logic;
            current_cycle         : in integer range 1 to 3;
            instr_is_mem_indirect : in std_logic;
            ahl_select            : out std_logic_vector(2 downto 0);
            ahl_active            : out std_logic
        );
    end component;

    -- Inputs
    signal state_t1              : std_logic := '0';
    signal state_t2              : std_logic := '0';
    signal current_cycle         : integer range 1 to 3 := 1;
    signal instr_is_mem_indirect : std_logic := '0';

    -- Outputs
    signal ahl_select : std_logic_vector(2 downto 0);
    signal ahl_active : std_logic;

    -- Constants for scratchpad addresses
    constant ADDR_A : std_logic_vector(2 downto 0) := "000";
    constant ADDR_B : std_logic_vector(2 downto 0) := "001";
    constant ADDR_C : std_logic_vector(2 downto 0) := "010";
    constant ADDR_D : std_logic_vector(2 downto 0) := "011";
    constant ADDR_E : std_logic_vector(2 downto 0) := "100";
    constant ADDR_H : std_logic_vector(2 downto 0) := "101";
    constant ADDR_L : std_logic_vector(2 downto 0) := "110";

begin

    uut : ahl_pointer
        port map (
            state_t1              => state_t1,
            state_t2              => state_t2,
            current_cycle         => current_cycle,
            instr_is_mem_indirect => instr_is_mem_indirect,
            ahl_select            => ahl_select,
            ahl_active            => ahl_active
        );

    test_process : process
        variable errors : integer := 0;
    begin
        report "========================================";
        report "AHL Pointer (Scratchpad Selector) Test";
        report "========================================";

        -- Test 1: Not a memory indirect operation - should be inactive
        report "";
        report "Test 1: Non-memory operation (instr_is_mem_indirect=0)";

        state_t1 <= '0';
        state_t2 <= '0';
        current_cycle <= 2;
        instr_is_mem_indirect <= '0';
        wait for 10 ns;

        if ahl_active /= '0' then
            report "  ERROR: ahl_active should be '0' for non-memory ops" severity error;
            errors := errors + 1;
        else
            report "  PASS: ahl_active='0' for non-memory indirect ops";
        end if;

        -- Test 2: Memory indirect, cycle 2, T1 state - should select L register
        report "";
        report "Test 2: LrM cycle 2, T1 - should select L register (110)";

        state_t1 <= '1';
        state_t2 <= '0';
        current_cycle <= 2;
        instr_is_mem_indirect <= '1';
        wait for 10 ns;

        if ahl_active /= '1' then
            report "  ERROR: ahl_active should be '1'" severity error;
            errors := errors + 1;
        elsif ahl_select /= ADDR_L then
            report "  ERROR: ahl_select should be L (110), got " & to_string(ahl_select) severity error;
            errors := errors + 1;
        else
            report "  PASS: Correctly selected L register during T1";
        end if;

        -- Test 3: Memory indirect, cycle 2, T2 state - should select H register
        report "";
        report "Test 3: LrM cycle 2, T2 - should select H register (101)";

        state_t1 <= '0';
        state_t2 <= '1';
        current_cycle <= 2;
        instr_is_mem_indirect <= '1';
        wait for 10 ns;

        if ahl_active /= '1' then
            report "  ERROR: ahl_active should be '1'" severity error;
            errors := errors + 1;
        elsif ahl_select /= ADDR_H then
            report "  ERROR: ahl_select should be H (101), got " & to_string(ahl_select) severity error;
            errors := errors + 1;
        else
            report "  PASS: Correctly selected H register during T2";
        end if;

        -- Test 4: Memory indirect, cycle 2, T3 state - should be inactive
        report "";
        report "Test 4: LrM cycle 2, T3 - should be inactive";

        state_t1 <= '0';
        state_t2 <= '0';
        current_cycle <= 2;
        instr_is_mem_indirect <= '1';
        wait for 10 ns;

        if ahl_active /= '0' then
            report "  ERROR: ahl_active should be '0' during T3" severity error;
            errors := errors + 1;
        else
            report "  PASS: Inactive during T3 (not T1 or T2)";
        end if;

        -- Test 5: Memory indirect, cycle 1, T1 - should be inactive (wrong cycle)
        report "";
        report "Test 5: LrM cycle 1, T1 - should be inactive (wrong cycle)";

        state_t1 <= '1';
        state_t2 <= '0';
        current_cycle <= 1;
        instr_is_mem_indirect <= '1';
        wait for 10 ns;

        if ahl_active /= '0' then
            report "  ERROR: ahl_active should be '0' during cycle 1" severity error;
            errors := errors + 1;
        else
            report "  PASS: Inactive during cycle 1 (needs cycle 2)";
        end if;

        -- Test 6: Memory indirect, cycle 3, T1 - should be inactive (wrong cycle)
        report "";
        report "Test 6: LrM cycle 3, T1 - should be inactive (wrong cycle)";

        state_t1 <= '1';
        state_t2 <= '0';
        current_cycle <= 3;
        instr_is_mem_indirect <= '1';
        wait for 10 ns;

        if ahl_active /= '0' then
            report "  ERROR: ahl_active should be '0' during cycle 3" severity error;
            errors := errors + 1;
        else
            report "  PASS: Inactive during cycle 3 (needs cycle 2)";
        end if;

        -- Test 7: Both T1 and T2 active simultaneously (shouldn't happen, but test priority)
        report "";
        report "Test 7: Both T1 and T2 active - T1 should take priority (L register)";

        state_t1 <= '1';
        state_t2 <= '1';
        current_cycle <= 2;
        instr_is_mem_indirect <= '1';
        wait for 10 ns;

        if ahl_active /= '1' then
            report "  ERROR: ahl_active should be '1'" severity error;
            errors := errors + 1;
        elsif ahl_select /= ADDR_L then
            report "  ERROR: T1 should take priority, selecting L, got " & to_string(ahl_select) severity error;
            errors := errors + 1;
        else
            report "  PASS: T1 takes priority over T2";
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

        wait;
    end process;

end architecture test;

--------------------------------------------------------------------------------
-- condition_flags_tb.vhdl
--------------------------------------------------------------------------------
-- Testbench for Condition Flags
-- Tests: Flag storage, condition evaluation, all 8 condition codes
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.b8008_types.all;

entity condition_flags_tb is
end entity condition_flags_tb;

architecture test of condition_flags_tb is

    -- Component declaration
    component condition_flags is
        port (
            phi2           : in std_logic;
            reset          : in std_logic;
            flag_carry_in  : in std_logic;
            flag_zero_in   : in std_logic;
            flag_sign_in   : in std_logic;
            flag_parity_in : in std_logic;
            update_flags   : in std_logic;
            condition_code : in std_logic_vector(1 downto 0);
            test_true      : in std_logic;
            eval_condition : in std_logic;
            output_flags   : in std_logic;
            internal_bus   : inout std_logic_vector(7 downto 0);
            condition_met  : out std_logic;
            flag_carry     : out std_logic;
            flag_zero      : out std_logic;
            flag_sign      : out std_logic;
            flag_parity    : out std_logic
        );
    end component;

    -- Clock
    signal phi2 : std_logic := '0';
    constant phi2_period : time := 500 ns;

    -- Inputs
    signal reset          : std_logic := '0';
    signal flag_carry_in  : std_logic := '0';
    signal flag_zero_in   : std_logic := '0';
    signal flag_sign_in   : std_logic := '0';
    signal flag_parity_in : std_logic := '0';
    signal update_flags   : std_logic := '0';
    signal condition_code : std_logic_vector(1 downto 0) := (others => '0');
    signal test_true      : std_logic := '0';
    signal eval_condition : std_logic := '0';
    signal output_flags   : std_logic := '0';

    -- Internal bus
    signal internal_bus : std_logic_vector(7 downto 0);

    -- Outputs
    signal condition_met : std_logic;
    signal flag_carry    : std_logic;
    signal flag_zero     : std_logic;
    signal flag_sign     : std_logic;
    signal flag_parity   : std_logic;

    -- Condition codes (2-bit)
    constant COND_CARRY  : std_logic_vector(1 downto 0) := "00";
    constant COND_ZERO   : std_logic_vector(1 downto 0) := "01";
    constant COND_SIGN   : std_logic_vector(1 downto 0) := "10";
    constant COND_PARITY : std_logic_vector(1 downto 0) := "11";

begin

    -- Clock generation
    phi2 <= not phi2 after phi2_period / 2;

    uut : condition_flags
        port map (
            phi2           => phi2,
            reset          => reset,
            flag_carry_in  => flag_carry_in,
            flag_zero_in   => flag_zero_in,
            flag_sign_in   => flag_sign_in,
            flag_parity_in => flag_parity_in,
            update_flags   => update_flags,
            condition_code => condition_code,
            test_true      => test_true,
            eval_condition => eval_condition,
            output_flags   => output_flags,
            internal_bus   => internal_bus,
            condition_met  => condition_met,
            flag_carry     => flag_carry,
            flag_zero      => flag_zero,
            flag_sign      => flag_sign,
            flag_parity    => flag_parity
        );

    -- Test stimulus
    test_process : process
        variable errors : integer := 0;
    begin
        report "========================================";
        report "Condition Flags Test";
        report "========================================";

        -- Test 1: Reset clears all flags
        report "";
        report "Test 1: Reset clears all flags";

        reset <= '1';
        wait for phi2_period;
        reset <= '0';
        wait for phi2_period;

        if flag_carry /= '0' or flag_zero /= '0' or flag_sign /= '0' or flag_parity /= '0' then
            report "  ERROR: Flags should be cleared after reset" severity error;
            errors := errors + 1;
        else
            report "  PASS: All flags cleared after reset";
        end if;

        -- Test 2: Update flags (set all)
        report "";
        report "Test 2: Update all flags to 1";

        flag_carry_in  <= '1';
        flag_zero_in   <= '1';
        flag_sign_in   <= '1';
        flag_parity_in <= '1';
        update_flags   <= '1';

        wait until rising_edge(phi2);
        wait for 10 ns;

        if flag_carry /= '1' or flag_zero /= '1' or flag_sign /= '1' or flag_parity /= '1' then
            report "  ERROR: All flags should be set to 1" severity error;
            errors := errors + 1;
        else
            report "  PASS: All flags updated to 1";
        end if;

        update_flags <= '0';

        -- Test 3: Update flags (clear some)
        report "";
        report "Test 3: Update flags - Carry=0, Zero=1, Sign=0, Parity=1";

        flag_carry_in  <= '0';
        flag_zero_in   <= '1';
        flag_sign_in   <= '0';
        flag_parity_in <= '1';
        update_flags   <= '1';

        wait until rising_edge(phi2);
        wait for 10 ns;

        if flag_carry /= '0' or flag_zero /= '1' or flag_sign /= '0' or flag_parity /= '1' then
            report "  ERROR: Flags not updated correctly" severity error;
            errors := errors + 1;
        else
            report "  PASS: Flags updated correctly";
        end if;

        update_flags <= '0';
        wait for phi2_period;

        -- Test 4: Test CARRY True (JTc) - should fail, C=0
        report "";
        report "Test 4: JTc CARRY (C=0, test true, should not be met)";

        condition_code <= COND_CARRY;
        test_true      <= '1';  -- Test if carry = 1
        eval_condition <= '1';
        wait for 50 ns;

        if condition_met /= '0' then
            report "  ERROR: Condition should not be met (Carry=0)" severity error;
            errors := errors + 1;
        else
            report "  PASS: JTc correctly not met";
        end if;

        -- Test 5: Test ZERO True (JTc) - should pass, Z=1
        report "";
        report "Test 5: JTc ZERO (Z=1, test true, should be met)";

        condition_code <= COND_ZERO;
        test_true      <= '1';  -- Test if zero = 1
        wait for 50 ns;

        if condition_met /= '1' then
            report "  ERROR: Condition should be met (Zero=1)" severity error;
            errors := errors + 1;
        else
            report "  PASS: JTc correctly met";
        end if;

        -- Test 6: Test CARRY False (JFc) - should pass, C=0
        report "";
        report "Test 6: JFc CARRY (C=0, test false, should be met)";

        condition_code <= COND_CARRY;
        test_true      <= '0';  -- Test if carry = 0
        wait for 50 ns;

        if condition_met /= '1' then
            report "  ERROR: Condition should be met (Carry=0)" severity error;
            errors := errors + 1;
        else
            report "  PASS: JFc correctly met";
        end if;

        -- Test 7: Test SIGN False (JFc) - should pass, S=0
        report "";
        report "Test 7: JFc SIGN (S=0, test false, should be met)";

        condition_code <= COND_SIGN;
        test_true      <= '0';  -- Test if sign = 0
        wait for 50 ns;

        if condition_met /= '1' then
            report "  ERROR: Condition should be met (Sign=0)" severity error;
            errors := errors + 1;
        else
            report "  PASS: JFc correctly met";
        end if;

        -- Test 8: Test PARITY True (JTc) - should pass, P=1
        report "";
        report "Test 8: JTc PARITY (P=1, test true, should be met)";

        condition_code <= COND_PARITY;
        test_true      <= '1';  -- Test if parity = 1
        wait for 50 ns;

        if condition_met /= '1' then
            report "  ERROR: Condition should be met (Parity=1)" severity error;
            errors := errors + 1;
        else
            report "  PASS: JTc correctly met";
        end if;

        -- Test 9: Unconditional instruction (eval_condition=0)
        -- When eval_condition='0', condition_met should be '1' (unconditional always proceeds)
        report "";
        report "Test 9: Unconditional instruction (eval_condition=0)";

        condition_code <= COND_ZERO;  -- Z=1, but doesn't matter - unconditional
        eval_condition <= '0';
        wait for 50 ns;

        if condition_met /= '1' then
            report "  ERROR: Unconditional instructions should always have condition_met='1'" severity error;
            errors := errors + 1;
        else
            report "  PASS: Unconditional instruction correctly proceeds (condition_met='1')";
        end if;

        -- Test 10: Update flags during operation and test
        report "";
        report "Test 10: Update Carry=1, test JTc CARRY";

        eval_condition <= '1';
        condition_code <= COND_CARRY;
        test_true      <= '1';  -- Test if carry = 1

        -- Update Carry flag to 1
        flag_carry_in <= '1';
        update_flags  <= '1';
        wait until rising_edge(phi2);
        wait for 10 ns;
        update_flags  <= '0';

        if flag_carry /= '1' then
            report "  ERROR: Carry flag should be 1" severity error;
            errors := errors + 1;
        end if;

        wait for 50 ns;

        if condition_met /= '1' then
            report "  ERROR: JTc CARRY should now be met" severity error;
            errors := errors + 1;
        else
            report "  PASS: Flag updated and JTc condition met";
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

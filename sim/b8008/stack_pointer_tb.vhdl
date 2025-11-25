--------------------------------------------------------------------------------
-- stack_pointer_tb.vhdl
--------------------------------------------------------------------------------
-- Testbench for Stack Pointer
-- Tests: Push (increment), Pop (decrement), Wraparound
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.b8008_types.all;

entity stack_pointer_tb is
end entity stack_pointer_tb;

architecture test of stack_pointer_tb is

    component stack_pointer is
        port (
            phi1       : in std_logic;
            reset      : in std_logic;
            stack_push : in std_logic;
            stack_pop  : in std_logic;
            sp_out     : out std_logic_vector(2 downto 0)
        );
    end component;

    -- Clock
    signal phi1 : std_logic := '0';
    constant phi1_period : time := 500 ns;

    -- Inputs
    signal reset      : std_logic := '0';
    signal stack_push : std_logic := '0';
    signal stack_pop  : std_logic := '0';

    -- Outputs
    signal sp_out : std_logic_vector(2 downto 0);

begin

    -- Clock generation
    phi1 <= not phi1 after phi1_period / 2;

    uut : stack_pointer
        port map (
            phi1       => phi1,
            reset      => reset,
            stack_push => stack_push,
            stack_pop  => stack_pop,
            sp_out     => sp_out
        );

    test_process : process
        variable errors : integer := 0;
    begin
        report "========================================";
        report "Stack Pointer Test";
        report "========================================";

        -- Test 1: Reset sets SP to 0
        report "";
        report "Test 1: Reset sets SP to 0";

        reset <= '1';
        wait for phi1_period;
        reset <= '0';
        wait for phi1_period;

        if sp_out /= "000" then
            report "  ERROR: SP should be 000 after reset" severity error;
            errors := errors + 1;
        else
            report "  PASS: SP reset to 0";
        end if;

        -- Test 2: Push increments SP
        report "";
        report "Test 2: Push increments SP (0->1->2->3)";

        for i in 1 to 3 loop
            stack_push <= '1';
            wait until rising_edge(phi1);
            wait for 10 ns;
            stack_push <= '0';
            wait for 10 ns;

            if unsigned(sp_out) /= i then
                report "  ERROR: SP should be " & integer'image(i) &
                       ", got " & integer'image(to_integer(unsigned(sp_out))) severity error;
                errors := errors + 1;
            end if;
        end loop;

        report "  PASS: Push increments correctly";

        -- Test 3: Pop decrements SP
        report "";
        report "Test 3: Pop decrements SP (3->2->1)";

        for i in 2 downto 1 loop
            stack_pop <= '1';
            wait until rising_edge(phi1);
            wait for 10 ns;
            stack_pop <= '0';
            wait for 10 ns;

            if unsigned(sp_out) /= i then
                report "  ERROR: SP should be " & integer'image(i) &
                       ", got " & integer'image(to_integer(unsigned(sp_out))) severity error;
                errors := errors + 1;
            end if;
        end loop;

        report "  PASS: Pop decrements correctly";

        -- Test 4: Push wraps around from 7 to 0
        report "";
        report "Test 4: Push wraparound (7->0)";

        -- Set SP to 7
        reset <= '1';
        wait for phi1_period;
        reset <= '0';
        wait for phi1_period;

        for i in 0 to 7 loop
            stack_push <= '1';
            wait until rising_edge(phi1);
            wait for 10 ns;
            stack_push <= '0';
            wait for 10 ns;
        end loop;

        -- SP should have wrapped to 0
        if sp_out /= "000" then
            report "  ERROR: SP should wrap to 000, got " & to_string(sp_out) severity error;
            errors := errors + 1;
        else
            report "  PASS: Push wraps from 7 to 0";
        end if;

        -- Test 5: Pop wraps around from 0 to 7
        report "";
        report "Test 5: Pop wraparound (0->7)";

        reset <= '1';
        wait for phi1_period;
        reset <= '0';
        wait for phi1_period;

        -- SP is at 0, pop should wrap to 7
        stack_pop <= '1';
        wait until rising_edge(phi1);
        wait for 10 ns;
        stack_pop <= '0';
        wait for 10 ns;

        if sp_out /= "111" then
            report "  ERROR: SP should wrap to 111, got " & to_string(sp_out) severity error;
            errors := errors + 1;
        else
            report "  PASS: Pop wraps from 0 to 7";
        end if;

        -- Test 6: SP holds when no push/pop
        report "";
        report "Test 6: SP holds at 7 when no push/pop";

        wait for phi1_period * 3;

        if sp_out /= "111" then
            report "  ERROR: SP should hold at 111" severity error;
            errors := errors + 1;
        else
            report "  PASS: SP holds correctly";
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

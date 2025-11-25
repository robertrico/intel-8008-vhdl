--------------------------------------------------------------------------------
-- sss_ddd_selector_tb.vhdl
--------------------------------------------------------------------------------
-- Testbench for SSS/DDD Register Address Selector
-- Tests: SSS selection, DDD selection, both disabled, priority
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.b8008_types.all;

entity sss_ddd_selector_tb is
end entity sss_ddd_selector_tb;

architecture test of sss_ddd_selector_tb is

    component sss_ddd_selector is
        port (
            sss_field  : in std_logic_vector(2 downto 0);
            ddd_field  : in std_logic_vector(2 downto 0);
            select_sss : in std_logic;
            select_ddd : in std_logic;
            reg_addr   : out std_logic_vector(2 downto 0)
        );
    end component;

    -- Inputs
    signal sss_field  : std_logic_vector(2 downto 0) := (others => '0');
    signal ddd_field  : std_logic_vector(2 downto 0) := (others => '0');
    signal select_sss : std_logic := '0';
    signal select_ddd : std_logic := '0';

    -- Outputs
    signal reg_addr : std_logic_vector(2 downto 0);

begin

    uut : sss_ddd_selector
        port map (
            sss_field  => sss_field,
            ddd_field  => ddd_field,
            select_sss => select_sss,
            select_ddd => select_ddd,
            reg_addr   => reg_addr
        );

    test_process : process
        variable errors : integer := 0;
    begin
        report "========================================";
        report "SSS/DDD Selector Test";
        report "========================================";

        -- Test 1: Select SSS (source register B)
        report "";
        report "Test 1: Select SSS=001 (B register)";

        sss_field  <= "001";  -- B
        ddd_field  <= "101";  -- H
        select_sss <= '1';
        select_ddd <= '0';
        wait for 10 ns;

        if reg_addr /= "001" then
            report "  ERROR: Should output SSS=001" severity error;
            errors := errors + 1;
        else
            report "  PASS: SSS selected correctly";
        end if;

        -- Test 2: Select DDD (destination register D)
        report "";
        report "Test 2: Select DDD=011 (D register)";

        sss_field  <= "110";  -- L
        ddd_field  <= "011";  -- D
        select_sss <= '0';
        select_ddd <= '1';
        wait for 10 ns;

        if reg_addr /= "011" then
            report "  ERROR: Should output DDD=011" severity error;
            errors := errors + 1;
        else
            report "  PASS: DDD selected correctly";
        end if;

        -- Test 3: Neither selected (default to 000)
        report "";
        report "Test 3: Neither SSS nor DDD selected";

        sss_field  <= "101";  -- H
        ddd_field  <= "100";  -- E
        select_sss <= '0';
        select_ddd <= '0';
        wait for 10 ns;

        if reg_addr /= "000" then
            report "  ERROR: Should default to 000" severity error;
            errors := errors + 1;
        else
            report "  PASS: Defaults to 000 when neither selected";
        end if;

        -- Test 4: Both selected (DDD takes priority)
        report "";
        report "Test 4: Both selected - DDD should take priority";

        sss_field  <= "010";  -- C
        ddd_field  <= "100";  -- E
        select_sss <= '1';
        select_ddd <= '1';
        wait for 10 ns;

        if reg_addr /= "100" then
            report "  ERROR: DDD should take priority, expected 100" severity error;
            errors := errors + 1;
        else
            report "  PASS: DDD takes priority when both selected";
        end if;

        -- Test 5: All register encodings for SSS
        report "";
        report "Test 5: Test all SSS register encodings";

        select_sss <= '1';
        select_ddd <= '0';
        ddd_field  <= "000";

        for i in 0 to 7 loop
            sss_field <= std_logic_vector(to_unsigned(i, 3));
            wait for 10 ns;

            if reg_addr /= std_logic_vector(to_unsigned(i, 3)) then
                report "  ERROR: SSS=" & integer'image(i) & " not passed through" severity error;
                errors := errors + 1;
            end if;
        end loop;

        report "  PASS: All SSS encodings work";

        -- Test 6: All register encodings for DDD
        report "";
        report "Test 6: Test all DDD register encodings";

        select_sss <= '0';
        select_ddd <= '1';
        sss_field  <= "000";

        for i in 0 to 7 loop
            ddd_field <= std_logic_vector(to_unsigned(i, 3));
            wait for 10 ns;

            if reg_addr /= std_logic_vector(to_unsigned(i, 3)) then
                report "  ERROR: DDD=" & integer'image(i) & " not passed through" severity error;
                errors := errors + 1;
            end if;
        end loop;

        report "  PASS: All DDD encodings work";

        -- Test 7: Verify register encoding meanings
        report "";
        report "Test 7: Verify specific register selections";

        -- A register (000)
        sss_field  <= "000";
        select_sss <= '1';
        select_ddd <= '0';
        wait for 10 ns;
        if reg_addr /= "000" then
            report "  ERROR: A register should be 000" severity error;
            errors := errors + 1;
        end if;

        -- M register (111) - memory indirect
        sss_field  <= "111";
        wait for 10 ns;
        if reg_addr /= "111" then
            report "  ERROR: M register should be 111" severity error;
            errors := errors + 1;
        end if;

        report "  PASS: Register encodings verified";

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

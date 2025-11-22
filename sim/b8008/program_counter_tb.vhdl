--------------------------------------------------------------------------------
-- program_counter_tb.vhdl
--------------------------------------------------------------------------------
-- Testbench for program_counter module
-- Tests: reset, increment, load, hold
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.b8008_types.all;

entity program_counter_tb is
end entity program_counter_tb;

architecture test of program_counter_tb is

    component program_counter is
        port (
            clk       : in  std_logic;
            reset     : in  std_logic;
            control   : in  pc_control_t;
            data_in   : in  address_t;
            pc_out    : out address_t
        );
    end component;

    signal clk     : std_logic := '0';
    signal reset   : std_logic := '1';
    signal control : pc_control_t := PC_HOLD;
    signal data_in : address_t := (others => '0');
    signal pc_out  : address_t;

    signal done    : boolean := false;

    constant CLK_PERIOD : time := 10 ns;

begin

    -- Unit under test
    uut : program_counter
        port map (
            clk       => clk,
            reset     => reset,
            control   => control,
            data_in   => data_in,
            pc_out    => pc_out
        );

    -- Clock generation
    process
    begin
        while not done loop
            clk <= '0';
            wait for CLK_PERIOD / 2;
            clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    -- Test stimulus
    process
        variable errors : integer := 0;
    begin
        report "========================================";
        report "Program Counter Test";
        report "========================================";

        -- Test 1: Reset
        report "Test 1: Reset";
        reset <= '1';
        wait for CLK_PERIOD * 2;
        reset <= '0';
        wait for CLK_PERIOD;

        if pc_out /= "00000000000000" then
            report "  ERROR: PC after reset = " & integer'image(to_integer(pc_out)) & ", expected 0" severity error;
            errors := errors + 1;
        else
            report "  PASS: PC = 0 after reset";
        end if;

        -- Test 2: Increment
        report "Test 2: Increment";
        control <= PC_INCREMENT;
        wait for CLK_PERIOD;

        if pc_out /= "00000000000001" then
            report "  ERROR: PC after increment = " & integer'image(to_integer(pc_out)) & ", expected 1" severity error;
            errors := errors + 1;
        else
            report "  PASS: PC = 1 after increment";
        end if;

        -- Test 3: Multiple increments
        report "Test 3: Multiple increments";
        for i in 2 to 10 loop
            wait for CLK_PERIOD;
            if pc_out /= to_unsigned(i, 14) then
                report "  ERROR: PC = " & integer'image(to_integer(pc_out)) & ", expected " & integer'image(i) severity error;
                errors := errors + 1;
            end if;
        end loop;
        report "  PASS: PC incremented to 10";

        -- Test 4: Hold
        report "Test 4: Hold";
        control <= PC_HOLD;
        wait for CLK_PERIOD * 3;

        if pc_out /= "00000000001010" then  -- Should still be 10
            report "  ERROR: PC after hold = " & integer'image(to_integer(pc_out)) & ", expected 10" severity error;
            errors := errors + 1;
        else
            report "  PASS: PC held at 10";
        end if;

        -- Test 5: Load
        report "Test 5: Load";
        data_in <= to_unsigned(16#1234#, 14);
        control <= PC_LOAD;
        wait for CLK_PERIOD;

        if pc_out /= to_unsigned(16#1234#, 14) then
            report "  ERROR: PC after load = " & integer'image(to_integer(pc_out)) & ", expected 4660 (0x1234)" severity error;
            errors := errors + 1;
        else
            report "  PASS: PC loaded with 0x1234";
        end if;

        -- Test 6: Increment from loaded value
        report "Test 6: Increment from loaded value";
        control <= PC_INCREMENT;
        wait for CLK_PERIOD;

        if pc_out /= to_unsigned(16#1235#, 14) then
            report "  ERROR: PC = " & integer'image(to_integer(pc_out)) & ", expected 4661 (0x1235)" severity error;
            errors := errors + 1;
        else
            report "  PASS: PC incremented to 0x1235";
        end if;

        -- Summary
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

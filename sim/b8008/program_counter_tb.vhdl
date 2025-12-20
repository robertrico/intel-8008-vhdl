--------------------------------------------------------------------------------
-- program_counter_tb.vhdl
--------------------------------------------------------------------------------
-- Testbench for program_counter module (two-stage increment design)
-- Tests: increment lower, increment upper (carry), load, hold
-- Note: Uses edge-triggered signals per the 1972 datasheet design
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
            control   : in  pc_control_t;
            data_in   : in  address_t;
            pc_out    : out address_t;
            carry_out : out std_logic
        );
    end component;

    signal control   : pc_control_t := PC_HOLD;
    signal data_in   : address_t := (others => '0');
    signal pc_out    : address_t;
    signal carry_out : std_logic;

    constant STROBE_TIME : time := 10 ns;  -- Duration of control strobe pulse

    -- Helper procedure: perform a full increment (lower + upper if carry)
    procedure do_increment(signal ctrl : out pc_control_t; signal carry : in std_logic) is
    begin
        -- T1: Increment lower byte
        ctrl <= PC_INCREMENT_LOWER;
        wait for STROBE_TIME;
        ctrl <= PC_HOLD;
        wait for STROBE_TIME;

        -- T2: Increment upper byte if carry occurred
        if carry = '1' then
            ctrl <= PC_INCREMENT_UPPER;
            wait for STROBE_TIME;
            ctrl <= PC_HOLD;
            wait for STROBE_TIME;
        end if;
    end procedure;

begin

    -- Unit under test
    uut : program_counter
        port map (
            control   => control,
            data_in   => data_in,
            pc_out    => pc_out,
            carry_out => carry_out
        );

    -- Test stimulus
    process
        variable errors : integer := 0;
    begin
        report "========================================";
        report "Program Counter Test (Two-Stage Increment)";
        report "========================================";
        report "NOTE: PC uses edge-triggered increment (lower then upper if carry)";
        report "";

        -- Test 1: Initial state
        report "Test 1: Initial state (PC should be 0)";
        wait for STROBE_TIME;

        if pc_out /= "00000000000000" then
            report "  ERROR: PC initial state = " & integer'image(to_integer(pc_out)) & ", expected 0" severity error;
            errors := errors + 1;
        else
            report "  PASS: PC = 0 at initialization";
        end if;

        -- Test 2: Single increment (lower byte only)
        report "Test 2: Increment strobe (lower byte)";
        control <= PC_INCREMENT_LOWER;
        wait for STROBE_TIME;
        control <= PC_HOLD;
        wait for STROBE_TIME;

        if pc_out /= "00000000000001" then
            report "  ERROR: PC after increment = " & integer'image(to_integer(pc_out)) & ", expected 1" severity error;
            errors := errors + 1;
        else
            report "  PASS: PC = 1 after increment";
        end if;

        -- Test 3: Multiple increments (using full increment sequence)
        report "Test 3: Multiple increment strobes";
        for i in 2 to 10 loop
            control <= PC_INCREMENT_LOWER;
            wait for STROBE_TIME;
            control <= PC_HOLD;
            wait for STROBE_TIME;
            if pc_out /= to_unsigned(i, 14) then
                report "  ERROR: PC = " & integer'image(to_integer(pc_out)) & ", expected " & integer'image(i) severity error;
                errors := errors + 1;
            end if;
        end loop;
        report "  PASS: PC incremented to 10";

        -- Test 4: Hold
        report "Test 4: Hold";
        wait for STROBE_TIME * 3;

        if pc_out /= "00000000001010" then  -- Should still be 10
            report "  ERROR: PC after hold = " & integer'image(to_integer(pc_out)) & ", expected 10" severity error;
            errors := errors + 1;
        else
            report "  PASS: PC held at 10";
        end if;

        -- Test 5: Load strobe
        report "Test 5: Load strobe";
        data_in <= to_unsigned(16#1234#, 14);
        control <= PC_LOAD;
        wait for STROBE_TIME;
        control <= PC_HOLD;
        wait for STROBE_TIME;

        if pc_out /= to_unsigned(16#1234#, 14) then
            report "  ERROR: PC after load = " & integer'image(to_integer(pc_out)) & ", expected 4660 (0x1234)" severity error;
            errors := errors + 1;
        else
            report "  PASS: PC loaded with 0x1234";
        end if;

        -- Test 6: Increment from loaded value
        report "Test 6: Increment from loaded value";
        control <= PC_INCREMENT_LOWER;
        wait for STROBE_TIME;
        control <= PC_HOLD;
        wait for STROBE_TIME;

        if pc_out /= to_unsigned(16#1235#, 14) then
            report "  ERROR: PC = " & integer'image(to_integer(pc_out)) & ", expected 4661 (0x1235)" severity error;
            errors := errors + 1;
        else
            report "  PASS: PC incremented to 0x1235";
        end if;

        -- Test 7: Carry test - load value ending in 0xFF and increment
        report "Test 7: Carry test (increment from 0x00FF)";
        data_in <= to_unsigned(16#00FF#, 14);
        control <= PC_LOAD;
        wait for STROBE_TIME;
        control <= PC_HOLD;
        wait for STROBE_TIME;

        -- Increment lower byte - should set carry
        control <= PC_INCREMENT_LOWER;
        wait for STROBE_TIME;
        control <= PC_HOLD;
        wait for STROBE_TIME;

        if carry_out /= '1' then
            report "  ERROR: Carry not set after 0xFF increment" severity error;
            errors := errors + 1;
        else
            report "  PASS: Carry set after 0xFF->0x00 increment";
        end if;

        -- Lower byte should be 0x00, upper should still be 0x00
        if pc_out /= to_unsigned(16#0000#, 14) then
            report "  ERROR: PC after lower increment = " & integer'image(to_integer(pc_out)) & ", expected 0x0000" severity error;
            errors := errors + 1;
        else
            report "  PASS: Lower byte wrapped to 0x00";
        end if;

        -- Now increment upper byte (T2 with carry)
        control <= PC_INCREMENT_UPPER;
        wait for STROBE_TIME;
        control <= PC_HOLD;
        wait for STROBE_TIME;

        if pc_out /= to_unsigned(16#0100#, 14) then
            report "  ERROR: PC after upper increment = " & integer'image(to_integer(pc_out)) & ", expected 0x0100" severity error;
            errors := errors + 1;
        else
            report "  PASS: Full increment 0x00FF -> 0x0100 complete";
        end if;

        -- Test 8: Load maximum value (14-bit boundary)
        report "Test 8: Load maximum value (0x3FFF)";
        data_in <= to_unsigned(16#3FFF#, 14);  -- 14-bit max = 16383
        control <= PC_LOAD;
        wait for STROBE_TIME;
        control <= PC_HOLD;
        wait for STROBE_TIME;

        if pc_out /= to_unsigned(16#3FFF#, 14) then
            report "  ERROR: PC after load max = " & integer'image(to_integer(pc_out)) & ", expected 16383 (0x3FFF)" severity error;
            errors := errors + 1;
        else
            report "  PASS: PC loaded with 0x3FFF (max 14-bit value)";
        end if;

        -- Test 9: Wraparound at 14-bit boundary
        report "Test 9: Wraparound at 14-bit boundary";
        -- Lower byte increment: 0xFF -> 0x00, carry set
        control <= PC_INCREMENT_LOWER;
        wait for STROBE_TIME;
        control <= PC_HOLD;
        wait for STROBE_TIME;

        -- Upper byte increment: 0x3F -> 0x00 (6-bit wrap)
        control <= PC_INCREMENT_UPPER;
        wait for STROBE_TIME;
        control <= PC_HOLD;
        wait for STROBE_TIME;

        if pc_out /= to_unsigned(0, 14) then
            report "  ERROR: PC after wraparound = " & integer'image(to_integer(pc_out)) & ", expected 0" severity error;
            errors := errors + 1;
        else
            report "  PASS: PC wrapped around to 0";
        end if;

        -- Test 10: Load zero explicitly
        report "Test 10: Load zero explicitly";
        data_in <= to_unsigned(0, 14);
        control <= PC_LOAD;
        wait for STROBE_TIME;
        control <= PC_HOLD;
        wait for STROBE_TIME;

        if pc_out /= to_unsigned(0, 14) then
            report "  ERROR: PC after load zero = " & integer'image(to_integer(pc_out)) & ", expected 0" severity error;
            errors := errors + 1;
        else
            report "  PASS: PC loaded with 0";
        end if;

        -- Test 11: All control signals low (default hold behavior)
        report "Test 11: All control signals low (default hold)";
        data_in <= to_unsigned(999, 14);
        control.increment_lower <= '0';
        control.increment_upper <= '0';
        control.load <= '0';
        control.hold <= '0';
        wait for STROBE_TIME * 2;

        if pc_out /= to_unsigned(0, 14) then
            report "  ERROR: PC changed with all controls low = " & integer'image(to_integer(pc_out)) & ", expected 0" severity error;
            errors := errors + 1;
        else
            report "  PASS: PC held when all control signals low";
        end if;

        -- Test 12: Rapid switching between strobes
        report "Test 12: Rapid switching between strobes";
        data_in <= to_unsigned(100, 14);
        control <= PC_LOAD;
        wait for STROBE_TIME;

        control <= PC_INCREMENT_LOWER;
        wait for STROBE_TIME;

        control <= PC_HOLD;
        wait for STROBE_TIME;

        control <= PC_INCREMENT_LOWER;
        wait for STROBE_TIME;

        if pc_out /= to_unsigned(102, 14) then
            report "  ERROR: PC after rapid switching = " & integer'image(to_integer(pc_out)) & ", expected 102" severity error;
            errors := errors + 1;
        else
            report "  PASS: Rapid switching (load 100, inc to 101, hold, inc to 102)";
        end if;

        -- Summary
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

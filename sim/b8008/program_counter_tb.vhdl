--------------------------------------------------------------------------------
-- program_counter_tb.vhdl
--------------------------------------------------------------------------------
-- Testbench for program_counter module (level-triggered latch design)
-- Tests: increment, load, hold with simple strobes
-- Note: Uses time delays to simulate control strobes (not a real clock)
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
            pc_out    : out address_t
        );
    end component;

    signal control : pc_control_t := PC_HOLD;
    signal data_in : address_t := (others => '0');
    signal pc_out  : address_t;

    constant STROBE_TIME : time := 10 ns;  -- Duration of control strobe pulse

begin

    -- Unit under test
    uut : program_counter
        port map (
            control   => control,
            data_in   => data_in,
            pc_out    => pc_out
        );

    -- Test stimulus
    process
        variable errors : integer := 0;
    begin
        report "========================================";
        report "Program Counter Test (Latch-Based)";
        report "========================================";
        report "NOTE: PC uses level-triggered latches, not clocked flip-flops";
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

        -- Test 2: Increment strobe
        report "Test 2: Increment strobe";
        control <= PC_INCREMENT;
        wait for STROBE_TIME;
        control <= PC_HOLD;  -- Return to hold
        wait for STROBE_TIME;

        if pc_out /= "00000000000001" then
            report "  ERROR: PC after increment = " & integer'image(to_integer(pc_out)) & ", expected 1" severity error;
            errors := errors + 1;
        else
            report "  PASS: PC = 1 after increment";
        end if;

        -- Test 3: Multiple increment strobes
        report "Test 3: Multiple increment strobes";
        for i in 2 to 10 loop
            control <= PC_INCREMENT;
            wait for STROBE_TIME;
            control <= PC_HOLD;
            wait for STROBE_TIME;
            if pc_out /= to_unsigned(i, 14) then
                report "  ERROR: PC = " & integer'image(to_integer(pc_out)) & ", expected " & integer'image(i) severity error;
                errors := errors + 1;
            end if;
        end loop;
        report "  PASS: PC incremented to 10";

        -- Test 4: Hold (already holding from previous test)
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
        control <= PC_INCREMENT;
        wait for STROBE_TIME;
        control <= PC_HOLD;
        wait for STROBE_TIME;

        if pc_out /= to_unsigned(16#1235#, 14) then
            report "  ERROR: PC = " & integer'image(to_integer(pc_out)) & ", expected 4661 (0x1235)" severity error;
            errors := errors + 1;
        else
            report "  PASS: PC incremented to 0x1235";
        end if;

        -- Test 7: Load maximum value (14-bit boundary)
        report "Test 7: Load maximum value (0x3FFF)";
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

        -- Test 8: Wraparound (increment from max value)
        report "Test 8: Wraparound at 14-bit boundary";
        control <= PC_INCREMENT;
        wait for STROBE_TIME;
        control <= PC_HOLD;
        wait for STROBE_TIME;

        if pc_out /= to_unsigned(0, 14) then
            report "  ERROR: PC after wraparound = " & integer'image(to_integer(pc_out)) & ", expected 0" severity error;
            errors := errors + 1;
        else
            report "  PASS: PC wrapped around to 0";
        end if;

        -- Test 9: Load zero explicitly
        report "Test 9: Load zero explicitly";
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

        -- Test 10: All control signals low (default behavior)
        report "Test 10: All control signals low (default hold)";
        data_in <= to_unsigned(999, 14);
        control.increment <= '0';
        control.load <= '0';
        control.hold <= '0';
        wait for STROBE_TIME * 2;

        if pc_out /= to_unsigned(0, 14) then
            report "  ERROR: PC changed with all controls low = " & integer'image(to_integer(pc_out)) & ", expected 0" severity error;
            errors := errors + 1;
        else
            report "  PASS: PC held when all control signals low";
        end if;

        -- Test 11: Rapid switching between strobes
        report "Test 11: Rapid switching between strobes";
        data_in <= to_unsigned(100, 14);
        control <= PC_LOAD;
        wait for STROBE_TIME;

        control <= PC_INCREMENT;
        wait for STROBE_TIME;

        control <= PC_HOLD;
        wait for STROBE_TIME;

        control <= PC_INCREMENT;
        wait for STROBE_TIME;

        if pc_out /= to_unsigned(102, 14) then
            report "  ERROR: PC after rapid switching = " & integer'image(to_integer(pc_out)) & ", expected 102" severity error;
            errors := errors + 1;
        else
            report "  PASS: Rapid switching (load 100, inc to 101, hold, inc to 102)";
        end if;

        -- Test 12: Both controls high (undefined behavior - just document what happens)
        report "Test 12: Both increment and load high (pathological case)";
        data_in <= to_unsigned(500, 14);
        control.increment <= '1';
        control.load <= '1';  -- Both increment and load high (should never happen)
        control.hold <= '0';
        wait for STROBE_TIME;

        -- Just report what actually happens, don't enforce a specific behavior
        report "  INFO: With both inc/load high, PC = " & integer'image(to_integer(pc_out));
        report "  (This case should never occur in normal operation - controls should be one-hot)";

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

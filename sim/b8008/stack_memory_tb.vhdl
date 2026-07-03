--------------------------------------------------------------------------------
-- stack_memory_tb.vhdl
--------------------------------------------------------------------------------
-- Testbench for the PC-in-stack address stack
-- Tests: slot[sp] increment (lower/upper + carry), load, hold,
-- slot isolation across sp moves, and the CALL/RET/wrap dance:
-- a "push" is only sp moving on (old slot keeps its value), a "pop"
-- is sp moving back (value simply reappears as the live PC).
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.b8008_types.all;

entity stack_memory_tb is
end entity stack_memory_tb;

architecture test of stack_memory_tb is

    component stack_memory is
        port (
            clk         : in std_logic;
            phi1_rising : in std_logic;
            reset       : in std_logic;
            sp_in       : in std_logic_vector(2 downto 0);
            control     : in pc_control_t;
            data_in     : in address_t;
            addr_out    : out address_t;
            carry_out   : out std_logic
        );
    end component;

    constant CLK_PERIOD : time := 40 ns;

    signal clk         : std_logic := '0';
    signal phi1_rising : std_logic := '1';  -- every clk edge acts as phi1
    signal reset       : std_logic := '0';
    signal sp_in       : std_logic_vector(2 downto 0) := "000";
    signal control     : pc_control_t := PC_HOLD;
    signal data_in     : address_t := (others => '0');
    signal addr_out    : address_t;
    signal carry_out   : std_logic;

    signal done : boolean := false;

begin

    clk <= not clk after CLK_PERIOD / 2 when not done else '0';

    uut : stack_memory
        port map (
            clk         => clk,
            phi1_rising => phi1_rising,
            reset       => reset,
            sp_in       => sp_in,
            control     => control,
            data_in     => data_in,
            addr_out    => addr_out,
            carry_out   => carry_out
        );

    stimulus : process
        variable errors : integer := 0;

        procedure tick is
        begin
            wait until rising_edge(clk);
            wait for 1 ns;
        end procedure;
    begin
        report "========================================";
        report "Stack Memory (PC-in-stack) Test";
        report "========================================";

        reset <= '1';
        tick;
        reset <= '0';
        control <= PC_HOLD;
        tick;

        -- Test 1: load slot 0, verify stored value
        report "Test 1: load slot 0";
        data_in <= to_unsigned(16#0100#, 14);
        control <= PC_LOAD;
        tick;
        control <= PC_HOLD;
        tick;
        if addr_out /= to_unsigned(16#0100#, 14) then
            report "  ERROR: slot 0 load failed" severity error;
            errors := errors + 1;
        else
            report "  PASS: slot 0 = 0x0100";
        end if;

        -- Test 2: increment lower advances the live slot
        report "Test 2: increment lower";
        control <= PC_INCREMENT_LOWER;
        tick;
        control <= PC_HOLD;
        tick;
        if addr_out /= to_unsigned(16#0101#, 14) then
            report "  ERROR: increment failed" severity error;
            errors := errors + 1;
        else
            report "  PASS: slot 0 = 0x0101";
        end if;

        -- Test 3: two-stage increment - lower wraps 0xFF -> 0x00 raising
        -- carry_out, upper increment completes the bump
        report "Test 3: two-stage increment with carry";
        data_in <= to_unsigned(16#01FF#, 14);
        control <= PC_LOAD;
        tick;
        control <= PC_INCREMENT_LOWER;
        tick;
        control <= PC_HOLD;
        tick;
        if addr_out /= to_unsigned(16#0100#, 14) or carry_out /= '1' then
            report "  ERROR: lower wrap/carry failed (addr=0x" & to_hstring(addr_out) &
                   " carry=" & std_logic'image(carry_out) & ")" severity error;
            errors := errors + 1;
        end if;
        control <= PC_INCREMENT_UPPER;
        tick;
        control <= PC_HOLD;
        tick;
        if addr_out /= to_unsigned(16#0200#, 14) then
            report "  ERROR: upper increment failed" severity error;
            errors := errors + 1;
        else
            report "  PASS: 0x01FF + 1 = 0x0200 via two stages";
        end if;

        -- Test 4: CALL dance - sp moves on (push = no copy), target loads
        -- the NEW slot; pop brings the old value straight back
        report "Test 4: push/load/pop (CALL then RET)";
        sp_in <= "001";
        data_in <= to_unsigned(16#2100#, 14);
        control <= PC_LOAD;
        tick;
        control <= PC_HOLD;
        tick;
        if addr_out /= to_unsigned(16#2100#, 14) then
            report "  ERROR: new slot load failed" severity error;
            errors := errors + 1;
        end if;
        sp_in <= "000";
        wait for 1 ns;
        if addr_out /= to_unsigned(16#0200#, 14) then
            report "  ERROR: return address lost (slot 0 = 0x" & to_hstring(addr_out) & ")" severity error;
            errors := errors + 1;
        else
            report "  PASS: slot 0 kept 0x0200 across push/pop";
        end if;

        -- Test 5: all 8 slots hold distinct values; an sp orbit reads
        -- each back untouched (wrap isolation)
        report "Test 5: 8 distinct slots survive an sp orbit";
        for i in 0 to 7 loop
            sp_in <= std_logic_vector(to_unsigned(i, 3));
            data_in <= to_unsigned(16#0300# + i, 14);
            control <= PC_LOAD;
            tick;
            control <= PC_HOLD;
            tick;
        end loop;
        for i in 0 to 7 loop
            sp_in <= std_logic_vector(to_unsigned(i, 3));
            wait for 1 ns;
            if addr_out /= to_unsigned(16#0300# + i, 14) then
                report "  ERROR: slot " & integer'image(i) & " corrupted" severity error;
                errors := errors + 1;
            end if;
        end loop;
        report "  PASS: all 8 slots independent";

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

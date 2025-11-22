--------------------------------------------------------------------------------
-- phase_clocks_tb.vhdl
--------------------------------------------------------------------------------
-- Testbench for phase_clocks module with SYNC signal
-- Tests: phi1, phi2 non-overlapping behavior and SYNC toggle
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity phase_clocks_tb is
end entity phase_clocks_tb;

architecture test of phase_clocks_tb is

    component phase_clocks is
        port (
            clk_in : in  std_logic;
            reset  : in  std_logic;
            phi1   : out std_logic;
            phi2   : out std_logic;
            sync   : out std_logic
        );
    end component;

    signal clk_in : std_logic := '0';
    signal reset  : std_logic := '1';
    signal phi1   : std_logic;
    signal phi2   : std_logic;
    signal sync   : std_logic;

    constant CLK_PERIOD : time := 10 ns;  -- 100 MHz input clock
    signal done : boolean := false;

begin

    -- Unit under test
    uut : phase_clocks
        port map (
            clk_in => clk_in,
            reset  => reset,
            phi1   => phi1,
            phi2   => phi2,
            sync   => sync
        );

    -- Clock generation (100 MHz = 10 ns period)
    process
    begin
        while not done loop
            clk_in <= '0';
            wait for CLK_PERIOD / 2;
            clk_in <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    -- Test stimulus
    process
        variable errors : integer := 0;
        variable prev_sync : std_logic;
    begin
        report "========================================";
        report "Phase Clocks with SYNC Test";
        report "========================================";

        -- Release reset
        reset <= '1';
        wait for CLK_PERIOD * 10;
        reset <= '0';
        wait for CLK_PERIOD * 5;

        report "Test 1: SYNC toggles every clock cycle (T_CY)";
        report "  T_CY = phi1 rising to next phi1 rising";
        report "  One clock cycle = phi1 pulse + phi2 pulse";

        -- Wait for first phi2 to fall (end of first T_CY)
        wait until phi2 = '0';
        wait for CLK_PERIOD * 10;

        if sync /= '1' then
            report "  ERROR: SYNC should be HIGH during first clock cycle" severity error;
            errors := errors + 1;
        else
            report "  PASS: Clock cycle 1 (phi11+phi21): SYNC = HIGH";
        end if;

        -- Wait for second phi2 to fall (end of second T_CY)
        wait until phi2 = '1';
        wait until phi2 = '0';
        wait for CLK_PERIOD * 10;

        if sync /= '0' then
            report "  ERROR: SYNC should be LOW during second clock cycle" severity error;
            errors := errors + 1;
        else
            report "  PASS: Clock cycle 2 (phi12+phi22): SYNC = LOW";
        end if;

        -- Check pattern continues: HIGH, LOW, HIGH, LOW
        for i in 3 to 8 loop
            wait until phi2 = '1';
            wait until phi2 = '0';
            wait for CLK_PERIOD * 10;

            -- Odd cycles should have SYNC high, even cycles should have SYNC low
            if (i mod 2 = 1 and sync /= '1') or (i mod 2 = 0 and sync /= '0') then
                report "  ERROR: Clock cycle " & integer'image(i) & ": SYNC = " & std_logic'image(sync) severity error;
                errors := errors + 1;
            else
                report "  PASS: Clock cycle " & integer'image(i) & ": SYNC = " & std_logic'image(sync);
            end if;
        end loop;

        report "";
        report "Test 2: Verify phi1 and phi2 never overlap";

        -- Check for a few microseconds
        for i in 1 to 1000 loop
            wait for CLK_PERIOD;
            if phi1 = '1' and phi2 = '1' then
                report "  ERROR: PHI1 and PHI2 both high at same time!" severity error;
                errors := errors + 1;
            end if;
        end loop;

        report "  PASS: No overlap detected in 1000 input clock cycles";

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

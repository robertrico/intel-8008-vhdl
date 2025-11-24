--------------------------------------------------------------------------------
-- interrupt_ready_ff_tb.vhdl
--------------------------------------------------------------------------------
-- Testbench for Interrupt and Ready Flip-Flops
-- Tests: Interrupt set/clear, Ready sampling
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.b8008_types.all;

entity interrupt_ready_ff_tb is
end entity interrupt_ready_ff_tb;

architecture test of interrupt_ready_ff_tb is

    component interrupt_ready_ff is
        port (
            phi2              : in std_logic;
            reset             : in std_logic;
            int_request       : in std_logic;
            int_clear         : in std_logic;
            ready_in          : in std_logic;
            interrupt_pending : out std_logic;
            ready_status      : out std_logic
        );
    end component;

    -- Clock
    signal phi2 : std_logic := '0';
    constant phi2_period : time := 500 ns;

    -- Inputs
    signal reset       : std_logic := '0';
    signal int_request : std_logic := '0';
    signal int_clear   : std_logic := '0';
    signal ready_in    : std_logic := '1';

    -- Outputs
    signal interrupt_pending : std_logic;
    signal ready_status      : std_logic;

begin

    -- Clock generation
    phi2 <= not phi2 after phi2_period / 2;

    uut : interrupt_ready_ff
        port map (
            phi2              => phi2,
            reset             => reset,
            int_request       => int_request,
            int_clear         => int_clear,
            ready_in          => ready_in,
            interrupt_pending => interrupt_pending,
            ready_status      => ready_status
        );

    test_process : process
        variable errors : integer := 0;
    begin
        report "========================================";
        report "Interrupt and Ready FF Test";
        report "========================================";

        -- Test 1: Reset clears interrupt and sets ready
        report "";
        report "Test 1: Reset state";

        reset <= '1';
        wait for phi2_period;
        reset <= '0';
        wait for phi2_period;

        if interrupt_pending /= '0' then
            report "  ERROR: Interrupt should be cleared after reset" severity error;
            errors := errors + 1;
        end if;

        if ready_status /= '1' then
            report "  ERROR: Ready should be high after reset" severity error;
            errors := errors + 1;
        end if;

        if interrupt_pending = '0' and ready_status = '1' then
            report "  PASS: Reset state correct";
        end if;

        -- Test 2: Set interrupt
        report "";
        report "Test 2: Set interrupt request";

        int_request <= '1';
        wait until rising_edge(phi2);
        wait for 10 ns;
        int_request <= '0';

        if interrupt_pending /= '1' then
            report "  ERROR: Interrupt should be set" severity error;
            errors := errors + 1;
        else
            report "  PASS: Interrupt set correctly";
        end if;

        -- Test 3: Interrupt stays set
        report "";
        report "Test 3: Interrupt remains set";

        wait for phi2_period * 2;

        if interrupt_pending /= '1' then
            report "  ERROR: Interrupt should remain set" severity error;
            errors := errors + 1;
        else
            report "  PASS: Interrupt remains set";
        end if;

        -- Test 4: Clear interrupt
        report "";
        report "Test 4: Clear interrupt";

        int_clear <= '1';
        wait until rising_edge(phi2);
        wait for 10 ns;
        int_clear <= '0';

        if interrupt_pending /= '0' then
            report "  ERROR: Interrupt should be cleared" severity error;
            errors := errors + 1;
        else
            report "  PASS: Interrupt cleared correctly";
        end if;

        -- Test 5: Ready low (not ready)
        report "";
        report "Test 5: Sample ready low";

        ready_in <= '0';
        wait until rising_edge(phi2);
        wait for 10 ns;

        if ready_status /= '0' then
            report "  ERROR: Ready should be low" severity error;
            errors := errors + 1;
        else
            report "  PASS: Ready sampled low";
        end if;

        -- Test 6: Ready high again
        report "";
        report "Test 6: Sample ready high";

        ready_in <= '1';
        wait until rising_edge(phi2);
        wait for 10 ns;

        if ready_status /= '1' then
            report "  ERROR: Ready should be high" severity error;
            errors := errors + 1;
        else
            report "  PASS: Ready sampled high";
        end if;

        -- Test 7: Simultaneous interrupt set and clear (clear wins)
        report "";
        report "Test 7: Interrupt set and clear simultaneously";

        int_request <= '1';
        int_clear   <= '1';
        wait until rising_edge(phi2);
        wait for 10 ns;
        int_request <= '0';
        int_clear   <= '0';

        if interrupt_pending /= '0' then
            report "  ERROR: Clear should take priority" severity error;
            errors := errors + 1;
        else
            report "  PASS: Clear takes priority over set";
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

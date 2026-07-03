--------------------------------------------------------------------------------
-- int_button_tb.vhdl
--------------------------------------------------------------------------------
-- Testbench for int_button
-- Cases:
--   1. flip while unarmed          -> no request
--   2. flip with bounce, armed     -> exactly one request, vector RST 5
--   3. request holds until t1i_ack -> then drops
--   4. flip other direction, vector_sel=1 -> one request, vector RST 7
--   5. two flips inside the debounce window -> still exactly one request
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity int_button_tb is
end entity int_button_tb;

architecture test of int_button_tb is

    constant CLK_PERIOD : time := 40 ns;   -- 25 MHz

    signal clk        : std_logic := '0';
    signal reset      : std_logic := '1';
    signal sw_raw     : std_logic := '0';
    signal vector_sel : std_logic := '0';
    signal armed      : std_logic := '0';
    signal t1i_ack    : std_logic := '0';
    signal int_req    : std_logic;
    signal int_vector : std_logic_vector(2 downto 0);

    signal done : boolean := false;

    -- DEBOUNCE_MS=1 at 25 MHz -> 25000 cycles = 1 ms
    constant DEBOUNCE_TIME : time := 1 ms;

begin

    clk <= not clk after CLK_PERIOD / 2 when not done else '0';

    uut : entity work.int_button
        generic map (
            CLK_FREQ_HZ => 25_000_000,
            DEBOUNCE_MS => 1
        )
        port map (
            clk        => clk,
            reset      => reset,
            sw_raw     => sw_raw,
            vector_sel => vector_sel,
            armed      => armed,
            t1i_ack    => t1i_ack,
            int_req    => int_req,
            int_vector => int_vector
        );

    stimulus : process
        variable errors : integer := 0;
    begin
        report "========================================";
        report "int_button Test";
        report "========================================";

        reset <= '1';
        wait for 10 * CLK_PERIOD;
        reset <= '0';
        wait for 10 * CLK_PERIOD;

        -- Case 1: flip while unarmed -> no request
        report "Case 1: flip while unarmed";
        sw_raw <= '1';
        wait for DEBOUNCE_TIME + DEBOUNCE_TIME / 2;
        if int_req /= '0' then
            report "  ERROR: request raised while unarmed" severity error;
            errors := errors + 1;
        else
            report "  PASS: no request while unarmed";
        end if;

        -- Case 2: armed, flip 1->0 with bounce -> one request, RST 5
        report "Case 2: bouncy flip while armed (vector_sel=0)";
        armed <= '1';
        wait for 10 * CLK_PERIOD;
        -- bouncy transition to '0'
        sw_raw <= '0';
        wait for 200 ns;
        sw_raw <= '1';
        wait for 200 ns;
        sw_raw <= '0';
        wait for 200 ns;
        sw_raw <= '1';
        wait for 200 ns;
        sw_raw <= '0';
        wait for DEBOUNCE_TIME + DEBOUNCE_TIME / 2;
        if int_req /= '1' then
            report "  ERROR: no request after debounced flip" severity error;
            errors := errors + 1;
        elsif int_vector /= "101" then
            report "  ERROR: vector should be RST 5 (101)" severity error;
            errors := errors + 1;
        else
            report "  PASS: one request, vector RST 5";
        end if;

        -- Case 3: request holds until t1i_ack
        report "Case 3: request holds until t1i_ack";
        wait for 1 ms;
        if int_req /= '1' then
            report "  ERROR: request dropped without ack" severity error;
            errors := errors + 1;
        end if;
        t1i_ack <= '1';
        wait for 4 * CLK_PERIOD;
        t1i_ack <= '0';
        wait for 4 * CLK_PERIOD;
        if int_req /= '0' then
            report "  ERROR: request not cleared by t1i_ack" severity error;
            errors := errors + 1;
        else
            report "  PASS: held until ack, then cleared";
        end if;

        -- Case 4: flip 0->1 with vector_sel=1 -> RST 7
        report "Case 4: opposite-direction flip, vector_sel=1";
        vector_sel <= '1';
        wait for 10 * CLK_PERIOD;
        sw_raw <= '1';
        wait for DEBOUNCE_TIME + DEBOUNCE_TIME / 2;
        if int_req /= '1' or int_vector /= "111" then
            report "  ERROR: expected request with vector RST 7 (111)" severity error;
            errors := errors + 1;
        else
            report "  PASS: one request, vector RST 7";
        end if;
        t1i_ack <= '1';
        wait for 4 * CLK_PERIOD;
        t1i_ack <= '0';
        wait for 4 * CLK_PERIOD;

        -- Case 5: two flips inside one debounce window -> one request max
        report "Case 5: chatter inside debounce window";
        sw_raw <= '0';
        wait for DEBOUNCE_TIME / 4;   -- shorter than debounce
        sw_raw <= '1';
        wait for DEBOUNCE_TIME / 4;   -- bounce back before acceptance
        -- net effect: back at '1' (current stable level), no accepted flip
        wait for 2 * DEBOUNCE_TIME;
        if int_req /= '0' then
            report "  ERROR: chatter shorter than debounce raised a request" severity error;
            errors := errors + 1;
        else
            report "  PASS: sub-debounce chatter ignored";
        end if;

        -- Case 6: pin resting at '1' across reset must NOT fire once armed
        report "Case 6: reset with pin high - settle, no spurious request";
        reset <= '1';
        sw_raw <= '1';               -- board pin rests high
        armed  <= '1';               -- worst case: armed immediately
        wait for 10 * CLK_PERIOD;
        reset <= '0';
        wait for 3 * DEBOUNCE_TIME;  -- settle window + margin
        if int_req /= '0' then
            report "  ERROR: spurious request from resting-high pin" severity error;
            errors := errors + 1;
        else
            report "  PASS: resting-high pin adopted silently";
        end if;
        -- and a real flip afterwards still fires
        sw_raw <= '0';
        wait for DEBOUNCE_TIME + DEBOUNCE_TIME / 2;
        if int_req /= '1' then
            report "  ERROR: real flip after settle did not fire" severity error;
            errors := errors + 1;
        else
            report "  PASS: real flip after settle fires";
        end if;
        t1i_ack <= '1';
        wait for 4 * CLK_PERIOD;
        t1i_ack <= '0';

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

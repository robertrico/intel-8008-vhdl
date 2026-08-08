------------------------------------------------------------------
-- props.vhdl: formal properties for interrupt_ready_ff
--
-- Proves:
--   P1  reset: interrupt 0, ready 1
--   P2  phi2 + int_clear clears the interrupt FF (clear wins)
--   P3  phi2 + int_request (no clear) sets it
--   P4  phi2 with neither leaves it; no phi2 holds both FFs
--   P5  phi2 samples ready_in into the ready FF
------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity interrupt_ready_ff_props is
    port (
        clk         : in std_logic;
        phi2_rising : in std_logic;
        reset       : in std_logic;
        int_request : in std_logic;
        int_clear   : in std_logic;
        ready_in    : in std_logic
    );
end entity interrupt_ready_ff_props;

architecture formal of interrupt_ready_ff_props is
    signal int_p, rdy : std_logic;

    signal tick : std_logic;

    -- one cycle of history (updated every clk, so induction-friendly)
    signal p_int, p_rdy : std_logic := '0';
    signal p_req, p_clr, p_rin, p_tick : std_logic := '0';
begin

    dut: entity work.interrupt_ready_ff
        port map (
            clk => clk, phi2_rising => phi2_rising, reset => reset,
            int_request => int_request, int_clear => int_clear,
            ready_in => ready_in,
            interrupt_pending => int_p, ready_status => rdy);

    tick <= phi2_rising and not reset;

    history: process(clk)
    begin
        if rising_edge(clk) then
            p_int <= int_p; p_rdy <= rdy;
            p_req <= int_request; p_clr <= int_clear; p_rin <= ready_in;
            p_tick <= tick;
        end if;
    end process;

    default clock is rising_edge(clk);

    -- P1: reset state
    assert always (reset = '1') -> ((int_p = '0') and (rdy = '1'));

    -- P2: clear wins
    assert (always ((tick and int_clear) = '1') -> next (int_p = '0'))
        abort (reset = '1');

    -- P3: request sets (when not cleared)
    assert (always ((tick and int_request and not int_clear) = '1') ->
        next (int_p = '1')) abort (reset = '1');

    -- P4: holds
    assert (always ((tick and not int_request and not int_clear) = '1') ->
        next (int_p = p_int)) abort (reset = '1');
    assert (always (tick = '0') ->
        next ((int_p = p_int) and (rdy = p_rdy))) abort (reset = '1');

    -- P5: ready FF samples ready_in on every phi2
    assert (always (tick = '1') -> next (rdy = p_rin)) abort (reset = '1');

    -- Reachability
    cover {(int_p = '1'); (int_p = '0')};
    cover {(rdy = '0'); (rdy = '1')};

end architecture formal;

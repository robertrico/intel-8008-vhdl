------------------------------------------------------------------
-- miter.vhdl: interrupt_ready_ff RTL vs write_vhdl round trip
-- Both FFs visible through the outputs: induction closes.
------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity interrupt_ready_ff_miter is
    port (
        clk         : in std_logic;
        phi2_rising : in std_logic;
        reset       : in std_logic;
        int_request : in std_logic;
        int_clear   : in std_logic;
        ready_in    : in std_logic
    );
end entity interrupt_ready_ff_miter;

architecture formal of interrupt_ready_ff_miter is
    signal ip_gold, ip_gate, rs_gold, rs_gate : std_logic;
begin

    gold: entity work.interrupt_ready_ff
        port map (
            clk => clk, phi2_rising => phi2_rising, reset => reset,
            int_request => int_request, int_clear => int_clear,
            ready_in => ready_in,
            interrupt_pending => ip_gold, ready_status => rs_gold);

    gate: entity work.interrupt_ready_ff_gate
        port map (
            clk => clk, phi2_rising => phi2_rising, reset => reset,
            int_request => int_request, int_clear => int_clear,
            ready_in => ready_in,
            interrupt_pending => ip_gate, ready_status => rs_gate);

    default clock is rising_edge(clk);

    assert always (ip_gold = ip_gate);
    assert always (rs_gold = rs_gate);

end architecture formal;

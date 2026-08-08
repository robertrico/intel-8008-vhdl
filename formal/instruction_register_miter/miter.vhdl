------------------------------------------------------------------
-- miter.vhdl: instruction_register RTL vs write_vhdl round trip
-- All 8 state bits visible through the outputs: induction closes.
------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity instruction_register_miter is
    port (
        clk          : in std_logic;
        phi1_falling : in std_logic;
        reset        : in std_logic;
        internal_bus_in : in std_logic_vector(7 downto 0);
        load_ir      : in std_logic;
        output_ir    : in std_logic
    );
end entity instruction_register_miter;

architecture formal of instruction_register_miter is
    signal bo_gold, bo_gate : std_logic_vector(7 downto 0);
    signal oe_gold, oe_gate : std_logic;
    signal g7, g6, g5, g4, g3, g2, g1, g0 : std_logic;
    signal n7, n6, n5, n4, n3, n2, n1, n0 : std_logic;
begin

    gold: entity work.instruction_register
        port map (
            clk => clk, phi1_falling => phi1_falling, reset => reset,
            internal_bus_in => internal_bus_in,
            internal_bus_out => bo_gold, internal_bus_oe => oe_gold,
            load_ir => load_ir, output_ir => output_ir,
            ir_bit_7 => g7, ir_bit_6 => g6, ir_bit_5 => g5, ir_bit_4 => g4,
            ir_bit_3 => g3, ir_bit_2 => g2, ir_bit_1 => g1, ir_bit_0 => g0);

    gate: entity work.instruction_register_gate
        port map (
            clk => clk, phi1_falling => phi1_falling, reset => reset,
            internal_bus_in => internal_bus_in,
            internal_bus_out => bo_gate, internal_bus_oe => oe_gate,
            load_ir => load_ir, output_ir => output_ir,
            ir_bit_7 => n7, ir_bit_6 => n6, ir_bit_5 => n5, ir_bit_4 => n4,
            ir_bit_3 => n3, ir_bit_2 => n2, ir_bit_1 => n1, ir_bit_0 => n0);

    default clock is rising_edge(clk);

    assert always (bo_gold = bo_gate);
    assert always (oe_gold = oe_gate);
    assert always ((g7 & g6 & g5 & g4 & g3 & g2 & g1 & g0)
                 = (n7 & n6 & n5 & n4 & n3 & n2 & n1 & n0));

end architecture formal;

------------------------------------------------------------------
-- miter.vhdl: temp_registers RTL vs write_vhdl round trip
-- Both registers visible through reg_a_out/reg_b_out: induction closes.
------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity temp_registers_miter is
    port (
        clk         : in std_logic;
        phi2_rising : in std_logic;
        reset       : in std_logic;
        load_reg_a  : in std_logic;
        load_reg_b  : in std_logic;
        output_reg_a : in std_logic;
        output_reg_b : in std_logic;
        internal_bus_in : in std_logic_vector(7 downto 0)
    );
end entity temp_registers_miter;

architecture formal of temp_registers_miter is
    signal bo_gold, bo_gate : std_logic_vector(7 downto 0);
    signal oe_gold, oe_gate : std_logic;
    signal a_gold, a_gate, b_gold, b_gate : std_logic_vector(7 downto 0);
begin

    gold: entity work.temp_registers
        port map (
            clk => clk, phi2_rising => phi2_rising, reset => reset,
            load_reg_a => load_reg_a, load_reg_b => load_reg_b,
            output_reg_a => output_reg_a, output_reg_b => output_reg_b,
            internal_bus_in => internal_bus_in,
            internal_bus_out => bo_gold, internal_bus_oe => oe_gold,
            reg_a_out => a_gold, reg_b_out => b_gold);

    gate: entity work.temp_registers_gate
        port map (
            clk => clk, phi2_rising => phi2_rising, reset => reset,
            load_reg_a => load_reg_a, load_reg_b => load_reg_b,
            output_reg_a => output_reg_a, output_reg_b => output_reg_b,
            internal_bus_in => internal_bus_in,
            internal_bus_out => bo_gate, internal_bus_oe => oe_gate,
            reg_a_out => a_gate, reg_b_out => b_gate);

    default clock is rising_edge(clk);

    assert always (bo_gold = bo_gate);
    assert always (oe_gold = oe_gate);
    assert always (a_gold = a_gate);
    assert always (b_gold = b_gate);

end architecture formal;

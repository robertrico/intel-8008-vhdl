------------------------------------------------------------------
-- miter.vhdl: alu gold (RTL) vs gate (write_vhdl round trip).
-- alu has a clocked result stage, so EQY's flop matching would break
-- on write_vhdl's vector-flop splitting; the miter decides instead
-- (same pattern proven on stack_pointer).
------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity alu_miter is
    port (
        clk            : in std_logic;
        phi2_rising    : in std_logic;
        accumulator_in : in std_logic_vector(7 downto 0);
        reg_b_in       : in std_logic_vector(7 downto 0);
        opcode         : in std_logic_vector(2 downto 0);
        is_inr_dcr     : in std_logic;
        is_rotate      : in std_logic;
        carry_in       : in std_logic;
        enable         : in std_logic;
        output_result  : in std_logic
    );
end entity alu_miter;

architecture formal of alu_miter is
    signal gold_bus, gate_bus       : std_logic_vector(7 downto 0);
    signal gold_oe, gate_oe         : std_logic;
    signal gold_result, gate_result : std_logic_vector(8 downto 0);
    signal gold_c, gate_c, gold_z, gate_z : std_logic;
    signal gold_s, gate_s, gold_p, gate_p : std_logic;
begin

    gold: entity work.alu
        port map (
            clk => clk, phi2_rising => phi2_rising,
            accumulator_in => accumulator_in, reg_b_in => reg_b_in,
            opcode => opcode, is_inr_dcr => is_inr_dcr,
            is_rotate => is_rotate, carry_in => carry_in,
            enable => enable, output_result => output_result,
            internal_bus_out => gold_bus, internal_bus_oe => gold_oe,
            result => gold_result, flag_carry => gold_c,
            flag_zero => gold_z, flag_sign => gold_s, flag_parity => gold_p);

    gate: entity work.alu_gate
        port map (
            clk => clk, phi2_rising => phi2_rising,
            accumulator_in => accumulator_in, reg_b_in => reg_b_in,
            opcode => opcode, is_inr_dcr => is_inr_dcr,
            is_rotate => is_rotate, carry_in => carry_in,
            enable => enable, output_result => output_result,
            internal_bus_out => gate_bus, internal_bus_oe => gate_oe,
            result => gate_result, flag_carry => gate_c,
            flag_zero => gate_z, flag_sign => gate_s, flag_parity => gate_p);

    default clock is rising_edge(clk);
    assert always (gold_bus = gate_bus);
    assert always (gold_oe = gate_oe);
    assert always (gold_result = gate_result);
    assert always ((gold_c = gate_c) and (gold_z = gate_z)
               and (gold_s = gate_s) and (gold_p = gate_p));

end architecture formal;

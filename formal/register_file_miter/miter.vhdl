------------------------------------------------------------------
-- miter.vhdl: register_file RTL vs write_vhdl round-trip netlist
--
-- Same stimulus into both; every output must match every cycle.
-- All 56 state bits are visible through the debug outputs, so the
-- equality asserts anchor the gate flops for induction.
------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity register_file_miter is
    port (
        clk          : in std_logic;
        phi2_rising  : in std_logic;
        reset        : in std_logic;
        data_in      : in std_logic_vector(7 downto 0);
        enable_a     : in std_logic;
        enable_b     : in std_logic;
        enable_c     : in std_logic;
        enable_d     : in std_logic;
        enable_e     : in std_logic;
        enable_h     : in std_logic;
        enable_l     : in std_logic;
        read_enable  : in std_logic;
        write_enable : in std_logic
    );
end entity register_file_miter;

architecture formal of register_file_miter is
    signal do_gold, do_gate   : std_logic_vector(7 downto 0);
    signal acc_gold, acc_gate : std_logic_vector(7 downto 0);
    signal a_gold, b_gold, c_gold, d_gold, e_gold, h_gold, l_gold : std_logic_vector(7 downto 0);
    signal a_gate, b_gate, c_gate, d_gate, e_gate, h_gate, l_gate : std_logic_vector(7 downto 0);
begin

    gold: entity work.register_file
        port map (
            clk => clk, phi2_rising => phi2_rising, reset => reset,
            data_in => data_in, data_out => do_gold,
            enable_a => enable_a, enable_b => enable_b,
            enable_c => enable_c, enable_d => enable_d,
            enable_e => enable_e, enable_h => enable_h,
            enable_l => enable_l,
            read_enable => read_enable, write_enable => write_enable,
            accumulator_out => acc_gold,
            debug_reg_a => a_gold, debug_reg_b => b_gold,
            debug_reg_c => c_gold, debug_reg_d => d_gold,
            debug_reg_e => e_gold, debug_reg_h => h_gold,
            debug_reg_l => l_gold);

    gate: entity work.register_file_gate
        port map (
            clk => clk, phi2_rising => phi2_rising, reset => reset,
            data_in => data_in, data_out => do_gate,
            enable_a => enable_a, enable_b => enable_b,
            enable_c => enable_c, enable_d => enable_d,
            enable_e => enable_e, enable_h => enable_h,
            enable_l => enable_l,
            read_enable => read_enable, write_enable => write_enable,
            accumulator_out => acc_gate,
            debug_reg_a => a_gate, debug_reg_b => b_gate,
            debug_reg_c => c_gate, debug_reg_d => d_gate,
            debug_reg_e => e_gate, debug_reg_h => h_gate,
            debug_reg_l => l_gate);

    default clock is rising_edge(clk);

    assert always (do_gold = do_gate);
    assert always (acc_gold = acc_gate);
    assert always (a_gold = a_gate);
    assert always (b_gold = b_gate);
    assert always (c_gold = c_gate);
    assert always (d_gold = d_gate);
    assert always (e_gold = e_gate);
    assert always (h_gold = h_gate);
    assert always (l_gold = l_gate);

end architecture formal;

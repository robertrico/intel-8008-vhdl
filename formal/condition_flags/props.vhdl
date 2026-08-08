------------------------------------------------------------------
-- props.vhdl: formal properties for condition_flags
--
-- Proves:
--   P1  reset clears all four flags
--   P2  full update: phi2+update (carry_only=0) loads all four inputs
--   P3  carry_only update: carry loads, Z/S/P hold
--   P4  no update: all four hold
--   P5  bus format is "0000" & C & P & Z & S (DS72 p.37 INP T4 order:
--       S->D0 Z->D1 P->D2 C->D3), oe mirrors output_flags
--   P6  condition_met truth table: 1 when unconditional; otherwise
--       selected flag (cc: 00=C 01=Z 10=S 11=P) xnor'd with test sense
------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity condition_flags_props is
    port (
        clk            : in std_logic;
        phi2_rising    : in std_logic;
        reset          : in std_logic;
        flag_carry_in  : in std_logic;
        flag_zero_in   : in std_logic;
        flag_sign_in   : in std_logic;
        flag_parity_in : in std_logic;
        update_flags   : in std_logic;
        carry_only     : in std_logic;
        condition_code : in std_logic_vector(1 downto 0);
        test_true      : in std_logic;
        eval_condition : in std_logic;
        output_flags   : in std_logic
    );
end entity condition_flags_props;

architecture formal of condition_flags_props is
    signal bus_out       : std_logic_vector(7 downto 0);
    signal bus_oe        : std_logic;
    signal condition_met : std_logic;
    signal fc, fz, fs, fp : std_logic;

    signal upd      : std_logic;
    signal upd_c    : std_logic;
    signal sel_flag : std_logic;

    -- one cycle of history (updated every clk, so induction-friendly)
    signal pc_c, pc_z, pc_s, pc_p : std_logic := '0';
    signal in_c, in_z, in_s, in_p : std_logic := '0';
begin

    dut: entity work.condition_flags
        port map (
            clk => clk, phi2_rising => phi2_rising, reset => reset,
            flag_carry_in => flag_carry_in, flag_zero_in => flag_zero_in,
            flag_sign_in => flag_sign_in, flag_parity_in => flag_parity_in,
            update_flags => update_flags, carry_only => carry_only,
            condition_code => condition_code, test_true => test_true,
            eval_condition => eval_condition, output_flags => output_flags,
            internal_bus_out => bus_out, internal_bus_oe => bus_oe,
            condition_met => condition_met,
            flag_carry => fc, flag_zero => fz, flag_sign => fs,
            flag_parity => fp);

    upd <= phi2_rising and update_flags and not reset;
    upd_c <= upd and carry_only;

    with condition_code select sel_flag <=
        fc when "00", fz when "01", fs when "10", fp when others;

    history: process(clk)
    begin
        if rising_edge(clk) then
            pc_c <= fc; pc_z <= fz; pc_s <= fs; pc_p <= fp;
            in_c <= flag_carry_in; in_z <= flag_zero_in;
            in_s <= flag_sign_in;  in_p <= flag_parity_in;
        end if;
    end process;

    default clock is rising_edge(clk);

    -- P1: reset clears
    assert always (reset = '1') ->
        ((fc = '0') and (fz = '0') and (fs = '0') and (fp = '0'));

    -- P2: full update loads all four
    assert (always ((upd and not carry_only) = '1') ->
            next ((fc = in_c) and (fz = in_z) and (fs = in_s) and (fp = in_p)))
        abort (reset = '1');

    -- P3: carry_only loads carry, holds the rest
    assert (always ((upd and carry_only) = '1') ->
            next ((fc = in_c) and (fz = pc_z) and (fs = pc_s) and (fp = pc_p)))
        abort (reset = '1');

    -- P4: no update means hold
    assert (always (upd = '0') ->
            next ((fc = pc_c) and (fz = pc_z) and (fs = pc_s) and (fp = pc_p)))
        abort (reset = '1');

    -- P5: bus format and output enable
    assert always (bus_out = ("0000" & fc & fp & fz & fs));
    assert always (bus_oe = output_flags);

    -- P6: condition evaluation truth table (combinational)
    assert always (eval_condition = '0') -> (condition_met = '1');
    assert always ((eval_condition and test_true) = '1') ->
        (condition_met = sel_flag);
    assert always ((eval_condition and not test_true) = '1') ->
        (condition_met = not sel_flag);

    -- Reachability
    cover {condition_met = '0'};
    cover {upd_c = '1'; fz = '1'};
    cover {bus_out = "00001111"};

end architecture formal;

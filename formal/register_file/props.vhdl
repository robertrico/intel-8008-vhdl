------------------------------------------------------------------
-- props.vhdl: formal properties for register_file
--
-- Proves:
--   P1  reset clears all seven registers
--   P2  write: phi2_rising + write_enable + enable_x loads data_in
--       into register x (each register independent)
--   P3  hold: a register without a write pulse keeps its value
--   P4  read mux: read_enable=0 drives 0x00; otherwise priority
--       order A > B > C > D > E > H > L; no enable drives 0x00
--   P5  accumulator_out always mirrors register A
------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity register_file_props is
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
end entity register_file_props;

architecture formal of register_file_props is
    signal data_out : std_logic_vector(7 downto 0);
    signal acc      : std_logic_vector(7 downto 0);
    signal ra, rb, rc, rd, re, rh, rl : std_logic_vector(7 downto 0);

    signal wr : std_logic;

    -- one cycle of history (updated every clk, so induction-friendly)
    signal p_a, p_b, p_c, p_d, p_e, p_h, p_l : std_logic_vector(7 downto 0) := (others => '0');
    signal p_di : std_logic_vector(7 downto 0) := (others => '0');
begin

    dut: entity work.register_file
        port map (
            clk => clk, phi2_rising => phi2_rising, reset => reset,
            data_in => data_in, data_out => data_out,
            enable_a => enable_a, enable_b => enable_b,
            enable_c => enable_c, enable_d => enable_d,
            enable_e => enable_e, enable_h => enable_h,
            enable_l => enable_l,
            read_enable => read_enable, write_enable => write_enable,
            accumulator_out => acc,
            debug_reg_a => ra, debug_reg_b => rb, debug_reg_c => rc,
            debug_reg_d => rd, debug_reg_e => re, debug_reg_h => rh,
            debug_reg_l => rl);

    wr <= phi2_rising and write_enable and not reset;

    history: process(clk)
    begin
        if rising_edge(clk) then
            p_a <= ra; p_b <= rb; p_c <= rc; p_d <= rd;
            p_e <= re; p_h <= rh; p_l <= rl;
            p_di <= data_in;
        end if;
    end process;

    default clock is rising_edge(clk);

    -- P1: reset clears all registers
    assert always (reset = '1') ->
        ((ra = x"00") and (rb = x"00") and (rc = x"00") and (rd = x"00") and
         (re = x"00") and (rh = x"00") and (rl = x"00"));

    -- P2: write pulse loads data_in into each enabled register
    assert (always ((wr and enable_a) = '1') -> next (ra = p_di)) abort (reset = '1');
    assert (always ((wr and enable_b) = '1') -> next (rb = p_di)) abort (reset = '1');
    assert (always ((wr and enable_c) = '1') -> next (rc = p_di)) abort (reset = '1');
    assert (always ((wr and enable_d) = '1') -> next (rd = p_di)) abort (reset = '1');
    assert (always ((wr and enable_e) = '1') -> next (re = p_di)) abort (reset = '1');
    assert (always ((wr and enable_h) = '1') -> next (rh = p_di)) abort (reset = '1');
    assert (always ((wr and enable_l) = '1') -> next (rl = p_di)) abort (reset = '1');

    -- P3: registers without a write pulse hold
    assert (always ((wr and enable_a) = '0') -> next (ra = p_a)) abort (reset = '1');
    assert (always ((wr and enable_b) = '0') -> next (rb = p_b)) abort (reset = '1');
    assert (always ((wr and enable_c) = '0') -> next (rc = p_c)) abort (reset = '1');
    assert (always ((wr and enable_d) = '0') -> next (rd = p_d)) abort (reset = '1');
    assert (always ((wr and enable_e) = '0') -> next (re = p_e)) abort (reset = '1');
    assert (always ((wr and enable_h) = '0') -> next (rh = p_h)) abort (reset = '1');
    assert (always ((wr and enable_l) = '0') -> next (rl = p_l)) abort (reset = '1');

    -- P4: read mux, priority A > B > C > D > E > H > L
    assert always (read_enable = '0') -> (data_out = x"00");
    assert always ((read_enable and enable_a) = '1') ->
        (data_out = ra);
    assert always ((read_enable and not enable_a and enable_b) = '1') ->
        (data_out = rb);
    assert always ((read_enable and not enable_a and not enable_b and enable_c) = '1') ->
        (data_out = rc);
    assert always ((read_enable and not enable_a and not enable_b and not enable_c and enable_d) = '1') ->
        (data_out = rd);
    assert always ((read_enable and not enable_a and not enable_b and not enable_c and not enable_d and enable_e) = '1') ->
        (data_out = re);
    assert always ((read_enable and not enable_a and not enable_b and not enable_c and not enable_d and not enable_e and enable_h) = '1') ->
        (data_out = rh);
    assert always ((read_enable and not enable_a and not enable_b and not enable_c and not enable_d and not enable_e and not enable_h and enable_l) = '1') ->
        (data_out = rl);
    assert always ((read_enable and not (enable_a or enable_b or enable_c or enable_d or enable_e or enable_h or enable_l)) = '1') ->
        (data_out = x"00");

    -- P5: accumulator direct path
    assert always (acc = ra);

    -- Reachability
    cover {((wr and enable_a) = '1'); (ra = x"5A")};
    cover {((wr and enable_h and enable_l) = '1')};  -- simultaneous multi-write
    cover {((read_enable and enable_l) = '1'); (data_out = x"A5")};

end architecture formal;

------------------------------------------------------------------
-- props.vhdl: formal properties for temp_registers (Reg.a / Reg.b)
--
-- Proves:
--   P1  reset clears both registers
--   P2  phi2_rising + load_reg_x loads the bus byte into x
--   P3  otherwise each register holds
--   P4  bus mux: Reg.a when output_reg_a else Reg.b; oe is the OR
------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity temp_registers_props is
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
end entity temp_registers_props;

architecture formal of temp_registers_props is
    signal bus_out : std_logic_vector(7 downto 0);
    signal bus_oe  : std_logic;
    signal ra, rb  : std_logic_vector(7 downto 0);

    signal ld_a, ld_b : std_logic;

    -- one cycle of history (updated every clk, so induction-friendly)
    signal p_a, p_b, p_di : std_logic_vector(7 downto 0) := (others => '0');
begin

    dut: entity work.temp_registers
        port map (
            clk => clk, phi2_rising => phi2_rising, reset => reset,
            load_reg_a => load_reg_a, load_reg_b => load_reg_b,
            output_reg_a => output_reg_a, output_reg_b => output_reg_b,
            internal_bus_in => internal_bus_in,
            internal_bus_out => bus_out, internal_bus_oe => bus_oe,
            reg_a_out => ra, reg_b_out => rb);

    ld_a <= phi2_rising and load_reg_a and not reset;
    ld_b <= phi2_rising and load_reg_b and not reset;

    history: process(clk)
    begin
        if rising_edge(clk) then
            p_a <= ra; p_b <= rb; p_di <= internal_bus_in;
        end if;
    end process;

    default clock is rising_edge(clk);

    -- P1: reset clears
    assert always (reset = '1') -> ((ra = x"00") and (rb = x"00"));

    -- P2: loads
    assert (always (ld_a = '1') -> next (ra = p_di)) abort (reset = '1');
    assert (always (ld_b = '1') -> next (rb = p_di)) abort (reset = '1');

    -- P3: holds
    assert (always (ld_a = '0') -> next (ra = p_a)) abort (reset = '1');
    assert (always (ld_b = '0') -> next (rb = p_b)) abort (reset = '1');

    -- P4: bus mux and output enable
    assert always (output_reg_a = '1') -> (bus_out = ra);
    assert always (output_reg_a = '0') -> (bus_out = rb);
    assert always (bus_oe = (output_reg_a or output_reg_b));

    -- Reachability
    cover {((ld_a and ld_b) = '1')};  -- simultaneous load of both
    cover {(ra = x"5A"); (bus_oe = '1')};

end architecture formal;

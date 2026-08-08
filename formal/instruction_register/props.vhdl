------------------------------------------------------------------
-- props.vhdl: formal properties for instruction_register
--
-- Proves:
--   P1  reset clears the IR
--   P2  phi1_falling + load_ir loads the bus byte
--   P3  otherwise the IR holds
--   P4  bus output mirrors the IR, oe mirrors output_ir
--   P5  decoder bit fan-out matches the IR
------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity instruction_register_props is
    port (
        clk          : in std_logic;
        phi1_falling : in std_logic;
        reset        : in std_logic;
        internal_bus_in : in std_logic_vector(7 downto 0);
        load_ir      : in std_logic;
        output_ir    : in std_logic
    );
end entity instruction_register_props;

architecture formal of instruction_register_props is
    signal bus_out : std_logic_vector(7 downto 0);
    signal bus_oe  : std_logic;
    signal b7, b6, b5, b4, b3, b2, b1, b0 : std_logic;

    signal ld : std_logic;

    -- one cycle of history (updated every clk, so induction-friendly)
    signal p_ir : std_logic_vector(7 downto 0) := (others => '0');
    signal p_di : std_logic_vector(7 downto 0) := (others => '0');
begin

    dut: entity work.instruction_register
        port map (
            clk => clk, phi1_falling => phi1_falling, reset => reset,
            internal_bus_in => internal_bus_in,
            internal_bus_out => bus_out, internal_bus_oe => bus_oe,
            load_ir => load_ir, output_ir => output_ir,
            ir_bit_7 => b7, ir_bit_6 => b6, ir_bit_5 => b5, ir_bit_4 => b4,
            ir_bit_3 => b3, ir_bit_2 => b2, ir_bit_1 => b1, ir_bit_0 => b0);

    ld <= phi1_falling and load_ir and not reset;

    history: process(clk)
    begin
        if rising_edge(clk) then
            p_ir <= bus_out;
            p_di <= internal_bus_in;
        end if;
    end process;

    default clock is rising_edge(clk);

    -- P1: reset clears
    assert always (reset = '1') -> (bus_out = x"00");

    -- P2: load
    assert (always (ld = '1') -> next (bus_out = p_di)) abort (reset = '1');

    -- P3: hold
    assert (always (ld = '0') -> next (bus_out = p_ir)) abort (reset = '1');

    -- P4: output enable mirrors control
    assert always (bus_oe = output_ir);

    -- P5: decoder bits mirror the IR
    assert always ((b7 & b6 & b5 & b4 & b3 & b2 & b1 & b0) = bus_out);

    -- Reachability
    cover {(ld = '1'); (bus_out = x"C7")};

end architecture formal;

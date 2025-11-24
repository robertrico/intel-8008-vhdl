--------------------------------------------------------------------------------
-- carry_lookahead.vhdl
--------------------------------------------------------------------------------
-- Carry Look-Ahead Logic for Intel 8008
--
-- Pre-computes carry propagation for 8-bit addition/subtraction
-- - Takes operands from Reg.a and Reg.b
-- - Receives enable signal from Register and ALU Control
-- - Outputs carry signals to ALU for fast arithmetic
-- - DUMB module: pure combinational logic, no state
--
-- Based on standard 4-bit carry look-ahead with extension to 8 bits
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.b8008_types.all;

entity carry_lookahead is
    port (
        -- Operand inputs from temp registers
        reg_a : in std_logic_vector(7 downto 0);
        reg_b : in std_logic_vector(7 downto 0);

        -- Carry input (from flags or operation)
        carry_in : in std_logic;

        -- Enable from Register and ALU Control
        enable : in std_logic;

        -- Carry outputs to ALU
        carry_out : out std_logic_vector(7 downto 0)  -- Carry for each bit position
    );
end entity carry_lookahead;

architecture rtl of carry_lookahead is

    -- Generate and Propagate signals for each bit
    signal gen : std_logic_vector(7 downto 0);  -- Generate signals (Gi)
    signal prop : std_logic_vector(7 downto 0); -- Propagate signals (Pi)

    -- Internal carry signals
    signal carry_internal : std_logic_vector(8 downto 0);

begin

    -- Compute Generate (Gi) and Propagate (Pi) for each bit
    -- Gi = Ai AND Bi (generates a carry)
    -- Pi = Ai XOR Bi (propagates a carry)
    gen_prop: for i in 0 to 7 generate
        gen(i) <= reg_a(i) and reg_b(i);
        prop(i) <= reg_a(i) xor reg_b(i);
    end generate;

    -- Carry input
    carry_internal(0) <= carry_in when enable = '1' else '0';

    -- Compute carry look-ahead for each bit position
    -- Ci+1 = Gi + Pi·Ci
    carry_internal(1) <= gen(0) or (prop(0) and carry_internal(0));
    carry_internal(2) <= gen(1) or (prop(1) and carry_internal(1));
    carry_internal(3) <= gen(2) or (prop(2) and carry_internal(2));
    carry_internal(4) <= gen(3) or (prop(3) and carry_internal(3));
    carry_internal(5) <= gen(4) or (prop(4) and carry_internal(4));
    carry_internal(6) <= gen(5) or (prop(5) and carry_internal(5));
    carry_internal(7) <= gen(6) or (prop(6) and carry_internal(6));
    carry_internal(8) <= gen(7) or (prop(7) and carry_internal(7));

    -- Output carries for each bit position (for ALU to use)
    -- ALU can use these for fast multi-bit operations
    carry_out <= carry_internal(7 downto 0) when enable = '1' else (others => '0');

end architecture rtl;

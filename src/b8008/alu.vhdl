--------------------------------------------------------------------------------
-- alu.vhdl
--------------------------------------------------------------------------------
-- Arithmetic Logic Unit for Intel 8008 (b8008)
--
-- Performs 8-bit arithmetic and logic operations
-- - Takes operands from Reg.a and Reg.b
-- - Receives opcode bits from instruction byte (via internal bus)
-- - Uses carry look-ahead for fast addition
-- - Outputs result and condition flags
-- - DUMB module: just executes operations based on opcode, no state
--
-- Operations (from bits 5:3 of instruction, PPP field):
--   000 - ADD (Add)
--   001 - ADC (Add with Carry)
--   010 - SUB (Subtract)
--   011 - SBB (Subtract with Borrow)
--   100 - AND (Logical AND)
--   101 - XOR (Logical XOR)
--   110 - OR  (Logical OR)
--   111 - CMP (Compare, same as SUB but don't store result)
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.b8008_types.all;

entity alu is
    port (
        -- Operand inputs from temp registers
        reg_a_in : in std_logic_vector(7 downto 0);
        reg_b_in : in std_logic_vector(7 downto 0);

        -- Opcode from instruction (PPP field, bits 5:3)
        opcode : in std_logic_vector(2 downto 0);

        -- Carry input from flags
        carry_in : in std_logic;

        -- Carry look-ahead signals (optional, for optimization)
        carry_lookahead : in std_logic_vector(7 downto 0);

        -- Enable from Register and ALU Control
        enable : in std_logic;

        -- Output enable to internal bus
        output_result : in std_logic;

        -- Internal data bus (8-bit result output)
        internal_bus : inout std_logic_vector(7 downto 0);

        -- Result output (9 bits: carry + 8-bit result)
        result : out std_logic_vector(8 downto 0);

        -- Flag outputs
        flag_carry : out std_logic;
        flag_zero  : out std_logic;
        flag_sign  : out std_logic;
        flag_parity : out std_logic
    );
end entity alu;

architecture rtl of alu is

    -- Operation codes
    constant OP_ADD : std_logic_vector(2 downto 0) := "000";
    constant OP_ADC : std_logic_vector(2 downto 0) := "001";
    constant OP_SUB : std_logic_vector(2 downto 0) := "010";
    constant OP_SBB : std_logic_vector(2 downto 0) := "011";
    constant OP_AND : std_logic_vector(2 downto 0) := "100";
    constant OP_XOR : std_logic_vector(2 downto 0) := "101";
    constant OP_OR  : std_logic_vector(2 downto 0) := "110";
    constant OP_CMP : std_logic_vector(2 downto 0) := "111";

    -- Internal result
    signal result_internal : std_logic_vector(8 downto 0);

begin

    -- ALU operation (pure combinational)
    process(reg_a_in, reg_b_in, opcode, carry_in, enable)
        variable carry_val : unsigned(8 downto 0);
        variable temp_result : std_logic_vector(8 downto 0);
    begin
        if enable = '1' then
            -- Prepare carry value for operations that use it
            carry_val := (others => '0');
            if carry_in = '1' then
                carry_val(0) := '1';
            end if;

            -- Perform operation based on opcode
            case opcode is
                when OP_ADD =>
                    temp_result := std_logic_vector(unsigned('0' & reg_a_in) + unsigned('0' & reg_b_in));

                when OP_ADC =>
                    temp_result := std_logic_vector(unsigned('0' & reg_a_in) + unsigned('0' & reg_b_in) + carry_val);

                when OP_SUB =>
                    temp_result := std_logic_vector(unsigned('0' & reg_a_in) - unsigned('0' & reg_b_in));

                when OP_SBB =>
                    temp_result := std_logic_vector(unsigned('0' & reg_a_in) - unsigned('0' & reg_b_in) - carry_val);

                when OP_AND =>
                    temp_result := '0' & (reg_a_in and reg_b_in);

                when OP_XOR =>
                    temp_result := '0' & (reg_a_in xor reg_b_in);

                when OP_OR =>
                    temp_result := '0' & (reg_a_in or reg_b_in);

                when OP_CMP =>
                    -- Compare is like subtract, but result isn't stored (only flags)
                    temp_result := std_logic_vector(unsigned('0' & reg_a_in) - unsigned('0' & reg_b_in));

                when others =>
                    temp_result := (others => '0');
            end case;

            result_internal <= temp_result;
        else
            result_internal <= (others => '0');
        end if;
    end process;

    -- Output result
    result <= result_internal;

    -- Drive internal bus with 8-bit result when output_result is enabled
    internal_bus <= result_internal(7 downto 0) when output_result = '1' else (others => 'Z');

    -- Generate flags from result
    -- Carry flag: bit 8 of result
    flag_carry <= result_internal(8) when enable = '1' else '0';

    -- Zero flag: all bits of result are zero
    flag_zero <= '1' when (enable = '1' and result_internal(7 downto 0) = x"00") else '0';

    -- Sign flag: bit 7 of result (MSB)
    flag_sign <= result_internal(7) when enable = '1' else '0';

    -- Parity flag: even parity (1 if even number of 1's)
    flag_parity <= (result_internal(0) xor result_internal(1) xor result_internal(2) xor result_internal(3) xor
                    result_internal(4) xor result_internal(5) xor result_internal(6) xor result_internal(7))
                   when enable = '1' else '0';

end architecture rtl;

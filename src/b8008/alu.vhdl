--------------------------------------------------------------------------------
-- alu.vhdl
--------------------------------------------------------------------------------
-- Arithmetic Logic Unit for Intel 8008 (b8008)
--
-- Performs 8-bit arithmetic and logic operations
-- - DUMB module: just executes operations based on opcode, no state
--
-- Architecture (based on actual Intel 8008):
-- - Accumulator feeds input 1 DIRECTLY (hardwired, not via temp register)
-- - Reg.b feeds input 2 (operand loaded via bus at T4)
-- - INR/DCR: ALU uses Reg.b as input 1 and generates +1/-1 internally
--
-- Operations (from bits 5:3 of instruction, PPP field):
--   000 - ADD (Add) / INR (Increment when is_inr_dcr=1)
--   001 - ADC (Add with Carry)
--   010 - SUB (Subtract) / DCR (Decrement when is_inr_dcr=1)
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
        -- Clock for latching result
        phi2 : in std_logic;

        -- Operand input 1: Direct from Accumulator (hardwired)
        accumulator_in : in std_logic_vector(7 downto 0);

        -- Operand input 2: From Reg.b (loaded via bus)
        reg_b_in : in std_logic_vector(7 downto 0);

        -- Opcode from instruction (PPP field, bits 5:3)
        opcode : in std_logic_vector(2 downto 0);

        -- INR/DCR mode: when '1', ALU uses Reg.b as input 1 and generates +1/-1 internally
        -- (Accumulator is ignored in this mode)
        is_inr_dcr : in std_logic;

        -- Rotate mode: when '1', perform rotate operation on accumulator
        -- Opcode specifies: 000=RLC, 001=RRC, 010=RAL, 011=RAR
        is_rotate : in std_logic;

        -- Carry input from flags
        carry_in : in std_logic;

        -- Enable from Register and ALU Control
        enable : in std_logic;

        -- Output enable to internal bus
        output_result : in std_logic;

        -- Internal data bus (8-bit result output)
        internal_bus : inOut std_logic_vector(7 downto 0);

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

    -- Operation codes (ALU arithmetic/logic)
    constant OP_ADD : std_logic_vector(2 downto 0) := "000";
    constant OP_ADC : std_logic_vector(2 downto 0) := "001";
    constant OP_SUB : std_logic_vector(2 downto 0) := "010";
    constant OP_SBB : std_logic_vector(2 downto 0) := "011";
    constant OP_AND : std_logic_vector(2 downto 0) := "100";
    constant OP_XOR : std_logic_vector(2 downto 0) := "101";
    constant OP_OR  : std_logic_vector(2 downto 0) := "110";
    constant OP_CMP : std_logic_vector(2 downto 0) := "111";

    -- Rotate operation codes (when is_rotate='1')
    constant ROT_RLC : std_logic_vector(2 downto 0) := "000";  -- Rotate Left Circular
    constant ROT_RRC : std_logic_vector(2 downto 0) := "001";  -- Rotate Right Circular
    constant ROT_RAL : std_logic_vector(2 downto 0) := "010";  -- Rotate Left through Accumulator
    constant ROT_RAR : std_logic_vector(2 downto 0) := "011";  -- Rotate Right through Accumulator

    -- Latched result (stable during entire T5)
    signal result_latched : std_logic_vector(8 downto 0) := (others => '0');

    -- Previous enable state for edge detection
    signal enable_prev : std_logic := '0';

    -- Internal result signal for cleaner output
    signal result_internal : std_logic_vector(8 downto 0);

begin

    -- Latch ALU result on the rising edge of enable (T4->T5 transition)
    -- This prevents the result from changing when the register file is updated
    process(phi2)
        variable carry_val : unsigned(8 downto 0);
        variable temp_result : std_logic_vector(8 downto 0);
        variable operand1 : std_logic_vector(7 downto 0);
        variable operand2 : std_logic_vector(7 downto 0);
    begin
        if rising_edge(phi2) then
            enable_prev <= enable;

            -- Latch result when enable goes from 0 to 1
            if enable = '1' and enable_prev = '0' then
                -- Prepare carry value for operations that use it
                carry_val := (others => '0');
                if carry_in = '1' then
                    carry_val(0) := '1';
                end if;

                -- Check for rotate operations first
                if is_rotate = '1' then
                    -- Rotate operations on accumulator
                    case opcode is
                        when ROT_RLC =>
                            -- Rotate Left Circular: bit 7 -> carry AND bit 0
                            temp_result(8) := accumulator_in(7);  -- Bit 7 to carry
                            temp_result(7 downto 1) := accumulator_in(6 downto 0);  -- Shift left
                            temp_result(0) := accumulator_in(7);  -- Bit 7 also to bit 0

                        when ROT_RRC =>
                            -- Rotate Right Circular: bit 0 -> carry AND bit 7
                            temp_result(8) := accumulator_in(0);  -- Bit 0 to carry
                            temp_result(6 downto 0) := accumulator_in(7 downto 1);  -- Shift right
                            temp_result(7) := accumulator_in(0);  -- Bit 0 also to bit 7

                        when ROT_RAL =>
                            -- Rotate Left through Accumulator: bit 7 -> carry, old carry -> bit 0
                            temp_result(8) := accumulator_in(7);  -- Bit 7 to new carry
                            temp_result(7 downto 1) := accumulator_in(6 downto 0);  -- Shift left
                            temp_result(0) := carry_in;  -- Old carry to bit 0

                        when ROT_RAR =>
                            -- Rotate Right through Accumulator: bit 0 -> carry, old carry -> bit 7
                            temp_result(8) := accumulator_in(0);  -- Bit 0 to new carry
                            temp_result(6 downto 0) := accumulator_in(7 downto 1);  -- Shift right
                            temp_result(7) := carry_in;  -- Old carry to bit 7

                        when others =>
                            temp_result := (others => '0');
                    end case;
                else
                    -- Select operands based on mode
                    if is_inr_dcr = '1' then
                        -- INR/DCR mode: Reg.b is the operand, +1/-1 is generated internally
                        operand1 := reg_b_in;  -- The register value to increment/decrement
                        operand2 := x"01";     -- Constant +1 (for ADD/SUB)
                    else
                        -- Normal binary ALU mode: Accumulator op Reg.b
                        operand1 := accumulator_in;  -- Direct from accumulator
                        operand2 := reg_b_in;        -- From temp register b
                    end if;

                    -- Perform operation based on opcode
                    case opcode is
                        when OP_ADD =>
                            -- ADD for normal ops, INR for is_inr_dcr mode
                            temp_result := std_logic_vector(unsigned('0' & operand1) + unsigned('0' & operand2));

                        when OP_ADC =>
                            temp_result := std_logic_vector(unsigned('0' & operand1) + unsigned('0' & operand2) + carry_val);

                        when OP_SUB =>
                            -- SUB for normal ops, DCR for is_inr_dcr mode
                            temp_result := std_logic_vector(unsigned('0' & operand1) - unsigned('0' & operand2));

                        when OP_SBB =>
                            temp_result := std_logic_vector(unsigned('0' & operand1) - unsigned('0' & operand2) - carry_val);

                        when OP_AND =>
                            temp_result := '0' & (operand1 and operand2);

                        when OP_XOR =>
                            temp_result := '0' & (operand1 xor operand2);

                        when OP_OR =>
                            temp_result := '0' & (operand1 or operand2);

                        when OP_CMP =>
                            -- Compare is like subtract, but result isn't stored (only flags)
                            temp_result := std_logic_vector(unsigned('0' & operand1) - unsigned('0' & operand2));

                        when others =>
                            temp_result := (others => '0');
                    end case;
                end if;

                result_latched <= temp_result;
            end if;
        end if;
    end process;

    -- Generate internal result (combinational, from latched value)
    result_internal <= result_latched when enable = '1' else (others => '0');

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

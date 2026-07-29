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
-- - Arithmetic comes from the carry_lookahead block (per the Intel block
--   diagram) - there is no inferred adder. Subtracts feed it two's
--   complement and invert its carry-out into the 8008 borrow flag.
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
        -- Master clock + phi2 rising-edge pulse (one clk cycle wide)
        clk         : in std_logic;
        phi2_rising : in std_logic;

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

        -- Internal data bus (separate in/out for synthesis compatibility)
        -- Note: ALU only writes to bus, never reads
        internal_bus_out : out std_logic_vector(7 downto 0);
        internal_bus_oe  : out std_logic;

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

    -- Operand selection, hoisted out of the clocked process so the
    -- carry look-ahead block can see the operands
    signal op1_sel : std_logic_vector(7 downto 0);
    signal op2_sel : std_logic_vector(7 downto 0);

    -- Subtraction preconditioning for the carry look-ahead adder.
    -- The look-ahead only adds (Gi = Ai and Bi), so SUB/SBB/CMP feed it
    -- two's complement: b inverted, carry_in forced per operation.
    signal op_is_subtract : std_logic;
    signal cla_b_in       : std_logic_vector(7 downto 0);
    signal cla_carry_in   : std_logic;

    -- Carry look-ahead outputs
    signal cla_carries : std_logic_vector(8 downto 0);
    signal cla_sum     : std_logic_vector(7 downto 0);

begin

    -- Operand selection (was inside the clocked process)
    -- INR/DCR mode: Reg.b is the operand, +1/-1 generated internally
    -- Normal mode:  Accumulator op Reg.b
    op1_sel <= reg_b_in when is_inr_dcr = '1' else accumulator_in;
    op2_sel <= x"01"    when is_inr_dcr = '1' else reg_b_in;

    op_is_subtract <= '1' when (opcode = OP_SUB or opcode = OP_SBB or opcode = OP_CMP) else '0';

    cla_b_in <= not op2_sel when op_is_subtract = '1' else op2_sel;

    -- SUB/CMP: +1 completes the two's complement (A + not B + 1)
    -- SBB:     borrow consumes the +1 (A + not B + 1 - borrow)
    -- ADC:     incoming carry
    -- ADD:     no carry in
    cla_carry_in <= '1'          when (opcode = OP_SUB or opcode = OP_CMP) else
                    not carry_in when opcode = OP_SBB else
                    carry_in     when opcode = OP_ADC else
                    '0';

    -- Carry Look-Ahead block (per the Intel block diagram): computes all
    -- carries and the sum for the arithmetic operations
    lookahead : entity work.carry_lookahead
        port map (
            reg_a     => op1_sel,
            reg_b     => cla_b_in,
            carry_in  => cla_carry_in,
            enable    => enable,
            carry_out => cla_carries,
            sum       => cla_sum
        );

    -- Latch ALU result on the rising edge of enable (T4->T5 transition)
    -- This prevents the result from changing when the register file is updated
    process(clk)
        variable temp_result : std_logic_vector(8 downto 0);
    begin
        if rising_edge(clk) and phi2_rising = '1' then
            enable_prev <= enable;

            -- Latch result when enable goes from 0 to 1
            if enable = '1' and enable_prev = '0' then
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
                    -- Perform operation based on opcode.
                    -- Arithmetic comes from the carry look-ahead block;
                    -- logic ops bypass the carry chain entirely.
                    case opcode is
                        when OP_ADD | OP_ADC =>
                            -- ADD/ADC for normal ops, INR for is_inr_dcr mode
                            temp_result := cla_carries(8) & cla_sum;

                        when OP_SUB | OP_SBB | OP_CMP =>
                            -- SUB/CMP/SBB for normal ops, DCR for is_inr_dcr mode.
                            -- Two's complement addition: carry-out HIGH means
                            -- NO borrow, so the 8008 borrow flag is the
                            -- inversion of the adder carry-out.
                            temp_result := (not cla_carries(8)) & cla_sum;

                        when OP_AND =>
                            temp_result := '0' & (op1_sel and op2_sel);

                        when OP_XOR =>
                            temp_result := '0' & (op1_sel xor op2_sel);

                        when OP_OR =>
                            temp_result := '0' & (op1_sel or op2_sel);

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
    internal_bus_out <= result_internal(7 downto 0);
    internal_bus_oe  <= output_result;

    -- Generate flags from result
    -- Carry flag: bit 8 of result.
    -- INR/DCR exception (8008 datasheet): increment/decrement affect
    -- Z/S/P only - carry passes through unchanged, so the flag writeback
    -- rewrites the current value. Without this, SCELBAL-style multi-byte
    -- adds ("ADC M / INR L / ADC M") and rotate loops ("RAL / DCR B")
    -- corrupt on every pointer/counter step.
    flag_carry <= carry_in          when (enable = '1' and is_inr_dcr = '1') else
                  result_internal(8) when enable = '1' else
                  '0';

    -- Zero flag: all bits of result are zero
    flag_zero <= '1' when (enable = '1' and result_internal(7 downto 0) = x"00") else '0';

    -- Sign flag: bit 7 of result (MSB)
    flag_sign <= result_internal(7) when enable = '1' else '0';

    -- Parity flag: even parity (1 if even number of 1's)
    -- XOR of all bits gives 0 for even parity, 1 for odd parity, so we invert
    flag_parity <= not (result_internal(0) xor result_internal(1) xor result_internal(2) xor result_internal(3) xor
                        result_internal(4) xor result_internal(5) xor result_internal(6) xor result_internal(7))
                   when enable = '1' else '0';

end architecture rtl;

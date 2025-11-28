--------------------------------------------------------------------------------
-- instruction_decoder.vhdl
--------------------------------------------------------------------------------
-- Instruction Decoder for Intel 8008
--
-- Decodes 8-bit instruction opcodes and outputs control signals based on isa.json
-- - Determines number of cycles needed (1, 2, or 3 cycles)
-- - Identifies I/O operations
-- - Identifies memory write operations
-- - DUMB module: just a lookup table, no execution logic
--
-- Based on /docs/isa.json specification
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.b8008_types.all;

entity instruction_decoder is
    port (
        -- Instruction input (from IR bit outputs)
        instruction_byte : in std_logic_vector(7 downto 0);

        -- Outputs to Machine Cycle Control
        instr_needs_immediate : out std_logic;  -- Needs 2nd cycle (not necessarily 2nd byte!)
        instr_needs_address   : out std_logic;  -- Needs 3 cycles (14-bit address: 3 bytes)
        instr_is_io           : out std_logic;  -- I/O operation (INP/OUT)
        instr_is_write        : out std_logic;  -- Memory write operation (LMr, LMI)

        -- Outputs to Memory/I/O Control
        instr_sss_field       : out std_logic_vector(2 downto 0);  -- Source register
        instr_ddd_field       : out std_logic_vector(2 downto 0);  -- Destination register
        instr_is_alu          : out std_logic;  -- ALU operation
        instr_is_call         : out std_logic;  -- CALL instruction
        instr_is_ret          : out std_logic;  -- RET instruction
        instr_is_rst          : out std_logic;  -- RST instruction
        instr_is_hlt          : out std_logic;  -- HLT (halt) instruction
        instr_writes_reg      : out std_logic;  -- Instruction writes to register
        instr_reads_reg       : out std_logic;  -- Instruction reads from register
        instr_is_mem_indirect : out std_logic;  -- Memory indirect (SSS or DDD = "111")

        -- For Register & ALU Control (temp register loading)
        instr_uses_temp_regs  : out std_logic;  -- Instruction uses Reg.a/Reg.b (ALU ops, JMP, CALL)
        instr_is_inr_dcr      : out std_logic;  -- INR/DCR instruction (load constant 0x01 into Reg.a)
        instr_is_binary_alu   : out std_logic;  -- Binary ALU op (ADD, SUB, etc. - load A register into Reg.a)

        -- For Machine Cycle Control (extended states T4/T5)
        instr_needs_t4t5      : out std_logic;  -- Instruction needs T4/T5 states (JMP, CALL, RET, RST, ALU ops)

        -- RST vector (CRITICAL ISSUE #3)
        rst_vector            : out std_logic_vector(2 downto 0);  -- RST instruction bits D5:D3

        -- Condition evaluation (for condition_flags module)
        condition_code        : out std_logic_vector(1 downto 0);  -- CC field: 00=C, 01=Z, 10=S, 11=P
        test_true             : out std_logic;  -- 1=test true, 0=test false
        eval_condition        : out std_logic;  -- 1=conditional instruction, evaluate condition

        -- State transition control (for state_timing_generator)
        transition_to_stopped : out std_logic   -- 1=transition to STOPPED state at T3 (HLT instruction)
    );
end entity instruction_decoder;

architecture rtl of instruction_decoder is

    -- Instruction bit fields
    alias op_76 : std_logic_vector(1 downto 0) is instruction_byte(7 downto 6);
    alias op_543 : std_logic_vector(2 downto 0) is instruction_byte(5 downto 3);
    alias op_210 : std_logic_vector(2 downto 0) is instruction_byte(2 downto 0);

begin

    -- Decode instruction and output control signals
    process(instruction_byte, op_76, op_543, op_210)
    begin
        -- Default: single-cycle register operation
        instr_needs_immediate <= '0';
        instr_needs_address <= '0';
        instr_is_io <= '0';
        instr_is_write <= '0';
        instr_sss_field <= op_210;  -- Default to SSS field
        instr_ddd_field <= op_543;  -- Default to DDD field
        instr_is_alu <= '0';
        instr_is_call <= '0';
        instr_is_ret <= '0';
        instr_is_rst <= '0';
        instr_is_hlt <= '0';
        instr_writes_reg <= '0';
        instr_reads_reg <= '0';
        instr_is_mem_indirect <= '0';  -- Default: not memory indirect
        instr_uses_temp_regs <= '0';  -- Default: doesn't use temp registers
        instr_is_inr_dcr <= '0';  -- Default: not INR/DCR
        instr_is_binary_alu <= '0';  -- Default: not binary ALU
        instr_needs_t4t5 <= '0';  -- Default: doesn't need T4/T5
        rst_vector <= (others => '0');  -- Default RST vector
        condition_code <= "00";  -- Default condition code
        test_true <= '0';  -- Default test false
        eval_condition <= '0';  -- Default no condition evaluation
        transition_to_stopped <= '0';  -- Default: don't stop

        -- Detect memory indirect operations (M register access)
        -- This happens when SSS or DDD field = "111" for move (11) or ALU register (10) ops
        -- NOT for ALU immediate (00PPP100) where PPP might be "111"
        if (op_210 = "111" or op_543 = "111") and op_76 /= "00" then
            instr_is_mem_indirect <= '1';
        end if;

        case op_76 is
            -- ================================================================
            -- 00 XXX XXX - Index register, ALU immediate, rotate, control
            -- ================================================================
            when "00" =>
                -- SPECIAL CASE: 00 000 00X - HLT (HALT) - 1 cycle
                if op_543 = "000" and op_210(2 downto 1) = "00" then
                    -- HLT: 0x00 or 0x01 (bit 0 is don't care)
                    instr_is_hlt <= '1';  -- Signal that this is HLT
                    transition_to_stopped <= '1';  -- Transition to STOPPED state at T3

                else
                    case op_210 is
                        when "000" =>
                            -- 00 DDD 000 - INr (increment) - 1 cycle
                            -- But NOT if DDD=000, that's HLT (handled above)
                            if op_543 /= "000" then
                                instr_is_alu <= '1';
                                instr_uses_temp_regs <= '1';
                                instr_is_inr_dcr <= '1';  -- Load constant 0x01 into Reg.a
                                instr_reads_reg <= '1';
                                instr_writes_reg <= '1';
                                instr_sss_field <= "000";   -- ALU opcode: ADD
                                instr_ddd_field <= op_543;  -- Write to DDD field (which register to increment)
                                instr_needs_t4t5 <= '1';  -- ALU needs T4/T5
                            end if;

                    when "001" =>
                        -- 00 DDD 001 - DCr (decrement) - 1 cycle
                        instr_is_alu <= '1';
                        instr_uses_temp_regs <= '1';
                        instr_is_inr_dcr <= '1';  -- Load constant 0x01 into Reg.a
                        instr_reads_reg <= '1';
                        instr_writes_reg <= '1';
                        instr_sss_field <= "010";   -- ALU opcode: SUB
                        instr_ddd_field <= op_543;  -- Write to DDD field (which register to decrement)
                        instr_needs_t4t5 <= '1';  -- ALU needs T4/T5

                    when "010" =>
                        -- 00 XXX 010 - Rotate instructions (RLC, RRC, RAL, RAR) - 1 cycle
                        instr_is_alu <= '1';
                        instr_uses_temp_regs <= '1';
                        instr_reads_reg <= '1';   -- Read A
                        instr_writes_reg <= '1';  -- Write A
                        instr_sss_field <= "000"; -- A register
                        instr_ddd_field <= "000"; -- A register
                        instr_needs_t4t5 <= '1';  -- ALU needs T4/T5

                    when "011" =>
                        -- 00 CCC 011 - RFc, RTc (conditional return) - 1 cycle
                        -- Bit 5 determines F (false) or T (true)
                        -- Bits 4:3 determine condition code
                        instr_is_ret <= '1';
                        instr_needs_t4t5 <= '1';  -- RET needs T5
                        eval_condition <= '1';
                        condition_code <= op_543(1 downto 0);  -- CC field
                        test_true <= op_543(2);  -- T=1, F=0

                    when "100" =>
                        -- 00 PPP 100 - ALU OP I (immediate) - 2 cycles
                        instr_needs_immediate <= '1';
                        instr_is_alu <= '1';
                        instr_is_binary_alu <= '1';  -- Binary ALU (Reg.a loads from A register, Reg.b loads from immediate byte)
                        -- NOTE: DON'T set instr_uses_temp_regs for immediate ops!
                        -- Immediate ops load the immediate byte into Reg.b during cycle 2 T3,
                        -- NOT from a source register during cycle 1 T4 like register ALU ops do.
                        instr_uses_temp_regs <= '0';
                        instr_reads_reg <= '1';   -- Read A
                        -- Write A for all ALU ops EXCEPT compare (PPP=111)
                        if op_543 = "111" then
                            instr_writes_reg <= '0';  -- Compare doesn't write
                        else
                            instr_writes_reg <= '1';  -- ADD/SUB/AND/XOR/OR write A
                        end if;
                        instr_sss_field <= op_543;  -- ALU opcode from PPP field (bits 5:3)
                        instr_ddd_field <= "000"; -- A register (destination)
                        instr_needs_t4t5 <= '1';  -- ALU needs T4/T5

                    when "101" =>
                        -- 00 AAA 101 - RST (restart) - 1 cycle
                        -- RST vector is in bits [5:3] (AAA field)
                        instr_is_rst <= '1';
                        instr_needs_t4t5 <= '1';  -- RST needs T5
                        rst_vector <= op_543;  -- Extract AAA field (bits D5:D3)

                    when "110" =>
                        -- 00 DDD 110 - LrI (load register immediate) - 2 cycles
                        -- 00 111 110 - LMI (load memory immediate) - 3 cycles
                        if op_543 = "111" then
                            -- LMI - needs 3 cycles, writes to memory
                            instr_needs_address <= '1';
                            instr_is_write <= '1';
                        else
                            -- LrI (MVI) - needs 2 cycles, needs T4 to write register
                            instr_needs_immediate <= '1';
                            instr_writes_reg <= '1';
                            instr_needs_t4t5 <= '1';  -- Need T4 to write result to register
                            -- NOTE: DON'T set instr_uses_temp_regs for MVI!
                            -- MVI loads immediate byte into Reg.b during cycle 2 T3,
                            -- NOT from a source register during cycle 1 T4.
                            instr_uses_temp_regs <= '0';
                        end if;

                    when "111" =>
                        -- 00 XXX 111 - RET (return) - 1 cycle
                        instr_is_ret <= '1';
                        instr_needs_t4t5 <= '1';  -- RET needs T5

                        when others =>
                            null;
                    end case;
                end if;  -- End of HLT check

            -- ================================================================
            -- 01 XXX XXX - Jump, Call, I/O
            -- ================================================================
            when "01" =>
                if op_210(0) = '1' then
                    -- 01 XXX XX1 - I/O instructions
                    -- 0100 MMM 1 - INP - 2 cycles, I/O read to A
                    -- 01RR MMM 1 - OUT - 2 cycles, I/O write from A
                    instr_needs_immediate <= '1';
                    instr_is_io <= '1';
                    if op_543(2) = '0' then
                        -- INP: writes to A
                        instr_writes_reg <= '1';
                        instr_ddd_field <= "000";  -- A register
                    else
                        -- OUT: reads from A
                        instr_reads_reg <= '1';
                        instr_sss_field <= "000";  -- A register
                    end if;
                else
                    -- 01 XXX XX0 - Jump/Call instructions - 3 cycles
                    -- 01 XXX 100 - JMP (unconditional)
                    -- 01 CCC 000 - JFc, JTc (conditional jump)
                    -- 01 XXX 110 - CAL (CALL, unconditional)
                    -- 01 0CC 010 - CFc (conditional call false)
                    -- 01 1CC 010 - CTc (conditional call true)
                    instr_needs_address <= '1';
                    instr_uses_temp_regs <= '1';  -- JMP/CALL load address into Reg.a/Reg.b
                    instr_needs_t4t5 <= '1';  -- JMP/CALL need T4/T5 in cycle 3

                    if op_210 = "000" then
                        -- 01 CCC 000 - JFc/JTc (conditional jump)
                        -- Bit 5 determines F (false) or T (true)
                        -- Bits 4:3 determine condition code
                        eval_condition <= '1';
                        condition_code <= op_543(1 downto 0);  -- CC field
                        test_true <= op_543(2);  -- T=1, F=0
                        report "INSTR_DEC: JZ/JNZ opcode=0x" & to_hstring(unsigned(instruction_byte)) &
                               " op_543=" & to_string(op_543) &
                               " test_true=" & std_logic'image(op_543(2));

                    elsif op_210 = "010" then
                        -- 01 XCC 010 - CFc/CTc (conditional call)
                        -- Bit 5 determines F (false) or T (true)
                        -- Bits 4:3 determine condition code
                        instr_is_call <= '1';
                        eval_condition <= '1';
                        condition_code <= op_543(1 downto 0);  -- CC field
                        test_true <= op_543(2);  -- T=1, F=0

                    elsif op_210 = "100" then
                        -- 01 XXX 100 - JMP (unconditional jump)
                        -- Already set: instr_needs_address, instr_uses_temp_regs, instr_needs_t4t5
                        -- No additional signals needed for unconditional JMP

                    elsif op_210(2 downto 1) = "11" then
                        -- 01 XXX 110 - CAL (unconditional CALL)
                        instr_is_call <= '1';
                    end if;
                end if;

            -- ================================================================
            -- 10 XXX XXX - ALU operations
            -- ================================================================
            when "10" =>
                -- 10 PPP SSS - ALU operations with A as destination
                instr_is_alu <= '1';
                instr_uses_temp_regs <= '1';
                instr_reads_reg <= '1';   -- Read source (SSS or memory)
                instr_is_binary_alu <= '1';  -- Binary ALU (Reg.a loads from A register, Reg.b loads from SSS/memory)
                -- Write A for all ALU ops EXCEPT compare (PPP=111)
                if op_543 = "111" then
                    instr_writes_reg <= '0';  -- Compare doesn't write
                else
                    instr_writes_reg <= '1';  -- ADD/SUB/AND/XOR/OR write A
                end if;
                instr_ddd_field <= "000"; -- A register
                instr_needs_t4t5 <= '1';  -- ALU needs T4/T5
                if op_210 = "111" then
                    -- 10 PPP 111 - ALU OP M (memory via H:L) - 2 cycles
                    instr_needs_immediate <= '1';
                else
                    -- 10 PPP SSS - ALU OP r (register) - 1 cycle
                    -- SSS field already set by default
                    null;
                end if;

            -- ================================================================
            -- 11 XXX XXX - Move instructions
            -- ================================================================
            when "11" =>
                if instruction_byte = "11111111" then
                    -- 11 111 111 - HLT - 1 cycle
                    instr_is_hlt <= '1';
                    transition_to_stopped <= '1';  -- Transition to STOPPED state at T3
                elsif op_210 = "111" then
                    -- 11 DDD 111 - LrM (load register from memory) - 2 cycles
                    -- NOTE: This is memory-indirect, NOT immediate
                    -- instr_is_mem_indirect is already set by line 107
                    instr_writes_reg <= '1';
                    instr_needs_t4t5 <= '1';  -- Need T4 to write result to register
                    -- DDD field already set by default
                elsif op_543 = "111" then
                    -- 11 111 SSS - LMr (load memory from register) - 2 cycles, write
                    -- NOTE: This is memory-indirect, NOT immediate
                    -- instr_is_mem_indirect is already set by line 107
                    instr_is_write <= '1';
                    instr_reads_reg <= '1';
                    -- SSS field already set by default
                else
                    -- 11 DDD SSS - Lr_1r_2 (MOV register to register) - 1 cycle, needs T4/T5
                    -- Per isa.json: T4 = "SSS TO REG. b", T5 = "REG. b TO DDD"
                    instr_reads_reg <= '1';
                    instr_writes_reg <= '1';
                    instr_needs_t4t5 <= '1';  -- Need T4/T5 to transfer register value
                    instr_uses_temp_regs <= '1';  -- Uses Reg.b to transfer value
                    -- SSS and DDD fields already set by default
                end if;

            when others =>
                null;
        end case;

    end process;

end architecture rtl;

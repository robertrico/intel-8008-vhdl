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

        -- RST vector (CRITICAL ISSUE #3)
        rst_vector            : out std_logic_vector(2 downto 0)  -- RST instruction bits D5:D3
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
        rst_vector <= (others => '0');  -- Default RST vector

        case op_76 is
            -- ================================================================
            -- 00 XXX XXX - Index register, ALU immediate, rotate, control
            -- ================================================================
            when "00" =>
                -- SPECIAL CASE: 00 000 00X - HLT (HALT) - 1 cycle
                if op_543 = "000" and op_210(2 downto 1) = "00" then
                    -- HLT: 0x00 or 0x01 (bit 0 is don't care)
                    instr_is_hlt <= '1';  -- Signal that this is HLT

                else
                    case op_210 is
                        when "000" =>
                            -- 00 DDD 000 - INr (increment) - 1 cycle
                            -- But NOT if DDD=000, that's HLT (handled above)
                            if op_543 /= "000" then
                                instr_is_alu <= '1';
                                instr_reads_reg <= '1';
                                instr_writes_reg <= '1';
                            end if;

                    when "001" =>
                        -- 00 DDD 001 - DCr (decrement) - 1 cycle
                        instr_is_alu <= '1';
                        instr_reads_reg <= '1';
                        instr_writes_reg <= '1';

                    when "010" =>
                        -- 00 XXX 010 - Rotate instructions (RLC, RRC, RAL, RAR) - 1 cycle
                        instr_is_alu <= '1';
                        instr_reads_reg <= '1';   -- Read A
                        instr_writes_reg <= '1';  -- Write A
                        instr_sss_field <= "000"; -- A register
                        instr_ddd_field <= "000"; -- A register

                    when "011" =>
                        -- 00 CCC 011 - RFc, RTc (conditional return) - 1 cycle
                        instr_is_ret <= '1';

                    when "100" =>
                        -- 00 PPP 100 - ALU OP I (immediate) - 2 cycles
                        instr_needs_immediate <= '1';
                        instr_is_alu <= '1';
                        instr_reads_reg <= '1';   -- Read A
                        instr_writes_reg <= '1';  -- Write A
                        instr_sss_field <= "000"; -- A register
                        instr_ddd_field <= "000"; -- A register

                    when "101" =>
                        -- 00 AAA 101 - RST (restart) - 1 cycle
                        -- RST vector is in bits [5:3] (AAA field)
                        instr_is_rst <= '1';
                        rst_vector <= op_543;  -- Extract AAA field (bits D5:D3)

                    when "110" =>
                        -- 00 DDD 110 - LrI (load register immediate) - 2 cycles
                        -- 00 111 110 - LMI (load memory immediate) - 3 cycles
                        if op_543 = "111" then
                            -- LMI - needs 3 cycles, writes to memory
                            instr_needs_address <= '1';
                            instr_is_write <= '1';
                        else
                            -- LrI - needs 2 cycles
                            instr_needs_immediate <= '1';
                            instr_writes_reg <= '1';
                        end if;

                    when "111" =>
                        -- 00 XXX 111 - RET (return) - 1 cycle
                        instr_is_ret <= '1';

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
                    -- 01 XXX 100 - JMP
                    -- 01 CCC 000 - JFc, JTc (conditional jump)
                    -- 01 XXX 110 - CAL (CALL)
                    -- 01 0CC 010 - CFc (conditional call false)
                    -- 01 1CC 010 - CTc (conditional call true)
                    instr_needs_address <= '1';
                    if op_210(2 downto 1) = "11" then
                        -- CAL (CALL) instruction
                        instr_is_call <= '1';
                    end if;
                end if;

            -- ================================================================
            -- 10 XXX XXX - ALU operations
            -- ================================================================
            when "10" =>
                -- 10 PPP SSS - ALU operations with A as destination
                instr_is_alu <= '1';
                instr_reads_reg <= '1';   -- Read source (SSS or memory)
                instr_writes_reg <= '1';  -- Write to A
                instr_ddd_field <= "000"; -- A register
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
                elsif op_210 = "111" then
                    -- 11 DDD 111 - LrM (load register from memory) - 2 cycles
                    instr_needs_immediate <= '1';
                    instr_writes_reg <= '1';
                    -- DDD field already set by default
                elsif op_543 = "111" then
                    -- 11 111 SSS - LMr (load memory from register) - 2 cycles, write
                    instr_needs_immediate <= '1';
                    instr_is_write <= '1';
                    instr_reads_reg <= '1';
                    -- SSS field already set by default
                else
                    -- 11 DDD SSS - Lr_1r_2 (MOV register to register) - 1 cycle
                    instr_reads_reg <= '1';
                    instr_writes_reg <= '1';
                    -- SSS and DDD fields already set by default
                end if;

            when others =>
                null;
        end case;

    end process;

end architecture rtl;

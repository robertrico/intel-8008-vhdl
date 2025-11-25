--------------------------------------------------------------------------------
-- instruction_decoder_tb.vhdl
--------------------------------------------------------------------------------
-- Testbench for instruction_decoder
-- Tests all 48 Intel 8008 instructions for correct cycle requirements
-- Based on /docs/isa.json specification
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.b8008_types.all;

entity instruction_decoder_tb is
end entity instruction_decoder_tb;

architecture test of instruction_decoder_tb is

    component instruction_decoder is
        port (
            instruction_byte      : in  std_logic_vector(7 downto 0);
            instr_needs_immediate : out std_logic;
            instr_needs_address   : out std_logic;
            instr_is_io           : out std_logic;
            instr_is_write        : out std_logic;
            instr_sss_field       : out std_logic_vector(2 downto 0);
            instr_ddd_field       : out std_logic_vector(2 downto 0);
            instr_is_alu          : out std_logic;
            instr_is_call         : out std_logic;
            instr_is_ret          : out std_logic;
            instr_is_rst          : out std_logic;
            instr_writes_reg      : out std_logic;
            instr_reads_reg       : out std_logic
        );
    end component;

    signal instruction_byte      : std_logic_vector(7 downto 0) := (others => '0');
    signal instr_needs_immediate : std_logic;
    signal instr_needs_address   : std_logic;
    signal instr_is_io           : std_logic;
    signal instr_is_write        : std_logic;
    signal instr_sss_field       : std_logic_vector(2 downto 0);
    signal instr_ddd_field       : std_logic_vector(2 downto 0);
    signal instr_is_alu          : std_logic;
    signal instr_is_call         : std_logic;
    signal instr_is_ret          : std_logic;
    signal instr_is_rst          : std_logic;
    signal instr_writes_reg      : std_logic;
    signal instr_reads_reg       : std_logic;

    -- Test procedure
    procedure test_instruction(
        opcode   : in std_logic_vector(7 downto 0);
        mnemonic : in string;
        cycles   : in integer;  -- Expected number of cycles (1, 2, or 3)
        is_io    : in std_logic;
        is_write : in std_logic;
        signal instr : out std_logic_vector(7 downto 0);
        signal imm   : in std_logic;
        signal addr  : in std_logic;
        signal io    : in std_logic;
        signal wr    : in std_logic;
        variable errors : inout integer
    ) is
        variable expected_imm  : std_logic;
        variable expected_addr : std_logic;
    begin
        -- Calculate expected signals based on cycles
        case cycles is
            when 1 =>   -- 1-cycle instruction
                expected_imm := '0';
                expected_addr := '0';
            when 2 =>   -- 2-cycle instruction
                expected_imm := '1';
                expected_addr := '0';
            when 3 =>  -- 3-cycle instruction
                expected_imm := '0';
                expected_addr := '1';
            when others =>
                report "ERROR: Invalid cycle count for " & mnemonic severity error;
                errors := errors + 1;
                return;
        end case;

        -- Apply instruction
        instr <= opcode;
        wait for 10 ns;

        -- Check outputs
        if imm /= expected_imm then
            report "  ERROR: " & mnemonic & " - instr_needs_immediate should be " &
                   std_logic'image(expected_imm) & ", got " & std_logic'image(imm) severity error;
            errors := errors + 1;
        end if;

        if addr /= expected_addr then
            report "  ERROR: " & mnemonic & " - instr_needs_address should be " &
                   std_logic'image(expected_addr) & ", got " & std_logic'image(addr) severity error;
            errors := errors + 1;
        end if;

        if io /= is_io then
            report "  ERROR: " & mnemonic & " - instr_is_io should be " &
                   std_logic'image(is_io) & ", got " & std_logic'image(io) severity error;
            errors := errors + 1;
        end if;

        if wr /= is_write then
            report "  ERROR: " & mnemonic & " - instr_is_write should be " &
                   std_logic'image(is_write) & ", got " & std_logic'image(wr) severity error;
            errors := errors + 1;
        end if;
    end procedure;

begin

    uut : instruction_decoder
        port map (
            instruction_byte      => instruction_byte,
            instr_needs_immediate => instr_needs_immediate,
            instr_needs_address   => instr_needs_address,
            instr_is_io           => instr_is_io,
            instr_is_write        => instr_is_write,
            instr_sss_field       => instr_sss_field,
            instr_ddd_field       => instr_ddd_field,
            instr_is_alu          => instr_is_alu,
            instr_is_call         => instr_is_call,
            instr_is_ret          => instr_is_ret,
            instr_is_rst          => instr_is_rst,
            instr_writes_reg      => instr_writes_reg,
            instr_reads_reg       => instr_reads_reg
        );

    process
        variable errors : integer := 0;
    begin
        report "========================================";
        report "Instruction Decoder Test - All 48 Instructions";
        report "Based on isa.json specification";
        report "========================================";

        wait for 20 ns;

        -- INDEX REGISTER INSTRUCTIONS
        report "";
        report "INDEX REGISTER INSTRUCTIONS";

        -- MOV instructions (register to register) - 1 cycle
        test_instruction("11000000", "MOV A,A", 1, '0', '0', instruction_byte,
                        instr_needs_immediate, instr_needs_address, instr_is_io, instr_is_write, errors);
        test_instruction("11000001", "MOV A,B", 1, '0', '0', instruction_byte,
                        instr_needs_immediate, instr_needs_address, instr_is_io, instr_is_write, errors);
        test_instruction("11001000", "MOV B,A", 1, '0', '0', instruction_byte,
                        instr_needs_immediate, instr_needs_address, instr_is_io, instr_is_write, errors);

        -- LrM (MOV Rd, M) - 2 cycles (read from memory at H:L)
        test_instruction("11000111", "MOV A,M (LrM)", 2, '0', '0', instruction_byte,
                        instr_needs_immediate, instr_needs_address, instr_is_io, instr_is_write, errors);
        test_instruction("11010111", "MOV C,M (LrM)", 2, '0', '0', instruction_byte,
                        instr_needs_immediate, instr_needs_address, instr_is_io, instr_is_write, errors);

        -- LMr (MOV M, Rs) - 2 cycles, write to memory at H:L
        test_instruction("11111000", "MOV M,A (LMr)", 2, '0', '1', instruction_byte,
                        instr_needs_immediate, instr_needs_address, instr_is_io, instr_is_write, errors);
        test_instruction("11111001", "MOV M,B (LMr)", 2, '0', '1', instruction_byte,
                        instr_needs_immediate, instr_needs_address, instr_is_io, instr_is_write, errors);

        -- LrI (MVI Rd, Imm) - 2 cycles
        test_instruction("00000110", "MVI A,Imm (LrI)", 2, '0', '0', instruction_byte,
                        instr_needs_immediate, instr_needs_address, instr_is_io, instr_is_write, errors);
        test_instruction("00010110", "MVI C,Imm (LrI)", 2, '0', '0', instruction_byte,
                        instr_needs_immediate, instr_needs_address, instr_is_io, instr_is_write, errors);

        -- LMI (MVI M, Imm) - 3 cycles, write to memory
        test_instruction("00111110", "MVI M,Imm (LMI)", 3, '0', '1', instruction_byte,
                        instr_needs_immediate, instr_needs_address, instr_is_io, instr_is_write, errors);

        -- INr, DCr - 1 cycle
        test_instruction("00000000", "INR A (INr)", 1, '0', '0', instruction_byte,
                        instr_needs_immediate, instr_needs_address, instr_is_io, instr_is_write, errors);
        test_instruction("00001000", "INR B (INr)", 1, '0', '0', instruction_byte,
                        instr_needs_immediate, instr_needs_address, instr_is_io, instr_is_write, errors);
        test_instruction("00000001", "DCR A (DCr)", 1, '0', '0', instruction_byte,
                        instr_needs_immediate, instr_needs_address, instr_is_io, instr_is_write, errors);
        test_instruction("00001001", "DCR B (DCr)", 1, '0', '0', instruction_byte,
                        instr_needs_immediate, instr_needs_address, instr_is_io, instr_is_write, errors);

        -- ACCUMULATOR GROUP INSTRUCTIONS
        report "";
        report "ACCUMULATOR GROUP INSTRUCTIONS";

        -- Rotate instructions - 1 cycle
        test_instruction("00000010", "RLC", 1, '0', '0', instruction_byte,
                        instr_needs_immediate, instr_needs_address, instr_is_io, instr_is_write, errors);
        test_instruction("00001010", "RRC", 1, '0', '0', instruction_byte,
                        instr_needs_immediate, instr_needs_address, instr_is_io, instr_is_write, errors);
        test_instruction("00010010", "RAL", 1, '0', '0', instruction_byte,
                        instr_needs_immediate, instr_needs_address, instr_is_io, instr_is_write, errors);
        test_instruction("00011010", "RAR", 1, '0', '0', instruction_byte,
                        instr_needs_immediate, instr_needs_address, instr_is_io, instr_is_write, errors);

        -- ALU with register - 1 cycle
        test_instruction("10000000", "ADD A", 1, '0', '0', instruction_byte,
                        instr_needs_immediate, instr_needs_address, instr_is_io, instr_is_write, errors);
        test_instruction("10000001", "ADD B", 1, '0', '0', instruction_byte,
                        instr_needs_immediate, instr_needs_address, instr_is_io, instr_is_write, errors);
        test_instruction("10001000", "ADC A", 1, '0', '0', instruction_byte,
                        instr_needs_immediate, instr_needs_address, instr_is_io, instr_is_write, errors);
        test_instruction("10010000", "SUB A", 1, '0', '0', instruction_byte,
                        instr_needs_immediate, instr_needs_address, instr_is_io, instr_is_write, errors);
        test_instruction("10011000", "SBB A", 1, '0', '0', instruction_byte,
                        instr_needs_immediate, instr_needs_address, instr_is_io, instr_is_write, errors);
        test_instruction("10100000", "AND A", 1, '0', '0', instruction_byte,
                        instr_needs_immediate, instr_needs_address, instr_is_io, instr_is_write, errors);
        test_instruction("10101000", "XOR A", 1, '0', '0', instruction_byte,
                        instr_needs_immediate, instr_needs_address, instr_is_io, instr_is_write, errors);
        test_instruction("10110000", "OR A", 1, '0', '0', instruction_byte,
                        instr_needs_immediate, instr_needs_address, instr_is_io, instr_is_write, errors);
        test_instruction("10111000", "CMP A", 1, '0', '0', instruction_byte,
                        instr_needs_immediate, instr_needs_address, instr_is_io, instr_is_write, errors);

        -- ALU with memory (M via H:L) - 2 cycles
        test_instruction("10000111", "ADD M", 2, '0', '0', instruction_byte,
                        instr_needs_immediate, instr_needs_address, instr_is_io, instr_is_write, errors);
        test_instruction("10010111", "SUB M", 2, '0', '0', instruction_byte,
                        instr_needs_immediate, instr_needs_address, instr_is_io, instr_is_write, errors);
        test_instruction("10100111", "AND M", 2, '0', '0', instruction_byte,
                        instr_needs_immediate, instr_needs_address, instr_is_io, instr_is_write, errors);

        -- ALU with immediate - 2 cycles
        test_instruction("00000100", "ADI", 2, '0', '0', instruction_byte,
                        instr_needs_immediate, instr_needs_address, instr_is_io, instr_is_write, errors);
        test_instruction("00001100", "ACI", 2, '0', '0', instruction_byte,
                        instr_needs_immediate, instr_needs_address, instr_is_io, instr_is_write, errors);
        test_instruction("00010100", "SUI", 2, '0', '0', instruction_byte,
                        instr_needs_immediate, instr_needs_address, instr_is_io, instr_is_write, errors);
        test_instruction("00011100", "SBI", 2, '0', '0', instruction_byte,
                        instr_needs_immediate, instr_needs_address, instr_is_io, instr_is_write, errors);
        test_instruction("00100100", "ANI", 2, '0', '0', instruction_byte,
                        instr_needs_immediate, instr_needs_address, instr_is_io, instr_is_write, errors);
        test_instruction("00101100", "XRI", 2, '0', '0', instruction_byte,
                        instr_needs_immediate, instr_needs_address, instr_is_io, instr_is_write, errors);
        test_instruction("00110100", "ORI", 2, '0', '0', instruction_byte,
                        instr_needs_immediate, instr_needs_address, instr_is_io, instr_is_write, errors);
        test_instruction("00111100", "CPI", 2, '0', '0', instruction_byte,
                        instr_needs_immediate, instr_needs_address, instr_is_io, instr_is_write, errors);

        -- PROGRAM COUNTER AND STACK CONTROL
        report "";
        report "PROGRAM COUNTER AND STACK CONTROL";

        -- Jump instructions - 3 cycles
        test_instruction("01000100", "JMP", 3, '0', '0', instruction_byte,
                        instr_needs_immediate, instr_needs_address, instr_is_io, instr_is_write, errors);
        test_instruction("01000000", "JFc (JNC)", 3, '0', '0', instruction_byte,
                        instr_needs_immediate, instr_needs_address, instr_is_io, instr_is_write, errors);
        test_instruction("01100000", "JTc (JC)", 3, '0', '0', instruction_byte,
                        instr_needs_immediate, instr_needs_address, instr_is_io, instr_is_write, errors);

        -- Call instructions - 3 cycles
        test_instruction("01000110", "CAL (CALL)", 3, '0', '0', instruction_byte,
                        instr_needs_immediate, instr_needs_address, instr_is_io, instr_is_write, errors);
        test_instruction("01000010", "CFc (CNC)", 3, '0', '0', instruction_byte,
                        instr_needs_immediate, instr_needs_address, instr_is_io, instr_is_write, errors);
        test_instruction("01100010", "CTc (CC)", 3, '0', '0', instruction_byte,
                        instr_needs_immediate, instr_needs_address, instr_is_io, instr_is_write, errors);

        -- Return instructions - 1 cycle
        test_instruction("00000111", "RET", 1, '0', '0', instruction_byte,
                        instr_needs_immediate, instr_needs_address, instr_is_io, instr_is_write, errors);
        test_instruction("00000011", "RFc (RNC)", 1, '0', '0', instruction_byte,
                        instr_needs_immediate, instr_needs_address, instr_is_io, instr_is_write, errors);
        test_instruction("00100011", "RTc (RC)", 1, '0', '0', instruction_byte,
                        instr_needs_immediate, instr_needs_address, instr_is_io, instr_is_write, errors);

        -- Restart - 1 cycle
        test_instruction("00000101", "RST 0", 1, '0', '0', instruction_byte,
                        instr_needs_immediate, instr_needs_address, instr_is_io, instr_is_write, errors);
        test_instruction("00001101", "RST 1", 1, '0', '0', instruction_byte,
                        instr_needs_immediate, instr_needs_address, instr_is_io, instr_is_write, errors);

        -- I/O INSTRUCTIONS
        report "";
        report "I/O INSTRUCTIONS";

        -- INP - 2 cycles, I/O (port in opcode)
        test_instruction("01000001", "INP 0 (IN)", 2, '1', '0', instruction_byte,
                        instr_needs_immediate, instr_needs_address, instr_is_io, instr_is_write, errors);
        test_instruction("01001001", "INP 1 (IN)", 2, '1', '0', instruction_byte,
                        instr_needs_immediate, instr_needs_address, instr_is_io, instr_is_write, errors);

        -- OUT - 2 cycles, I/O (port in opcode)
        test_instruction("01010001", "OUT 0 (OUT)", 2, '1', '0', instruction_byte,
                        instr_needs_immediate, instr_needs_address, instr_is_io, instr_is_write, errors);
        test_instruction("01011001", "OUT 1 (OUT)", 2, '1', '0', instruction_byte,
                        instr_needs_immediate, instr_needs_address, instr_is_io, instr_is_write, errors);

        -- MACHINE INSTRUCTIONS
        report "";
        report "MACHINE INSTRUCTIONS";

        -- HLT - 1 cycle (two encodings)
        test_instruction("00000000", "HLT (variant 1)", 1, '0', '0', instruction_byte,
                        instr_needs_immediate, instr_needs_address, instr_is_io, instr_is_write, errors);
        test_instruction("11111111", "HLT (variant 2)", 1, '0', '0', instruction_byte,
                        instr_needs_immediate, instr_needs_address, instr_is_io, instr_is_write, errors);

        -- ================================================================
        -- NEW CONTROL SIGNAL TESTS
        -- ================================================================
        report "";
        report "========================================";
        report "TESTING NEW CONTROL SIGNALS";
        report "========================================";

        -- Test 1: MOV B,C (11 DDD SSS) - register read/write
        report "";
        report "Test: MOV B,C - Register read/write signals";
        instruction_byte <= "11001010";  -- 11 001 010 (DDD=B=001, SSS=C=010)
        wait for 10 ns;

        if instr_reads_reg /= '1' then
            report "  ERROR: MOV should set reads_reg=1" severity error;
            errors := errors + 1;
        end if;
        if instr_writes_reg /= '1' then
            report "  ERROR: MOV should set writes_reg=1" severity error;
            errors := errors + 1;
        end if;
        if instr_sss_field /= "010" then
            report "  ERROR: SSS should be 010 (C)" severity error;
            errors := errors + 1;
        end if;
        if instr_ddd_field /= "001" then
            report "  ERROR: DDD should be 001 (B)" severity error;
            errors := errors + 1;
        else
            report "  PASS: MOV B,C register fields correct";
        end if;

        -- Test 2: ADD E (10 000 101) - ALU operation
        report "";
        report "Test: ADD E - ALU operation signals";
        instruction_byte <= "10000101";  -- 10 000 101 (ALU add, SSS=E=101)
        wait for 10 ns;

        if instr_is_alu /= '1' then
            report "  ERROR: ADD should set is_alu=1" severity error;
            errors := errors + 1;
        end if;
        if instr_reads_reg /= '1' then
            report "  ERROR: ADD should set reads_reg=1" severity error;
            errors := errors + 1;
        end if;
        if instr_writes_reg /= '1' then
            report "  ERROR: ADD should set writes_reg=1 (writes A)" severity error;
            errors := errors + 1;
        end if;
        if instr_sss_field /= "101" then
            report "  ERROR: SSS should be 101 (E)" severity error;
            errors := errors + 1;
        end if;
        if instr_ddd_field /= "000" then
            report "  ERROR: DDD should be 000 (A)" severity error;
            errors := errors + 1;
        else
            report "  PASS: ADD E signals correct";
        end if;

        -- Test 3: LrI B,data (00 001 110) - Load register immediate
        report "";
        report "Test: LrI B - Load register immediate";
        instruction_byte <= "00001110";  -- 00 001 110 (DDD=B=001)
        wait for 10 ns;

        if instr_writes_reg /= '1' then
            report "  ERROR: LrI should set writes_reg=1" severity error;
            errors := errors + 1;
        end if;
        if instr_ddd_field /= "001" then
            report "  ERROR: DDD should be 001 (B)" severity error;
            errors := errors + 1;
        else
            report "  PASS: LrI B signals correct";
        end if;

        -- Test 4: INP port (01 000 001) - I/O read
        report "";
        report "Test: INP - I/O input to A";
        instruction_byte <= "01000001";  -- 01 000 001
        wait for 10 ns;

        if instr_is_io /= '1' then
            report "  ERROR: INP should set is_io=1" severity error;
            errors := errors + 1;
        end if;
        if instr_writes_reg /= '1' then
            report "  ERROR: INP should set writes_reg=1" severity error;
            errors := errors + 1;
        end if;
        if instr_ddd_field /= "000" then
            report "  ERROR: DDD should be 000 (A)" severity error;
            errors := errors + 1;
        else
            report "  PASS: INP signals correct";
        end if;

        -- Test 5: OUT port (01 100 001) - I/O write
        report "";
        report "Test: OUT - I/O output from A";
        instruction_byte <= "01100001";  -- 01 100 001
        wait for 10 ns;

        if instr_is_io /= '1' then
            report "  ERROR: OUT should set is_io=1" severity error;
            errors := errors + 1;
        end if;
        if instr_reads_reg /= '1' then
            report "  ERROR: OUT should set reads_reg=1" severity error;
            errors := errors + 1;
        end if;
        if instr_sss_field /= "000" then
            report "  ERROR: SSS should be 000 (A)" severity error;
            errors := errors + 1;
        else
            report "  PASS: OUT signals correct";
        end if;

        -- Test 6: CALL (01 XXX 110)
        report "";
        report "Test: CALL - Stack push";
        instruction_byte <= "01000110";  -- 01 000 110
        wait for 10 ns;

        if instr_is_call /= '1' then
            report "  ERROR: CALL should set is_call=1" severity error;
            errors := errors + 1;
        else
            report "  PASS: CALL signals correct";
        end if;

        -- Test 7: RET (00 XXX 111)
        report "";
        report "Test: RET - Stack pop";
        instruction_byte <= "00000111";  -- 00 000 111
        wait for 10 ns;

        if instr_is_ret /= '1' then
            report "  ERROR: RET should set is_ret=1" severity error;
            errors := errors + 1;
        else
            report "  PASS: RET signals correct";
        end if;

        -- Test 8: RST 0 (00 000 101)
        report "";
        report "Test: RST 0 - Restart";
        instruction_byte <= "00000101";  -- 00 000 101
        wait for 10 ns;

        if instr_is_rst /= '1' then
            report "  ERROR: RST should set is_rst=1" severity error;
            errors := errors + 1;
        else
            report "  PASS: RST signals correct";
        end if;

        -- Test 9: INr D (00 011 000) - Increment
        report "";
        report "Test: INr D - Increment register";
        instruction_byte <= "00011000";  -- 00 011 000 (DDD=D=011)
        wait for 10 ns;

        if instr_is_alu /= '1' then
            report "  ERROR: INr should set is_alu=1" severity error;
            errors := errors + 1;
        end if;
        if instr_reads_reg /= '1' then
            report "  ERROR: INr should set reads_reg=1" severity error;
            errors := errors + 1;
        end if;
        if instr_writes_reg /= '1' then
            report "  ERROR: INr should set writes_reg=1" severity error;
            errors := errors + 1;
        end if;
        if instr_ddd_field /= "011" then
            report "  ERROR: DDD should be 011 (D)" severity error;
            errors := errors + 1;
        else
            report "  PASS: INr D signals correct";
        end if;

        -- Test 10: LMr C (11 111 010) - Load memory from register
        report "";
        report "Test: LMr C - Memory write from register";
        instruction_byte <= "11111010";  -- 11 111 010 (SSS=C=010)
        wait for 10 ns;

        if instr_is_write /= '1' then
            report "  ERROR: LMr should set is_write=1" severity error;
            errors := errors + 1;
        end if;
        if instr_reads_reg /= '1' then
            report "  ERROR: LMr should set reads_reg=1" severity error;
            errors := errors + 1;
        end if;
        if instr_sss_field /= "010" then
            report "  ERROR: SSS should be 010 (C)" severity error;
            errors := errors + 1;
        else
            report "  PASS: LMr C signals correct";
        end if;

        -- Summary
        report "";
        report "========================================";
        if errors = 0 then
            report "*** ALL TESTS PASSED ***";
        else
            report "*** TESTS FAILED: " & integer'image(errors) & " errors ***" severity error;
        end if;
        report "========================================";

        wait;
    end process;

end architecture test;

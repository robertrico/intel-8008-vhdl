-------------------------------------------------------------------------------
-- Intel 8008 - v8008 Refactored Implementation
-------------------------------------------------------------------------------
-- Copyright (c) 2025 Robert Rico
--
-- Refactored VHDL implementation of the Intel 8008 microprocessor.
-- This is a clean-slate implementation to fix ALU timing issues.
--
-- Reference: Intel 8008 Datasheet (April 1974)
-- License: MIT (see LICENSE.txt)
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity v8008 is
    port (
        -- Two-phase clock inputs (non-overlapping)
        phi1 : in std_logic;
        phi2 : in std_logic;

        -- 8-bit multiplexed address/data bus
        data_bus_in     : in  std_logic_vector(7 downto 0);
        data_bus_out    : out std_logic_vector(7 downto 0);
        data_bus_enable : out std_logic;

        -- State outputs (timing state indication)
        S0 : out std_logic;
        S1 : out std_logic;
        S2 : out std_logic;

        -- SYNC output (timing reference)
        SYNC : out std_logic;

        -- READY input (wait state control)
        READY : in std_logic;

        -- Interrupt request input
        INT : in std_logic := '0';

        -- Debug outputs (for testbench verification)
        debug_reg_A : out std_logic_vector(7 downto 0);
        debug_reg_B : out std_logic_vector(7 downto 0);
        debug_reg_C : out std_logic_vector(7 downto 0);
        debug_reg_D : out std_logic_vector(7 downto 0);
        debug_reg_E : out std_logic_vector(7 downto 0);
        debug_reg_H : out std_logic_vector(7 downto 0);
        debug_reg_L : out std_logic_vector(7 downto 0);
        debug_pc : out std_logic_vector(13 downto 0);
        debug_flags : out std_logic_vector(3 downto 0);
        debug_instruction : out std_logic_vector(7 downto 0);
        debug_stack_pointer : out std_logic_vector(2 downto 0);
        debug_hl_address : out std_logic_vector(13 downto 0)
    );
end v8008;

architecture rtl of v8008 is

    --===========================================
    -- Register File
    --===========================================
    --   000 = A (Accumulator)
    --   001 = B
    --   010 = C
    --   011 = D
    --   100 = E
    --   101 = H (High byte of memory pointer)
    --   110 = L (Low byte of memory pointer)
    --   111 = M (Memory reference via H:L - not a physical register)
    type register_file_t is array (0 to 6) of std_logic_vector(7 downto 0);
    signal registers : register_file_t := (others => (others => '0'));

    -- Register addressing constants for clarity (3-bit register codes)
    constant REG_A : std_logic_vector(2 downto 0) := "000";  -- Accumulator
    constant REG_B : std_logic_vector(2 downto 0) := "001";
    constant REG_C : std_logic_vector(2 downto 0) := "010";
    constant REG_D : std_logic_vector(2 downto 0) := "011";
    constant REG_E : std_logic_vector(2 downto 0) := "100";
    constant REG_H : std_logic_vector(2 downto 0) := "101";  -- High byte of address
    constant REG_L : std_logic_vector(2 downto 0) := "110";  -- Low byte of address
    constant REG_M : std_logic_vector(2 downto 0) := "111";  -- Memory reference via H:L

    -- Register addressing aliases for clarity
    constant REG_A_DATA : integer := 0;  -- Accumulator
    constant REG_B_DATA : integer := 1;
    constant REG_C_DATA : integer := 2;
    constant REG_D_DATA : integer := 3;
    constant REG_E_DATA : integer := 4;
    constant REG_H_DATA : integer := 5;  -- High byte of address
    constant REG_L_DATA : integer := 6;  -- Low byte of address

    --===========================================
    -- Component Declarations
    --===========================================

    -- ALU Component
    component i8008_alu is
        port(
            data_0 : in std_logic_vector(7 downto 0);
            data_1 : in std_logic_vector(7 downto 0);
            flag_carry : in std_logic;
            command : in std_logic_vector(2 downto 0);
            alu_result : out std_logic_vector(8 downto 0)
        );
    end component;

    --===========================================
    -- Internal Signals
    --===========================================

    -- ALU signals
    signal alu_data_0 : std_logic_vector(7 downto 0);
    signal alu_data_1 : std_logic_vector(7 downto 0);
    signal alu_command : std_logic_vector(2 downto 0);
    signal alu_result : std_logic_vector(8 downto 0);
    signal flag_carry : std_logic;
    
    -- SYNC signal generation
    -- Per Intel 8008 datasheet: SYNC is phi2 divided by 2
    -- SYNC changes on both rising and falling edges of phi2
    signal sync_reg : std_logic := '0';      -- Registered SYNC output
    
    -- Timing state machine
    -- The 8008 starts in STOPPED state (no reset pin!)
    type timing_state_t is (T1, T1I, T2, TWAIT, T3, T4, T5, STOPPED);
    signal timing_state : timing_state_t := STOPPED;  -- Power-on state is STOPPED
    signal timing_state_prev : timing_state_t := STOPPED;
    
    -- Machine cycle tracking
    signal current_cycle : integer range 0 to 2 := 0;  -- Which machine cycle (0-2)
    signal cycle_type : std_logic_vector(1 downto 0) := "00";  -- PCI/PCR/PCC/PCW
    
    -- Cycle type constants
    constant CYCLE_PCI : std_logic_vector(1 downto 0) := "00";  -- Instruction fetch
    constant CYCLE_PCR : std_logic_vector(1 downto 0) := "01";  -- Memory read
    constant CYCLE_PCC : std_logic_vector(1 downto 0) := "10";  -- I/O operation
    constant CYCLE_PCW : std_logic_vector(1 downto 0) := "11";  -- Memory write
    
    -- Interrupt handling signals
    signal int_pending : std_logic := '0';      -- Latched interrupt request (cleared at T3 of int ack)
    signal int_previous : std_logic := '0';     -- Previous INT value for edge detection
    signal in_int_ack_cycle : std_logic := '0'; -- '1' during entire interrupt acknowledge cycle
    
    -- Instruction Register (8-bit)
    -- Holds the current instruction being executed
    signal instruction_reg : std_logic_vector(7 downto 0) := (others => '0');
    
    -- Instruction cycle counter
    -- Tracks which byte of a multi-byte instruction we're fetching
    signal instruction_cycle : integer range 0 to 2 := 0;
    
    -- Program Counter (14-bit for 16K address space)
    -- Note: The PC is conceptually stack(stack_pointer) but kept separate for clarity
    signal pc : unsigned(13 downto 0) := (others => '0');
    
    --===========================================
    -- Address Stack (8 levels of 14-bit addresses)
    --===========================================
    -- The 8008 has 8 address registers that form a stack
    -- One is used as PC, the other 7 for subroutine return addresses
    -- This is a circular buffer - overflow wraps around
    type address_stack_t is array (0 to 7) of unsigned(13 downto 0);
    signal address_stack : address_stack_t := (others => (others => '0'));
    
    -- 3-bit stack pointer (0-7)
    -- Points to the current PC location in the stack
    signal stack_pointer : unsigned(2 downto 0) := "000";
    
    -- Stack control signals
    signal push_stack : boolean := false;  -- Push PC and increment pointer
    signal pop_stack : boolean := false;   -- Decrement pointer and pop to PC
    
    -- Flags register (Carry, Zero, Sign, Parity)
    signal flags : std_logic_vector(3 downto 0) := (others => '0');
    alias flag_c : std_logic is flags(3);  -- Carry flag
    alias flag_z : std_logic is flags(2);  -- Zero flag  
    alias flag_s : std_logic is flags(1);  -- Sign flag
    alias flag_p : std_logic is flags(0);  -- Parity flag
    
    -- Internal data bus for register transfers
    signal internal_data_bus : std_logic_vector(7 downto 0) := (others => '0');
    
    -- Temporary registers for instruction execution
    signal temp_a : std_logic_vector(7 downto 0) := (others => '0');  -- Reg.a from datasheet
    signal temp_b : std_logic_vector(7 downto 0) := (others => '0');  -- Reg.b from datasheet

    -- Sub-phase tracking for proper φ₁/φ₂ timing
    -- Each timing state (T1-T5) has TWO phi1/phi2 cycles:
    --   φ₁₁/φ₂₁ (sub=0): First half - setup, register reads
    --   φ₁₂/φ₂₂ (sub=1): Second half - data movement, temp register loads
    signal phi1_sub : integer range 0 to 1 := 0;  -- 0=φ₁₁, 1=φ₁₂
    signal phi2_sub : integer range 0 to 1 := 0;  -- 0=φ₂₁, 1=φ₂₂

    --===========================================
    -- Microcode Architecture
    --===========================================
    -- Each instruction's behavior is explicitly defined for each state
    type microcode_entry is record
        -- State control
        next_state          : timing_state_t;
        advance_state       : boolean;           -- True=advance to next_state, False=stay in current state
        new_cycle           : boolean;           -- Start new machine cycle
        instruction_complete: boolean;           -- Entire instruction done

        -- Data movement
        load_ir             : boolean;           -- Load instruction register
        load_temp_a         : boolean;           -- Load temp_a
        load_temp_b         : boolean;           -- Load temp_b
        temp_a_source       : std_logic_vector(1 downto 0); -- 00=zero, 01=data_bus, 10=reg
        temp_b_source       : std_logic_vector(1 downto 0); -- 00=zero, 01=data_bus, 10=reg
        
        -- PC control
        pc_inc              : boolean;           -- Increment PC
        pc_load_high        : boolean;           -- Load PC high from temp_a
        pc_load_low         : boolean;           -- Load PC low from temp_b (RST vector)
        
        -- Stack control
        stack_push          : boolean;           -- Push PC to stack
        stack_pop           : boolean;           -- Pop PC from stack

        -- Register control
        reg_write           : boolean;           -- Write to register file
        reg_read            : boolean;           -- Read from register file
        reg_target          : std_logic_vector(2 downto 0); -- Which register (A/B/C/D/E/H/L)
        reg_source          : std_logic_vector(1 downto 0); -- 00=zero, 01=data_bus_in, 10=temp_a, 11=temp_b

        -- Flag control
        flags_update        : boolean;           -- Update flags from ALU result

        -- Next cycle type (for T2 output)
        next_cycle_type     : std_logic_vector(1 downto 0);
    end record;
    
    -- Default microcode entry (safe do-nothing)
    constant DEFAULT_UCODE : microcode_entry := (
        next_state => T1,  -- Will be overridden for STOPPED state
        advance_state => true,  -- By default, advance to next_state after both sub-phases
        new_cycle => false,
        instruction_complete => false,
        load_ir => false,
        load_temp_a => false,
        load_temp_b => false,
        temp_a_source => "00",
        temp_b_source => "00",
        pc_inc => false,
        pc_load_high => false,
        pc_load_low => false,
        stack_push => false,
        stack_pop => false,
        reg_write => false,
        reg_read => false,
        reg_target => "000",
        reg_source => "00",
        flags_update => false,
        next_cycle_type => CYCLE_PCI
    );
    
    --===========================================
    -- Instruction Decoder Types
    --===========================================
    -- Instruction classes based on opcode bits [7:6]
    type instruction_class_t is (
        CLASS_00,  -- Mixed ops: HLT, RST, MVI, ALU immediate, rotate, inc/dec
        CLASS_01,  -- Jump, call, return, I/O
        CLASS_10,  -- ALU register operations
        CLASS_11,  -- MOV operations
        CLASS_UNKNOWN
    );

    -- Decoded instruction information
    type decoded_instruction_t is record
        -- Primary class (from bits [7:6])
        iclass : instruction_class_t;

        -- Extracted opcode fields (3-bit fields from instruction)
        ddd_field : std_logic_vector(2 downto 0);  -- Destination register (bits 5:3)
        sss_field : std_logic_vector(2 downto 0);  -- Source register (bits 2:0)
        fff_field : std_logic_vector(2 downto 0);  -- Function code (bits 5:3)
        aaa_field : std_logic_vector(2 downto 0);  -- RST vector (bits 5:3)
        ccc_field : std_logic_vector(2 downto 0);  -- Condition code (bits 5:3)
        mmm_field : std_logic_vector(2 downto 0);  -- I/O port (bits 3:1)

        -- Variant detection flags
        is_memory_source : boolean;  -- SSS = 111 (M register - memory indirect)
        is_memory_dest   : boolean;  -- DDD = 111 (M register - memory indirect)
        is_immediate     : boolean;  -- Instruction has immediate byte following

        -- Specific instruction identifiers
        is_hlt : boolean;   -- HLT instruction
        is_rst : boolean;   -- RST instruction
        is_mvi : boolean;   -- MVI instruction (all variants)
        is_inp : boolean;   -- INP instruction
        is_out : boolean;   -- OUT instruction
        is_mov : boolean;   -- MOV instruction (future)
        is_alu : boolean;   -- ALU operation (any variant)
        is_alu_register : boolean;  -- ALU with register operand (10 PPP SSS, SSS ≠ 111)
        is_alu_memory   : boolean;  -- ALU with memory operand (10 PPP 111)
        is_alu_imm      : boolean;  -- ALU with immediate operand (00 PPP 100)
        is_jmp : boolean;   -- JMP unconditional (01 XXX 100)
        is_jmp_conditional : boolean;  -- Conditional JMP (01 CCC 000)
        is_call : boolean;  -- CALL unconditional (01 XXX 110)
        is_inr : boolean;   -- INR instruction (00 DDD 000, DDD ≠ 000)
        is_dcr : boolean;   -- DCR instruction (00 DDD 001, DDD ≠ 000)
        is_rotate : boolean;  -- Rotate instruction (00 FFF 010, FFF = 000-011)
    end record;

    -- Current microcode being executed (moved to process as variable)

    --===========================================
    -- Condition Evaluation Function
    --===========================================
    -- Evaluates conditional jump/call/return conditions based on CCC field and flags
    -- CCC field (bits 5:3 of conditional instruction):
    --   000 = JFC/CFC/RFC - Jump/Call/Return if Carry = 0
    --   001 = JFZ/CFZ/RFZ - Jump/Call/Return if Zero = 0
    --   010 = JFS/CFS/RFS - Jump/Call/Return if Sign = 0
    --   011 = JFP/CFP/RFP - Jump/Call/Return if Parity = 0
    --   100 = JTC/CTC/RTC - Jump/Call/Return if Carry = 1
    --   101 = JTZ/CTZ/RTZ - Jump/Call/Return if Zero = 1
    --   110 = JTS/CTS/RTS - Jump/Call/Return if Sign = 1
    --   111 = JTP/CTP/RTP - Jump/Call/Return if Parity = 1
    function evaluate_condition(
        ccc : std_logic_vector(2 downto 0);
        flag_vector : std_logic_vector(3 downto 0)
    ) return boolean is
        variable v_flag_c : std_logic := flag_vector(3);  -- Carry flag
        variable v_flag_z : std_logic := flag_vector(2);  -- Zero flag
        variable v_flag_s : std_logic := flag_vector(1);  -- Sign flag
        variable v_flag_p : std_logic := flag_vector(0);  -- Parity flag
        variable test_true : boolean;  -- Bit 5: 0=False, 1=True
        variable flag_value : std_logic;
    begin
        -- CCC encoding: bit 2 = T/F, bits 1-0 = flag selector
        -- JFc (Jump if False): 01 0CC 000, JTc (Jump if True): 01 1CC 000
        -- CC: 00=carry, 01=zero, 10=sign, 11=parity

        test_true := (ccc(2) = '1');  -- Bit 5 of opcode

        -- Select flag based on bits 4-3 of opcode (bits 1-0 of ccc)
        case ccc(1 downto 0) is
            when "00" => flag_value := v_flag_c;  -- Carry
            when "01" => flag_value := v_flag_z;  -- Zero
            when "10" => flag_value := v_flag_s;  -- Sign
            when "11" => flag_value := v_flag_p;  -- Parity
            when others => flag_value := '0';
        end case;

        -- Return true if: (test_true and flag=1) or (test_false and flag=0)
        if test_true then
            return (flag_value = '1');  -- JTx: jump if flag is true
        else
            return (flag_value = '0');  -- JFx: jump if flag is false
        end if;
    end function;

    --===========================================
    -- Instruction Decoder Function
    --===========================================
    -- Decodes an opcode and returns all relevant instruction information
    -- This eliminates hardcoded bit-pattern checks throughout the microcode
    function decode_instruction(
        opcode : std_logic_vector(7 downto 0)
    ) return decoded_instruction_t is
        variable result : decoded_instruction_t;
    begin
        -- Extract all opcode fields (always extract, use as needed)
        result.ddd_field := opcode(5 downto 3);  -- Destination register
        result.sss_field := opcode(2 downto 0);  -- Source register
        result.fff_field := opcode(5 downto 3);  -- ALU/rotate function
        result.aaa_field := opcode(5 downto 3);  -- RST vector
        result.ccc_field := opcode(5 downto 3);  -- Condition code
        result.mmm_field := opcode(3 downto 1);  -- I/O port

        -- Memory reference detection (M register = 111)
        result.is_memory_source := (opcode(2 downto 0) = "111");
        result.is_memory_dest   := (opcode(5 downto 3) = "111");

        -- Default all instruction flags to false
        result.is_immediate := false;
        result.is_hlt := false;
        result.is_rst := false;
        result.is_mvi := false;
        result.is_inp := false;
        result.is_out := false;
        result.is_mov := false;
        result.is_alu := false;
        result.is_alu_register := false;
        result.is_alu_memory := false;
        result.is_alu_imm := false;
        result.is_jmp := false;
        result.is_jmp_conditional := false;
        result.is_call := false;
        result.is_inr := false;
        result.is_dcr := false;
        result.is_rotate := false;
        result.iclass := CLASS_UNKNOWN;

        -- Special case: HLT has multiple encodings across different classes
        -- 0x00, 0x01 (CLASS_00) and 0xFF (CLASS_11)
        if opcode = x"00" or opcode = x"01" or opcode = x"FF" then
            result.is_hlt := true;
            -- Set class based on opcode bits for consistency
            if opcode = x"FF" then
                result.iclass := CLASS_11;
            else
                result.iclass := CLASS_00;
            end if;
        end if;

        -- Decode by instruction class (bits [7:6])
        case opcode(7 downto 6) is
            when "00" =>
                if not result.is_hlt then  -- Skip if already identified as HLT
                    result.iclass := CLASS_00;
                end if;

                -- HLT already handled above, skip redundant check here

                -- RST: 00 AAA 101
                if opcode(2 downto 0) = "101" then
                    result.is_rst := true;

                -- MVI: 00 DDD 110 (includes MVI M when DDD=111)
                elsif opcode(2 downto 0) = "110" then
                    result.is_mvi := true;
                    result.is_immediate := true;
                    report "Decoder: Recognized MVI for opcode 0x" & to_hstring(opcode);

                -- ALU immediate: 00 FFF 100 (ADI, ACI, SUI, SBI, ANI, XRI, ORI, CPI)
                elsif opcode(2 downto 0) = "100" then
                    result.is_alu := true;
                    result.is_alu_imm := true;
                    result.is_immediate := true;

                -- INR: 00 DDD 000 (DDD ≠ 000)
                elsif opcode(2 downto 0) = "000" and opcode(5 downto 3) /= "000" then
                    result.is_inr := true;

                -- DCR: 00 DDD 001 (DDD ≠ 000)
                elsif opcode(2 downto 0) = "001" and opcode(5 downto 3) /= "000" then
                    result.is_dcr := true;

                -- Rotate: 00 FFF 010 (RLC, RRC, RAL, RAR where FFF = 000-011)
                elsif opcode(2 downto 0) = "010" and opcode(5) = '0' then
                    result.is_rotate := true;

                -- More CLASS_00 instructions can be added here:
                -- RET: 00 XXX 111, 00 CCC 011

                end if;

            when "01" =>
                result.iclass := CLASS_01;

                -- INP: 01 00M MM1
                if opcode(5 downto 4) = "00" and opcode(0) = '1' then
                    result.is_inp := true;

                -- OUT: 01 RRM MM1 (RR ≠ 00)
                elsif opcode(0) = '1' and opcode(5 downto 4) /= "00" then
                    result.is_out := true;

                -- JMP unconditional: 01 XXX 100
                elsif opcode(2 downto 0) = "100" then
                    result.is_jmp := true;
                    result.is_immediate := true;  -- 3-byte instruction (opcode + 2 address bytes)

                -- JMP conditional: 01 CCC 000
                elsif opcode(2 downto 0) = "000" then
                    result.is_jmp_conditional := true;
                    result.is_jmp := true;  -- Also set is_jmp for combined checks
                    result.is_immediate := true;  -- 3-byte instruction
                    report "Decoder: Recognized conditional JMP for opcode 0x" & to_hstring(opcode) & ", CCC=" & to_string(opcode(5 downto 3));

                -- CALL unconditional: 01 XXX 110
                elsif opcode(2 downto 0) = "110" then
                    result.is_call := true;
                    result.is_immediate := true;  -- 3-byte instruction (opcode + 2 address bytes)
                    report "Decoder: Recognized CALL for opcode 0x" & to_hstring(opcode);

                -- More CLASS_01 instructions can be added here:
                -- Conditional CALL: 01 CCC 010

                end if;

            when "10" =>
                result.iclass := CLASS_10;
                result.is_alu := true;
                -- ALU operations: 10 PPP SSS
                -- PPP = operation code (ADD, ADC, SUB, SBB, AND, XOR, OR, CMP)
                -- SSS = source (register or memory via M=111)

                if result.is_memory_source then  -- SSS = 111
                    result.is_alu_memory := true;
                else  -- SSS = 000-110 (register)
                    result.is_alu_register := true;
                end if;

            when "11" =>
                result.iclass := CLASS_11;
                result.is_mov := true;
                -- MOV: 11 DDD SSS
                -- Destination can be register (DDD ≠ 111) or memory (DDD = 111)
                -- Source can be register (SSS ≠ 111) or memory (SSS = 111)
                -- Both cannot be memory simultaneously (invalid encoding)

            when others =>
                result.iclass := CLASS_UNKNOWN;
        end case;

        return result;
    end function;

    --===========================================
    -- Microcode Lookup Function
    --===========================================
    -- Returns the microcode for a given instruction, cycle, and state
    function get_microcode(
        instr : std_logic_vector(7 downto 0);
        cycle : integer;
        state : timing_state_t;
        sub_phase : integer;  -- 0=φ₁₁/φ₂₁ (first half), 1=φ₁₂/φ₂₂ (second half)
        int_ack : std_logic;
        data_in : std_logic_vector(7 downto 0);  -- For T3 instruction fetch
        cpu_flags : std_logic_vector(3 downto 0)  -- CPU flags for conditional instructions
    ) return microcode_entry is
        variable decoded : decoded_instruction_t;  -- Decoded instruction info
    begin
        -- ===========================================
        -- CYCLE 0: INSTRUCTION FETCH & DECODE
        -- ===========================================
        -- This handles ALL cycle 0 operations including:
        -- - Normal instruction fetch (T1, T2, T3)
        -- - Interrupt acknowledge (T1I transitions to T2)
        -- - Instruction-specific T4/T5 states
        -- Note: When int_ack='1', external hardware injects instruction at T3
        if cycle = 0 then
            case state is
                when T1I =>
                    -- T1I: Start interrupt acknowledge cycle
                    return (
                        next_state => T2,
                        advance_state => true,
                        new_cycle => false,
                        instruction_complete => false,
                        load_ir => false,
                        load_temp_a => false,
                        load_temp_b => false,
                        temp_a_source => "00",
                        temp_b_source => "00",
                        pc_inc => false,
                        pc_load_high => false,
                        pc_load_low => false,
                        stack_push => false,
                        stack_pop => false,
                        reg_write => false,
                        reg_read => false,
                        reg_target => "000",
                        reg_source => "00",
                        flags_update => false,
                        next_cycle_type => CYCLE_PCI
                    );
                    
                when T1 =>
                    -- Generic T1 for ALL instructions: PCL OUT
                    return (
                        next_state => T2,
                        advance_state => true,
                        new_cycle => false,  -- Already in cycle 0
                        instruction_complete => false,
                        load_ir => false,
                        load_temp_a => false,
                        load_temp_b => false,
                        temp_a_source => "00",
                        temp_b_source => "00",
                        pc_inc => false,
                        pc_load_high => false,
                        pc_load_low => false,
                        stack_push => false,
                        stack_pop => false,
                        reg_write => false,
                        reg_read => false,
                        reg_target => "000",
                        reg_source => "00",
                        flags_update => false,
                        next_cycle_type => CYCLE_PCI
                    );
                    
                when T2 =>
                    -- Generic T2 for ALL instructions: PCH OUT
                    -- Same for both normal fetch and interrupt acknowledge
                    return (
                        next_state => T3,
                        advance_state => true,
                        new_cycle => false,
                        instruction_complete => false,
                        load_ir => false,
                        load_temp_a => false,
                        load_temp_b => false,
                        temp_a_source => "00",
                        temp_b_source => "00",
                        pc_inc => false,
                        pc_load_high => false,
                        pc_load_low => false,
                        stack_push => false,
                        stack_pop => false,
                        reg_write => false,
                        reg_read => false,
                        reg_target => "000",
                        reg_source => "00",
                        flags_update => false,
                        next_cycle_type => CYCLE_PCI
                    );
                    
                when T3 =>
                    -- Generic T3: ALWAYS fetch instruction to IR and Reg.b
                    -- Per Intel 8008 behavior, temp_b holds instruction for later use
                    -- PC increment behavior:
                    --   - HLT: No increment (stays at same address)
                    --   - RST/JMP/CALL: No increment (PC will be loaded)
                    --   - Single-byte instructions: Increment after fetch
                    --   - Multi-byte: Increment after each byte (handled in later cycles)
                    -- Then decode and determine next state
                    --
                    -- SUB-PHASE HANDLING FOR T3:
                    --   sub_phase=0: Load IR, set control signals, advance_state=false (stay in T3)
                    --   sub_phase=1: Execute state transition, advance_state=true (move to next_state)

                    -- AT SUB_PHASE=1: Just advance state without reloading IR
                    -- Decode from instr (which is instruction_reg, already loaded at sub_phase=0)
                    if sub_phase = 1 then
                        decoded := decode_instruction(instr);
                        report "T3 decode: instr=0x" & to_hstring(instr) &
                               ", is_mvi=" & boolean'image(decoded.is_mvi) &
                               ", is_inp=" & boolean'image(decoded.is_inp) &
                               ", is_out=" & boolean'image(decoded.is_out) &
                               ", is_alu_imm=" & boolean'image(decoded.is_alu_imm);

                        -- Determine next_state and return minimal microcode
                        if decoded.is_hlt then
                            return (
                                next_state => STOPPED,
                                advance_state => true,
                                new_cycle => false,
                                instruction_complete => true,
                                load_ir => false,
                                load_temp_a => false,
                                load_temp_b => false,
                                temp_a_source => "00",
                                temp_b_source => "00",
                                pc_inc => false,
                                pc_load_high => false,
                                pc_load_low => false,
                                stack_push => false,
                                stack_pop => false,
                                reg_write => false,
                                reg_read => false,
                                reg_target => "000",
                                reg_source => "00",
                                flags_update => false,
                                next_cycle_type => CYCLE_PCI
                            );
                        elsif decoded.is_rst then
                            return (
                                next_state => T4,
                                advance_state => true,
                                new_cycle => false,
                                instruction_complete => false,
                                load_ir => false,
                                load_temp_a => false,
                                load_temp_b => false,
                                temp_a_source => "00",
                                temp_b_source => "00",
                                pc_inc => false,
                                pc_load_high => false,
                                pc_load_low => false,
                                stack_push => false,
                                stack_pop => false,
                                reg_write => false,
                                reg_read => false,
                                reg_target => "000",
                                reg_source => "00",
                                flags_update => false,
                                next_cycle_type => CYCLE_PCI
                            );
                        elsif decoded.is_alu_memory then
                            -- ALU M: ALU operation with memory operand (5-state, 2-cycle)
                            -- Opcode: 10 PPP 111 (bits [7:6] = 10, PPP = operation, 111 = memory reference)
                            -- Cycle 0 T3: Fetch instruction and start cycle 1
                            return (
                                next_state => T1,
                                advance_state => true,
                                new_cycle => true,
                                instruction_complete => false,
                                load_ir => false,
                                load_temp_a => false,
                                load_temp_b => false,
                                temp_a_source => "00",
                                temp_b_source => "00",
                                pc_inc => true,                  -- Increment PC to next instruction
                                pc_load_high => false,
                                pc_load_low => false,
                                stack_push => false,
                                stack_pop => false,
                                reg_write => false,
                                reg_read => false,
                                reg_target => "000",
                                reg_source => "00",
                                flags_update => false,
                                next_cycle_type => CYCLE_PCI
                            );
                        elsif decoded.is_inp or decoded.is_out then
                            -- I/O instructions: INP and OUT
                            -- Next cycle is I/O operation (CYCLE_PCC)
                            -- PC increment happens here during Cycle 0 T3 sub_phase=1
                            return (
                                next_state => T1,
                                advance_state => true,
                                new_cycle => true,
                                instruction_complete => false,
                                load_ir => false,
                                load_temp_a => false,
                                load_temp_b => false,
                                temp_a_source => "00",
                                temp_b_source => "00",
                                pc_inc => true,
                                pc_load_high => false,
                                pc_load_low => false,
                                stack_push => false,
                                stack_pop => false,
                                reg_write => false,
                                reg_read => false,
                                reg_target => "000",
                                reg_source => "00",
                                flags_update => false,
                                next_cycle_type => CYCLE_PCC
                            );
                        elsif decoded.is_mvi or decoded.is_alu_imm or decoded.is_jmp or decoded.is_jmp_conditional or decoded.is_call then
                            -- Multi-byte instructions: MVI, ALU_IMM, JMP, CALL
                            -- Next cycle fetches next byte (CYCLE_PCI)
                            return (
                                next_state => T1,
                                advance_state => true,
                                new_cycle => true,
                                instruction_complete => false,
                                load_ir => false,
                                load_temp_a => false,
                                load_temp_b => false,
                                temp_a_source => "00",
                                temp_b_source => "00",
                                pc_inc => false,
                                pc_load_high => false,
                                pc_load_low => false,
                                stack_push => false,
                                stack_pop => false,
                                reg_write => false,
                                reg_read => false,
                                reg_target => "000",
                                reg_source => "00",
                                flags_update => false,
                                next_cycle_type => CYCLE_PCI
                            );
                        elsif decoded.is_mov and not decoded.is_memory_source and not decoded.is_memory_dest then
                            -- MOV r,r: Register-to-register (5-state, 1-cycle)
                            return (
                                next_state => T4,
                                advance_state => true,
                                new_cycle => false,
                                instruction_complete => false,
                                load_ir => false,
                                load_temp_a => false,
                                load_temp_b => false,
                                temp_a_source => "00",
                                temp_b_source => "00",
                                pc_inc => true,                  -- Increment PC to next instruction
                                pc_load_high => false,
                                pc_load_low => false,
                                stack_push => false,
                                stack_pop => false,
                                reg_write => false,
                                reg_read => false,
                                reg_target => "000",
                                reg_source => "00",
                                flags_update => false,
                                next_cycle_type => CYCLE_PCI
                            );
                        elsif decoded.is_alu_register then
                            -- ALU register: ALU operation with register operand (5-state, 1-cycle)
                            -- Opcode: 10 PPP SSS (bits [7:6] = 10, PPP = operation, SSS = source register)
                            -- Similar to MOV r,r but updates flags and uses ALU
                            return (
                                next_state => T4,
                                advance_state => true,
                                new_cycle => false,
                                instruction_complete => false,
                                load_ir => false,
                                load_temp_a => false,
                                load_temp_b => false,
                                temp_a_source => "00",
                                temp_b_source => "00",
                                pc_inc => true,                  -- Increment PC to next instruction
                                pc_load_high => false,
                                pc_load_low => false,
                                stack_push => false,
                                stack_pop => false,
                                reg_write => false,
                                reg_read => false,
                                reg_target => "000",
                                reg_source => "00",
                                flags_update => false,
                                next_cycle_type => CYCLE_PCI
                            );
                        elsif decoded.is_inr or decoded.is_dcr or decoded.is_rotate then
                            -- INR/DCR/ROTATE: Single-cycle 5-state instructions
                            -- INR: 00 DDD 000 (DDD ≠ 000), DCR: 00 DDD 001 (DDD ≠ 000)
                            -- ROTATE: 00 FFF 010 (FFF = 000-011: RLC, RRC, RAL, RAR)
                            -- T3: Fetch instruction, T4: IDLE, T5: Execute operation and update flags
                            return (
                                next_state => T4,
                                advance_state => true,
                                new_cycle => false,
                                instruction_complete => false,
                                load_ir => false,
                                load_temp_a => false,
                                load_temp_b => false,
                                temp_a_source => "00",
                                temp_b_source => "00",
                                pc_inc => true,                  -- Increment PC to next instruction
                                pc_load_high => false,
                                pc_load_low => false,
                                stack_push => false,
                                stack_pop => false,
                                reg_write => false,
                                reg_read => false,
                                reg_target => "000",
                                reg_source => "00",
                                flags_update => false,
                                next_cycle_type => CYCLE_PCI
                            );
                        elsif decoded.is_mov and decoded.is_memory_source and not decoded.is_memory_dest then
                            -- MOV r,M (LrM): Load from memory [HL] to register (2-cycle)
                            -- Cycle 0 T3 sub_phase=1: Increment PC and advance to Cycle 1
                            -- (IR and temp_b already loaded in sub_phase=0)
                            -- Per 8008 datasheet: T4 and T5 are skipped in cycle 0
                            return (
                                next_state => T1,                -- Start cycle 1
                                advance_state => true,           -- sub_phase=1 always advances
                                new_cycle => true,               -- Advance to cycle 1
                                instruction_complete => false,   -- Not done yet
                                load_ir => false,                -- Already loaded in sub_phase=0
                                load_temp_a => false,
                                load_temp_b => false,            -- Already loaded in sub_phase=0
                                temp_a_source => "00",
                                temp_b_source => "00",
                                pc_inc => true,                  -- Increment PC to next instruction
                                pc_load_high => false,
                                pc_load_low => false,
                                stack_push => false,
                                stack_pop => false,
                                reg_write => false,
                                reg_read => false,
                                reg_target => "000",
                                reg_source => "00",
                                flags_update => false,
                                next_cycle_type => CYCLE_PCR     -- Next cycle is memory read from HL
                            );
                        elsif decoded.is_mov and decoded.is_memory_dest and not decoded.is_memory_source then
                            -- MOV M,r (LMr): Write register to memory [HL] (2-cycle)
                            -- Cycle 0 T3: Fetch instruction to IR and temp_b, advance to T4
                            -- Per datasheet: T4 will load SSS register into temp_b
                            return (
                                next_state => T4,                -- Continue to T4 (not T1!)
                                advance_state => (sub_phase = 1),
                                new_cycle => false,              -- Stay in cycle 0
                                instruction_complete => false,   -- Not done yet
                                load_ir => true,                 -- Load instruction register
                                load_temp_a => false,
                                load_temp_b => true,             -- Save instruction in temp_b
                                temp_a_source => "00",
                                temp_b_source => "01",           -- temp_b = data_bus (instruction)
                                pc_inc => true,                  -- Increment PC to next instruction
                                pc_load_high => false,
                                pc_load_low => false,
                                stack_push => false,
                                stack_pop => false,
                                reg_write => false,
                                reg_read => false,
                                reg_target => "000",
                                reg_source => "00",
                                flags_update => false,
                                next_cycle_type => CYCLE_PCI
                            );
                        else
                            -- Default: single-cycle instruction
                            return (
                                next_state => T1,
                                advance_state => true,
                                new_cycle => false,
                                instruction_complete => true,
                                load_ir => false,
                                load_temp_a => false,
                                load_temp_b => false,
                                temp_a_source => "00",
                                temp_b_source => "00",
                                pc_inc => false,
                                pc_load_high => false,
                                pc_load_low => false,
                                stack_push => false,
                                stack_pop => false,
                                reg_write => false,
                                reg_read => false,
                                reg_target => "000",
                                reg_source => "00",
                                flags_update => false,
                                next_cycle_type => CYCLE_PCI
                            );
                        end if;
                    end if;

                    -- AT SUB_PHASE=0: Decode from data_in and load IR
                    decoded := decode_instruction(data_in);

                    -- FOR T3: Only perform IR loading and setup at sub_phase=0
                    -- At sub_phase=1, just advance to the next_state determined at sub_phase=0
                    -- This is done by modifying advance_state in all T3 returns below

                    -- ========== HLT (HALT) ==========
                    -- HLT opcodes: 0000000x (0x00, 0x01) and 11111111 (0xFF)
                    if decoded.is_hlt then
                        -- HLT: Cycle ends at T3, instruction complete
                        -- Special case: Go to STOPPED (not T1/T1I)
                        return (
                            next_state => STOPPED,
                        advance_state => (sub_phase = 1),
                            new_cycle => false,
                            instruction_complete => true,   -- HLT is complete
                            load_ir => true,                -- Always load IR
                            load_temp_a => false,
                            load_temp_b => true,             -- Always load temp_b with instruction
                            temp_a_source => "00",
                            temp_b_source => "01",           -- temp_b = data_bus (instruction)
                            pc_inc => false,                 -- Don't increment PC for HLT
                            pc_load_high => false,
                            pc_load_low => false,
                            stack_push => false,
                            stack_pop => false,
                            reg_write => false,
                            reg_read => false,
                            reg_target => "000",
                            reg_source => "00",
                            flags_update => false,
                            next_cycle_type => CYCLE_PCI
                        );

                    -- ========== RST (RESTART) ==========
                    -- RST: 00 AAA 101
                    elsif decoded.is_rst then
                        -- RST: Cycle continues to T4 (needs T4 and T5)
                        return (
                            next_state => T4,               -- Continue to T4
                        advance_state => (sub_phase = 1),
                            new_cycle => false,
                            instruction_complete => false,   -- Not complete yet
                            load_ir => true,
                            load_temp_a => true,       -- Zero Reg.a
                            load_temp_b => true,       -- Load instruction to Reg.b
                            temp_a_source => "00",     -- temp_a = 0x00
                            temp_b_source => "01",     -- temp_b = data_bus (instruction)
                            pc_inc => false,
                            pc_load_high => false,
                            pc_load_low => false,
                            stack_push => true,        -- Push PC to stack
                            stack_pop => false,
                            reg_write => false,
                            reg_read => false,
                            reg_target => "000",
                            reg_source => "00",
                            flags_update => false,
                            next_cycle_type => CYCLE_PCI
                        );
                        
                    -- ========== MVI (Move Immediate) ==========
                    -- MVI: 00 DDD 110 + immediate byte
                    -- Includes MVI M (DDD=111, 0x3E) which writes to memory[HL]
                    -- 3-cycle for MVI M, 2-cycle for MVI r
                    elsif decoded.is_mvi then
                        -- Start multi-cycle instruction
                        -- NOTE: PC increment moved to cycle 1 T1 to avoid ROM race condition
                        report "T3: MVI handler, sub_phase=" & integer'image(sub_phase) & ", returning pc_inc=false";
                        return (
                            next_state => T1,                -- Will be overridden by interrupt logic
                        advance_state => (sub_phase = 1),
                            new_cycle => true,               -- Start new cycle for immediate fetch
                            instruction_complete => false,   -- Not complete yet (need 2 more cycles)
                            load_ir => true,                 -- Load instruction register
                            load_temp_a => false,
                            load_temp_b => true,             -- Save instruction in temp_b
                            temp_a_source => "00",
                            temp_b_source => "01",           -- temp_b = data_bus (instruction)
                            pc_inc => false,                 -- Don't increment yet (moved to cycle 1 T1)
                            pc_load_high => false,
                            pc_load_low => false,
                            stack_push => false,
                            stack_pop => false,
                            reg_write => false,
                            reg_read => false,
                            reg_target => "000",
                            reg_source => "00",
                            flags_update => false,
                            next_cycle_type => CYCLE_PCI     -- Next cycle fetches immediate data
                        );

                    -- ========== ALU Immediate (ADI, ACI, SUI, SBI, ANI, XRI, ORI, CPI) ==========
                    -- ALU IMM: 00 FFF 100 + immediate byte
                    -- 2-cycle instruction: fetch opcode, fetch immediate, execute ALU op
                    elsif decoded.is_alu_imm then
                        -- Start multi-cycle instruction
                        -- NOTE: PC increment moved to cycle 1 T1 to avoid ROM race condition
                        report "ALU IMM handler in Cycle 0 T3, sub_phase=" & integer'image(sub_phase) & ", returning new_cycle=true, advance_state=" & boolean'image(sub_phase = 1);
                        return (
                            next_state => T1,                -- Will be overridden by interrupt logic
                        advance_state => (sub_phase = 1),
                            new_cycle => true,               -- Start new cycle for immediate fetch
                            instruction_complete => false,   -- Not complete yet (need cycle 1)
                            load_ir => true,                 -- Load instruction register
                            load_temp_a => false,
                            load_temp_b => true,             -- Save instruction in temp_b
                            temp_a_source => "00",
                            temp_b_source => "01",           -- temp_b = data_bus (instruction)
                            pc_inc => false,                 -- Don't increment yet (moved to cycle 1 T1)
                            pc_load_high => false,
                            pc_load_low => false,
                            stack_push => false,
                            stack_pop => false,
                            reg_write => false,
                            reg_read => false,
                            reg_target => "000",
                            reg_source => "00",
                            flags_update => false,
                            next_cycle_type => CYCLE_PCI     -- Next cycle fetches immediate data
                        );

                    -- ========== JMP (Jump) ==========
                    -- JMP unconditional: 01 XXX 100
                    -- JMP conditional:   01 CCC 000
                    -- 3-cycle instruction (opcode + low addr + high addr)
                    -- Loads PC with 14-bit address from bytes 2-3
                    elsif decoded.is_jmp or decoded.is_jmp_conditional then
                        -- Start multi-cycle jump instruction
                        return (
                            next_state => T1,
                            advance_state => (sub_phase = 1),
                            new_cycle => true,               -- Start cycle 1 to fetch low address byte
                            instruction_complete => false,   -- Not complete (need 2 more cycles)
                            load_ir => true,                 -- Load instruction register
                            load_temp_a => false,
                            load_temp_b => true,             -- Save instruction to temp_b
                            temp_a_source => "00",
                            temp_b_source => "01",           -- temp_b = instruction
                            pc_inc => false,                 -- Don't increment yet
                            pc_load_high => false,
                            pc_load_low => false,
                            stack_push => false,
                            stack_pop => false,
                            reg_write => false,
                            reg_read => false,
                            reg_target => "000",
                            reg_source => "00",
                            flags_update => false,
                            next_cycle_type => CYCLE_PCI     -- Next cycle fetches low address byte
                        );

                    -- ========== CALL (Unconditional Call) ==========
                    -- CALL: 01 XXX 110
                    -- 3-cycle instruction (opcode + low addr + high addr)
                    -- Cycle 0: T1-T3 (fetch opcode, skip T4/T5)
                    -- Cycle 1: T1-T3 (fetch low addr, skip T4/T5)
                    -- Cycle 2: T1-T5 (fetch high addr, push PC, load new PC)
                    elsif decoded.is_call then
                        -- Cycle 0: Fetch instruction, skip T4/T5, advance to Cycle 1
                        return (
                            next_state => T1,
                            advance_state => (sub_phase = 1),
                            new_cycle => true,               -- Start cycle 1 to fetch low address byte
                            instruction_complete => false,   -- Not complete (need 2 more cycles)
                            load_ir => true,                 -- Load instruction register
                            load_temp_a => false,
                            load_temp_b => true,             -- Save instruction to temp_b
                            temp_a_source => "00",
                            temp_b_source => "01",           -- temp_b = instruction
                            pc_inc => false,                 -- Don't increment yet (happens in sub_phase=1)
                            pc_load_high => false,
                            pc_load_low => false,
                            stack_push => false,
                            stack_pop => false,
                            reg_write => false,
                            reg_read => false,
                            reg_target => "000",
                            reg_source => "00",
                            flags_update => false,
                            next_cycle_type => CYCLE_PCI     -- Next cycle fetches low address byte
                        );

                    -- ========== INP (Input from Port) ==========
                    -- INP: 01 00M MM1 (0x41, 0x43, 0x45, 0x47, 0x49, 0x4B, 0x4D, 0x4F)
                    -- 2-cycle instruction: fetch opcode, perform I/O read
                    -- MMM bits [3:1] specify which of 8 input ports (0-7)
                    elsif decoded.is_inp then
                        -- Start I/O read cycle
                        return (
                            next_state => T1,                -- Will be overridden by interrupt logic
                        advance_state => (sub_phase = 1),
                            new_cycle => true,               -- Start cycle 1 for I/O operation
                            instruction_complete => false,   -- Not complete yet (need cycle 1)
                            load_ir => true,                 -- Load instruction register
                            load_temp_a => false,
                            load_temp_b => true,             -- Save instruction in temp_b
                            temp_a_source => "00",
                            temp_b_source => "01",           -- temp_b = data_bus (instruction)
                            pc_inc => false,                 -- PC increment happens in sub_phase=1 handler
                            pc_load_high => false,
                            pc_load_low => false,
                            stack_push => false,
                            stack_pop => false,
                            reg_write => false,
                            reg_read => false,
                            reg_target => "000",
                            reg_source => "00",
                            flags_update => false,
                            next_cycle_type => CYCLE_PCC     -- Next cycle is I/O (PCC)
                        );

                    -- ========== OUT (Output to Port) ==========
                    -- OUT: 01 RRM MM0 (RR ≠ 00)
                    -- 2-cycle instruction: fetch opcode, perform I/O write
                    -- RRMMM bits specify which of 24 output ports (0-23)
                    -- Port address uses bits [5:1] with RR ≠ 00
                    elsif decoded.is_out then
                        -- Start I/O write cycle
                        report "OUT handler executing! Setting next_cycle_type=CYCLE_PCC";
                        return (
                            next_state => T1,                -- Will be overridden by interrupt logic
                        advance_state => (sub_phase = 1),
                            new_cycle => true,               -- Start cycle 1 for I/O operation
                            instruction_complete => false,   -- Not complete yet (need cycle 1)
                            load_ir => true,                 -- Load instruction register
                            load_temp_a => false,
                            load_temp_b => true,             -- Save instruction in temp_b (port address)
                            temp_a_source => "00",
                            temp_b_source => "01",           -- temp_b = data_bus (instruction)
                            pc_inc => false,                 -- PC increment happens in sub_phase=1 handler
                            pc_load_high => false,
                            pc_load_low => false,
                            stack_push => false,
                            stack_pop => false,
                            reg_write => false,
                            reg_read => false,
                            reg_target => "000",
                            reg_source => "00",
                            flags_update => false,
                            next_cycle_type => CYCLE_PCC     -- Next cycle is I/O (PCC)
                        );

                    -- ========== ALU M (ALU Memory Operations) ==========
                    -- ALU M: 10 PPP 111 (ADD M, ADC M, SUB M, SBB M, AND M, XOR M, OR M, CMP M)
                    -- 2-cycle instruction: fetch opcode, read memory from [HL]
                    elsif decoded.is_alu_memory then
                        -- Start memory read cycle from HL address
                        return (
                            next_state => T1,                -- Will be overridden by interrupt logic
                        advance_state => (sub_phase = 1),
                            new_cycle => true,               -- Start cycle 1 for memory read
                            instruction_complete => false,   -- Not complete yet (need cycle 1)
                            load_ir => true,                 -- Load instruction register
                            load_temp_a => false,
                            load_temp_b => true,             -- Save instruction in temp_b
                            temp_a_source => "00",
                            temp_b_source => "01",           -- temp_b = data_bus (instruction)
                            pc_inc => true,                  -- Increment PC to next instruction
                            pc_load_high => false,
                            pc_load_low => false,
                            stack_push => false,
                            stack_pop => false,
                            reg_write => false,
                            reg_read => false,
                            reg_target => "000",
                            reg_source => "00",
                            flags_update => false,
                            next_cycle_type => CYCLE_PCR     -- Next cycle is memory read from HL
                        );

                    -- ========== LrM (MOV r,M - Load from Memory) ==========
                    -- LrM: 11 DDD 111 (load from memory [HL] to register)
                    -- 2-cycle instruction: fetch opcode, read memory from [HL]
                    elsif decoded.is_mov and decoded.is_memory_source and not decoded.is_memory_dest then
                        -- Start memory read cycle from HL address
                        return (
                            next_state => T1,                -- Start cycle 1
                        advance_state => (sub_phase = 1),
                            new_cycle => true,               -- Start cycle 1 for memory read
                            instruction_complete => false,   -- Not complete yet (need cycle 1)
                            load_ir => true,                 -- Load instruction register
                            load_temp_a => false,
                            load_temp_b => true,             -- Save instruction in temp_b
                            temp_a_source => "00",
                            temp_b_source => "01",           -- temp_b = data_bus (instruction)
                            pc_inc => false,                 -- PC does NOT increment for LrM
                            pc_load_high => false,
                            pc_load_low => false,
                            stack_push => false,
                            stack_pop => false,
                            reg_write => false,
                            reg_read => false,
                            reg_target => "000",
                            reg_source => "00",
                            flags_update => false,
                            next_cycle_type => CYCLE_PCR     -- Next cycle is memory read from HL
                        );

                    -- ========== MOV r1, r2 (Register-to-Register Move) ==========
                    -- MOV r1, r2: 11 DDD SSS (where DDD ≠ 111 and SSS ≠ 111)
                    -- 5-state instruction (T1-T5) in single machine cycle
                    -- Excludes MOV M,r and MOV r,M (memory variants)
                    elsif decoded.is_mov and
                          not decoded.is_memory_source and
                          not decoded.is_memory_dest then
                        -- Start 5-state register transfer
                        return (
                            next_state => T4,                -- Continue to T4
                        advance_state => (sub_phase = 1),
                            new_cycle => false,              -- Same machine cycle
                            instruction_complete => false,   -- Not done yet (need T4, T5)
                            load_ir => true,                 -- Load instruction register
                            load_temp_a => false,
                            load_temp_b => true,             -- Save instruction in temp_b
                            temp_a_source => "00",
                            temp_b_source => "01",           -- temp_b = data_bus (instruction)
                            pc_inc => true,                  -- Increment PC after fetch
                            pc_load_high => false,
                            pc_load_low => false,
                            stack_push => false,
                            stack_pop => false,
                            reg_write => false,              -- Don't write yet
                            reg_read => false,               -- Don't read yet
                            reg_target => "000",
                            reg_source => "00",
                            flags_update => false,
                            next_cycle_type => CYCLE_PCI
                        );

                    -- ========== ADD MORE INSTRUCTIONS HERE ==========
                    -- Template for 5-state instruction (continues to T4):
                    -- elsif (data_in matches pattern) then
                    --     return (
                    --         next_state => T4,
                    --         advance_state => (sub_phase = 1),
                    --         instruction_complete => false,  -- Not done yet
                    --         ... other control signals ...
                    --     );

                    else
                        -- DEFAULT: Unknown instructions treated as NOP
                        -- Cycle ends at T3, instruction complete
                        -- For single-byte instructions, PC increments after fetch
                        return (
                            next_state => T1,                -- Will be overridden by interrupt logic
                        advance_state => (sub_phase = 1),
                            new_cycle => false,
                            instruction_complete => true,    -- Single cycle instruction
                            load_ir => true,                 -- Always load IR
                            load_temp_a => false,
                            load_temp_b => true,             -- Always load temp_b with instruction
                            temp_a_source => "00",
                            temp_b_source => "01",           -- temp_b = data_bus (instruction)
                            pc_inc => true,                  -- Increment PC after fetch
                            pc_load_high => false,
                            pc_load_low => false,
                            stack_push => false,
                            stack_pop => false,
                            reg_write => false,
                            reg_read => false,
                            reg_target => "000",
                            reg_source => "00",
                            flags_update => false,
                            next_cycle_type => CYCLE_PCI
                        );
                    end if;

                when T4 =>
                    -- T4: Instruction-specific behavior
                    -- Only reached if instruction needs more than 3 states
                    
                    -- ========== RST (RESTART) ==========
                    if (instr(7 downto 6) = "00" and instr(2 downto 0) = "101") then
                        if sub_phase = 0 then
                            -- RST T4 φ₁₁/φ₂₁: Setup phase
                            return (
                                next_state => T5,
                                advance_state => false,          -- Stay in T4 for second sub-phase
                                new_cycle => false,
                                instruction_complete => false,
                                load_ir => false,
                                load_temp_a => false,
                                load_temp_b => false,
                                temp_a_source => "00",
                                temp_b_source => "00",
                                pc_inc => false,
                                pc_load_high => false,
                                pc_load_low => false,
                                stack_push => false,
                                stack_pop => false,
                                reg_write => false,
                                reg_read => false,
                                reg_target => "000",
                                reg_source => "00",
                                flags_update => false,
                                next_cycle_type => CYCLE_PCI
                            );
                        else  -- sub_phase = 1
                            -- RST T4 φ₁₂/φ₂₂: Load PC high
                            return (
                                next_state => T5,
                                advance_state => true,           -- Advance to T5
                                new_cycle => false,
                                instruction_complete => false,
                                load_ir => false,
                                load_temp_a => false,
                                load_temp_b => false,
                                temp_a_source => "00",
                                temp_b_source => "00",
                                pc_inc => false,
                                pc_load_high => true,            -- PC(13:8) = temp_a(5:0) = 0x00
                                pc_load_low => false,
                                stack_push => false,
                                stack_pop => false,
                                reg_write => false,
                                reg_read => false,
                                reg_target => "000",
                                reg_source => "00",
                                flags_update => false,
                                next_cycle_type => CYCLE_PCI
                            );
                        end if;

                    -- ========== MOV r1, r2 (Register-to-Register Move) ==========
                    -- Decode instruction to get SSS and DDD fields
                    -- T4: Read source register (SSS) and load into temp_b
                    --   - φ₁/φ₂₁: Read source register to internal_data_bus
                    --   - φ₁₂: Load temp_b from internal_data_bus
                    elsif (instr(7 downto 6) = "11" and
                           instr(5 downto 3) /= "111" and
                           instr(2 downto 0) /= "111") then

                        if sub_phase = 0 then
                            -- T4 φ₁₁/φ₂₁: Read source register to internal_data_bus
                            -- Register read happens at T4 φ₂₁ (phi2_sub=0)
                            return (
                                next_state => T5,                -- Target state (will stay in T4 for now)
                                advance_state => false,          -- Stay in T4 for second sub-phase
                                new_cycle => false,
                                instruction_complete => false,
                                load_ir => false,
                                load_temp_a => false,
                                load_temp_b => false,
                                temp_a_source => "00",
                                temp_b_source => "00",
                                pc_inc => false,
                                pc_load_high => false,
                                pc_load_low => false,
                                stack_push => false,
                                stack_pop => false,
                                reg_write => false,
                                reg_read => true,                -- Read source register
                                reg_target => instr(2 downto 0), -- SSS field = source register
                                reg_source => "00",
                                flags_update => false,
                                next_cycle_type => CYCLE_PCI
                            );
                        else  -- sub_phase = 1
                            -- T4 φ₁₂/φ₂₂: Load temp_b from internal_data_bus
                            -- temp_b loads at φ₁₂, capturing value from register read
                            return (
                                next_state => T5,                -- Advance to T5
                                advance_state => true,           -- Advance to T5 after this sub-phase
                                new_cycle => false,
                                instruction_complete => false,
                                load_ir => false,
                                load_temp_a => false,
                                load_temp_b => true,             -- Load temp_b from internal_data_bus
                                temp_a_source => "00",
                                temp_b_source => "10",           -- temp_b = internal_data_bus
                                pc_inc => false,
                                pc_load_high => false,
                                pc_load_low => false,
                                stack_push => false,
                                stack_pop => false,
                                reg_write => false,
                                reg_read => false,
                                reg_target => "000",
                                reg_source => "00",
                                flags_update => false,
                                next_cycle_type => CYCLE_PCI
                            );
                        end if;

                    -- ========== LMr (MOV M,r) - Cycle 0 T4 ==========
                    -- MOV M,r: Store register to memory [HL]
                    -- Opcode: 11 111 SSS (SSS = source register 000-110)
                    -- Cycle 0 T4: Read source register (SSS) into temp_b
                    --   - φ₁₁/φ₂₁: Read source register to internal_data_bus
                    --   - φ₁₂: Load temp_b from internal_data_bus
                    elsif cycle = 0 and
                          instr(7 downto 6) = "11" and
                          instr(5 downto 3) = "111" then

                        if sub_phase = 0 then
                            -- LMr Cycle 0 T4 φ₁₁/φ₂₁: Read source register to internal_data_bus
                            return (
                                next_state => T5,
                                advance_state => false,          -- Stay in T4 for second sub-phase
                                new_cycle => false,
                                instruction_complete => false,
                                load_ir => false,
                                load_temp_a => false,
                                load_temp_b => false,            -- Don't load yet
                                temp_a_source => "00",
                                temp_b_source => "00",
                                pc_inc => false,
                                pc_load_high => false,
                                pc_load_low => false,
                                stack_push => false,
                                stack_pop => false,
                                reg_write => false,
                                reg_read => true,                -- Read source register (SSS)
                                reg_target => instr(2 downto 0), -- SSS = source register
                                reg_source => "00",
                                flags_update => false,
                                next_cycle_type => CYCLE_PCI
                            );
                        else  -- sub_phase = 1
                            -- LMr Cycle 0 T4 φ₁₂/φ₂₂: Load temp_b from internal_data_bus
                            return (
                                next_state => T5,
                                advance_state => true,           -- Advance to T5
                                new_cycle => false,
                                instruction_complete => false,
                                load_ir => false,
                                load_temp_a => false,
                                load_temp_b => true,             -- Load register value into temp_b
                                temp_a_source => "00",
                                temp_b_source => "10",           -- temp_b = internal_data_bus
                                pc_inc => false,
                                pc_load_high => false,
                                pc_load_low => false,
                                stack_push => false,
                                stack_pop => false,
                                reg_write => false,
                                reg_read => false,
                                reg_target => "000",
                                reg_source => "00",
                                flags_update => false,
                                next_cycle_type => CYCLE_PCI
                            );
                        end if;

                    -- ========== ALU Register (ADD r, ADC r, SUB r, etc.) ==========
                    -- Decode instruction: 10 PPP SSS (PPP = operation, SSS = source register ≠ 111)
                    -- T4: Read source register (SSS) and load into temp_b
                    --   - φ₁/φ₂₁: Read source register to internal_data_bus
                    --   - φ₁₂: Load temp_b from internal_data_bus
                    elsif (instr(7 downto 6) = "10" and
                           instr(2 downto 0) /= "111") then

                        if sub_phase = 0 then
                            -- T4 φ₁₁/φ₂₁: Read source register to internal_data_bus
                            -- Register read happens at T4 φ₂₁ (phi2_sub=0)
                            return (
                                next_state => T5,                -- Target state (will stay in T4 for now)
                                advance_state => false,          -- Stay in T4 for second sub-phase
                                new_cycle => false,
                                instruction_complete => false,
                                load_ir => false,
                                load_temp_a => false,
                                load_temp_b => false,
                                temp_a_source => "00",
                                temp_b_source => "00",
                                pc_inc => false,
                                pc_load_high => false,
                                pc_load_low => false,
                                stack_push => false,
                                stack_pop => false,
                                reg_write => false,
                                reg_read => true,                -- Read source register
                                reg_target => instr(2 downto 0), -- SSS field = source register
                                reg_source => "00",
                                flags_update => false,
                                next_cycle_type => CYCLE_PCI
                            );
                        else  -- sub_phase = 1
                            -- T4 φ₁₂/φ₂₂: Load temp_b from internal_data_bus
                            -- temp_b loads at φ₁₂, capturing value from register read
                            return (
                                next_state => T5,                -- Advance to T5
                                advance_state => true,           -- Advance to T5 after this sub-phase
                                new_cycle => false,
                                instruction_complete => false,
                                load_ir => false,
                                load_temp_a => false,
                                load_temp_b => true,             -- Load temp_b from internal_data_bus
                                temp_a_source => "00",
                                temp_b_source => "10",           -- temp_b = internal_data_bus
                                pc_inc => false,
                                pc_load_high => false,
                                pc_load_low => false,
                                stack_push => false,
                                stack_pop => false,
                                reg_write => false,
                                reg_read => false,
                                reg_target => "000",
                                reg_source => "00",
                                flags_update => false,
                                next_cycle_type => CYCLE_PCI
                            );
                        end if;

                    -- ========== ADD MORE INSTRUCTIONS HERE ==========
                    -- Template for instruction ending at T4:
                    -- elsif (instr matches pattern) then
                    --     return (
                    --         next_state => T1,  -- Will be overridden by interrupt logic
                    --         advance_state => true,
                    --         instruction_complete => true/false,
                    --         ... other control signals ...
                    --     );

                    -- Template for instruction continuing to T5:
                    -- elsif (instr matches pattern) then
                    --     return (
                    --         next_state => T5,
                    --         advance_state => true,
                    --         instruction_complete => false,
                    --         ... other control signals ...
                    --     );

                    -- ========== INR/DCR (Increment/Decrement Register) ==========
                    -- Opcode: 00 DDD 000 (INR) or 00 DDD 001 (DCR), where DDD ≠ 000
                    -- T4: IDLE state (4.4μs wait)
                    elsif (instr(7 downto 6) = "00" and
                           (instr(2 downto 0) = "000" or instr(2 downto 0) = "001") and
                           instr(5 downto 3) /= "000") then

                        if sub_phase = 0 then
                            -- INR/DCR T4 φ₁₁/φ₂₁: IDLE phase (no operation)
                            return (
                                next_state => T5,
                                advance_state => false,          -- Stay in T4 for second sub-phase
                                new_cycle => false,
                                instruction_complete => false,
                                load_ir => false,
                                load_temp_a => false,
                                load_temp_b => false,
                                temp_a_source => "00",
                                temp_b_source => "00",
                                pc_inc => false,
                                pc_load_high => false,
                                pc_load_low => false,
                                stack_push => false,
                                stack_pop => false,
                                reg_write => false,
                                reg_read => false,
                                reg_target => "000",
                                reg_source => "00",
                                flags_update => false,
                                next_cycle_type => CYCLE_PCI
                            );
                        else  -- sub_phase = 1
                            -- INR/DCR T4 φ₁₂/φ₂₂: Continue IDLE, advance to T5
                            return (
                                next_state => T5,
                                advance_state => true,           -- Advance to T5
                                new_cycle => false,
                                instruction_complete => false,
                                load_ir => false,
                                load_temp_a => false,
                                load_temp_b => false,
                                temp_a_source => "00",
                                temp_b_source => "00",
                                pc_inc => false,
                                pc_load_high => false,
                                pc_load_low => false,
                                stack_push => false,
                                stack_pop => false,
                                reg_write => false,
                                reg_read => false,
                                reg_target => "000",
                                reg_source => "00",
                                flags_update => false,
                                next_cycle_type => CYCLE_PCI
                            );
                        end if;

                    else
                        -- Should not reach here - only instructions that need T4 should get here
                        return DEFAULT_UCODE;
                    end if;
                    
                when T5 =>
                    -- T5: Final state for 5-state instructions
                    -- Cycle ALWAYS ends at T5

                    -- Decode instruction to eliminate hardcoded checks
                    decoded := decode_instruction(instr);

                    -- ========== LMr (MOV M,r) - Cycle 0 T5 ==========
                    -- Per datasheet: Cycle 0 T5 is skipped, advance to Cycle 1
                    if cycle = 0 and
                       instr(7 downto 6) = "11" and
                       instr(5 downto 3) = "111" then
                        -- T5: Skip (advance to Cycle 1)
                        return (
                            next_state => T1,                -- Start Cycle 1
                            advance_state => (sub_phase = 1),
                            new_cycle => true,               -- Advance to Cycle 1
                            instruction_complete => false,   -- Not done yet
                            load_ir => false,
                            load_temp_a => false,
                            load_temp_b => false,
                            temp_a_source => "00",
                            temp_b_source => "00",
                            pc_inc => false,
                            pc_load_high => false,
                            pc_load_low => false,
                            stack_push => false,
                            stack_pop => false,
                            reg_write => false,
                            reg_read => false,
                            reg_target => "000",
                            reg_source => "00",
                            flags_update => false,
                            next_cycle_type => CYCLE_PCW     -- Next cycle is memory write
                        );

                    -- ========== RST (RESTART) ==========
                    elsif decoded.is_rst then
                        if sub_phase = 0 then
                            -- RST T5 φ₁₁/φ₂₁: Setup phase
                            return (
                                next_state => T1,
                                advance_state => false,          -- Stay in T5 for second sub-phase
                                new_cycle => false,
                                instruction_complete => false,
                                load_ir => false,
                                load_temp_a => false,
                                load_temp_b => false,
                                temp_a_source => "00",
                                temp_b_source => "00",
                                pc_inc => false,
                                pc_load_high => false,
                                pc_load_low => false,
                                stack_push => false,
                                stack_pop => false,
                                reg_write => false,
                                reg_read => false,
                                reg_target => "000",
                                reg_source => "00",
                                flags_update => false,
                                next_cycle_type => CYCLE_PCI
                            );
                        else  -- sub_phase = 1
                            -- RST T5 φ₁₂/φ₂₂: Load PC low, instruction complete
                            return (
                                next_state => T1,
                                advance_state => true,           -- Instruction complete
                                new_cycle => false,
                                instruction_complete => true,
                                load_ir => false,
                                load_temp_a => false,
                                load_temp_b => false,
                                temp_a_source => "00",
                                temp_b_source => "00",
                                pc_inc => false,
                                pc_load_high => false,
                                pc_load_low => true,             -- PC(7:0) = RST vector (AAA << 3)
                                stack_push => false,
                                stack_pop => false,
                                reg_write => false,
                                reg_read => false,
                                reg_target => "000",
                                reg_source => "00",
                                flags_update => false,
                                next_cycle_type => CYCLE_PCI
                            );
                        end if;

                    -- ========== MOV r1, r2 (Register-to-Register Move) ==========
                    -- T5: Write temp_b (loaded at T4) to destination register (DDD)
                    --   - φ₁₁: Setup (temp_b already loaded from T4)
                    --   - φ₁₂: Trigger register write (actual write at φ₂₂)
                    elsif decoded.is_mov and
                          not decoded.is_memory_source and
                          not decoded.is_memory_dest then

                        if sub_phase = 0 then
                            -- T5 φ₁₁/φ₂₁: Setup phase (temp_b already contains source value from T4)
                            -- No operations needed, just stay in T5 for second sub-phase
                            return (
                                next_state => T1,                -- Target state after completion
                                advance_state => false,          -- Stay in T5 for second sub-phase
                                new_cycle => false,
                                instruction_complete => false,   -- Not complete yet
                                load_ir => false,
                                load_temp_a => false,
                                load_temp_b => false,
                                temp_a_source => "00",
                                temp_b_source => "00",
                                pc_inc => false,
                                pc_load_high => false,
                                pc_load_low => false,
                                stack_push => false,
                                stack_pop => false,
                                reg_write => false,
                                reg_read => false,
                                reg_target => "000",
                                reg_source => "00",
                                flags_update => false,
                                next_cycle_type => CYCLE_PCI
                            );
                        else  -- sub_phase = 1
                            -- T5 φ₁₂/φ₂₂: Write temp_b to destination register
                            -- reg_write triggers write at T5 φ₂₂ (phi2_sub=1)
                            return (
                                next_state => T1,                -- Will be overridden by interrupt logic
                                advance_state => true,           -- Instruction complete, advance
                                new_cycle => false,
                                instruction_complete => true,    -- MOV is complete
                                load_ir => false,
                                load_temp_a => false,
                                load_temp_b => false,
                                temp_a_source => "00",
                                temp_b_source => "00",
                                pc_inc => false,
                                pc_load_high => false,
                                pc_load_low => false,
                                stack_push => false,
                                stack_pop => false,
                                reg_write => true,               -- Write to destination register
                                reg_read => false,
                                reg_target => decoded.ddd_field, -- DDD field = destination register
                                reg_source => "11",              -- reg_source = temp_b
                                flags_update => false,
                                next_cycle_type => CYCLE_PCI
                            );
                        end if;

                    -- ========== ALU Register (ADD r, ADC r, SUB r, etc.) ==========
                    -- T5: Perform ALU operation and update flags
                    --   - φ₁₁: Setup (temp_b contains source value from T4)
                    --   - φ₁₂: Write ALU result to accumulator and update flags
                    --   - Note: CMP (PPP=111) only updates flags, doesn't write to accumulator
                    elsif decoded.is_alu_register then

                        -- Check if this is CMP (PPP = 111)
                        if decoded.fff_field = "111" then
                            -- CMP r: Update flags only, don't write to accumulator
                            if sub_phase = 0 then
                                -- CMP T5 φ₁₁/φ₂₁: Setup phase
                                return (
                                    next_state => T1,
                                    advance_state => false,
                                    new_cycle => false,
                                    instruction_complete => false,
                                    load_ir => false,
                                    load_temp_a => false,
                                    load_temp_b => false,
                                    temp_a_source => "00",
                                    temp_b_source => "00",
                                    pc_inc => false,
                                    pc_load_high => false,
                                    pc_load_low => false,
                                    stack_push => false,
                                    stack_pop => false,
                                    reg_write => false,              -- No accumulator write for CMP
                                    reg_read => false,
                                    reg_target => "000",
                                    reg_source => "10",              -- ALU result (for flags only)
                                    flags_update => true,            -- Update flags from ALU result
                                    next_cycle_type => CYCLE_PCI
                                );
                            else  -- sub_phase = 1
                                -- CMP T5 φ₁₂/φ₂₂: Complete flag update
                                return (
                                    next_state => T1,
                                    advance_state => true,
                                    new_cycle => false,
                                    instruction_complete => true,
                                    load_ir => false,
                                    load_temp_a => false,
                                    load_temp_b => false,
                                    temp_a_source => "00",
                                    temp_b_source => "00",
                                    pc_inc => false,
                                    pc_load_high => false,
                                    pc_load_low => false,
                                    stack_push => false,
                                    stack_pop => false,
                                    reg_write => false,              -- No accumulator write for CMP
                                    reg_read => false,
                                    reg_target => "000",
                                    reg_source => "10",              -- ALU result (for flags only)
                                    flags_update => false,           -- Flags already updated in sub_phase=0
                                    next_cycle_type => CYCLE_PCI
                                );
                            end if;
                        else
                            -- Normal ALU register: Write result to accumulator
                            if sub_phase = 0 then
                                -- T5 φ₁₁/φ₂₁: Setup phase (temp_b already contains source value from T4)
                                -- No operations needed, just stay in T5 for second sub-phase
                                return (
                                    next_state => T1,                -- Target state after completion
                                    advance_state => false,          -- Stay in T5 for second sub-phase
                                    new_cycle => false,
                                    instruction_complete => false,   -- Not complete yet
                                    load_ir => false,
                                    load_temp_a => false,
                                    load_temp_b => false,
                                    temp_a_source => "00",
                                    temp_b_source => "00",
                                    pc_inc => false,
                                    pc_load_high => false,
                                    pc_load_low => false,
                                    stack_push => false,
                                    stack_pop => false,
                                    reg_write => false,
                                    reg_read => false,
                                    reg_target => "000",
                                    reg_source => "00",
                                    flags_update => false,
                                    next_cycle_type => CYCLE_PCI
                                );
                            else  -- sub_phase = 1
                                -- T5 φ₁₂/φ₂₂: Write ALU result to accumulator and update flags
                                -- reg_write triggers write at T5 φ₂₂ (phi2_sub=1)
                                -- flags_update triggers flag update at T5 φ₂₂
                                return (
                                    next_state => T1,                -- Will be overridden by interrupt logic
                                    advance_state => true,           -- Instruction complete, advance
                                    new_cycle => false,
                                    instruction_complete => true,    -- ALU operation is complete
                                    load_ir => false,
                                    load_temp_a => false,
                                    load_temp_b => false,
                                    temp_a_source => "00",
                                    temp_b_source => "00",
                                    pc_inc => false,
                                    pc_load_high => false,
                                    pc_load_low => false,
                                    stack_push => false,
                                    stack_pop => false,
                                    reg_write => true,               -- Write ALU result to accumulator
                                    reg_read => false,
                                    reg_target => "000",             -- Target = register A (accumulator)
                                    reg_source => "10",              -- reg_source = ALU result
                                    flags_update => true,            -- Update flags from ALU result
                                    next_cycle_type => CYCLE_PCI
                                );
                            end if;
                        end if;

                    -- ========== INR/DCR (Increment/Decrement Register) ==========
                    -- T5: Perform increment/decrement and update flags (except carry)
                    --   - φ₁₁: Read source register
                    --   - φ₁₂: Write incremented/decremented value and update flags
                    elsif decoded.is_inr or decoded.is_dcr then

                        if sub_phase = 0 then
                            -- INR/DCR T5 φ₁₁/φ₂₁: Read target register
                            return (
                                next_state => T1,                -- Target state after completion
                                advance_state => false,          -- Stay in T5 for second sub-phase
                                new_cycle => false,
                                instruction_complete => false,   -- Not complete yet
                                load_ir => false,
                                load_temp_a => false,
                                load_temp_b => false,
                                temp_a_source => "00",
                                temp_b_source => "00",
                                pc_inc => false,
                                pc_load_high => false,
                                pc_load_low => false,
                                stack_push => false,
                                stack_pop => false,
                                reg_write => false,
                                reg_read => true,                -- Read target register
                                reg_target => instr(5 downto 3), -- DDD field
                                reg_source => "00",
                                flags_update => false,
                                next_cycle_type => CYCLE_PCI
                            );
                        else  -- sub_phase = 1
                            -- INR/DCR T5 φ₁₂/φ₂₂: Write result and update flags
                            -- For INR: result = reg + 1
                            -- For DCR: result = reg - 1
                            -- Flags updated: Sign, Zero, Parity (NOT Carry)
                            return (
                                next_state => T1,                -- Will be overridden by interrupt logic
                                advance_state => true,           -- Instruction complete, advance
                                new_cycle => false,
                                instruction_complete => true,    -- INR/DCR is complete
                                load_ir => false,
                                load_temp_a => false,
                                load_temp_b => false,
                                temp_a_source => "00",
                                temp_b_source => "00",
                                pc_inc => false,
                                pc_load_high => false,
                                pc_load_low => false,
                                stack_push => false,
                                stack_pop => false,
                                reg_write => true,               -- Write result back to target register
                                reg_read => false,
                                reg_target => instr(5 downto 3), -- DDD field
                                reg_source => "10",              -- reg_source = ALU result (inc/dec uses ALU)
                                flags_update => true,            -- Update flags (S, Z, P - not C)
                                next_cycle_type => CYCLE_PCI
                            );
                        end if;

                    -- ========== ROTATE (RLC, RRC, RAL, RAR) ==========
                    -- T5: Perform rotate and update carry flag
                    --   - φ₁₁: Read accumulator
                    --   - φ₁₂: Write rotated value and update carry
                    elsif decoded.is_rotate then

                        if sub_phase = 0 then
                            -- ROTATE T5 φ₁₁/φ₂₁: Read accumulator
                            return (
                                next_state => T1,                -- Target state after completion
                                advance_state => false,          -- Stay in T5 for second sub-phase
                                new_cycle => false,
                                instruction_complete => false,   -- Not complete yet
                                load_ir => false,
                                load_temp_a => false,
                                load_temp_b => false,
                                temp_a_source => "00",
                                temp_b_source => "00",
                                pc_inc => false,
                                pc_load_high => false,
                                pc_load_low => false,
                                stack_push => false,
                                stack_pop => false,
                                reg_write => false,
                                reg_read => true,                -- Read accumulator
                                reg_target => "000",             -- Register A (accumulator)
                                reg_source => "00",
                                flags_update => false,
                                next_cycle_type => CYCLE_PCI
                            );
                        else  -- sub_phase = 1
                            -- ROTATE T5 φ₁₂/φ₂₂: Write rotated value and update carry
                            -- Rotation is performed by the ALU based on FFF field:
                            --   FFF=000: RLC (rotate left circular)
                            --   FFF=001: RRC (rotate right circular)
                            --   FFF=010: RAL (rotate left through carry)
                            --   FFF=011: RAR (rotate right through carry)
                            return (
                                next_state => T1,                -- Will be overridden by interrupt logic
                                advance_state => true,           -- Instruction complete, advance
                                new_cycle => false,
                                instruction_complete => true,    -- Rotate is complete
                                load_ir => false,
                                load_temp_a => false,
                                load_temp_b => false,
                                temp_a_source => "00",
                                temp_b_source => "00",
                                pc_inc => false,
                                pc_load_high => false,
                                pc_load_low => false,
                                stack_push => false,
                                stack_pop => false,
                                reg_write => true,               -- Write result back to accumulator
                                reg_read => false,
                                reg_target => "000",             -- Register A (accumulator)
                                reg_source => "10",              -- reg_source = ALU result (rotate uses ALU)
                                flags_update => true,            -- Update carry flag only
                                next_cycle_type => CYCLE_PCI
                            );
                        end if;

                    -- ========== ADD MORE INSTRUCTIONS HERE ==========
                    -- Template for any instruction reaching T5:
                    -- elsif (instr matches pattern) then
                    --     return (
                    --         next_state => T1,  -- Will be overridden by interrupt logic
                    --         advance_state => true,
                    --         instruction_complete => true/false,  -- Usually true at T5
                    --         ... other control signals ...
                    --     );

                    else
                        -- Should not reach here - only instructions that need T5 should get here
                        return DEFAULT_UCODE;
                    end if;

                when others =>
                    return DEFAULT_UCODE;
            end case;
            
        -- ===========================================
        -- CYCLE 1: Second machine cycle
        -- ===========================================
        elsif cycle = 1 then
            -- Instruction-specific behavior for cycle 1
            case state is
                when T1 =>
                    -- Cycle 1 T1: Address low byte OUT
                    -- Decode instruction to determine address source
                    decoded := decode_instruction(instr);

                    if decoded.is_mvi then
                        if sub_phase = 0 then
                            -- MVI Cycle 1 T1 φ₁₁/φ₂₁: Setup
                            return (
                                next_state => T2,
                                advance_state => false,          -- Stay in T1 for second sub-phase
                                new_cycle => false,
                                instruction_complete => false,
                                load_ir => false,
                                load_temp_a => false,
                                load_temp_b => false,
                                temp_a_source => "00",
                                temp_b_source => "00",
                                pc_inc => false,
                                pc_load_high => false,
                                pc_load_low => false,
                                stack_push => false,
                                stack_pop => false,
                                reg_write => false,
                                reg_read => false,
                                reg_target => "000",
                                reg_source => "00",
                                flags_update => false,
                                next_cycle_type => CYCLE_PCI
                            );
                        else  -- sub_phase = 1
                            -- MVI Cycle 1 T1 φ₁₂/φ₂₂: Increment PC to immediate byte
                            return (
                                next_state => T2,
                                advance_state => true,           -- Advance to T2
                                new_cycle => false,
                                instruction_complete => false,
                                load_ir => false,
                                load_temp_a => false,
                                load_temp_b => false,
                                temp_a_source => "00",
                                temp_b_source => "00",
                                pc_inc => true,                  -- Increment PC to immediate byte address
                                pc_load_high => false,
                                pc_load_low => false,
                                stack_push => false,
                                stack_pop => false,
                                reg_write => false,
                                reg_read => false,
                                reg_target => "000",
                                reg_source => "00",
                                flags_update => false,
                                next_cycle_type => CYCLE_PCI     -- Fetching immediate from PC
                            );
                        end if;
                    elsif decoded.is_alu_imm then
                        -- ALU IMM: Cycle 1 T1 - Increment PC to immediate byte
                        if sub_phase = 0 then
                            -- ALU IMM Cycle 1 T1 φ₁₁/φ₂₁: Setup
                            return (
                                next_state => T2,
                                advance_state => false,          -- Stay in T1 for second sub-phase
                                new_cycle => false,
                                instruction_complete => false,
                                load_ir => false,
                                load_temp_a => false,
                                load_temp_b => false,
                                temp_a_source => "00",
                                temp_b_source => "00",
                                pc_inc => false,
                                pc_load_high => false,
                                pc_load_low => false,
                                stack_push => false,
                                stack_pop => false,
                                reg_write => false,
                                reg_read => false,
                                reg_target => "000",
                                reg_source => "00",
                                flags_update => false,
                                next_cycle_type => CYCLE_PCI
                            );
                        else  -- sub_phase = 1
                            -- ALU IMM Cycle 1 T1 φ₁₂/φ₂₂: Increment PC to immediate byte
                            return (
                                next_state => T2,
                                advance_state => true,           -- Advance to T2
                                new_cycle => false,
                                instruction_complete => false,
                                load_ir => false,
                                load_temp_a => false,
                                load_temp_b => false,
                                temp_a_source => "00",
                                temp_b_source => "00",
                                pc_inc => true,                  -- Increment PC from opcode to immediate
                                pc_load_high => false,
                                pc_load_low => false,
                                stack_push => false,
                                stack_pop => false,
                                reg_write => false,
                                reg_read => false,
                                reg_target => "000",
                                reg_source => "00",
                                flags_update => false,
                                next_cycle_type => CYCLE_PCI     -- Fetching immediate from PC
                            );
                        end if;
                    elsif decoded.is_alu_memory then
                        if sub_phase = 0 then
                            -- ALU M Cycle 1 T1 φ₁₁/φ₂₁: Setup
                            return (
                                next_state => T2,
                                advance_state => false,          -- Stay in T1 for second sub-phase
                                new_cycle => false,
                                instruction_complete => false,
                                load_ir => false,
                                load_temp_a => false,
                                load_temp_b => false,
                                temp_a_source => "00",
                                temp_b_source => "00",
                                pc_inc => false,
                                pc_load_high => false,
                                pc_load_low => false,
                                stack_push => false,
                                stack_pop => false,
                                reg_write => false,
                                reg_read => false,
                                reg_target => "000",
                                reg_source => "00",
                                flags_update => false,
                                next_cycle_type => CYCLE_PCR
                            );
                        else  -- sub_phase = 1
                            -- ALU M Cycle 1 T1 φ₁₂/φ₂₂: Advance
                            return (
                                next_state => T2,
                                advance_state => true,
                                new_cycle => false,
                                instruction_complete => false,
                                load_ir => false,
                                load_temp_a => false,
                                load_temp_b => false,
                                temp_a_source => "00",
                                temp_b_source => "00",
                                pc_inc => false,
                                pc_load_high => false,
                                pc_load_low => false,
                                stack_push => false,
                                stack_pop => false,
                                reg_write => false,
                                reg_read => false,
                                reg_target => "000",
                                reg_source => "00",
                                flags_update => false,
                                next_cycle_type => CYCLE_PCR     -- Memory read from HL
                            );
                        end if;
                    elsif decoded.is_mov and decoded.is_memory_source then
                        -- LrM (MOV r,M): Cycle 1 T1 - Output L register (address low)
                        if sub_phase = 0 then
                            -- LrM Cycle 1 T1 φ₁₁/φ₂₁: Setup
                            return (
                                next_state => T2,
                                advance_state => false,          -- Stay in T1 for second sub-phase
                                new_cycle => false,
                                instruction_complete => false,
                                load_ir => false,
                                load_temp_a => false,
                                load_temp_b => false,
                                temp_a_source => "00",
                                temp_b_source => "00",
                                pc_inc => false,
                                pc_load_high => false,
                                pc_load_low => false,
                                stack_push => false,
                                stack_pop => false,
                                reg_write => false,
                                reg_read => false,
                                reg_target => "000",
                                reg_source => "00",
                                flags_update => false,
                                next_cycle_type => CYCLE_PCR
                            );
                        else  -- sub_phase = 1
                            -- LrM Cycle 1 T1 φ₁₂/φ₂₂: Advance to T2
                            return (
                                next_state => T2,
                                advance_state => true,
                                new_cycle => false,
                                instruction_complete => false,
                                load_ir => false,
                                load_temp_a => false,
                                load_temp_b => false,
                                temp_a_source => "00",
                                temp_b_source => "00",
                                pc_inc => false,                 -- PC already incremented at Cycle 0 T3
                                pc_load_high => false,
                                pc_load_low => false,
                                stack_push => false,
                                stack_pop => false,
                                reg_write => false,
                                reg_read => false,
                                reg_target => "000",
                                reg_source => "00",
                                flags_update => false,
                                next_cycle_type => CYCLE_PCR     -- Memory read from HL
                            );
                        end if;
                    elsif decoded.is_memory_dest then
                        -- LMr (MOV M,r): Cycle 1 T1 - Output L register (address low)
                        -- temp_b already contains register value from Cycle 0 T4
                        if sub_phase = 0 then
                            -- LMr Cycle 1 T1 φ₁₁/φ₂₁: Setup
                            return (
                                next_state => T2,
                                advance_state => false,          -- Stay in T1 for second sub-phase
                                new_cycle => false,
                                instruction_complete => false,
                                load_ir => false,
                                load_temp_a => false,
                                load_temp_b => false,
                                temp_a_source => "00",
                                temp_b_source => "00",
                                pc_inc => false,
                                pc_load_high => false,
                                pc_load_low => false,
                                stack_push => false,
                                stack_pop => false,
                                reg_write => false,
                                reg_read => false,
                                reg_target => "000",
                                reg_source => "00",
                                flags_update => false,
                                next_cycle_type => CYCLE_PCW     -- Memory write to HL
                            );
                        else  -- sub_phase = 1
                            -- LMr Cycle 1 T1 φ₁₂/φ₂₂: Advance to T2
                            return (
                                next_state => T2,
                                advance_state => true,
                                new_cycle => false,
                                instruction_complete => false,
                                load_ir => false,
                                load_temp_a => false,
                                load_temp_b => false,
                                temp_a_source => "00",
                                temp_b_source => "00",
                                pc_inc => false,                 -- PC already incremented at Cycle 0 T3
                                pc_load_high => false,
                                pc_load_low => false,
                                stack_push => false,
                                stack_pop => false,
                                reg_write => false,
                                reg_read => false,
                                reg_target => "000",
                                reg_source => "00",
                                flags_update => false,
                                next_cycle_type => CYCLE_PCW     -- Memory write to HL
                            );
                        end if;
                    elsif decoded.is_jmp or decoded.is_jmp_conditional or decoded.is_call then
                        -- JMP/CALL: Cycle 1 T1 - Increment PC to low address byte
                        if sub_phase = 0 then
                            -- JMP/CALL Cycle 1 T1 φ₁₁/φ₂₁: Setup
                            return (
                                next_state => T2,
                                advance_state => false,          -- Stay in T1 for second sub-phase
                                new_cycle => false,
                                instruction_complete => false,
                                load_ir => false,
                                load_temp_a => false,
                                load_temp_b => false,
                                temp_a_source => "00",
                                temp_b_source => "00",
                                pc_inc => false,
                                pc_load_high => false,
                                pc_load_low => false,
                                stack_push => false,
                                stack_pop => false,
                                reg_write => false,
                                reg_read => false,
                                reg_target => "000",
                                reg_source => "00",
                                flags_update => false,
                                next_cycle_type => CYCLE_PCI
                            );
                        else  -- sub_phase = 1
                            -- JMP/CALL Cycle 1 T1 φ₁₂/φ₂₂: Increment PC to low address byte
                            return (
                                next_state => T2,
                                advance_state => true,           -- Advance to T2
                                new_cycle => false,
                                instruction_complete => false,
                                load_ir => false,
                                load_temp_a => false,
                                load_temp_b => false,
                                temp_a_source => "00",
                                temp_b_source => "00",
                                pc_inc => true,                  -- Increment PC to low address byte
                                pc_load_high => false,
                                pc_load_low => false,
                                stack_push => false,
                                stack_pop => false,
                                reg_write => false,
                                reg_read => false,
                                reg_target => "000",
                                reg_source => "00",
                                flags_update => false,
                                next_cycle_type => CYCLE_PCI     -- Fetching low address byte from PC
                            );
                        end if;
                    elsif decoded.is_out then
                        -- OUT: Cycle 1 T1 - Output accumulator to data bus
                        if sub_phase = 0 then
                            -- OUT Cycle 1 T1 φ₁₁/φ₂₁: Setup
                            return (
                                next_state => T2,
                                advance_state => false,          -- Stay in T1 for second sub-phase
                                new_cycle => false,
                                instruction_complete => false,
                                load_ir => false,
                                load_temp_a => false,
                                load_temp_b => false,
                                temp_a_source => "00",
                                temp_b_source => "00",
                                pc_inc => false,
                                pc_load_high => false,
                                pc_load_low => false,
                                stack_push => false,
                                stack_pop => false,
                                reg_write => false,
                                reg_read => true,                -- Read accumulator
                                reg_target => "000",
                                reg_source => "00",              -- Source = A (accumulator)
                                flags_update => false,
                                next_cycle_type => CYCLE_PCC     -- I/O cycle
                            );
                        else  -- sub_phase = 1
                            -- OUT Cycle 1 T1 φ₁₂/φ₂₂: Advance to T2
                            return (
                                next_state => T2,
                                advance_state => true,           -- Advance to T2
                                new_cycle => false,
                                instruction_complete => false,
                                load_ir => false,
                                load_temp_a => false,
                                load_temp_b => false,
                                temp_a_source => "00",
                                temp_b_source => "00",
                                pc_inc => false,                 -- PC already incremented in Cycle 0 T3
                                pc_load_high => false,
                                pc_load_low => false,
                                stack_push => false,
                                stack_pop => false,
                                reg_write => false,
                                reg_read => true,                -- Continue reading accumulator for output
                                reg_target => "000",
                                reg_source => "00",              -- Source = A (accumulator)
                                flags_update => false,
                                next_cycle_type => CYCLE_PCC     -- I/O cycle
                            );
                        end if;
                    else
                        if sub_phase = 0 then
                            -- Default Cycle 1 T1 φ₁₁/φ₂₁: Setup
                            return (
                                next_state => T2,
                                advance_state => false,          -- Stay in T1 for second sub-phase
                                new_cycle => false,
                                instruction_complete => false,
                                load_ir => false,
                                load_temp_a => false,
                                load_temp_b => false,
                                temp_a_source => "00",
                                temp_b_source => "00",
                                pc_inc => false,
                                pc_load_high => false,
                                pc_load_low => false,
                                stack_push => false,
                                stack_pop => false,
                                reg_write => false,
                                reg_read => false,
                                reg_target => "000",
                                reg_source => "00",
                                flags_update => false,
                                next_cycle_type => CYCLE_PCI
                            );
                        else  -- sub_phase = 1
                            -- Default Cycle 1 T1 φ₁₂/φ₂₂: Advance
                            return (
                                next_state => T2,
                                advance_state => true,
                                new_cycle => false,
                                instruction_complete => false,
                                load_ir => false,
                                load_temp_a => false,
                                load_temp_b => false,
                                temp_a_source => "00",
                                temp_b_source => "00",
                                pc_inc => false,
                                pc_load_high => false,
                                pc_load_low => false,
                                stack_push => false,
                                stack_pop => false,
                                reg_write => false,
                                reg_read => false,
                                reg_target => "000",
                                reg_source => "00",
                                flags_update => false,
                                next_cycle_type => CYCLE_PCI     -- Still fetching from PC
                            );
                        end if;
                    end if;
                    
                when T2 =>
                    -- Cycle 1 T2: Address high byte OUT
                    -- Decode instruction to determine address source
                    decoded := decode_instruction(instr);

                    if decoded.is_out then
                        -- OUT: Output port address from temp_b
                        -- temp_b contains the OUT instruction opcode with RRMMM bits [5:1]
                        return (
                            next_state => T3,
                        advance_state => true,
                            new_cycle => false,
                            instruction_complete => false,
                            load_ir => false,
                            load_temp_a => false,
                            load_temp_b => false,
                            temp_a_source => "00",
                            temp_b_source => "00",
                            pc_inc => false,
                            pc_load_high => false,
                            pc_load_low => false,
                            stack_push => false,
                            stack_pop => false,
                            reg_write => false,
                            reg_read => false,
                            reg_target => "000",
                            reg_source => "00",
                            flags_update => false,
                            next_cycle_type => CYCLE_PCC  -- I/O cycle
                        );
                    elsif decoded.is_alu_memory or (decoded.is_mov and decoded.is_memory_source) then
                        -- ALU M or LrM: Output H register (HL address high byte)
                        return (
                            next_state => T3,
                        advance_state => true,
                            new_cycle => false,
                            instruction_complete => false,
                            load_ir => false,
                            load_temp_a => false,
                            load_temp_b => false,
                            temp_a_source => "00",
                            temp_b_source => "00",
                            pc_inc => false,
                            pc_load_high => false,
                            pc_load_low => false,
                            stack_push => false,
                            stack_pop => false,
                            reg_write => false,
                            reg_read => false,
                            reg_target => "000",
                            reg_source => "00",
                            flags_update => false,
                            next_cycle_type => CYCLE_PCR  -- Memory read from HL
                        );
                    else
                        -- Default: PCH OUT for immediate/address fetch
                        return (
                            next_state => T3,
                        advance_state => true,
                            new_cycle => false,
                            instruction_complete => false,
                            load_ir => false,
                            load_temp_a => false,
                            load_temp_b => false,
                            temp_a_source => "00",
                            temp_b_source => "00",
                            pc_inc => false,
                            pc_load_high => false,
                            pc_load_low => false,
                            stack_push => false,
                            stack_pop => false,
                            reg_write => false,
                            reg_read => false,
                            reg_target => "000",
                            reg_source => "00",
                            flags_update => false,
                            next_cycle_type => CYCLE_PCI
                        );
                    end if;
                    
                when T3 =>
                    -- Cycle 1 T3: Data IN - instruction specific
                    -- Decode instruction to eliminate hardcoded checks
                    decoded := decode_instruction(instr);

                    if decoded.is_mvi then  -- MVI (all variants including MVI M)
                        -- Fetch immediate data and save to temp_a
                        -- NOTE: PC increment moved to cycle 2 T1 to avoid ROM race condition
                        return (
                            next_state => T1,               -- Will be overridden if needed
                        advance_state => (sub_phase = 1),
                            new_cycle => true,              -- Start cycle 2 for memory write
                            instruction_complete => false,  -- Not done yet
                            load_ir => false,
                            load_temp_a => true,            -- Save immediate data to temp_a
                            load_temp_b => false,
                            temp_a_source => "01",          -- temp_a = data_bus (immediate)
                            temp_b_source => "00",
                            pc_inc => false,                -- Don't increment yet (moved to cycle 2 T1)
                            pc_load_high => false,
                            pc_load_low => false,
                            stack_push => false,
                            stack_pop => false,
                            reg_write => false,
                            reg_read => false,
                            reg_target => "000",
                            reg_source => "00",
                            flags_update => false,
                            next_cycle_type => CYCLE_PCW    -- Next cycle is memory write
                        );

                    elsif decoded.is_inp then  -- INP instruction
                        -- Cycle 1 T3: Read data from I/O port into temp_b
                        return (
                            next_state => T4,               -- Continue to T4 for flag output
                        advance_state => (sub_phase = 1),
                            new_cycle => false,
                            instruction_complete => false,  -- Not done yet
                            load_ir => false,
                            load_temp_a => false,
                            load_temp_b => true,            -- Save I/O data to temp_b
                            temp_a_source => "00",
                            temp_b_source => "01",          -- temp_b = data_bus_in (I/O data)
                            pc_inc => false,                -- PC already incremented in cycle 0
                            pc_load_high => false,
                            pc_load_low => false,
                            stack_push => false,
                            stack_pop => false,
                            reg_write => false,
                            reg_read => false,
                            reg_target => "000",
                            reg_source => "00",
                            flags_update => false,
                            next_cycle_type => CYCLE_PCC    -- Still in I/O cycle
                        );

                    elsif decoded.is_out then  -- OUT instruction
                        -- Cycle 1 T3: IDLE state waiting for READY signal
                        -- After READY, instruction is complete
                        return (
                            next_state => T1,               -- Return to T1 for next instruction
                        advance_state => (sub_phase = 1),
                            new_cycle => false,             -- Don't advance cycle (instruction complete)
                            instruction_complete => true,   -- OUT instruction complete
                            load_ir => false,
                            load_temp_a => false,
                            load_temp_b => false,
                            temp_a_source => "00",
                            temp_b_source => "00",
                            pc_inc => false,                -- PC already incremented in cycle 0
                            pc_load_high => false,
                            pc_load_low => false,
                            stack_push => false,
                            stack_pop => false,
                            reg_write => false,
                            reg_read => false,
                            reg_target => "000",
                            reg_source => "00",
                            flags_update => false,
                            next_cycle_type => CYCLE_PCI    -- Next cycle is instruction fetch
                        );

                    elsif decoded.is_alu_imm then  -- ALU Immediate instructions
                        -- Cycle 1 T3: Fetch immediate data to temp_b
                        -- ALU operation will execute in T4, result written in T5
                        return (
                            next_state => T4,               -- Continue to T4 for ALU operation
                            advance_state => (sub_phase = 1),
                            new_cycle => false,
                            instruction_complete => false,  -- Not done yet
                            load_ir => false,
                            load_temp_a => false,
                            load_temp_b => true,            -- Load immediate data
                            temp_a_source => "00",
                            temp_b_source => "01",          -- temp_b = data_bus_in (immediate)
                            pc_inc => false,                -- Don't increment yet (happens in T5)
                            pc_load_high => false,
                            pc_load_low => false,
                            stack_push => false,
                            stack_pop => false,
                            reg_write => false,
                            reg_read => false,
                            reg_target => "000",
                            reg_source => "00",
                            flags_update => false,
                            next_cycle_type => CYCLE_PCI
                        );

                    elsif decoded.is_alu_memory then  -- ALU M instructions
                        -- Cycle 1 T3: Read memory data from [HL] into temp_b
                        return (
                            next_state => T5,               -- Skip T4, go directly to T5
                        advance_state => (sub_phase = 1),
                            new_cycle => false,
                            instruction_complete => false,  -- Not done yet
                            load_ir => false,
                            load_temp_a => false,
                            load_temp_b => true,            -- Save memory data to temp_b
                            temp_a_source => "00",
                            temp_b_source => "01",          -- temp_b = data_bus_in (memory data)
                            pc_inc => false,                -- PC already incremented in cycle 0
                            pc_load_high => false,
                            pc_load_low => false,
                            stack_push => false,
                            stack_pop => false,
                            reg_write => false,
                            reg_read => false,
                            reg_target => "000",
                            reg_source => "00",
                            flags_update => false,
                            next_cycle_type => CYCLE_PCR    -- Memory read from HL
                        );

                    elsif decoded.is_mov and decoded.is_memory_source then  -- LrM (MOV r,M)
                        -- Cycle 1 T3: Read memory data from [HL] into temp_b
                        return (
                            next_state => T4,               -- Continue to T4 (IDLE state per spec)
                        advance_state => (sub_phase = 1),
                            new_cycle => false,
                            instruction_complete => false,  -- Not done yet
                            load_ir => false,
                            load_temp_a => false,
                            load_temp_b => true,            -- Save memory data to temp_b
                            temp_a_source => "00",
                            temp_b_source => "01",          -- temp_b = data_bus_in (memory data)
                            pc_inc => false,                -- PC already incremented in cycle 0
                            pc_load_high => false,
                            pc_load_low => false,
                            stack_push => false,
                            stack_pop => false,
                            reg_write => false,
                            reg_read => false,
                            reg_target => "000",
                            reg_source => "00",
                            flags_update => false,
                            next_cycle_type => CYCLE_PCR    -- Memory read from HL
                        );

                    elsif decoded.is_mov and decoded.is_memory_dest then  -- LMr (MOV M,r)
                        -- Cycle 1 T3: Write register data to memory [HL]
                        -- Register data is already on internal_data_bus from reg_read in Cycle 0 T3
                        -- This write completes the instruction
                        return (
                            next_state => T1,               -- Next instruction
                            advance_state => (sub_phase = 1),
                            new_cycle => false,
                            instruction_complete => true,   -- Instruction complete after T3
                            load_ir => false,
                            load_temp_a => false,
                            load_temp_b => false,
                            temp_a_source => "00",
                            temp_b_source => "00",
                            pc_inc => false,                -- PC already incremented in cycle 0
                            pc_load_high => false,
                            pc_load_low => false,
                            stack_push => false,
                            stack_pop => false,
                            reg_write => false,
                            reg_read => false,              -- Data already on bus from Cycle 0
                            reg_target => "000",
                            reg_source => "00",
                            flags_update => false,
                            next_cycle_type => CYCLE_PCI    -- Next instruction
                        );

                    elsif decoded.is_jmp or decoded.is_jmp_conditional then  -- JMP instructions
                        -- Cycle 1 T3: Fetch low address byte
                        -- Both unconditional and conditional JMP proceed to cycle 2
                        -- Condition evaluation happens in Cycle 2 T3
                        return (
                            next_state => T1,
                            advance_state => (sub_phase = 1),
                            new_cycle => true,              -- Start cycle 2 to fetch high address byte
                            instruction_complete => false,  -- Not done yet
                            load_ir => false,
                            load_temp_a => false,
                            load_temp_b => true,            -- Save low address byte to temp_b
                            temp_a_source => "00",
                            temp_b_source => "01",          -- temp_b = low address byte
                            pc_inc => false,                -- Don't increment yet
                            pc_load_high => false,
                            pc_load_low => false,
                            stack_push => false,
                            stack_pop => false,
                            reg_write => false,
                            reg_read => false,
                            reg_target => "000",
                            reg_source => "00",
                            flags_update => false,
                            next_cycle_type => CYCLE_PCI    -- Next cycle fetches high address byte
                        );

                    elsif decoded.is_call then  -- CALL instruction
                        -- Cycle 1 T3: Fetch low address byte, skip T4/T5, advance to Cycle 2
                        return (
                            next_state => T1,
                            advance_state => (sub_phase = 1),
                            new_cycle => true,              -- Start cycle 2 to fetch high address byte
                            instruction_complete => false,  -- Not done yet
                            load_ir => false,
                            load_temp_a => false,
                            load_temp_b => true,            -- Save low address byte to temp_b
                            temp_a_source => "00",
                            temp_b_source => "01",          -- temp_b = low address byte
                            pc_inc => false,                -- Don't increment yet (happens in sub_phase=1)
                            pc_load_high => false,
                            pc_load_low => false,
                            stack_push => false,
                            stack_pop => false,
                            reg_write => false,
                            reg_read => false,
                            reg_target => "000",
                            reg_source => "00",
                            flags_update => false,
                            next_cycle_type => CYCLE_PCI    -- Next cycle fetches high address byte
                        );

                    else
                        -- Default for unknown instructions in cycle 1
                        return DEFAULT_UCODE;
                    end if;

                when T4 =>
                    -- Cycle 1 T4 - instruction specific
                    -- Decode instruction to eliminate hardcoded checks
                    decoded := decode_instruction(instr);

                    if decoded.is_inp then  -- INP instruction
                        -- Cycle 1 T4: Output flags to data bus
                        -- Per datasheet: S→D0, Z→D1, P→D2, C→D3
                        -- Data bus output handled in data_bus_output process
                        return (
                            next_state => T5,               -- Continue to T5
                        advance_state => true,
                            new_cycle => false,
                            instruction_complete => false,  -- Not done yet
                            load_ir => false,
                            load_temp_a => false,
                            load_temp_b => false,
                            temp_a_source => "00",
                            temp_b_source => "00",
                            pc_inc => false,
                            pc_load_high => false,
                            pc_load_low => false,
                            stack_push => false,
                            stack_pop => false,
                            reg_write => false,
                            reg_read => false,
                            reg_target => "000",
                            reg_source => "00",
                            flags_update => false,
                            next_cycle_type => CYCLE_PCC    -- Still in I/O cycle
                        );
                    elsif decoded.is_alu_imm then  -- ALU Immediate instructions
                        -- Cycle 1 T4: IDLE state - ALU operation in progress
                        -- Full 4.4μs state, no bus activity
                        -- ALU is computing A op temp_b combinatorially
                        return (
                            next_state => T5,               -- Continue to T5 for result write
                            advance_state => true,
                            new_cycle => false,
                            instruction_complete => false,  -- Not done yet
                            load_ir => false,
                            load_temp_a => false,
                            load_temp_b => false,
                            temp_a_source => "00",
                            temp_b_source => "00",
                            pc_inc => false,
                            pc_load_high => false,
                            pc_load_low => false,
                            stack_push => false,
                            stack_pop => false,
                            reg_write => false,
                            reg_read => false,
                            reg_target => "000",
                            reg_source => "00",
                            flags_update => false,
                            next_cycle_type => CYCLE_PCI
                        );
                    elsif decoded.is_mov and decoded.is_memory_source then  -- LrM (MOV r,M)
                        -- Cycle 1 T4: IDLE state - no operation, just advance to T5
                        return (
                            next_state => T5,               -- Continue to T5
                        advance_state => true,
                            new_cycle => false,
                            instruction_complete => false,  -- Not done yet
                            load_ir => false,
                            load_temp_a => false,
                            load_temp_b => false,
                            temp_a_source => "00",
                            temp_b_source => "00",
                            pc_inc => false,
                            pc_load_high => false,
                            pc_load_low => false,
                            stack_push => false,
                            stack_pop => false,
                            reg_write => false,
                            reg_read => false,
                            reg_target => "000",
                            reg_source => "00",
                            flags_update => false,
                            next_cycle_type => CYCLE_PCR    -- Memory read from HL
                        );
                    else
                        return DEFAULT_UCODE;
                    end if;

                when T5 =>
                    -- Cycle 1 T5 - instruction specific
                    -- Decode instruction to eliminate hardcoded checks
                    decoded := decode_instruction(instr);

                    if decoded.is_inp then  -- INP instruction
                        -- Cycle 1 T5: Transfer I/O data from temp_b to accumulator
                        if sub_phase = 0 then
                            -- INP Cycle 1 T5 φ₁₁/φ₂₁: Setup accumulator write
                            return (
                                next_state => T1,
                                advance_state => false,         -- Stay in T5 for second sub-phase
                                new_cycle => false,
                                instruction_complete => false,
                                load_ir => false,
                                load_temp_a => false,
                                load_temp_b => false,
                                temp_a_source => "00",
                                temp_b_source => "00",
                                pc_inc => false,
                                pc_load_high => false,
                                pc_load_low => false,
                                stack_push => false,
                                stack_pop => false,
                                reg_write => true,              -- Setup register write
                                reg_read => false,
                                reg_target => REG_A,
                                reg_source => "11",             -- Source: temp_b (I/O data)
                                flags_update => false,
                                next_cycle_type => CYCLE_PCI
                            );
                        else  -- sub_phase = 1
                            -- INP Cycle 1 T5 φ₁₂/φ₂₂: Complete accumulator write
                            return (
                                next_state => T1,
                                advance_state => true,          -- Advance (instruction complete)
                                new_cycle => false,
                                instruction_complete => true,   -- INP instruction complete!
                                load_ir => false,
                                load_temp_a => false,
                                load_temp_b => false,
                                temp_a_source => "00",
                                temp_b_source => "00",
                                pc_inc => false,                -- PC already incremented in cycle 0
                                pc_load_high => false,
                                pc_load_low => false,
                                stack_push => false,
                                stack_pop => false,
                                reg_write => true,              -- Complete register write
                                reg_read => false,
                                reg_target => REG_A,
                                reg_source => "11",             -- Source: temp_b (I/O data)
                                flags_update => false,
                                next_cycle_type => CYCLE_PCI    -- Next instruction fetch
                            );
                        end if;

                    elsif decoded.is_alu_imm then  -- ALU Immediate instructions
                        -- Cycle 1 T5: Write ALU result to accumulator, update flags, increment PC
                        -- Note: CPI (FFF=111) only updates flags, doesn't write to accumulator
                        if decoded.fff_field = "111" then
                            -- CPI: Update flags only, don't write to accumulator
                            if sub_phase = 0 then
                                -- CPI Cycle 1 T5 φ₁₁/φ₂₁: Setup flag update
                                return (
                                    next_state => T1,
                                    advance_state => false,         -- Stay in T5 for second sub-phase
                                    new_cycle => false,
                                    instruction_complete => false,
                                    load_ir => false,
                                    load_temp_a => false,
                                    load_temp_b => false,
                                    temp_a_source => "00",
                                    temp_b_source => "00",
                                    pc_inc => false,
                                    pc_load_high => false,
                                    pc_load_low => false,
                                    stack_push => false,
                                    stack_pop => false,
                                    reg_write => false,             -- No accumulator write for CPI
                                    reg_read => false,
                                    reg_target => REG_A,
                                    reg_source => "10",             -- ALU result (for flags only)
                                    flags_update => true,           -- Update flags from ALU result
                                    next_cycle_type => CYCLE_PCI
                                );
                            else  -- sub_phase = 1
                                -- CPI Cycle 1 T5 φ₁₂/φ₂₂: Complete flag update, increment PC
                                return (
                                    next_state => T1,
                                    advance_state => true,
                                    new_cycle => false,
                                    instruction_complete => true,   -- Instruction complete!
                                    load_ir => false,
                                    load_temp_a => false,
                                    load_temp_b => false,
                                    temp_a_source => "00",
                                    temp_b_source => "00",
                                    pc_inc => true,                 -- Move PC to next instruction
                                    pc_load_high => false,
                                    pc_load_low => false,
                                    stack_push => false,
                                    stack_pop => false,
                                    reg_write => false,             -- No accumulator write for CPI
                                    reg_read => false,
                                    reg_target => REG_A,
                                    reg_source => "10",             -- ALU result (for flags only)
                                    flags_update => false,          -- Flags already updated in sub_phase=0
                                    next_cycle_type => CYCLE_PCI
                                );
                            end if;
                        else
                            -- Normal ALU immediate: Write result to accumulator
                            if sub_phase = 0 then
                                -- ALU IMM Cycle 1 T5 φ₁₁/φ₂₁: Setup accumulator write
                                return (
                                    next_state => T1,
                                    advance_state => false,         -- Stay in T5 for second sub-phase
                                    new_cycle => false,
                                    instruction_complete => false,
                                    load_ir => false,
                                    load_temp_a => false,
                                    load_temp_b => false,
                                    temp_a_source => "00",
                                    temp_b_source => "00",
                                    pc_inc => false,
                                    pc_load_high => false,
                                    pc_load_low => false,
                                    stack_push => false,
                                    stack_pop => false,
                                    reg_write => true,              -- Write ALU result to accumulator
                                    reg_read => false,
                                    reg_target => REG_A,
                                    reg_source => "10",             -- Source: ALU result
                                    flags_update => true,           -- Update flags from ALU result
                                    next_cycle_type => CYCLE_PCI
                                );
                            else  -- sub_phase = 1
                                -- ALU IMM Cycle 1 T5 φ₁₂/φ₂₂: Complete accumulator write, increment PC
                                return (
                                    next_state => T1,
                                    advance_state => true,
                                    new_cycle => false,
                                    instruction_complete => true,   -- Instruction complete!
                                    load_ir => false,
                                    load_temp_a => false,
                                    load_temp_b => false,
                                    temp_a_source => "00",
                                    temp_b_source => "00",
                                    pc_inc => true,                 -- Move PC to next instruction
                                    pc_load_high => false,
                                    pc_load_low => false,
                                    stack_push => false,
                                    stack_pop => false,
                                    reg_write => true,              -- Write ALU result to accumulator
                                    reg_read => false,
                                    reg_target => REG_A,
                                    reg_source => "10",             -- Source: ALU result
                                    flags_update => false,          -- Flags already updated in sub_phase=0
                                    next_cycle_type => CYCLE_PCI
                                );
                            end if;
                        end if;

                    elsif decoded.is_alu_memory then  -- ALU M instructions
                        -- Cycle 1 T5: Execute ALU operation, update accumulator and flags
                        -- Note: reg_source "10" indicates ALU result
                        -- Note: CMP (PPP=111) doesn't update accumulator, only flags
                        -- Check if this is CMP (PPP = 111)
                        if decoded.fff_field = "111" then
                            -- CMP: Update flags only, don't write to accumulator
                            if sub_phase = 0 then
                                -- CMP Cycle 1 T5 φ₁₁/φ₂₁: Setup flag update
                                return (
                                    next_state => T1,
                                    advance_state => false,
                                    new_cycle => false,
                                    instruction_complete => false,
                                    load_ir => false,
                                    load_temp_a => false,
                                    load_temp_b => false,
                                    temp_a_source => "00",
                                    temp_b_source => "00",
                                    pc_inc => false,
                                    pc_load_high => false,
                                    pc_load_low => false,
                                    stack_push => false,
                                    stack_pop => false,
                                    reg_write => false,
                                    reg_read => false,
                                    reg_target => REG_A,
                                    reg_source => "10",
                                    flags_update => false,
                                    next_cycle_type => CYCLE_PCI
                                );
                            else  -- sub_phase = 1
                                -- CMP Cycle 1 T5 φ₁₂/φ₂₂: Complete flag update
                                return (
                                    next_state => T1,
                                    advance_state => true,
                                    new_cycle => false,
                                    instruction_complete => true,
                                    load_ir => false,
                                    load_temp_a => false,
                                    load_temp_b => false,
                                    temp_a_source => "00",
                                    temp_b_source => "00",
                                    pc_inc => false,
                                    pc_load_high => false,
                                    pc_load_low => false,
                                    stack_push => false,
                                    stack_pop => false,
                                    reg_write => false,
                                    reg_read => false,
                                    reg_target => REG_A,
                                    reg_source => "10",
                                    flags_update => false,
                                    next_cycle_type => CYCLE_PCI
                                );
                            end if;
                        else
                            -- Other ALU operations: Write result to accumulator
                            if sub_phase = 0 then
                                -- ALU M Cycle 1 T5 φ₁₁/φ₂₁: Setup accumulator write
                                return (
                                    next_state => T1,
                                    advance_state => false,
                                    new_cycle => false,
                                    instruction_complete => false,
                                    load_ir => false,
                                    load_temp_a => false,
                                    load_temp_b => false,
                                    temp_a_source => "00",
                                    temp_b_source => "00",
                                    pc_inc => false,
                                    pc_load_high => false,
                                    pc_load_low => false,
                                    stack_push => false,
                                    stack_pop => false,
                                    reg_write => true,
                                    reg_read => false,
                                    reg_target => REG_A,
                                    reg_source => "10",
                                    flags_update => false,
                                    next_cycle_type => CYCLE_PCI
                                );
                            else  -- sub_phase = 1
                                -- ALU M Cycle 1 T5 φ₁₂/φ₂₂: Complete accumulator write
                                return (
                                    next_state => T1,
                                    advance_state => true,
                                    new_cycle => false,
                                    instruction_complete => true,
                                    load_ir => false,
                                    load_temp_a => false,
                                    load_temp_b => false,
                                    temp_a_source => "00",
                                    temp_b_source => "00",
                                    pc_inc => false,
                                    pc_load_high => false,
                                    pc_load_low => false,
                                    stack_push => false,
                                    stack_pop => false,
                                    reg_write => true,
                                    reg_read => false,
                                    reg_target => REG_A,
                                    reg_source => "10",
                                    flags_update => false,
                                    next_cycle_type => CYCLE_PCI
                                );
                            end if;
                        end if;

                    elsif decoded.is_mov and decoded.is_memory_source then  -- LrM (MOV r,M)
                        -- Cycle 1 T5: Write memory data from temp_b to destination register (DDD)
                        -- Use instr(5:3) for DDD field from instruction register
                        if sub_phase = 0 then
                            -- LrM Cycle 1 T5 φ₁₁/φ₂₁: Setup register write
                            return (
                                next_state => T1,
                                advance_state => false,         -- Stay in T5 for second sub-phase
                                new_cycle => false,
                                instruction_complete => false,
                                load_ir => false,
                                load_temp_a => false,
                                load_temp_b => false,
                                temp_a_source => "00",
                                temp_b_source => "00",
                                pc_inc => false,
                                pc_load_high => false,
                                pc_load_low => false,
                                stack_push => false,
                                stack_pop => false,
                                reg_write => true,              -- Setup register write
                                reg_read => false,
                                reg_target => instr(5 downto 3),  -- DDD from instruction register
                                reg_source => "11",             -- Source: temp_b (memory data)
                                flags_update => false,
                                next_cycle_type => CYCLE_PCI
                            );
                        else  -- sub_phase = 1
                            -- LrM Cycle 1 T5 φ₁₂/φ₂₂: Complete register write
                            return (
                                next_state => T1,
                                advance_state => true,          -- Advance (instruction complete)
                                new_cycle => false,
                                instruction_complete => true,   -- LrM instruction complete!
                                load_ir => false,
                                load_temp_a => false,
                                load_temp_b => false,
                                temp_a_source => "00",
                                temp_b_source => "00",
                                pc_inc => false,                -- PC already incremented in cycle 0
                                pc_load_high => false,
                                pc_load_low => false,
                                stack_push => false,
                                stack_pop => false,
                                reg_write => true,              -- Complete register write
                                reg_read => false,
                                reg_target => instr(5 downto 3),  -- DDD from instruction register
                                reg_source => "11",             -- Source: temp_b (memory data)
                                flags_update => false,
                                next_cycle_type => CYCLE_PCI    -- Next instruction fetch
                            );
                        end if;

                    else
                        return DEFAULT_UCODE;
                    end if;

                when others =>
                    return DEFAULT_UCODE;
            end case;

        -- ===========================================
        -- CYCLE 2: Third machine cycle
        -- ===========================================
        elsif cycle = 2 then
            -- Instruction-specific behavior for cycle 2
            case state is
                when T1 =>
                    -- Cycle 2 T1: Write immediate to register OR start memory write
                    decoded := decode_instruction(instr);

                    if decoded.is_mvi and not decoded.is_memory_dest then
                        -- MVI to register (A, B, C, D, E, H, L): Write temp_a to destination register
                        -- Increment PC to point to next instruction
                        if sub_phase = 0 then
                            -- MVI reg Cycle 2 T1 φ₁₁/φ₂₁: Setup register write
                            return (
                                next_state => T1,               -- Will be overridden by interrupt logic
                                advance_state => false,         -- Stay in T1 for second sub-phase
                                new_cycle => false,
                                instruction_complete => false,  -- Not complete until sub_phase=1
                                load_ir => false,
                                load_temp_a => false,
                                load_temp_b => false,
                                temp_a_source => "00",
                                temp_b_source => "00",
                                pc_inc => false,
                                pc_load_high => false,
                                pc_load_low => false,
                                stack_push => false,
                                stack_pop => false,
                                reg_write => true,              -- Setup register write
                                reg_read => false,
                                reg_target => decoded.ddd_field,
                                reg_source => "10",             -- Source: temp_a
                                flags_update => false,
                                next_cycle_type => CYCLE_PCI
                            );
                        else  -- sub_phase = 1
                            -- MVI reg Cycle 2 T1 φ₁₂/φ₂₂: Complete register write, increment PC
                            return (
                                next_state => T1,               -- Will be overridden by interrupt logic
                                advance_state => true,          -- Advance (instruction complete)
                                new_cycle => false,
                                instruction_complete => true,   -- MVI register complete!
                                load_ir => false,
                                load_temp_a => false,
                                load_temp_b => false,
                                temp_a_source => "00",
                                temp_b_source => "00",
                                pc_inc => true,                 -- Increment PC to next instruction
                                pc_load_high => false,
                                pc_load_low => false,
                                stack_push => false,
                                stack_pop => false,
                                reg_write => true,              -- Complete register write (at phi2_sub=1)
                                reg_read => false,
                                reg_target => decoded.ddd_field,
                                reg_source => "10",             -- Source: temp_a
                                flags_update => false,
                                next_cycle_type => CYCLE_PCI    -- Next: fetch next instruction
                            );
                        end if;
                    elsif decoded.is_jmp or decoded.is_jmp_conditional or decoded.is_call then
                        -- JMP/CALL: Cycle 2 T1 - Increment PC to high address byte
                        if sub_phase = 0 then
                            -- JMP/CALL Cycle 2 T1 φ₁₁/φ₂₁: Setup
                            return (
                                next_state => T2,
                                advance_state => false,          -- Stay in T1 for second sub-phase
                                new_cycle => false,
                                instruction_complete => false,
                                load_ir => false,
                                load_temp_a => false,
                                load_temp_b => false,
                                temp_a_source => "00",
                                temp_b_source => "00",
                                pc_inc => false,
                                pc_load_high => false,
                                pc_load_low => false,
                                stack_push => false,
                                stack_pop => false,
                                reg_write => false,
                                reg_read => false,
                                reg_target => "000",
                                reg_source => "00",
                                flags_update => false,
                                next_cycle_type => CYCLE_PCI
                            );
                        else  -- sub_phase = 1
                            -- JMP/CALL Cycle 2 T1 φ₁₂/φ₂₂: Increment PC to high address byte
                            return (
                                next_state => T2,
                                advance_state => true,           -- Advance to T2
                                new_cycle => false,
                                instruction_complete => false,
                                load_ir => false,
                                load_temp_a => false,
                                load_temp_b => false,
                                temp_a_source => "00",
                                temp_b_source => "00",
                                pc_inc => true,                  -- Increment PC to high address byte
                                pc_load_high => false,
                                pc_load_low => false,
                                stack_push => false,
                                stack_pop => false,
                                reg_write => false,
                                reg_read => false,
                                reg_target => "000",
                                reg_source => "00",
                                flags_update => false,
                                next_cycle_type => CYCLE_PCI     -- Fetching high address byte from PC
                            );
                        end if;
                    else
                        -- MVI M or other: Continue to T2 for memory write cycle
                        return (
                            next_state => T2,
                        advance_state => true,
                            new_cycle => false,
                            instruction_complete => false,
                            load_ir => false,
                            load_temp_a => false,
                            load_temp_b => false,
                            temp_a_source => "00",
                            temp_b_source => "00",
                            pc_inc => false,
                            pc_load_high => false,
                            pc_load_low => false,
                            stack_push => false,
                            stack_pop => false,
                            reg_write => false,
                            reg_read => false,
                            reg_target => "000",
                            reg_source => "00",
                            flags_update => false,
                            next_cycle_type => CYCLE_PCW  -- Memory write cycle
                        );
                    end if;
                    
                when T2 =>
                    -- Cycle 2 T2: Address HIGH out (memory write cycle)
                    -- For MVI M, output H register contents
                    return (
                        next_state => T3,
                        advance_state => true,
                        new_cycle => false,
                        instruction_complete => false,
                        load_ir => false,
                        load_temp_a => false,
                        load_temp_b => false,
                        temp_a_source => "00",
                        temp_b_source => "00",
                        pc_inc => false,
                        pc_load_high => false,
                        pc_load_low => false,
                        stack_push => false,
                        stack_pop => false,
                        reg_write => false,
                        reg_read => false,
                        reg_target => "000",
                        reg_source => "00",
                        flags_update => false,
                        next_cycle_type => CYCLE_PCW
                    );
                    
                when T3 =>
                    -- Cycle 2 T3: Data OUT - write to memory
                    -- Decode instruction to eliminate hardcoded checks
                    decoded := decode_instruction(instr);

                    if decoded.is_mvi and decoded.is_memory_dest then  -- MVI M
                        -- Write immediate data (in temp_a) to memory[HL]
                        -- Data output will be handled by bus control logic
                        return (
                            next_state => T1,               -- Will be overridden by interrupt logic
                        advance_state => (sub_phase = 1),
                            new_cycle => false,
                            instruction_complete => true,   -- MVI M complete!
                            load_ir => false,
                            load_temp_a => false,
                            load_temp_b => false,
                            temp_a_source => "00",
                            temp_b_source => "00",
                            pc_inc => false,               -- PC already points to next instruction
                            pc_load_high => false,
                            pc_load_low => false,
                            stack_push => false,
                            stack_pop => false,
                            reg_write => false,
                            reg_read => false,
                            reg_target => "000",
                            reg_source => "00",
                            flags_update => false,
                            next_cycle_type => CYCLE_PCI    -- Next cycle will fetch next instruction
                        );
                    elsif decoded.is_jmp or decoded.is_jmp_conditional then  -- JMP instructions
                        -- Cycle 2 T3: Fetch higher address byte and evaluate condition (if conditional)
                        -- For conditional JMP: evaluate condition
                        --   - If TRUE: proceed to T4/T5 to load PC
                        --   - If FALSE: skip T4/T5, increment PC to next instruction
                        -- For unconditional JMP: always proceed to T4/T5

                        if decoded.is_jmp_conditional and not evaluate_condition(decoded.ccc_field, cpu_flags) then
                            -- Condition FALSE: Skip T4/T5, increment PC to next instruction
                            report "Conditional JMP: Condition FALSE, skipping jump. CCC=" & to_string(decoded.ccc_field) & ", flags=" & to_string(cpu_flags);
                            return (
                                next_state => T1,               -- Skip to next instruction
                                advance_state => (sub_phase = 1),
                                new_cycle => false,
                                instruction_complete => true,   -- Instruction complete (jump not taken)
                                load_ir => false,
                                load_temp_a => false,           -- Don't load high address byte
                                load_temp_b => false,
                                temp_a_source => "00",
                                temp_b_source => "00",
                                pc_inc => true,                 -- Increment PC to next instruction
                                pc_load_high => false,          -- Don't load PC (jump not taken)
                                pc_load_low => false,
                                stack_push => false,
                                stack_pop => false,
                                reg_write => false,
                                reg_read => false,
                                reg_target => "000",
                                reg_source => "00",
                                flags_update => false,
                                next_cycle_type => CYCLE_PCI
                            );
                        else
                            -- Condition TRUE or unconditional: Proceed to T4/T5
                            report "Conditional JMP: Condition TRUE, taking jump. CCC=" & to_string(decoded.ccc_field) & ", flags=" & to_string(cpu_flags) & ", is_conditional=" & boolean'image(decoded.is_jmp_conditional);
                            return (
                                next_state => T4,               -- Continue to T4 for PC loading
                                advance_state => (sub_phase = 1),
                                new_cycle => false,
                                instruction_complete => false,  -- Not done yet, need T4 & T5
                                load_ir => false,
                                load_temp_a => true,            -- Load high address byte to temp_a (Reg.a)
                                load_temp_b => false,           -- temp_b already has low address byte
                                temp_a_source => "01",          -- temp_a = data_bus (high address byte)
                                temp_b_source => "00",
                                pc_inc => false,
                                pc_load_high => false,          -- PC load happens in T4 & T5
                                pc_load_low => false,
                                stack_push => false,
                                stack_pop => false,
                                reg_write => false,
                                reg_read => false,
                                reg_target => "000",
                                reg_source => "00",
                                flags_update => false,
                                next_cycle_type => CYCLE_PCI
                            );
                        end if;

                    elsif decoded.is_call then  -- CALL instruction
                        -- Cycle 2 T3: Fetch higher address byte, push PC to stack, proceed to T4/T5
                        return (
                            next_state => T4,               -- Continue to T4 for PC loading
                            advance_state => (sub_phase = 1),
                            new_cycle => false,
                            instruction_complete => false,  -- Not done yet, need T4 & T5
                            load_ir => false,
                            load_temp_a => true,            -- Load high address byte to temp_a (Reg.a)
                            load_temp_b => false,           -- temp_b already has low address byte
                            temp_a_source => "01",          -- temp_a = data_bus (high address byte)
                            temp_b_source => "00",
                            pc_inc => false,
                            pc_load_high => false,          -- PC load happens in T4 & T5
                            pc_load_low => false,
                            stack_push => true,             -- Push current PC to stack before we overwrite it
                            stack_pop => false,
                            reg_write => false,
                            reg_read => false,
                            reg_target => "000",
                            reg_source => "00",
                            flags_update => false,
                            next_cycle_type => CYCLE_PCI
                        );

                    else
                        -- Default for unknown instructions in cycle 2
                        return DEFAULT_UCODE;
                    end if;

                when T4 =>
                    -- Cycle 2 T4 - instruction specific
                    decoded := decode_instruction(instr);

                    if decoded.is_jmp or decoded.is_jmp_conditional then  -- JMP instructions
                        -- Cycle 2 T4: Reg.a (temp_a) to PCH
                        -- Load PC high byte from temp_a[5:0] (14-bit addressing)
                        return (
                            next_state => T5,
                            advance_state => true,
                            new_cycle => false,
                            instruction_complete => false,  -- Not done yet, need T5
                            load_ir => false,
                            load_temp_a => false,
                            load_temp_b => false,
                            temp_a_source => "00",
                            temp_b_source => "00",
                            pc_inc => false,
                            pc_load_high => true,           -- Load PC[13:8] from temp_a[5:0]
                            pc_load_low => false,
                            stack_push => false,
                            stack_pop => false,
                            reg_write => false,
                            reg_read => false,
                            reg_target => "000",
                            reg_source => "00",
                            flags_update => false,
                            next_cycle_type => CYCLE_PCI
                        );

                    elsif decoded.is_call then  -- CALL instruction
                        -- Cycle 2 T4: Reg.a (temp_a) to PCH
                        -- Load PC high byte from temp_a[5:0] (14-bit addressing)
                        return (
                            next_state => T5,
                            advance_state => true,
                            new_cycle => false,
                            instruction_complete => false,  -- Not done yet, need T5
                            load_ir => false,
                            load_temp_a => false,
                            load_temp_b => false,
                            temp_a_source => "00",
                            temp_b_source => "00",
                            pc_inc => false,
                            pc_load_high => true,           -- Load PC[13:8] from temp_a[5:0]
                            pc_load_low => false,
                            stack_push => false,            -- Stack already pushed in T3
                            stack_pop => false,
                            reg_write => false,
                            reg_read => false,
                            reg_target => "000",
                            reg_source => "00",
                            flags_update => false,
                            next_cycle_type => CYCLE_PCI
                        );

                    else
                        return DEFAULT_UCODE;  -- TODO: implement for other instructions
                    end if;

                when T5 =>
                    -- Cycle 2 T5 - instruction specific
                    decoded := decode_instruction(instr);

                    if decoded.is_jmp or decoded.is_jmp_conditional then  -- JMP instructions
                        -- Cycle 2 T5: Reg.b (temp_b) to PCL
                        -- Load PC low byte from temp_b[7:0]
                        return (
                            next_state => T1,               -- Will be overridden by interrupt logic
                            advance_state => true,
                            new_cycle => false,
                            instruction_complete => true,   -- JMP complete!
                            load_ir => false,
                            load_temp_a => false,
                            load_temp_b => false,
                            temp_a_source => "00",
                            temp_b_source => "00",
                            pc_inc => false,
                            pc_load_high => false,          -- Already loaded in T4
                            pc_load_low => true,            -- Load PC[7:0] from temp_b[7:0]
                            stack_push => false,
                            stack_pop => false,
                            reg_write => false,
                            reg_read => false,
                            reg_target => "000",
                            reg_source => "00",
                            flags_update => false,
                            next_cycle_type => CYCLE_PCI    -- Next cycle fetches from new PC address
                        );

                    elsif decoded.is_call then  -- CALL instruction
                        -- Cycle 2 T5: Reg.b (temp_b) to PCL
                        -- Load PC low byte from temp_b[7:0]
                        return (
                            next_state => T1,               -- Will be overridden by interrupt logic
                            advance_state => true,
                            new_cycle => false,
                            instruction_complete => true,   -- CALL complete!
                            load_ir => false,
                            load_temp_a => false,
                            load_temp_b => false,
                            temp_a_source => "00",
                            temp_b_source => "00",
                            pc_inc => false,
                            pc_load_high => false,          -- Already loaded in T4
                            pc_load_low => true,            -- Load PC[7:0] from temp_b[7:0]
                            stack_push => false,            -- Stack already pushed in T3
                            stack_pop => false,
                            reg_write => false,
                            reg_read => false,
                            reg_target => "000",
                            reg_source => "00",
                            flags_update => false,
                            next_cycle_type => CYCLE_PCI    -- Next cycle fetches from new PC address
                        );

                    else
                        return DEFAULT_UCODE;  -- TODO: implement for other instructions
                    end if;
                    
                when others =>
                    return DEFAULT_UCODE;
            end case;

        -- Default case for unimplemented instructions
        else
            return DEFAULT_UCODE;
        end if;
    end function;
    
    -- Control signals from microcode (unused legacy signals)
    signal fetch_instruction : boolean := false;
    signal instr_decode_phase : boolean := false;  -- Renamed to avoid conflict with decode_instruction function
    signal execute_instruction : boolean := false;

    -- Cycle and instruction tracking
    signal cycle_complete : boolean := false;      -- True when current machine cycle ends (T3 or T5)
    signal instruction_complete : boolean := true; -- True when entire instruction finishes
    signal cycles_in_instruction : integer := 1;   -- How many cycles this instruction needs

    -- Register control signals
    signal reg_write_enable : boolean := false;
    signal reg_read_enable : boolean := false;
    signal reg_select : std_logic_vector(2 downto 0) := "000";  -- Which register to access
    signal reg_data_source : std_logic_vector(1 downto 0) := "00";  -- Source selector for cross-clock-domain
    signal flags_update_enable : boolean := false;  -- Enable flag updates from ALU

    -- H:L indirect addressing
    -- Combines H (high 6 bits) and L (low 8 bits) for 14-bit memory address
    signal hl_address : std_logic_vector(13 downto 0) := (others => '0');
    
    -- Memory reference flag (when REG_M is used)
    signal memory_reference : boolean := false;

begin

    --=========================================
    -- Component Instantiations
    --=========================================

    -- ALU Instance
    ALU: i8008_alu
        port map (
            data_0 => alu_data_0,
            data_1 => alu_data_1,
            flag_carry => flag_carry,
            command => alu_command,
            alu_result => alu_result
        );

    --===========================================
    -- Interrupt Synchronizer Process
    --===========================================
    -- Per Intel 8008 Rev 2 datasheet:
    -- Interrupts are synchronized with the leading edge of phi2
    -- The interrupt line must not change within 200ns of falling edge of phi1
    -- The interrupt is latched and cleared when acknowledged at T1I
    
    interrupt_sync: process(phi2)
    begin
        if rising_edge(phi2) then
            
            -- Detect rising edge of INT and latch the request
            if INT = '1' and int_previous = '0' then
                -- Clean rising edge of INT: latch the request
                int_pending <= '1';
                report "Interrupt: INT rising edge detected, setting int_pending";
            elsif timing_state = T3 and in_int_ack_cycle = '1' then
                -- Clear interrupt pending at T3 of interrupt ack cycle
                -- This is when external hardware provides the instruction
                int_pending <= '0';
                report "Interrupt: T3 of int ack cycle, clearing int_pending";
            end if;
            
            -- Store current INT value for next edge detection
            int_previous <= INT;
        end if;
    end process interrupt_sync;
    
    --===========================================
    -- SYNC Signal Generation
    --===========================================
    -- Per Intel 8008 datasheet:
    -- SYNC is phi2 divided by 2, with transitions on phi2 edges
    -- This is the master timing reference for the CPU
    
    -- SYNC generation process - toggles on EVERY phi2 edge (both rising and falling)
    sync_generation: process(phi2)
    begin
        if phi2'event then  -- Triggers on both rising and falling edges
            sync_reg <= not sync_reg;
        end if;
    end process sync_generation;
    
    -- SYNC output assignment
    SYNC <= sync_reg;
    
    --===========================================
    -- State Machine Process (Microcode-Driven)
    --===========================================
    -- This process executes microcode commands
    
    state_machine: process(phi1)
        variable next_state : timing_state_t;
        variable ucode : microcode_entry;
    begin
        if rising_edge(phi1) then
            report "State machine: Running, timing_state=" & timing_state_t'image(timing_state) &
                   ", phi1_sub=" & integer'image(phi1_sub);

            -- Store previous state (only on first sub-phase)
            if phi1_sub = 0 then
                timing_state_prev <= timing_state;

                -- Clear register control signals at start of each timing state
                reg_write_enable <= false;
                reg_read_enable <= false;
            end if;

            -- Default to current state
            next_state := timing_state;

            -- Special handling for STOPPED state (8008 has no reset, stays STOPPED until INT)
            if timing_state = STOPPED then
                if int_pending = '1' and phi1_sub = 0 then
                    -- Transition to T1I interrupt acknowledge (only on first sub-phase)
                    timing_state <= T1I;
                    in_int_ack_cycle <= '1';  -- Start interrupt acknowledge cycle
                    phi1_sub <= 0;  -- Keep sub-phase at 0 for T1I
                    report "Microcode: STOPPED -> T1I (interrupt), setting in_int_ack_cycle";
                    -- Don't execute microcode on transition from STOPPED to T1I
                elsif int_pending = '1' and phi1_sub = 1 then
                    -- Second sub-phase while waiting for interrupt - reset to first sub-phase
                    phi1_sub <= 0;
                elsif int_pending = '0' and phi1_sub = 1 then
                    -- Toggle sub-phase even when staying in STOPPED (for consistency)
                    phi1_sub <= 0;
                elsif int_pending = '0' and phi1_sub = 0 then
                    -- First sub-phase, no interrupt - advance to second sub-phase
                    phi1_sub <= 1;
                    report "Microcode: Staying in STOPPED, int_pending=" & std_logic'image(int_pending);
                end if;
            -- Normal operation: fetch and execute microcode for current state
            elsif timing_state /= STOPPED then
                report "State machine: Fetching microcode for state " & timing_state_t'image(timing_state) &
                       ", cycle=" & integer'image(current_cycle) &
                       ", sub_phase=" & integer'image(phi1_sub) &
                       ", instr=0x" & to_hstring(instruction_reg);
                ucode := get_microcode(instruction_reg, current_cycle, timing_state, phi1_sub, in_int_ack_cycle, data_bus_in, flags);
            
                -- Execute microcode commands
            
            -- Instruction register loading
            if ucode.load_ir then
                instruction_reg <= data_bus_in;
                report "Microcode: Loading instruction register with 0x" & to_hstring(data_bus_in);
            end if;
            
            -- Temporary register loading
            if ucode.load_temp_a then
                case ucode.temp_a_source is
                    when "00" =>
                        temp_a <= X"00";  -- Load zero
                        report "Microcode: Loading temp_a with 0x00";
                    when "01" =>
                        temp_a <= data_bus_in;  -- From data bus
                        report "Microcode: Loading temp_a from data_bus_in=0x" & to_hstring(unsigned(data_bus_in));
                    when "10" =>
                        temp_a <= internal_data_bus;  -- From internal data bus (register read)
                        report "Microcode: Loading temp_a from internal_data_bus=0x" & to_hstring(unsigned(internal_data_bus));
                    when others => null;
                end case;
            end if;
            
            if ucode.load_temp_b then
                case ucode.temp_b_source is
                    when "00" =>
                        temp_b <= X"00";  -- Load zero
                        report "Microcode: Loading temp_b with 0x00";
                    when "01" =>
                        temp_b <= data_bus_in;  -- From data bus (instruction)
                        report "Microcode: Loading temp_b from data_bus_in=0x" & to_hstring(unsigned(data_bus_in));
                    when "10" =>
                        temp_b <= internal_data_bus;  -- From internal data bus (register read)
                        report "Microcode: Loading temp_b from internal_data_bus=0x" & to_hstring(unsigned(internal_data_bus));
                    when others => null;
                end case;
            end if;

            -- PC control
            -- Suppress PC increment during interrupt ack cycle 0 (instruction injection)
            -- PC should only increment during normal fetches or subsequent cycles of injected instruction
            -- IMPORTANT: Only increment when advance_state is true (typically sub_phase=1) to avoid double increments
            if ucode.pc_inc and ucode.advance_state and not (in_int_ack_cycle = '1' and current_cycle = 0) then
                pc <= pc + 1;
                report "Microcode: PC INCREMENT from 0x" & to_hstring(pc) & " to 0x" & to_hstring(pc + 1) &
                       ", instr=0x" & to_hstring(instruction_reg) &
                       ", cycle=" & integer'image(current_cycle) &
                       ", state=" & timing_state_t'image(timing_state) &
                       ", sub_phase=" & integer'image(phi1_sub);
            end if;
            
            if ucode.pc_load_high then
                -- Load high 6 bits of PC from temp_a
                pc(13 downto 8) <= unsigned(temp_a(5 downto 0));
                report "Microcode: Loading PC high from temp_a: 0x" & to_hstring(temp_a(5 downto 0));
            end if;
            
            if ucode.pc_load_low then
                -- Check instruction type to determine how to load PC low byte
                if instruction_reg(7 downto 6) = "00" and instruction_reg(2 downto 0) = "101" then
                    -- RST instruction: extract vector from temp_b (instruction)
                    -- RST instruction format: 00 AAA 101
                    -- Vector address = 00 AAA 000 (AAA field shifted left by 3)
                    pc(7 downto 6) <= "00";
                    pc(5 downto 3) <= unsigned(temp_b(5 downto 3));  -- AAA field
                    pc(2 downto 0) <= "000";
                    report "Microcode: Loading PC low for RST, temp_b=0x" & to_hstring(temp_b) &
                           ", AAA bits: " &
                           std_logic'image(temp_b(5)) & std_logic'image(temp_b(4)) & std_logic'image(temp_b(3)) &
                           ", vector address: 0x00" & to_hstring(unsigned(temp_b(5 downto 3)) & "000");
                else
                    -- JMP/CAL/RET: load full 8-bit low address from temp_b
                    pc(7 downto 0) <= unsigned(temp_b);
                    report "Microcode: Loading PC low from temp_b: 0x" & to_hstring(temp_b);
                end if;
            end if;
            
            -- Stack control
            -- Only push/pop when advance_state is true to avoid double operations
            if ucode.stack_push and ucode.advance_state then
                -- Save current PC to stack and increment pointer
                address_stack(to_integer(stack_pointer)) <= pc;
                stack_pointer <= stack_pointer + 1;
                report "Microcode: Pushing PC to stack, SP: " & integer'image(to_integer(stack_pointer)) &
                       " -> " & integer'image(to_integer(stack_pointer + 1));
            end if;
            
            if ucode.stack_pop and ucode.advance_state then
                -- Decrement pointer and restore PC
                stack_pointer <= stack_pointer - 1;
                report "Microcode: Popping from stack, SP: " & integer'image(to_integer(stack_pointer)) &
                       " -> " & integer'image(to_integer(stack_pointer - 1));
                -- PC will be loaded from stack on next cycle
            end if;

            -- Register control
            if ucode.reg_write then
                -- Set register control signals for register_control process
                -- Note: Don't set internal_data_bus here due to cross-clock-domain issues
                -- The register_control process will select the source directly
                reg_select <= ucode.reg_target;
                reg_data_source <= ucode.reg_source;  -- Tell phi2 process which source to use
                reg_write_enable <= true;
                report "Microcode: Writing to register " & integer'image(to_integer(unsigned(ucode.reg_target))) &
                       " from source " & integer'image(to_integer(unsigned(ucode.reg_source)));
            end if;

            -- Flag update control (independent of register write)
            flags_update_enable <= ucode.flags_update;

            if ucode.reg_read then
                -- Read from register file to internal_data_bus
                reg_select <= ucode.reg_target;
                reg_read_enable <= true;
                report "Microcode: Reading from register " & integer'image(to_integer(unsigned(ucode.reg_target)));
            end if;

            -- ===========================================
            -- INTERRUPT ACKNOWLEDGE CYCLE
            -- ===========================================
            -- Per Intel 8008 datasheet:
            -- After completing instruction, if interrupt pending:
            -- - Goes to T1I state (interrupt acknowledge)
            -- - External hardware provides RST instruction
            -- - RST executes, jumping to interrupt vector
            
            -- ===========================================
            -- SUB-PHASE CONTROL & STATE ADVANCEMENT
            -- ===========================================
            -- Each timing state has TWO phi1 cycles (φ₁₁ and φ₁₂)
            -- Only advance to next state after BOTH sub-phases complete
            -- (when phi1_sub=1 AND advance_state=true)

            -- Get base next state from microcode
            next_state := ucode.next_state;

            -- Update instruction complete flag (only on second sub-phase)
            if phi1_sub = 1 then
                instruction_complete <= ucode.instruction_complete;
            end if;

            -- Check for cycle management (only on second sub-phase)
            if phi1_sub = 1 then
                report "Cycle management check: phi1_sub=1, new_cycle=" & boolean'image(ucode.new_cycle) & ", instr_complete=" & boolean'image(ucode.instruction_complete);
                if ucode.new_cycle then
                    current_cycle <= current_cycle + 1;
                    cycle_type <= ucode.next_cycle_type;
                    report "Cycle advance: " & integer'image(current_cycle) & " -> " & integer'image(current_cycle + 1) &
                           ", instr=0x" & to_hstring(instruction_reg) &
                           ", next_cycle_type=" & to_string(ucode.next_cycle_type);
                elsif ucode.instruction_complete then
                    current_cycle <= 0;
                    cycle_type <= ucode.next_cycle_type;  -- Reset to next cycle type (usually PCI)
                end if;
            end if;

            -- Override next_state for interrupt handling
            -- Only check at instruction boundaries (when instruction_complete = true)
            -- Check on second sub-phase only
            if phi1_sub = 1 and ucode.instruction_complete and int_pending = '1' and timing_state /= STOPPED then
                -- Instruction just completed and interrupt is pending
                next_state := T1I;  -- Start interrupt acknowledge cycle
                in_int_ack_cycle <= '1';  -- Mark start of interrupt ack cycle
                report "Interrupt: Instruction complete, starting interrupt acknowledge";
            elsif phi1_sub = 1 and ucode.instruction_complete and in_int_ack_cycle = '1' then
                -- Interrupt acknowledge cycle complete, clear flag
                in_int_ack_cycle <= '0';
                report "Interrupt: Int ack instruction complete, clearing in_int_ack_cycle";
            end if;

            -- Handle WAIT states (only on second sub-phase)
            if phi1_sub = 1 then
                if next_state = T2 and READY = '0' then
                    next_state := TWAIT;
                elsif next_state = TWAIT and READY = '1' then
                    next_state := T3;
                end if;
            end if;

            end if;  -- End of STOPPED/normal operation check

            -- ===========================================
            -- STATE ADVANCEMENT LOGIC
            -- ===========================================
            -- Advance state only when:
            --   1. advance_state flag is true, AND
            --   2. We're at second sub-phase (phi1_sub=1)
            -- Otherwise, stay in current state and toggle sub-phase
            -- NOTE: STOPPED state handles its own phi1_sub and timing_state updates above

            if timing_state /= STOPPED then
                if phi1_sub = 0 then
                    -- First sub-phase (φ₁₁): Stay in current state, advance to second sub-phase
                    phi1_sub <= 1;
                    timing_state <= timing_state;  -- Stay in same state
                    report "State machine: phi1_sub 0->1, staying in state " & timing_state_t'image(timing_state);
                elsif phi1_sub = 1 and ucode.advance_state then
                    -- Second sub-phase (φ₁₂) with advance_state=true: Advance to next state, reset sub-phase
                    phi1_sub <= 0;
                    timing_state <= next_state;
                    report "State machine: phi1_sub 1->0, advancing to state " & timing_state_t'image(next_state);
                elsif phi1_sub = 1 and not ucode.advance_state then
                    -- Second sub-phase (φ₁₂) with advance_state=false: Stay in state, reset sub-phase
                    -- This allows instructions to use both sub-phases of a single timing state
                    phi1_sub <= 0;
                    timing_state <= timing_state;  -- Stay in same state
                    report "State machine: phi1_sub 1->0, staying in state (advance_state=false) " &
                           timing_state_t'image(timing_state);
                end if;
            end if;
        end if;
    end process state_machine;
    
    --===========================================
    -- Register File Access and H:L Addressing
    --===========================================
    -- Handles register read/write operations and H:L indirect addressing
    
    register_control: process(phi2)
        variable write_data : std_logic_vector(7 downto 0);
    begin
        if rising_edge(phi2) then
            report "Register Control: phi2_sub=" & integer'image(phi2_sub);

            -- Toggle phi2_sub: 0->1->0
            if phi2_sub = 0 then
                phi2_sub <= 1;
            else
                phi2_sub <= 0;
            end if;

            -- H:L address combination (H provides high 6 bits, L provides low 8 bits)
            -- Bits 7-6 of H are ignored (don't cares) for 14-bit addressing
            -- Update on both sub-phases (always needed)
            hl_address <= registers(REG_H_DATA)(5 downto 0) & registers(REG_L_DATA);

            -- Check if accessing memory through M register
            -- Update on both sub-phases (always needed)
            memory_reference <= (reg_select = REG_M);

            -- ALU operations: put temp_b (memory/register operand) on internal_data_bus FIRST
            -- This must happen BEFORE register write logic so ALU sees correct operand
            -- (works for both reg_write=true and CMP with reg_write=false)
            -- Do this early (phi2_sub=0) so ALU has operand ready
            if phi2_sub = 0 and ((instruction_reg(7 downto 6) = "10") or
                                 (instruction_reg(7 downto 6) = "00" and instruction_reg(2 downto 0) = "100"))
                             and reg_data_source = "10" then
                -- ALU operation (register/memory or immediate): temp_b contains the operand
                internal_data_bus <= temp_b;
                report "Register Control (phi2): Putting temp_b (0x" & to_hstring(temp_b) &
                       ") on internal_data_bus for ALU operation";
            end if;

            -- ===========================================
            -- REGISTER WRITE (φ₂₂ - second sub-phase)
            -- ===========================================
            -- Per Intel 8008 timing: register writes happen at φ₂₂
            -- After toggle above: when phi2_sub WAS 0 and became 1, that's φ₂₁
            -- When phi2_sub WAS 1 and becomes 0, that's φ₂₂ (next phi2 rising edge)
            -- So writes happen when phi2_sub=1 BEFORE toggle (check current value at start of process)

            if phi2_sub = 1 and reg_write_enable and not memory_reference then
                -- Select data source based on reg_data_source
                -- Use a variable to avoid delta-cycle issues
                case reg_data_source is
                    when "00" =>  -- Zero
                        write_data := (others => '0');
                    when "01" =>  -- data_bus_in
                        write_data := data_bus_in;
                    when "10" =>  -- temp_a OR ALU result (for ALU operations)
                        -- Check if this is an ALU operation or rotate
                        -- CLASS_10: 10 PPP SSS (ALU register/memory)
                        -- CLASS_00: 00 FFF 100 (ALU immediate)
                        -- CLASS_00: 00 DDD 000 (INR - increment register, DDD ≠ 000)
                        -- CLASS_00: 00 DDD 001 (DCR - decrement register, DDD ≠ 000)
                        -- CLASS_00: 00 FFF 010 (ROTATE - RLC, RRC, RAL, RAR, FFF = 000-011)
                        if (instruction_reg(7 downto 6) = "10") or
                           (instruction_reg(7 downto 6) = "00" and instruction_reg(2 downto 0) = "100") or
                           (instruction_reg(7 downto 6) = "00" and instruction_reg(2 downto 0) = "000" and instruction_reg(5 downto 3) /= "000") or
                           (instruction_reg(7 downto 6) = "00" and instruction_reg(2 downto 0) = "001" and instruction_reg(5 downto 3) /= "000") or
                           (instruction_reg(7 downto 6) = "00" and instruction_reg(2 downto 0) = "010" and instruction_reg(5 downto 4) = "00") then
                            -- ALU/Rotate operation: use ALU result (bits 7:0, bit 8 is carry)
                            -- For rotate instructions, compute result here based on FFF field
                            if instruction_reg(7 downto 6) = "00" and instruction_reg(2 downto 0) = "010" and instruction_reg(5 downto 4) = "00" then
                                -- Rotate instruction: compute rotation
                                case instruction_reg(4 downto 3) is
                                    when "00" =>  -- RLC: Rotate left circular
                                        write_data := internal_data_bus(6 downto 0) & internal_data_bus(7);
                                    when "01" =>  -- RRC: Rotate right circular
                                        write_data := internal_data_bus(0) & internal_data_bus(7 downto 1);
                                    when "10" =>  -- RAL: Rotate left through carry
                                        write_data := internal_data_bus(6 downto 0) & flag_carry;
                                    when "11" =>  -- RAR: Rotate right through carry
                                        write_data := flag_carry & internal_data_bus(7 downto 1);
                                    when others =>
                                        write_data := internal_data_bus;
                                end case;
                                report "Register Control (phi2): Using rotate result 0x" & to_hstring(write_data);
                            else
                                -- ALU operation: use ALU result (bits 7:0, bit 8 is carry)
                                write_data := alu_result(7 downto 0);
                                report "Register Control (phi2): Using ALU result 0x" & to_hstring(alu_result(7 downto 0));
                            end if;
                        else
                            -- Non-ALU operation: use temp_a
                            write_data := temp_a;
                        end if;
                    when "11" =>  -- temp_b
                        write_data := temp_b;
                    when others =>
                        write_data := (others => '0');
                end case;

                -- Write to selected register
                case reg_select is
                    when REG_A =>
                        registers(REG_A_DATA) <= write_data;
                        report "Register Control (phi2): Writing 0x" & to_hstring(write_data) & " to accumulator (source=" &
                               integer'image(to_integer(unsigned(reg_data_source))) & ", temp_b=0x" & to_hstring(temp_b) & ")";
                    when REG_B =>
                        registers(REG_B_DATA) <= write_data;
                        report "Register Control (phi2): Writing 0x" & to_hstring(write_data) & " to REG_B (source=" &
                               integer'image(to_integer(unsigned(reg_data_source))) & ", temp_b=0x" & to_hstring(temp_b) & ")";
                    when REG_C =>
                        registers(REG_C_DATA) <= write_data;
                        report "Register Control (phi2): Writing 0x" & to_hstring(write_data) & " to REG_C";
                    when REG_D =>
                        registers(REG_D_DATA) <= write_data;
                        report "Register Control (phi2): Writing 0x" & to_hstring(write_data) & " to REG_D";
                    when REG_E =>
                        registers(REG_E_DATA) <= write_data;
                        report "Register Control (phi2): Writing 0x" & to_hstring(write_data) & " to REG_E";
                    when REG_H =>
                        registers(REG_H_DATA) <= write_data;
                        report "Register Control (phi2): Writing 0x" & to_hstring(write_data) & " to REG_H";
                    when REG_L =>
                        registers(REG_L_DATA) <= write_data;
                        report "Register Control (phi2): Writing 0x" & to_hstring(write_data) & " to REG_L";
                    when others => null;  -- REG_M handled separately
                end case;

                -- Also update internal_data_bus for other uses
                internal_data_bus <= write_data;
            end if;

            -- ===========================================
            -- REGISTER READ (φ₂₁ - first sub-phase)
            -- ===========================================
            -- Per Intel 8008 timing: register reads happen at φ₂₁
            -- This puts register value on internal_data_bus for use in next sub-phase
            if phi2_sub = 0 and reg_read_enable and not memory_reference then
                -- Direct register read
                case reg_select is
                    when REG_A =>
                        internal_data_bus <= registers(REG_A_DATA);
                        report "Register Control (phi2_sub=0): Read reg A = 0x" & to_hstring(registers(REG_A_DATA));
                    when REG_B =>
                        internal_data_bus <= registers(REG_B_DATA);
                        report "Register Control (phi2_sub=0): Read reg B = 0x" & to_hstring(registers(REG_B_DATA));
                    when REG_C =>
                        internal_data_bus <= registers(REG_C_DATA);
                        report "Register Control (phi2_sub=0): Read reg C = 0x" & to_hstring(registers(REG_C_DATA));
                    when REG_D =>
                        internal_data_bus <= registers(REG_D_DATA);
                        report "Register Control (phi2_sub=0): Read reg D = 0x" & to_hstring(registers(REG_D_DATA));
                    when REG_E =>
                        internal_data_bus <= registers(REG_E_DATA);
                        report "Register Control (phi2_sub=0): Read reg E = 0x" & to_hstring(registers(REG_E_DATA));
                    when REG_H =>
                        internal_data_bus <= registers(REG_H_DATA);
                        report "Register Control (phi2_sub=0): Read reg H = 0x" & to_hstring(registers(REG_H_DATA));
                    when REG_L =>
                        internal_data_bus <= registers(REG_L_DATA);
                        report "Register Control (phi2_sub=0): Read reg L = 0x" & to_hstring(registers(REG_L_DATA));
                    when others => null;  -- REG_M handled separately
                end case;
            end if;

            -- ALU flag updates (only when microcode explicitly signals)
            -- Flags should only be updated in Cycle 1 T5 for ALU immediate ops
            -- and in T5 for ALU register/memory ops
            -- INR/DCR: Update S, Z, P but NOT C (carry preserved)
            -- ROTATE: Update C only, preserve S, Z, P
            if flags_update_enable then
                -- Check if this is a rotate instruction
                if instruction_reg(7 downto 6) = "00" and instruction_reg(2 downto 0) = "010" and instruction_reg(5) = '0' then
                    -- ROTATE: Only update carry flag based on which bit rotated out
                    case instruction_reg(4 downto 3) is
                        when "00" =>  -- RLC: Bit 7 rotated out
                            flags(3) <= internal_data_bus(7);
                        when "01" =>  -- RRC: Bit 0 rotated out
                            flags(3) <= internal_data_bus(0);
                        when "10" =>  -- RAL: Bit 7 rotated out
                            flags(3) <= internal_data_bus(7);
                        when "11" =>  -- RAR: Bit 0 rotated out
                            flags(3) <= internal_data_bus(0);
                        when others =>
                            null;
                    end case;
                    report "Register Control (phi2): Updated ROTATE carry flag - C=" & std_logic'image(flags(3)) &
                           " from internal_data_bus=0x" & to_hstring(internal_data_bus);
                else
                    -- Carry flag: Update for normal ALU ops, preserve for INR/DCR
                    if not ((instruction_reg(7 downto 6) = "00" and instruction_reg(2 downto 0) = "000" and instruction_reg(5 downto 3) /= "000") or
                            (instruction_reg(7 downto 6) = "00" and instruction_reg(2 downto 0) = "001" and instruction_reg(5 downto 3) /= "000")) then
                        flags(3) <= alu_result(8);  -- Carry flag (normal ALU ops)
                    end if;
                    -- Zero, Sign, Parity: Always update
                    flags(2) <= '1' when alu_result(7 downto 0) = x"00" else '0';  -- Zero flag
                    flags(1) <= alu_result(7);  -- Sign flag
                    -- Parity: even parity (1 if even number of 1 bits)
                    flags(0) <= not (alu_result(0) xor alu_result(1) xor alu_result(2) xor alu_result(3) xor
                                     alu_result(4) xor alu_result(5) xor alu_result(6) xor alu_result(7));
                    report "Register Control (phi2): Updated flags - C=" & std_logic'image(flags(3)) &
                           ", Z=" & std_logic'image(flags(2)) &
                           ", S=" & std_logic'image(alu_result(7)) &
                           ", P=" & std_logic'image(flags(0));
                end if;
            end if;

            -- Memory reference through H:L requires external memory access
            -- This will be handled by memory controller using hl_address
        end if;
    end process register_control;
    
    -- ALU data_0: Accumulator for most operations, register value for INR/DCR
    alu_data_0 <= internal_data_bus when ((instruction_reg(7 downto 6) = "00" and instruction_reg(2 downto 0) = "000" and instruction_reg(5 downto 3) /= "000") or
                                          (instruction_reg(7 downto 6) = "00" and instruction_reg(2 downto 0) = "001" and instruction_reg(5 downto 3) /= "000"))
                  else registers(REG_A_DATA);  -- Accumulator is default first ALU operand
    
    --===========================================
    -- State Output Generation
    --===========================================
    -- CRITICAL NOTE ON BIT ORDERING:
    -- Intel 8008 datasheet uses S0 S1 S2 ordering (LSB first)
    -- Our VHDL signals are named S0, S1, S2 matching the datasheet
    -- But we often concatenate as S2 & S1 & S0 for MSB-first notation
    --
    -- State encodings (both notations shown):
    --   State    | S0 S1 S2 (datasheet) | S2 S1 S0 (concatenated)
    --   ---------|----------------------|------------------------
    --   T1       | 0  1  0              | 0  1  0
    --   T1I      | 0  1  1              | 1  1  0  (interrupt ack)
    --   T2       | 0  0  1              | 1  0  0
    --   WAIT     | 0  0  0              | 0  0  0
    --   T3       | 1  0  0              | 0  0  1
    --   STOPPED  | 1  1  0              | 0  1  1
    --   T4       | 1  1  1              | 1  1  1
    --   T5       | 1  0  1              | 1  0  1
    --
    -- Per Intel 8008 datasheet state encoding
    process(timing_state)
    begin
        case timing_state is
            when T1      => S0 <= '0'; S1 <= '1'; S2 <= '0';  -- S0S1S2=010, S2S1S0=010
            when T1I     => S0 <= '0'; S1 <= '1'; S2 <= '1';  -- S0S1S2=011, S2S1S0=110
            when T2      => S0 <= '0'; S1 <= '0'; S2 <= '1';  -- S0S1S2=001, S2S1S0=100
            when TWAIT   => S0 <= '0'; S1 <= '0'; S2 <= '0';  -- S0S1S2=000, S2S1S0=000
            when T3      => S0 <= '1'; S1 <= '0'; S2 <= '0';  -- S0S1S2=100, S2S1S0=001
            when STOPPED => S0 <= '1'; S1 <= '1'; S2 <= '0';  -- S0S1S2=110, S2S1S0=011
            when T4      => S0 <= '1'; S1 <= '1'; S2 <= '1';  -- S0S1S2=111, S2S1S0=111
            when T5      => S0 <= '1'; S1 <= '0'; S2 <= '1';  -- S0S1S2=101, S2S1S0=101
        end case;
    end process;
    
    --===========================================
    -- Data Bus Output Control
    --===========================================
    -- Output appropriate data based on state and cycle type
    data_bus_output: process(timing_state, pc, cycle_type, current_cycle, instruction_reg,
                           hl_address, temp_a, temp_b, registers)
    begin
        -- Debug: Log when we're in Cycle 1
        if current_cycle = 1 and (timing_state = T1 or timing_state = T2) then
            report "data_bus_output: cycle=" & integer'image(current_cycle) &
                   ", cycle_type=" & to_string(cycle_type) &
                   ", instr=" & to_hstring(instruction_reg);
        end if;

        case timing_state is
            when T1 | T1I =>
                -- T1/T1I: Output lower 8 bits of address
                -- Special case: INP/OUT instruction Cycle 1 T1 outputs accumulator
                if current_cycle = 1 and cycle_type = CYCLE_PCC and
                   (instruction_reg(7 downto 6) = "01" and
                    instruction_reg(5 downto 4) = "00" and
                    instruction_reg(0) = '1') then  -- INP instruction
                    -- Output accumulator value for I/O cycle
                    data_bus_out <= registers(REG_A_DATA);
                elsif current_cycle = 1 and cycle_type = CYCLE_PCC and
                   (instruction_reg(7 downto 6) = "01" and
                    instruction_reg(0) = '1' and
                    instruction_reg(5 downto 4) /= "00") then  -- OUT instruction
                    -- Output accumulator value for I/O write cycle
                    report "data_bus_output T1: OUT detected! cycle=" & integer'image(current_cycle) &
                           ", cycle_type=" & to_string(cycle_type) & ", instr=" & to_hstring(instruction_reg) &
                           ", A=" & to_hstring(registers(REG_A_DATA));
                    data_bus_out <= registers(REG_A_DATA);
                -- Check if this is a memory write cycle for MVI M
                elsif current_cycle = 2 and instruction_reg = "00111110" then
                    -- Output L register (low byte of HL address)
                    data_bus_out <= registers(REG_L_DATA);
                -- Check if this is a memory read cycle for LrM (MOV r,M)
                elsif current_cycle = 1 and cycle_type = CYCLE_PCR and
                   instruction_reg(7 downto 6) = "11" and
                   instruction_reg(2 downto 0) = "111" then  -- LrM: 11 DDD 111
                    -- Output L register (low byte of HL address)
                    data_bus_out <= registers(REG_L_DATA);
                -- Check if this is a memory write cycle for LMr (MOV M,r)
                elsif current_cycle = 1 and cycle_type = CYCLE_PCW and
                   instruction_reg(7 downto 6) = "11" and
                   instruction_reg(5 downto 3) = "111" then  -- LMr: 11 111 SSS
                    -- Output L register (low byte of HL address)
                    data_bus_out <= registers(REG_L_DATA);
                else
                    -- Normal PC output
                    data_bus_out <= std_logic_vector(pc(7 downto 0));
                end if;
                data_bus_enable <= '1';
                
            when T2 =>
                -- T2: Output cycle type (D7:D6) and upper address (D5:D0)
                -- Special case: INP/OUT instruction Cycle 1 T2 outputs instruction (for I/O decode)
                if current_cycle = 1 and cycle_type = CYCLE_PCC and
                   (instruction_reg(7 downto 6) = "01" and
                    instruction_reg(5 downto 4) = "00" and
                    instruction_reg(0) = '1') then  -- INP instruction
                    -- Output instruction from temp_b (contains INP opcode with MMM bits)
                    data_bus_out <= temp_b;
                elsif current_cycle = 1 and cycle_type = CYCLE_PCC and
                   (instruction_reg(7 downto 6) = "01" and
                    instruction_reg(0) = '1' and
                    instruction_reg(5 downto 4) /= "00") then  -- OUT instruction
                    -- Output instruction from temp_b (contains OUT opcode with RRMMM bits [5:1])
                    report "data_bus_output T2: OUT detected! cycle=" & integer'image(current_cycle) &
                           ", cycle_type=" & to_string(cycle_type) & ", instr=" & to_hstring(instruction_reg) &
                           ", temp_b=" & to_hstring(temp_b);
                    data_bus_out <= temp_b;
                -- Check if this is a memory write cycle for MVI M
                elsif current_cycle = 2 and instruction_reg = "00111110" then
                    -- Output cycle type PCW and H register (high byte of HL address)
                    data_bus_out <= CYCLE_PCW & registers(REG_H_DATA)(5 downto 0);
                -- Check if this is a memory read cycle for LrM (MOV r,M)
                elsif current_cycle = 1 and cycle_type = CYCLE_PCR and
                   instruction_reg(7 downto 6) = "11" and
                   instruction_reg(2 downto 0) = "111" then  -- LrM: 11 DDD 111
                    -- Output cycle type PCR and H register (high byte of HL address)
                    data_bus_out <= CYCLE_PCR & registers(REG_H_DATA)(5 downto 0);
                -- Check if this is a memory write cycle for LMr (MOV M,r)
                elsif current_cycle = 1 and cycle_type = CYCLE_PCW and
                   instruction_reg(7 downto 6) = "11" and
                   instruction_reg(5 downto 3) = "111" then  -- LMr: 11 111 SSS
                    -- Output cycle type PCW and H register (high byte of HL address)
                    data_bus_out <= CYCLE_PCW & registers(REG_H_DATA)(5 downto 0);
                else
                    -- Normal PC output with cycle type
                    data_bus_out <= cycle_type & std_logic_vector(pc(13 downto 8));
                end if;
                data_bus_enable <= '1';
                
            when T3 =>
                -- T3: Data transfer
                if cycle_type = CYCLE_PCI then
                    -- Instruction/data fetch - we read, don't drive
                    data_bus_enable <= '0';
                    data_bus_out <= (others => '0');
                elsif cycle_type = CYCLE_PCC then
                    -- I/O read - tristate (external I/O provides data)
                    data_bus_enable <= '0';
                    data_bus_out <= (others => '0');
                elsif cycle_type = CYCLE_PCW and current_cycle = 2 and instruction_reg = "00111110" then
                    -- MVI M memory write - output immediate data from temp_a
                    data_bus_out <= temp_a;
                    data_bus_enable <= '1';
                elsif cycle_type = CYCLE_PCW and current_cycle = 1 and
                      instruction_reg(7 downto 6) = "11" and instruction_reg(5 downto 3) = "111" then
                    -- LMr (MOV M,r) memory write - output register data from temp_b
                    data_bus_out <= temp_b;
                    data_bus_enable <= '1';
                else
                    -- Default: don't drive
                    data_bus_enable <= '0';
                    data_bus_out <= (others => '0');
                end if;

            when T4 =>
                -- T4: Output flags for INP instruction
                if current_cycle = 1 and cycle_type = CYCLE_PCC and
                   (instruction_reg(7 downto 6) = "01" and
                    instruction_reg(5 downto 4) = "00" and
                    instruction_reg(0) = '1') then  -- INP instruction
                    -- Output flags: S→D0, Z→D1, P→D2, C→D3
                    -- Upper 4 bits are zero
                    data_bus_out <= "0000" & flags;
                    data_bus_enable <= '1';
                else
                    -- Default: don't drive bus
                    data_bus_out <= (others => '0');
                    data_bus_enable <= '0';
                end if;

            when T5 =>
                -- T5: Internal data transfer, don't drive external bus
                data_bus_out <= (others => '0');
                data_bus_enable <= '0';

            when others =>
                -- TWAIT, STOPPED: Don't drive bus
                data_bus_out <= (others => '0');
                data_bus_enable <= '0';
        end case;
    end process data_bus_output;
    
    -- Debug outputs - connect to actual internal signals
    debug_reg_A <= registers(REG_A_DATA);
    debug_reg_B <= registers(REG_B_DATA);
    debug_reg_C <= registers(REG_C_DATA);
    debug_reg_D <= registers(REG_D_DATA);
    debug_reg_E <= registers(REG_E_DATA);
    debug_reg_H <= registers(REG_H_DATA);
    debug_reg_L <= registers(REG_L_DATA);
    debug_pc    <= std_logic_vector(pc);
    debug_flags <= flags;
    debug_instruction <= instruction_reg;
    debug_stack_pointer <= std_logic_vector(stack_pointer);
    debug_hl_address <= hl_address;

    -- ALU inputs
    -- alu_data_0 set above (accumulator or register value for INR/DCR)
    -- alu_data_1: For ALU operations, directly use temp_b to avoid timing issues
    --   Class 10 (ALU register/memory): temp_b contains register or memory operand
    --   Class 00 with x100 (ALU immediate): temp_b contains immediate operand
    --   INR/DCR: constant 1
    alu_data_1  <= x"01" when ((instruction_reg(7 downto 6) = "00" and instruction_reg(2 downto 0) = "000" and instruction_reg(5 downto 3) /= "000") or
                               (instruction_reg(7 downto 6) = "00" and instruction_reg(2 downto 0) = "001" and instruction_reg(5 downto 3) /= "000"))
                   else temp_b when ((instruction_reg(7 downto 6) = "10" and reg_data_source = "10") or
                                     (instruction_reg(7 downto 6) = "00" and instruction_reg(2 downto 0) = "100" and reg_data_source = "10"))
                   else internal_data_bus;  -- Second operand from selected register or memory

    -- alu_command: FFF/PPP field for normal ALU ops, special for INR/DCR
    --   INR (00 DDD 000): Use ADD operation (000)
    --   DCR (00 DDD 001): Use SUB operation (010)
    alu_command <= "000" when (instruction_reg(7 downto 6) = "00" and instruction_reg(2 downto 0) = "000" and instruction_reg(5 downto 3) /= "000")  -- INR: ADD
                   else "010" when (instruction_reg(7 downto 6) = "00" and instruction_reg(2 downto 0) = "001" and instruction_reg(5 downto 3) /= "000")  -- DCR: SUB
                   else instruction_reg(5 downto 3);  -- Normal: FFF/PPP field

    flag_carry  <= flag_c;             -- Current carry flag state

end rtl;

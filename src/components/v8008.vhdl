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
    
    --===========================================
    -- Microcode Architecture
    --===========================================
    -- Each instruction's behavior is explicitly defined for each state
    type microcode_entry is record
        -- State control
        next_state          : timing_state_t;
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
        
        -- Next cycle type (for T2 output)
        next_cycle_type     : std_logic_vector(1 downto 0);
    end record;
    
    -- Default microcode entry (safe do-nothing)  
    constant DEFAULT_UCODE : microcode_entry := (
        next_state => T1,  -- Will be overridden for STOPPED state
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
        next_cycle_type => CYCLE_PCI
    );
    
    -- Current microcode being executed (moved to process as variable)
    
    --===========================================
    -- Microcode Lookup Function
    --===========================================
    -- Returns the microcode for a given instruction, cycle, and state
    function get_microcode(
        instr : std_logic_vector(7 downto 0);
        cycle : integer;
        state : timing_state_t;
        int_ack : std_logic;
        data_in : std_logic_vector(7 downto 0)  -- For T3 instruction fetch
    ) return microcode_entry is
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
                        next_cycle_type => CYCLE_PCI
                    );
                    
                when T1 =>
                    -- Generic T1 for ALL instructions: PCL OUT
                    return (
                        next_state => T2,
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
                        next_cycle_type => CYCLE_PCI
                    );
                    
                when T2 =>
                    -- Generic T2 for ALL instructions: PCH OUT
                    -- Same for both normal fetch and interrupt acknowledge
                    return (
                        next_state => T3,
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
                        next_cycle_type => CYCLE_PCI
                    );
                    
                when T3 =>
                    -- Generic T3: Fetch instruction to IR and Reg.b
                    -- Then decode and determine next state
                    
                    -- ========== HLT (HALT) ==========
                    if data_in = x"00" or data_in = x"FF" then
                        -- HLT: Cycle ends at T3, instruction complete
                        -- Special case: Go to STOPPED (not T1/T1I)
                        return (
                            next_state => STOPPED,
                            new_cycle => false,
                            instruction_complete => true,   -- HLT is complete
                            load_ir => true,
                            load_temp_a => false,
                            load_temp_b => false,
                            temp_a_source => "00",
                            temp_b_source => "00",
                            pc_inc => false,  -- Don't increment PC for HLT
                            pc_load_high => false,
                            pc_load_low => false,
                            stack_push => false,
                            stack_pop => false,
                            next_cycle_type => CYCLE_PCI
                        );
                        
                    -- ========== RST (RESTART) ==========
                    elsif (data_in(7 downto 6) = "00" and data_in(2 downto 0) = "101") then
                        -- RST: Cycle continues to T4 (needs T4 and T5)
                        return (
                            next_state => T4,               -- Continue to T4
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
                            next_cycle_type => CYCLE_PCI
                        );
                        
                    -- ========== ADD MORE INSTRUCTIONS HERE ==========
                    -- Template for 3-state instruction (ends at T3):
                    -- elsif (data_in matches pattern) then
                    --     return (
                    --         next_state => T1,  -- Will be overridden by interrupt logic
                    --         instruction_complete => true/false,  -- Is whole instruction done?
                    --         ... other control signals ...
                    --     );
                    
                    -- Template for 5-state instruction (continues to T4):
                    -- elsif (data_in matches pattern) then
                    --     return (
                    --         next_state => T4,
                    --         instruction_complete => false,  -- Not done yet
                    --         ... other control signals ...
                    --     );
                        
                    else
                        -- DEFAULT: Unknown instructions treated as NOP
                        -- Cycle ends at T3, instruction complete
                        return (
                            next_state => T1,  -- Will be overridden by interrupt logic
                            new_cycle => false,
                            instruction_complete => true,   -- Single cycle instruction
                            load_ir => true,
                            load_temp_a => false,
                            load_temp_b => false,
                            temp_a_source => "00",
                            temp_b_source => "00",
                            pc_inc => true,                -- Increment PC for next instruction
                            pc_load_high => false,
                            pc_load_low => false,
                            stack_push => false,
                            stack_pop => false,
                            next_cycle_type => CYCLE_PCI
                        );
                    end if;
                    
                when T4 =>
                    -- T4: Instruction-specific behavior
                    -- Only reached if instruction needs more than 3 states
                    
                    -- ========== RST (RESTART) ==========
                    if (instr(7 downto 6) = "00" and instr(2 downto 0) = "101") then
                        -- RST T4: Load PC high, continue to T5
                        return (
                            next_state => T5,               -- Continue to T5
                            new_cycle => false,
                            instruction_complete => false,   -- Not complete yet
                            load_ir => false,
                            load_temp_a => false,
                            load_temp_b => false,
                            temp_a_source => "00",
                            temp_b_source => "00",
                            pc_inc => false,
                            pc_load_high => true,      -- PC(13:8) = temp_a(5:0)
                            pc_load_low => false,
                            stack_push => false,
                            stack_pop => false,
                            next_cycle_type => CYCLE_PCI
                        );
                        
                    -- ========== ADD MORE INSTRUCTIONS HERE ==========
                    -- Template for instruction ending at T4:
                    -- elsif (instr matches pattern) then
                    --     return (
                    --         next_state => T1,  -- Will be overridden by interrupt logic
                    --         instruction_complete => true/false,
                    --         ... other control signals ...
                    --     );
                    
                    -- Template for instruction continuing to T5:
                    -- elsif (instr matches pattern) then
                    --     return (
                    --         next_state => T5,
                    --         instruction_complete => false,
                    --         ... other control signals ...
                    --     );
                        
                    else
                        -- Should not reach here - only instructions that need T4 should get here
                        return DEFAULT_UCODE;
                    end if;
                    
                when T5 =>
                    -- T5: Final state for 5-state instructions
                    -- Cycle ALWAYS ends at T5
                    
                    -- ========== RST (RESTART) ==========
                    if (instr(7 downto 6) = "00" and instr(2 downto 0) = "101") then
                        -- RST T5: Load PC low, instruction complete
                        return (
                            next_state => T1,               -- Will be overridden by interrupt logic
                            new_cycle => false,
                            instruction_complete => true,    -- RST is complete
                            load_ir => false,
                            load_temp_a => false,
                            load_temp_b => false,
                            temp_a_source => "00",
                            temp_b_source => "00",
                            pc_inc => false,
                            pc_load_high => false,
                            pc_load_low => true,       -- PC(7:0) = RST vector
                            stack_push => false,
                            stack_pop => false,
                            next_cycle_type => CYCLE_PCI
                        );
                        
                    -- ========== ADD MORE INSTRUCTIONS HERE ==========
                    -- Template for any instruction reaching T5:
                    -- elsif (instr matches pattern) then
                    --     return (
                    --         next_state => T1,  -- Will be overridden by interrupt logic
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
        elsif cycle = 1 and int_ack = '0' then
            -- Instruction-specific behavior for cycle 1
            -- TODO: Add multi-cycle instruction handlers here
            case state is
                when T1 =>
                    -- Cycle 1 T1 - instruction specific
                    return DEFAULT_UCODE;  -- TODO: implement
                    
                when T2 =>
                    -- Cycle 1 T2 - instruction specific
                    return DEFAULT_UCODE;  -- TODO: implement
                    
                when T3 =>
                    -- Cycle 1 T3 - instruction specific
                    return DEFAULT_UCODE;  -- TODO: implement
                    
                when T4 =>
                    -- Cycle 1 T4 - instruction specific
                    return DEFAULT_UCODE;  -- TODO: implement
                    
                when T5 =>
                    -- Cycle 1 T5 - instruction specific
                    return DEFAULT_UCODE;  -- TODO: implement
                    
                when others =>
                    return DEFAULT_UCODE;
            end case;
            
        -- ===========================================
        -- CYCLE 2: Third machine cycle
        -- ===========================================
        elsif cycle = 2 and int_ack = '0' then
            -- Instruction-specific behavior for cycle 2
            -- TODO: Add 3-cycle instruction handlers here
            case state is
                when T1 =>
                    -- Cycle 2 T1 - instruction specific
                    return DEFAULT_UCODE;  -- TODO: implement
                    
                when T2 =>
                    -- Cycle 2 T2 - instruction specific
                    return DEFAULT_UCODE;  -- TODO: implement
                    
                when T3 =>
                    -- Cycle 2 T3 - instruction specific
                    return DEFAULT_UCODE;  -- TODO: implement
                    
                when T4 =>
                    -- Cycle 2 T4 - instruction specific
                    return DEFAULT_UCODE;  -- TODO: implement
                    
                when T5 =>
                    -- Cycle 2 T5 - instruction specific
                    return DEFAULT_UCODE;  -- TODO: implement
                    
                when others =>
                    return DEFAULT_UCODE;
            end case;

        -- Default case for unimplemented instructions
        else
            return DEFAULT_UCODE;
        end if;
    end function;
    
    -- Control signals from microcode
    signal fetch_instruction : boolean := false;
    signal decode_instruction : boolean := false;
    signal execute_instruction : boolean := false;
    
    -- Cycle and instruction tracking
    signal cycle_complete : boolean := false;      -- True when current machine cycle ends (T3 or T5)
    signal instruction_complete : boolean := true; -- True when entire instruction finishes
    signal cycles_in_instruction : integer := 1;   -- How many cycles this instruction needs
    
    -- Register control signals
    signal reg_write_enable : boolean := false;
    signal reg_read_enable : boolean := false;
    signal reg_select : std_logic_vector(2 downto 0) := "000";  -- Which register to access
    
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
            report "State machine: Running, timing_state=" & timing_state_t'image(timing_state);
            -- Store previous state
            timing_state_prev <= timing_state;
            
            -- Default to current state
            next_state := timing_state;
            
            -- Special handling for STOPPED state (8008 has no reset, stays STOPPED until INT)
            if timing_state = STOPPED then
                if int_pending = '1' then
                    next_state := T1I;
                    in_int_ack_cycle <= '1';  -- Start interrupt acknowledge cycle
                    report "Microcode: STOPPED -> T1I (interrupt), setting in_int_ack_cycle";
                    -- Don't execute microcode on transition from STOPPED to T1I
                else
                    -- Stay in STOPPED
                    report "Microcode: Staying in STOPPED, int_pending=" & std_logic'image(int_pending);
                end if;
            -- Normal operation: fetch and execute microcode for current state
            else
                report "State machine: Fetching microcode for state " & timing_state_t'image(timing_state);
                ucode := get_microcode(instruction_reg, current_cycle, timing_state, in_int_ack_cycle, data_bus_in);
            
                -- Execute microcode commands
            
            -- Instruction register loading
            if ucode.load_ir then
                instruction_reg <= data_bus_in;
                report "Microcode: Loading instruction register with 0x" & to_hstring(data_bus_in);
            end if;
            
            -- Temporary register loading
            if ucode.load_temp_a then
                case ucode.temp_a_source is
                    when "00" => temp_a <= X"00";  -- Load zero
                    when "01" => temp_a <= data_bus_in;  -- From data bus
                    when others => null;
                end case;
                report "Microcode: Loading temp_a";
            end if;
            
            if ucode.load_temp_b then
                case ucode.temp_b_source is
                    when "00" => 
                        temp_b <= X"00";  -- Load zero
                        report "Microcode: Loading temp_b with 0x00";
                    when "01" => 
                        temp_b <= data_bus_in;  -- From data bus (instruction)
                        report "Microcode: Loading temp_b from data_bus_in=0x" & to_hstring(unsigned(data_bus_in));
                    when others => null;
                end case;
            end if;
            
            -- PC control
            if ucode.pc_inc then
                pc <= pc + 1;
            end if;
            
            if ucode.pc_load_high then
                -- Load high 6 bits of PC from temp_a
                pc(13 downto 8) <= unsigned(temp_a(5 downto 0));
                report "Microcode: Loading PC high from temp_a: 0x" & to_hstring(temp_a(5 downto 0));
            end if;
            
            if ucode.pc_load_low then
                -- For RST, extract vector from temp_b (instruction)
                -- RST instruction format: 00 AAA 101
                -- Vector address = 00 AAA 000 (AAA field shifted left by 3)
                -- RST 0 (0x05): AAA=000 -> 0x0000
                -- RST 1 (0x0D): AAA=001 -> 0x0008
                -- RST 2 (0x15): AAA=010 -> 0x0010, etc.
                pc(7 downto 6) <= "00";
                pc(5 downto 3) <= unsigned(temp_b(5 downto 3));  -- AAA field
                pc(2 downto 0) <= "000";
                report "Microcode: Loading PC low for RST, temp_b=0x" & to_hstring(temp_b) &
                       ", AAA bits: " & 
                       std_logic'image(temp_b(5)) & std_logic'image(temp_b(4)) & std_logic'image(temp_b(3)) &
                       ", vector address: 0x00" & to_hstring(unsigned(temp_b(5 downto 3)) & "000");
            end if;
            
            -- Stack control
            if ucode.stack_push then
                -- Save current PC to stack and increment pointer
                address_stack(to_integer(stack_pointer)) <= pc;
                stack_pointer <= stack_pointer + 1;
                report "Microcode: Pushing PC to stack";
            end if;
            
            if ucode.stack_pop then
                -- Decrement pointer and restore PC
                stack_pointer <= stack_pointer - 1;
                -- PC will be loaded from stack on next cycle
            end if;
            
            -- Cycle management
            if ucode.new_cycle then
                current_cycle <= current_cycle + 1;
                cycle_type <= ucode.next_cycle_type;
            end if;
            
            -- ===========================================
            -- INTERRUPT ACKNOWLEDGE CYCLE
            -- ===========================================
            -- Per Intel 8008 datasheet:
            -- After completing instruction, if interrupt pending:
            -- - Goes to T1I state (interrupt acknowledge)
            -- - External hardware provides RST instruction
            -- - RST executes, jumping to interrupt vector
            
            -- Get base next state from microcode
            next_state := ucode.next_state;
            
            -- Update instruction complete flag
            instruction_complete <= ucode.instruction_complete;
            
            -- Check for cycle management
            if ucode.new_cycle then
                current_cycle <= current_cycle + 1;
            elsif ucode.instruction_complete then
                current_cycle <= 0;
            end if;
            
            -- Override next_state for interrupt handling
            -- Only check at instruction boundaries (when instruction_complete = true)
            if ucode.instruction_complete and int_pending = '1' and timing_state /= STOPPED then
                -- Instruction just completed and interrupt is pending
                next_state := T1I;  -- Start interrupt acknowledge cycle
                in_int_ack_cycle <= '1';  -- Mark start of interrupt ack cycle
                report "Interrupt: Instruction complete, starting interrupt acknowledge";
            elsif ucode.instruction_complete and in_int_ack_cycle = '1' then
                -- Interrupt acknowledge cycle complete, clear flag
                in_int_ack_cycle <= '0';
                report "Interrupt: Int ack instruction complete, clearing in_int_ack_cycle";
            end if;
            
            -- Handle WAIT states
            if next_state = T2 and READY = '0' then
                next_state := TWAIT;
            elsif next_state = TWAIT and READY = '1' then
                next_state := T3;
            end if;
                
            end if;  -- End of STOPPED/normal operation check
            
            -- Update timing state for next cycle
            timing_state <= next_state;
            report "State machine: timing_state <= " & timing_state_t'image(next_state);
        end if;
    end process state_machine;
    
    --===========================================
    -- Address Stack Management
    --===========================================
    -- NOTE: Stack management is now handled by microcode in state_machine process
    -- This process is disabled to avoid signal conflicts
    
    -- stack_control: process(phi1)
    -- begin
    --     if rising_edge(phi1) then
    --         -- Always keep current stack location synchronized with PC
    --         address_stack(to_integer(stack_pointer)) <= pc;
    --         
    --         if push_stack then
    --             -- CALL instruction: save PC+3 and increment pointer
    --             -- PC+3 accounts for 3-byte CALL instruction
    --             address_stack(to_integer(stack_pointer)) <= pc + 3;
    --             stack_pointer <= stack_pointer + 1;  -- Wraps at 8
    --             push_stack <= false;
    --             
    --         elsif pop_stack then
    --             -- RETURN instruction: decrement pointer and restore PC
    --             stack_pointer <= stack_pointer - 1;  -- Wraps at 0
    --             -- PC will be loaded from stack on next cycle
    --             pop_stack <= false;
    --         end if;
    --         
    --         -- Load PC from current stack position
    --         -- This happens after stack_pointer changes
    --         if pop_stack = false and push_stack = false then
    --             pc <= address_stack(to_integer(stack_pointer));
    --         end if;
    --     end if;
    -- end process stack_control;
    
    --===========================================
    -- Register File Access and H:L Addressing
    --===========================================
    -- Handles register read/write operations and H:L indirect addressing
    
    register_control: process(phi2)
    begin
        if rising_edge(phi2) then
            -- H:L address combination (H provides high 6 bits, L provides low 8 bits)
            -- Bits 7-6 of H are ignored (don't cares) for 14-bit addressing
            hl_address <= registers(REG_H_DATA)(5 downto 0) & registers(REG_L_DATA);
            
            -- Check if accessing memory through M register
            memory_reference <= (reg_select = REG_M);
            
            -- Register write operation
            if reg_write_enable and not memory_reference then
                -- Direct register write
                case reg_select is
                    when REG_A => registers(REG_A_DATA) <= internal_data_bus;
                    when REG_B => registers(REG_B_DATA) <= internal_data_bus;
                    when REG_C => registers(REG_C_DATA) <= internal_data_bus;
                    when REG_D => registers(REG_D_DATA) <= internal_data_bus;
                    when REG_E => registers(REG_E_DATA) <= internal_data_bus;
                    when REG_H => registers(REG_H_DATA) <= internal_data_bus;
                    when REG_L => registers(REG_L_DATA) <= internal_data_bus;
                    when others => null;  -- REG_M handled separately
                end case;
                reg_write_enable <= false;
            end if;
            
            -- Register read operation
            if reg_read_enable and not memory_reference then
                -- Direct register read
                case reg_select is
                    when REG_A => internal_data_bus <= registers(REG_A_DATA);
                    when REG_B => internal_data_bus <= registers(REG_B_DATA);
                    when REG_C => internal_data_bus <= registers(REG_C_DATA);
                    when REG_D => internal_data_bus <= registers(REG_D_DATA);
                    when REG_E => internal_data_bus <= registers(REG_E_DATA);
                    when REG_H => internal_data_bus <= registers(REG_H_DATA);
                    when REG_L => internal_data_bus <= registers(REG_L_DATA);
                    when others => null;  -- REG_M handled separately
                end case;
                reg_read_enable <= false;
            end if;
            
            -- Memory reference through H:L requires external memory access
            -- This will be handled by memory controller using hl_address
        end if;
    end process register_control;
    
    -- ALU always uses accumulator as one operand
    alu_data_0 <= registers(REG_A_DATA);  -- Accumulator is always first ALU operand
    
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
    data_bus_output: process(timing_state, pc, cycle_type)
    begin
        case timing_state is
            when T1 | T1I =>
                -- T1/T1I: Output lower 8 bits of address
                data_bus_out <= std_logic_vector(pc(7 downto 0));
                data_bus_enable <= '1';
                
            when T2 =>
                -- T2: Output cycle type (D7:D6) and upper address (D5:D0)
                data_bus_out <= cycle_type & std_logic_vector(pc(13 downto 8));
                data_bus_enable <= '1';
                
            when T3 =>
                -- T3: Data transfer
                -- For PCI (instruction fetch), we read - don't drive
                if cycle_type = CYCLE_PCI then
                    data_bus_enable <= '0';  -- Reading instruction
                else
                    data_bus_enable <= '0';  -- For now, only PCI implemented
                end if;
                data_bus_out <= (others => '0');
                
            when others =>
                -- T4, T5, TWAIT, STOPPED: Don't drive bus
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
    -- alu_data_0 is set in register_control process (always accumulator)
    alu_data_1  <= internal_data_bus;  -- Second operand from selected register or memory
    alu_command <= (others => '0');    -- Will be set by instruction decoder
    flag_carry  <= flag_c;             -- Current carry flag state

end rtl;

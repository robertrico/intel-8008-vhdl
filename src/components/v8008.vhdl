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
    
    -- Interrupt handling signals
    signal int_latched : std_logic := '0';     -- Latched interrupt request
    signal int_previous : std_logic := '0';    -- Previous INT value for edge detection
    signal in_int_ack_cycle : std_logic := '0';  -- '1' during T1I→T2→T3 interrupt acknowledge
    
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
    
    -- Control signals from instruction decoder
    signal fetch_instruction : boolean := false;
    signal decode_instruction : boolean := false;
    signal execute_instruction : boolean := false;
    
    -- Cycle and instruction tracking
    signal cycle_complete : boolean := false;      -- True when current machine cycle ends (T3 or T5)
    signal instruction_complete : boolean := true; -- True when entire instruction finishes
    signal cycles_in_instruction : integer := 1;   -- How many cycles this instruction needs
    signal current_cycle : integer := 0;           -- Which cycle we're in
    
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
                int_latched <= '1';
            elsif timing_state = T1I then
                -- CPU acknowledged interrupt: clear latch
                int_latched <= '0';
                in_int_ack_cycle <= '1';  -- Mark that external hardware is providing instruction
            elsif timing_state = T1 and in_int_ack_cycle = '1' then
                -- Clear interrupt acknowledge flag after returning to T1
                in_int_ack_cycle <= '0';
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
    -- State Machine Process
    --===========================================
    -- This process handles state transitions and instruction capture
    
    state_machine: process(phi2)
    begin
        if rising_edge(phi2) then
            -- Store previous state
            timing_state_prev <= timing_state;
            
            case timing_state is
                when T1 =>
                    -- T1: Start of a machine cycle
                    cycle_complete <= false;  -- Starting new cycle
                    -- Note: instruction_complete is set by instruction decoder
                    timing_state <= T2;
                    
                when T1I =>
                    -- T1I: Interrupt acknowledge cycle
                    -- External hardware provides an instruction on data bus
                    -- (typically RST, but can be any valid 8008 instruction)
                    -- This acts like a normal instruction fetch, but externally driven
                    cycle_complete <= false;  -- Starting new cycle
                    -- Don't touch instruction_complete - let decoder handle instruction normally
                    timing_state <= T2;
                    
                when T2 =>
                    -- T2: Address/cycle type output
                    -- Check for READY signal (wait states)
                    if READY = '1' then
                        timing_state <= T3;
                    else
                        timing_state <= TWAIT;
                    end if;
                    
                when TWAIT =>
                    -- TWAIT: Wait state
                    if READY = '1' then
                        timing_state <= T3;
                    end if;
                    
                when T3 =>
                    -- T3: Data transfer cycle - capture instruction from data bus
                    instruction_reg <= data_bus_in;
                    
                    -- TODO: Instruction decoder determines if this is 3-state or 5-state
                    -- For now, assume 3-state (most common)
                    cycle_complete <= true;  -- 3-state cycle ends after T3
                    
                    -- Check if cycle ended (3-state ends here, 5-state continues)
                    if cycle_complete then
                        -- Cycle ended at T3 (3-state instruction)
                        -- TODO: Decoder determines if instruction needs more cycles
                        instruction_complete <= true;  -- For now, assume single cycle
                        
                        -- Now check if instruction is complete
                        if instruction_complete then
                            -- Instruction complete - check for interrupt
                            if int_latched = '1' then
                                timing_state <= T1I;  -- Service interrupt
                            else
                                timing_state <= T1;   -- Next instruction
                            end if;
                        else
                            -- Instruction NOT complete (multi-cycle)
                            -- Check if instruction was jammed during interrupt cycle
                            if in_int_ack_cycle = '1' then
                                timing_state <= T1I;  -- Instruction jammed by interrupt controller
                            else
                                timing_state <= T1;   -- Continue multi-cycle instruction
                            end if;
                        end if;
                    else
                        -- Cycle not complete - this is a 5-state instruction
                        -- Continue to T4
                        timing_state <= T4;
                    end if;
                    
                when T4 =>
                    -- T4: Extended cycle for 5-state instructions
                    -- TODO: Some operations might complete at T4
                    -- For now, assume 5-state continues to T5
                    cycle_complete <= false;  -- Not done yet
                    
                    -- Check if cycle ended at T4
                    if cycle_complete then
                        -- Some instructions might end at T4
                        -- TODO: Decoder determines if instruction is complete
                        instruction_complete <= true;  -- For now, assume complete
                        
                        -- Check if instruction is complete
                        if instruction_complete then
                            -- Instruction complete - check for interrupt
                            if int_latched = '1' then
                                timing_state <= T1I;  -- Service interrupt
                            else
                                timing_state <= T1;   -- Next instruction
                            end if;
                        else
                            -- Instruction NOT complete (multi-cycle)
                            -- Check if instruction was jammed during interrupt cycle
                            if in_int_ack_cycle = '1' then
                                timing_state <= T1I;  -- Instruction jammed by interrupt controller
                            else
                                timing_state <= T1;   -- Continue multi-cycle instruction
                            end if;
                        end if;
                    else
                        -- Cycle not complete - continue to T5
                        timing_state <= T5;
                    end if;
                    
                when T5 =>
                    -- T5: Final state of 5-state cycle
                    -- 5-state cycles always end at T5
                    cycle_complete <= true;
                    
                    -- TODO: Decoder determines if instruction needs more cycles
                    instruction_complete <= true;  -- For now, assume complete
                    
                    -- Since cycle definitely ends at T5, check instruction completion
                    if instruction_complete then
                        -- Instruction complete - check for interrupt
                        if int_latched = '1' then
                            timing_state <= T1I;  -- Service interrupt
                        else
                            timing_state <= T1;   -- Next instruction
                        end if;
                    else
                        -- Instruction NOT complete (multi-cycle)
                        -- Check if RST was jammed during interrupt cycle
                        if in_int_ack_cycle = '1' then
                            timing_state <= T1I;  -- RST jammed, go to T1I
                        else
                            timing_state <= T1;   -- Continue multi-cycle instruction
                        end if;
                    end if;
                    
                when STOPPED =>
                    -- CPU halted - wait for interrupt to exit
                    if int_latched = '1' then
                        timing_state <= T1I;
                    end if;
                    
                when others =>
                    timing_state <= T1;
            end case;
        end if;
    end process state_machine;
    
    --===========================================
    -- Address Stack Management
    --===========================================
    -- Handles CALL/RETURN stack operations
    -- The stack is circular - overflow wraps around destroying oldest entry
    
    stack_control: process(phi1)
    begin
        if rising_edge(phi1) then
            -- Always keep current stack location synchronized with PC
            address_stack(to_integer(stack_pointer)) <= pc;
            
            if push_stack then
                -- CALL instruction: save PC+3 and increment pointer
                -- PC+3 accounts for 3-byte CALL instruction
                address_stack(to_integer(stack_pointer)) <= pc + 3;
                stack_pointer <= stack_pointer + 1;  -- Wraps at 8
                push_stack <= false;
                
            elsif pop_stack then
                -- RETURN instruction: decrement pointer and restore PC
                stack_pointer <= stack_pointer - 1;  -- Wraps at 0
                -- PC will be loaded from stack on next cycle
                pop_stack <= false;
            end if;
            
            -- Load PC from current stack position
            -- This happens after stack_pointer changes
            if pop_stack = false and push_stack = false then
                pc <= address_stack(to_integer(stack_pointer));
            end if;
        end if;
    end process stack_control;
    
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
    -- Generate S0, S1, S2 based on current timing state
    -- Per Intel 8008 datasheet state encoding
    
    -- State outputs based on timing_state
    -- Per Intel 8008 datasheet state encoding
    process(timing_state)
    begin
        case timing_state is
            when T1      => S0 <= '0'; S1 <= '1'; S2 <= '0';  -- 010
            when T1I     => S0 <= '0'; S1 <= '1'; S2 <= '1';  -- 110 (interrupt acknowledge)
            when T2      => S0 <= '0'; S1 <= '0'; S2 <= '1';  -- 100
            when TWAIT   => S0 <= '0'; S1 <= '0'; S2 <= '0';  -- 000
            when T3      => S0 <= '1'; S1 <= '0'; S2 <= '0';  -- 001
            when STOPPED => S0 <= '1'; S1 <= '1'; S2 <= '0';  -- 011
            when T4      => S0 <= '1'; S1 <= '1'; S2 <= '1';  -- 111
            when T5      => S0 <= '1'; S1 <= '0'; S2 <= '1';  -- 101
        end case;
    end process;
    
    -- Data bus (temporary)
    data_bus_out    <= (others => '0');
    data_bus_enable <= '0';
    
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

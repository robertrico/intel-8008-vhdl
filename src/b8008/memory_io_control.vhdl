--------------------------------------------------------------------------------
-- memory_io_control.vhdl
--------------------------------------------------------------------------------
-- Memory and I/O Control for Intel 8008
--
-- Master control block for memory and I/O operations
-- - Controls data flow between internal bus and external world
-- - Manages instruction register output
-- - Controls address generation and multiplexing
-- - Manages stack operations
-- - Handles DRAM refresh (if needed)
-- - DUMB module: timing-based signal generation
--
-- Inputs from:
--   - Machine Cycle Control
--   - Condition Flags
--   - State Timing Generator
--   - Clock Generator
--   - Ready FF
--   - Interrupt FF
--   - Instruction Decoder
--
-- Outputs to:
--   - Instruction Register (output enable)
--   - I/O Buffer (enable, direction)
--   - Address generation blocks (AHL pointer, stack, etc.)
--   - Memory interface
--   - Register file multiplexers
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.b8008_types.all;

entity memory_io_control is
    port (
        -- Clock (phi1 from clock generator)
        phi1 : in std_logic;

        -- Reset
        reset : in std_logic;

        -- From State Timing Generator
        state_t1  : in std_logic;
        state_t2  : in std_logic;
        state_t3  : in std_logic;
        state_t4  : in std_logic;
        state_t5  : in std_logic;
        state_t1i : in std_logic;
        status_s0 : in std_logic;
        status_s1 : in std_logic;
        status_s2 : in std_logic;

        -- From Machine Cycle Control
        cycle_type     : in std_logic_vector(1 downto 0);  -- 00=PCI, 01=PCR, 10=PCC, 11=PCW
        current_cycle  : in integer range 1 to 3;
        advance_state  : in std_logic;

        -- From Instruction Decoder
        instr_needs_immediate : in std_logic;
        instr_needs_address   : in std_logic;
        instr_is_io           : in std_logic;
        instr_is_write        : in std_logic;
        instr_sss_field       : in std_logic_vector(2 downto 0);  -- Source register
        instr_ddd_field       : in std_logic_vector(2 downto 0);  -- Destination register
        instr_is_alu          : in std_logic;  -- ALU operation
        instr_is_call         : in std_logic;  -- CALL instruction
        instr_is_ret          : in std_logic;  -- RET instruction
        instr_is_rst          : in std_logic;  -- RST instruction
        instr_writes_reg      : in std_logic;  -- Instruction writes to register
        instr_reads_reg       : in std_logic;  -- Instruction reads from register

        -- From Condition Flags
        condition_met : in std_logic;

        -- From Interrupt/Ready Flip-Flops
        interrupt_pending : in std_logic;
        ready_status      : in std_logic;

        -- To Instruction Register
        ir_output_enable : out std_logic;

        -- To I/O Buffer
        io_buffer_enable    : out std_logic;
        io_buffer_direction : out std_logic;  -- 0=read, 1=write

        -- To Address Generation (SSS/DDD register selection)
        addr_select_sss : out std_logic_vector(2 downto 0);  -- Source register for address
        addr_select_ddd : out std_logic_vector(2 downto 0);  -- Destination register

        -- To AHL Address Pointer
        ahl_load   : out std_logic;  -- Load H:L into address pointer
        ahl_output : out std_logic;  -- Output address from H:L

        -- To Scratchpad Multiplexer (Register File)
        scratchpad_select : out std_logic_vector(2 downto 0);  -- Which register to access
        scratchpad_read   : out std_logic;  -- Read from register
        scratchpad_write  : out std_logic;  -- Write to register

        -- To Memory Multiplexer and Refresh Amplifiers
        memory_read    : out std_logic;  -- Read from memory
        memory_write   : out std_logic;  -- Write to memory
        memory_refresh : out std_logic;  -- DRAM refresh cycle

        -- To Memory Multiplexer - Register File routing
        regfile_to_bus : out std_logic;  -- Register file drives internal bus
        bus_to_regfile : out std_logic;  -- Internal bus drives register file

        -- To Memory Multiplexer - Address selection
        select_pc    : out std_logic;  -- Use PC for address bus
        select_ahl   : out std_logic;  -- Use AHL for address bus (M operations)
        select_stack : out std_logic;  -- Use Stack for address bus

        -- To Memory Multiplexer - PC load source selection
        pc_load_from_regs  : out std_logic;  -- Load PC from temp regs (JMP/CALL)
        pc_load_from_stack : out std_logic;  -- Load PC from stack (RET)
        pc_load_from_rst   : out std_logic;  -- Load PC from RST vector

        -- To Refresh Counter
        refresh_increment : out std_logic;  -- Increment refresh address

        -- To Stack Address Multiplexer
        stack_addr_select : out std_logic;  -- 0=PC, 1=stack

        -- To Stack Pointer
        stack_push : out std_logic;  -- Push to stack
        stack_pop  : out std_logic;  -- Pop from stack

        -- To Program Counter (CRITICAL ISSUE #1)
        pc_increment : out std_logic;  -- Increment PC
        pc_load      : out std_logic;  -- Load PC from data_in
        pc_hold      : out std_logic   -- Hold PC (wait states)
    );
end entity memory_io_control;

architecture rtl of memory_io_control is

    -- Cycle type constants
    constant CYCLE_PCI : std_logic_vector(1 downto 0) := "00";  -- Instruction fetch
    constant CYCLE_PCR : std_logic_vector(1 downto 0) := "01";  -- Memory read
    constant CYCLE_PCC : std_logic_vector(1 downto 0) := "10";  -- I/O
    constant CYCLE_PCW : std_logic_vector(1 downto 0) := "11";  -- Memory write

begin

    -- Control signal generation (combinational based on state and cycle)
    process(state_t1, state_t2, state_t3, state_t4, state_t5, state_t1i,
            status_s0, status_s1, status_s2,
            cycle_type, current_cycle, instr_is_io, instr_is_write,
            condition_met, ready_status, interrupt_pending,
            instr_needs_immediate, instr_needs_address,
            instr_sss_field, instr_ddd_field, instr_is_alu,
            instr_is_call, instr_is_ret, instr_is_rst,
            instr_writes_reg, instr_reads_reg)
    begin
        -- Defaults: all outputs inactive
        ir_output_enable      <= '0';
        io_buffer_enable      <= '0';
        io_buffer_direction   <= '0';
        addr_select_sss       <= (others => '0');
        addr_select_ddd       <= (others => '0');
        ahl_load              <= '0';
        ahl_output            <= '0';
        scratchpad_select     <= (others => '0');
        scratchpad_read       <= '0';
        scratchpad_write      <= '0';
        memory_read           <= '0';
        memory_write          <= '0';
        memory_refresh        <= '0';
        regfile_to_bus        <= '0';
        bus_to_regfile        <= '0';
        select_pc             <= '1';  -- Default to PC
        select_ahl            <= '0';
        select_stack          <= '0';
        pc_load_from_regs     <= '0';
        pc_load_from_stack    <= '0';
        pc_load_from_rst      <= '0';
        refresh_increment     <= '0';
        stack_addr_select     <= '0';
        stack_push            <= '0';
        stack_pop             <= '0';
        pc_increment          <= '0';
        pc_load               <= '0';
        pc_hold               <= '0';

        -- PC Control Logic (CRITICAL ISSUE #1)
        -- Hold PC if ready signal is low or interrupt pending
        if ready_status = '0' or interrupt_pending = '1' then
            pc_hold <= '1';
        else
            -- Increment PC after instruction fetch (T3 during PCI cycle)
            if state_t3 = '1' and cycle_type = CYCLE_PCI then
                pc_increment <= '1';
            -- Or after T2 when advancing to next cycle
            elsif state_t2 = '1' and advance_state = '1' then
                pc_increment <= '1';
            end if;

            -- Load PC during T4 for JMP/CALL
            if state_t4 = '1' then
                if current_cycle = 3 and (instr_is_call = '1' or instr_needs_address = '1') then
                    pc_load <= '1';
                end if;
            -- Load PC during T5 for RET/RST
            elsif state_t5 = '1' then
                if instr_is_ret = '1' or instr_is_rst = '1' then
                    pc_load <= '1';
                end if;
            end if;
        end if;

        -- State-based control
        if state_t1 = '1' then
            -- T1: Output address low byte (from PC or stack)
            -- S2=0, S1=1, S0=0: Address low from PC or stack
            -- For normal instructions: use PC
            -- For RET: use stack (will implement when we decode instruction)
            stack_addr_select <= '0';  -- Default to PC

        elsif state_t2 = '1' then
            -- T2: Output address high byte + cycle type on D[7:6]
            -- S2=1, S1=0, S0=0
            -- Cycle type encoding is handled by machine_cycle_control
            -- D[7:6] driven from cycle_type signal
            null;

        elsif state_t3 = '1' then
            -- T3: Data transfer state (main activity happens here)
            -- S2=0, S1=0, S0=1

            -- Register file access for single-cycle instructions
            if current_cycle = 1 then
                if instr_reads_reg = '1' then
                    -- ALU operations, MOV, etc. - read source register
                    scratchpad_select <= instr_sss_field;
                    scratchpad_read   <= '1';
                    regfile_to_bus    <= '1';  -- Register file drives internal bus
                end if;
                if instr_writes_reg = '1' and instr_needs_immediate = '0' then
                    -- Single-cycle register write (MOV, ALU result)
                    scratchpad_select <= instr_ddd_field;
                    scratchpad_write  <= '1';
                    bus_to_regfile    <= '1';  -- Bus writes to register file
                end if;
            end if;

            case cycle_type is
                when CYCLE_PCI =>
                    -- Instruction fetch: read from external memory
                    io_buffer_enable    <= '1';
                    io_buffer_direction <= '0';  -- Read from external
                    memory_read         <= '1';
                    -- Data goes to internal bus, will be loaded into IR by rising edge of phi1

                when CYCLE_PCR =>
                    -- Memory read: read data from memory
                    io_buffer_enable    <= '1';
                    io_buffer_direction <= '0';  -- Read from external
                    memory_read         <= '1';
                    select_ahl          <= '1';  -- Use AHL for address

                when CYCLE_PCW =>
                    -- Memory write: write data to memory
                    io_buffer_enable    <= '1';
                    io_buffer_direction <= '1';  -- Write to external
                    memory_write        <= '1';
                    select_ahl          <= '1';  -- Use AHL for address
                    -- Data on internal bus comes from register file
                    scratchpad_select <= instr_sss_field;
                    scratchpad_read   <= '1';
                    regfile_to_bus    <= '1';

                when CYCLE_PCC =>
                    -- I/O operation (INP/OUT)
                    io_buffer_enable <= '1';
                    if instr_is_write = '1' then
                        -- OUT: write accumulator to I/O
                        io_buffer_direction <= '1';
                        scratchpad_select   <= "000";  -- A register
                        scratchpad_read     <= '1';
                        regfile_to_bus      <= '1';  -- Register file drives bus
                    else
                        -- INP: read from I/O
                        io_buffer_direction <= '0';
                    end if;

                when others =>
                    null;
            end case;

        elsif state_t4 = '1' then
            -- T4: Extended cycle processing
            -- S2=0, S1=1, S0=1
            -- Used for multi-cycle instructions

            if current_cycle = 2 then
                -- Second cycle: data has been read in T3, now write to destination
                if instr_writes_reg = '1' then
                    -- Instructions like LrI, LrM, INP - write to register
                    scratchpad_select <= instr_ddd_field;
                    scratchpad_write  <= '1';
                    bus_to_regfile    <= '1';  -- Bus writes to register file
                end if;

            elsif current_cycle = 3 then
                -- Third cycle of CALL/JMP - load PC from temp registers
                if instr_is_call = '1' then
                    stack_push         <= '1';
                    pc_load_from_regs  <= '1';  -- Load PC from Reg.a+Reg.b
                elsif instr_needs_address = '1' then  -- JMP
                    pc_load_from_regs  <= '1';  -- Load PC from Reg.a+Reg.b
                end if;
            end if;

        elsif state_t5 = '1' then
            -- T5: Final extended cycle processing
            -- S2=1, S1=0, S0=1
            -- RET: pop return address from stack and load PC
            -- RST: push current PC to stack and load RST vector

            if instr_is_ret = '1' then
                stack_pop           <= '1';
                pc_load_from_stack  <= '1';  -- Load PC from stack
                select_stack        <= '1';  -- Use stack for address
            elsif instr_is_rst = '1' then
                stack_push          <= '1';
                pc_load_from_rst    <= '1';  -- Load PC from RST vector
            end if;

        elsif state_t1i = '1' then
            -- T1I: Interrupt acknowledge cycle
            -- S2=1, S1=1, S0=0
            -- Output interrupt acknowledge signals
            -- Prepare for interrupt vector read
            null;

        end if;

    end process;

end architecture rtl;

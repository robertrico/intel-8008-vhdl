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
        state_half : in std_logic;  -- Which half of 2-cycle state (0=first, 1=second)
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
        instr_is_mem_indirect : in std_logic;  -- Memory indirect (SSS or DDD = "111")

        -- From Condition Flags
        condition_met : in std_logic;

        -- From Interrupt/Ready Flip-Flops
        interrupt_pending : in std_logic;
        ready_status      : in std_logic;

        -- To Instruction Register
        ir_load          : out std_logic;  -- Load IR from internal bus
        ir_output_enable : out std_logic;  -- Output IR to internal bus

        -- To I/O Buffer
        io_buffer_enable    : out std_logic;
        io_buffer_direction : out std_logic;  -- 0=read, 1=write

        -- To Address Generation (SSS/DDD register selection)
        addr_select_sss : out std_logic_vector(2 downto 0);  -- Source register for address
        addr_select_ddd : out std_logic_vector(2 downto 0);  -- Destination register

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

        -- To Stack Address Decoder
        stack_read  : out std_logic;  -- Read from stack (RET)
        stack_write : out std_logic;  -- Write to stack (CALL, RST)

        -- To Program Counter
        pc_increment_lower : out std_logic;  -- Increment PC lower byte (T1)
        pc_increment_upper : out std_logic;  -- Increment PC upper byte (T2 if carry)
        pc_carry_in        : in  std_logic;  -- Carry flag from PC
        pc_load            : out std_logic;  -- Load PC from data_in
        pc_hold            : out std_logic   -- Hold PC (wait states)
    );
end entity memory_io_control;

architecture rtl of memory_io_control is

    -- Cycle type constants
    constant CYCLE_PCI : std_logic_vector(1 downto 0) := "00";  -- Instruction fetch
    constant CYCLE_PCR : std_logic_vector(1 downto 0) := "01";  -- Memory read
    constant CYCLE_PCC : std_logic_vector(1 downto 0) := "10";  -- I/O
    constant CYCLE_PCW : std_logic_vector(1 downto 0) := "11";  -- Memory write

    -- Edge detection for generating single-cycle pulses
    signal prev_state_t2 : std_logic := '0';
    signal prev_state_t5 : std_logic := '0';
    signal state_t2_edge : std_logic;
    signal state_t5_edge : std_logic;

begin

    -- Detect rising edges of state signals
    state_t2_edge <= '1' when (state_t2 = '1' and prev_state_t2 = '0') else '0';
    state_t5_edge <= '1' when (state_t5 = '1' and prev_state_t5 = '0') else '0';

    -- Track state transitions and generate edge signals
    process(phi1, reset)
    begin
        if reset = '1' then
            prev_state_t2 <= '0';
            prev_state_t5 <= '0';
        elsif rising_edge(phi1) then
            -- Update previous state values for edge detection
            prev_state_t2 <= state_t2;
            prev_state_t5 <= state_t5;
        end if;
    end process;

    -- Control signal generation (combinational based on state and cycle)
    process(state_t1, state_t2, state_t3, state_t4, state_t5, state_t1i, state_half,
            status_s0, status_s1, status_s2,
            cycle_type, current_cycle, instr_is_io, instr_is_write, instr_is_mem_indirect,
            condition_met, ready_status, interrupt_pending,
            instr_needs_immediate, instr_needs_address,
            instr_sss_field, instr_ddd_field, instr_is_alu,
            instr_is_call, instr_is_ret, instr_is_rst,
            instr_writes_reg, instr_reads_reg)
    begin
        -- Defaults: all outputs inactive
        ir_load               <= '0';
        ir_output_enable      <= '0';
        io_buffer_enable      <= '0';
        io_buffer_direction   <= '0';
        addr_select_sss       <= (others => '0');
        addr_select_ddd       <= (others => '0');
        scratchpad_select     <= (others => '0');
        scratchpad_read       <= '0';
        scratchpad_write      <= '0';
        memory_read           <= '0';
        memory_write          <= '0';
        memory_refresh        <= '0';
        regfile_to_bus        <= '0';
        bus_to_regfile        <= '0';
        select_pc             <= '1';  -- Default to PC
        select_stack          <= '0';
        pc_load_from_regs     <= '0';
        pc_load_from_stack    <= '0';
        pc_load_from_rst      <= '0';
        refresh_increment     <= '0';
        stack_addr_select     <= '0';
        stack_push            <= '0';
        stack_pop              <= '0';
        stack_read             <= '0';
        stack_write            <= '0';
        pc_increment_lower     <= '0';
        pc_increment_upper     <= '0';
        pc_load                <= '0';
        pc_hold                <= '0';

        -- PC Control Logic (Two-stage increment per 1972 datasheet)
        -- T1: Increment lower byte after address bits sent out
        -- T2: If carry occurred, increment upper byte
        -- Hold PC if ready signal is low or interrupt pending
        if ready_status = '0' or interrupt_pending = '1' then
            pc_hold <= '1';
        else
            -- T1 second half: Increment lower byte
            -- Per datasheet: "incremented immediately after the lower order address bits are sent out"
            -- BUT NOT during T1I - PC is not advanced during interrupt acknowledge
            -- ALSO NOT during cycle 2+ of memory-indirect instructions (PC stays at next instruction)
            -- For address instructions (JMP/CALL), PC increments in cycles 2 and 3 to fetch address bytes
            if state_t1 = '1' and state_half = '1' and state_t1i = '0' and
               (current_cycle = 1 or instr_needs_address = '1') then
                pc_increment_lower <= '1';
            end if;

            -- T2 first half: Increment upper byte if carry occurred
            -- Per datasheet: "Increment program counter if there has been a carry from T1"
            if state_t2 = '1' and state_half = '0' and pc_carry_in = '1' then
                pc_increment_upper <= '1';
            end if;

            -- Load PC during T4/T5 for various instructions
            -- JMP/CALL: T5 of cycle 3
            -- RET/RST: T5 of cycle 1
            if state_t5 = '1' then
                if current_cycle = 3 and instr_needs_address = '1' then
                    -- JMP/CALL: Load PC from Reg.a+Reg.b during T5 of cycle 3
                    pc_load <= '1';
                    if instr_is_call = '1' then
                        report "MEM_IO: Setting pc_load at T5 cycle 3 for CALL";
                    else
                        report "MEM_IO: Setting pc_load at T5 cycle 3 for JMP";
                    end if;
                elsif instr_is_ret = '1' then
                    -- RET: Load PC from stack during T5 of cycle 1
                    -- T4 reads from stack, T5 loads PC to avoid timing issues
                    pc_load <= '1';
                    report "MEM_IO: Setting pc_load at T5 cycle 1 for RET";
                elsif instr_is_rst = '1' then
                    -- RST: Load PC from RST vector during T5
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

            -- Special case: During cycle 2 T1/T2 of memory indirect operations,
            -- output H/L registers to data bus for external address latch
            if current_cycle = 2 and instr_is_mem_indirect = '1' then
                -- Output L register during T1 (ahl_pointer selects L via final_scratchpad_addr)
                scratchpad_read     <= '1';
                regfile_to_bus      <= '1';  -- Register file drives internal bus
                io_buffer_enable    <= '1';
                io_buffer_direction <= '1';  -- Internal bus drives data bus (write direction)
            end if;

        elsif state_t2 = '1' then
            -- T2: Output address high byte + cycle type on D[7:6]
            -- S2=1, S1=0, S0=0
            -- Cycle type encoding is handled by machine_cycle_control
            -- D[7:6] driven from cycle_type signal

            -- Special case: During cycle 2 T1/T2 of memory indirect operations,
            -- output H/L registers to data bus for external address latch
            if current_cycle = 2 and instr_is_mem_indirect = '1' then
                -- Output H register during T2 (ahl_pointer selects H via final_scratchpad_addr)
                scratchpad_read     <= '1';
                regfile_to_bus      <= '1';  -- Register file drives internal bus
                io_buffer_enable    <= '1';
                io_buffer_direction <= '1';  -- Internal bus drives data bus (write direction)
            end if;

        elsif state_t3 = '1' then
            -- T3: Data transfer state (main activity happens here)
            -- S2=0, S1=0, S0=1

            -- Register file access for single-cycle instructions
            -- NOTE: During PCI (instruction fetch), don't access register file at T3!
            -- The instruction is still being loaded, so decoder signals aren't stable yet.
            if current_cycle = 1 and cycle_type /= CYCLE_PCI then
                if instr_reads_reg = '1' then
                    -- ALU operations, MOV, etc. - read source register
                    scratchpad_select <= instr_sss_field;
                    scratchpad_read   <= '1';
                    regfile_to_bus    <= '1';  -- Register file drives internal bus
                end if;
                if instr_writes_reg = '1' and instr_needs_immediate = '0' and instr_is_alu = '0' then
                    -- Single-cycle register write (MOV only, NOT ALU!)
                    -- ALU results are written at T4/T5, not T3
                    scratchpad_select <= instr_ddd_field;
                    scratchpad_write  <= '1';
                    bus_to_regfile    <= '1';  -- Bus writes to register file
                end if;
            end if;

            case cycle_type is
                when CYCLE_PCI =>
                    -- Instruction fetch: read from external memory and load IR
                    -- Cycle type PCI only occurs during cycle 1 (machine_cycle_control ensures this)
                    io_buffer_enable    <= '1';
                    io_buffer_direction <= '0';  -- Read from external
                    memory_read         <= '1';
                    ir_load             <= '1';  -- Load instruction into IR

                when CYCLE_PCR =>
                    -- Memory read: read data from memory
                    io_buffer_enable    <= '1';
                    io_buffer_direction <= '0';  -- Read from external
                    memory_read         <= '1';
                    -- Note: Address selection (PC vs H:L) is handled by b8008.vhdl
                    -- based on whether we're in cycle 2 of a memory operation

                when CYCLE_PCW =>
                    -- Memory write: write data to memory
                    io_buffer_enable    <= '1';
                    io_buffer_direction <= '1';  -- Write to external
                    memory_write        <= '1';
                    -- Note: Address selection (PC vs H:L) is handled by b8008.vhdl
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

            if current_cycle = 1 then
                -- First cycle T4: Handle single-cycle ALU ops, RET/RST instructions
                if instr_is_alu = '1' and instr_needs_immediate = '0' and instr_reads_reg = '1' then
                    -- Single-cycle ALU operations (INR, DCR, rotate, binary ALU with register)
                    -- Read source register onto bus so Reg.b can load it
                    -- For INR/DCR: source == destination, so use DDD field
                    -- For binary ALU (ADD r, SUB r, etc.): source is SSS, destination is A
                    if instr_writes_reg = '1' and instr_ddd_field /= "000" then
                        -- Unary operations (INR/DCR) - read from DDD field
                        scratchpad_select <= instr_ddd_field;
                    else
                        -- Binary operations or rotate (dest is A) - read from SSS field
                        scratchpad_select <= instr_sss_field;
                    end if;
                    scratchpad_read   <= '1';
                    regfile_to_bus    <= '1';
                elsif instr_is_ret = '1' then
                    -- RET/RFc/RTc: Pop stack during T4 (only if condition met for conditional returns)
                    -- The condition_met signal is already handled by machine_cycle_control
                    -- which only enables T4/T5 if the condition is met
                    stack_pop           <= '1';
                    stack_read          <= '1';  -- Read from stack
                    pc_load_from_stack  <= '1';  -- Load PC from stack
                    select_stack        <= '1';  -- Use stack for address
                    report "MEM_IO: T4 cycle 1 RET - popping from stack and loading PC";
                elsif instr_is_rst = '1' then
                    -- RST: Push current PC to stack during T4, load RST vector during T5
                    stack_push         <= '1';
                    stack_write        <= '1';  -- Write PC to stack
                end if;

            elsif current_cycle = 2 then
                -- Second cycle: data has been read in T3, now write to destination
                if instr_writes_reg = '1' then
                    -- Instructions like LrI, LrM, INP - write to register
                    scratchpad_select <= instr_ddd_field;
                    scratchpad_write  <= '1';
                    bus_to_regfile    <= '1';  -- Bus writes to register file
                    report "MEM_IO: T4 cycle 2, writing to register DDD=" & integer'image(to_integer(unsigned(instr_ddd_field)));
                    -- For memory read (LrM), keep io_buffer enabled to transfer data from external bus
                    if cycle_type = CYCLE_PCR then
                        io_buffer_enable    <= '1';
                        io_buffer_direction <= '0';  -- Read from external
                    end if;
                end if;

            elsif current_cycle = 3 then
                -- Third cycle of CALL - push to stack during T4
                if instr_is_call = '1' then
                    stack_push         <= '1';
                    stack_write        <= '1';  -- Write PC to stack
                    report "MEM_IO: T4 cycle 3 CALL - pushing return address to stack";
                end if;
                -- JMP loads PC during T5, handled below
                -- CALL loads PC during T5, handled below
            end if;

        elsif state_t5 = '1' then
            -- T5: Final extended cycle processing
            -- S2=1, S1=0, S0=1

            -- Single-cycle ALU operations: Write result back to register
            if current_cycle = 1 and instr_is_alu = '1' and instr_writes_reg = '1' and instr_needs_immediate = '0' then
                -- INR, DCR, rotate, binary ALU ops - write ALU result to destination register
                scratchpad_select <= instr_ddd_field;  -- Destination register
                scratchpad_write  <= '1';
                bus_to_regfile    <= '1';  -- ALU result (on internal bus) writes to register
            end if;

            -- JMP/CALL: Load PC from temp registers during T5 of cycle 3
            if current_cycle = 3 and instr_needs_address = '1' then
                pc_load_from_regs  <= '1';  -- Load PC from Reg.a+Reg.b
                if instr_is_call = '1' then
                    report "MEM_IO: Setting pc_load_from_regs at T5 cycle 3 for CALL";
                else
                    report "MEM_IO: Setting pc_load_from_regs at T5 cycle 3 for JMP";
                end if;
            end if;

            -- RET: Keep pc_load_from_stack set during T5 (was set during T4)
            if instr_is_ret = '1' then
                pc_load_from_stack <= '1';  -- Load PC from stack
                select_stack       <= '1';  -- Use stack for address
            end if;

            -- RST: Load PC from RST vector during T5 (stack push happened in T4)
            -- RET is handled in T4, not T5
            if instr_is_rst = '1' then
                pc_load_from_rst    <= '1';  -- Load PC from RST vector
            end if;

        elsif state_t1i = '1' then
            -- T1I: Interrupt acknowledge cycle
            -- S2=1, S1=1, S0=0
            -- External hardware provides interrupt instruction (typically RST 0)
            -- Read instruction from external data bus and load into IR
            io_buffer_enable    <= '1';
            io_buffer_direction <= '0';  -- Read from external
            -- Load IR during second half of T1I (state_half='1') to allow data to stabilize
            ir_load             <= state_half;  -- Load interrupt instruction into IR

        end if;

    end process;

end architecture rtl;

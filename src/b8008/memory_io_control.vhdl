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
        -- Master clock + phi1 rising-edge pulse (one clk cycle wide)
        clk         : in std_logic;
        phi1_rising : in std_logic;

        -- Reset
        reset : in std_logic;

        -- From State Timing Generator
        state_t1      : in std_logic;
        state_t2      : in std_logic;
        state_t3      : in std_logic;
        state_t4      : in std_logic;
        state_t5      : in std_logic;
        state_t1i     : in std_logic;
        state_stopped : in std_logic;
        state_half    : in std_logic;  -- Which half of 2-cycle state (0=first, 1=second)
        status_s0     : in std_logic;
        status_s1     : in std_logic;
        status_s2     : in std_logic;

        -- From Machine Cycle Control
        cycle_type        : in std_logic_vector(1 downto 0);  -- 00=PCI, 01=PCR, 10=PCC, 11=PCW
        current_cycle     : in integer range 0 to 3;  -- 0=cycle1, 1=cycle2, 2=cycle3
        next_cycle        : in integer range 0 to 3;  -- Predicted next cycle (valid at T1 start)
        advance_state     : in std_logic;

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
        eval_condition        : in std_logic;  -- Conditional instruction flag

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

        -- To Scratchpad Multiplexer (Register File)
        scratchpad_select : out std_logic_vector(2 downto 0);  -- Which register to access
        scratchpad_read   : out std_logic;  -- Read from register
        scratchpad_write  : out std_logic;  -- Write to register

        -- To Memory Multiplexer
        memory_read    : out std_logic;  -- Read from memory
        memory_write   : out std_logic;  -- Write to memory

        -- To Memory Multiplexer - Register File routing
        regfile_to_bus : out std_logic;  -- Register file drives internal bus
        bus_to_regfile : out std_logic;  -- Internal bus drives register file

        -- To Memory Multiplexer - PC load source selection
        pc_load_from_regs  : out std_logic;  -- Load PC from temp regs (JMP/CALL)
        pc_load_from_rst   : out std_logic;  -- Load PC from RST vector

        -- To Stack Pointer
        stack_push : out std_logic;  -- Push to stack
        stack_pop  : out std_logic;  -- Pop from stack

        -- To Program Counter
        pc_increment_lower : out std_logic;  -- Increment PC lower byte (T1)
        pc_increment_upper : out std_logic;  -- Increment PC upper byte (T2 if carry)
        pc_carry_in        : in  std_logic;  -- Carry flag from PC
        pc_load            : out std_logic   -- Load PC from data_in
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
    signal prev_state_t3 : std_logic := '0';
    signal prev_state_t4 : std_logic := '0';
    signal prev_state_t5 : std_logic := '0';
    signal state_t2_edge : std_logic;
    signal state_t5_edge : std_logic;

    -- Track when PC was loaded (JMP/CALL/RET/RST) to prevent increment at next T1

    -- Track when entering a cycle that uses H:L address (to suppress PC increment at next T1)
    -- This flag is SET at T5 of the PREVIOUS cycle and CLEARED at T2 of the current cycle.
    -- This ensures the flag is stable when T1 arrives (avoiding delta cycle races).
    -- - LrM/LMr: Set at T5 of cycle 1, suppress PC inc at T1 of cycle 2
    -- - LMI: Set at T5 of cycle 2, suppress PC inc at T1 of cycle 3
    signal suppress_pc_inc_next_cycle : std_logic := '0';

    -- Track when IR was loaded during T1I (interrupt acknowledge)
    -- This suppresses the normal IR load at T3 of cycle 1 since the instruction
    -- was already jammed during T1I. Cleared at T2.
    signal ir_loaded_from_interrupt : std_logic := '0';

begin

    -- Detect rising edges of state signals
    state_t2_edge <= '1' when (state_t2 = '1' and prev_state_t2 = '0') else '0';
    state_t5_edge <= '1' when (state_t5 = '1' and prev_state_t5 = '0') else '0';

    -- Track state transitions and generate edge signals
    process(clk, reset)
    begin
        if reset = '1' then
            prev_state_t2 <= '0';
            prev_state_t3 <= '0';
            prev_state_t4 <= '0';
            prev_state_t5 <= '0';
            suppress_pc_inc_next_cycle <= '0';
            ir_loaded_from_interrupt <= '0';
        elsif rising_edge(clk) and phi1_rising = '1' then
            -- Set flag when entering T1I (instruction will be jammed)
            if state_t1i = '1' and state_half = '1' then
                ir_loaded_from_interrupt <= '1';
                report "MEM_IO: Setting ir_loaded_from_interrupt flag (T1I second half)";
            end if;
            -- Clear the flag at T4 (after T3 completed - uses prev_state_t4 for proper timing)
            -- This ensures the flag is active throughout all of T3 to block IR reload
            if prev_state_t4 = '1' and ir_loaded_from_interrupt = '1' then
                ir_loaded_from_interrupt <= '0';
                report "MEM_IO: Clearing ir_loaded_from_interrupt flag (after T4)";
            end if;
            -- Update previous state values for edge detection
            prev_state_t2 <= state_t2;
            prev_state_t3 <= state_t3;
            prev_state_t4 <= state_t4;
            prev_state_t5 <= state_t5;

            -- Set suppress_pc_inc_next_cycle at the END of the current cycle
            -- when the NEXT cycle doesn't use the PC. Cycles now end at T3
            -- (fetch/middle, empty T4/T5), T4 (LMr fetch), or T5 (tails), so
            -- the trigger fires at whichever end-state the cycle actually
            -- has. The flag is checked at the NEXT T1.
            if (prev_state_t5 = '1' and advance_state = '0') or
               (prev_state_t3 = '1' and advance_state = '0' and current_cycle = 0 and
                (instr_needs_immediate = '1' or instr_needs_address = '1') and
                not (instr_is_mem_indirect = '1' and instr_is_write = '1' and
                     instr_needs_address = '0' and instr_is_io = '0')) or
               (prev_state_t3 = '1' and advance_state = '0' and current_cycle = 1 and
                instr_needs_address = '1') or
               (prev_state_t4 = '1' and advance_state = '0' and current_cycle = 0 and
                instr_is_mem_indirect = '1' and instr_is_write = '1' and
                instr_needs_address = '0' and instr_is_io = '0') then
                report "MEM_IO: At T5 edge, current_cycle=" & integer'image(current_cycle) &
                       " instr_is_mem_indirect=" & std_logic'image(instr_is_mem_indirect) &
                       " instr_needs_address=" & std_logic'image(instr_needs_address) &
                       " instr_is_io=" & std_logic'image(instr_is_io);
                -- At end of T5, check if next cycle uses H:L address or is I/O
                -- LrM/LMr: cycle 1 T5, about to enter cycle 2 (uses H:L)
                -- LMI: cycle 2 T5, about to enter cycle 3 (uses H:L)
                -- INP/OUT: cycle 1 T5, about to enter cycle 2 (I/O port, not PC)
                if instr_is_mem_indirect = '1' then
                    if current_cycle = 0 and instr_needs_address = '0' then
                        -- LrM/LMr: cycle 2 will use H:L
                        suppress_pc_inc_next_cycle <= '1';
                        report "MEM_IO: Setting suppress_pc_inc_next_cycle for LrM/LMr cycle 2";
                    elsif current_cycle = 1 and instr_needs_address = '1' then
                        -- LMI: cycle 3 will use H:L
                        suppress_pc_inc_next_cycle <= '1';
                        report "MEM_IO: Setting suppress_pc_inc_next_cycle for LMI cycle 3";
                    end if;
                end if;
                -- I/O instructions: cycle 2 uses I/O port address, not PC
                if instr_is_io = '1' and current_cycle = 0 then
                    suppress_pc_inc_next_cycle <= '1';
                    report "MEM_IO: Setting suppress_pc_inc_next_cycle for I/O cycle 2";
                end if;
            end if;
            -- Clear the flag at T2 (after T1 increment was suppressed)
            if prev_state_t2 = '1' and suppress_pc_inc_next_cycle = '1' then
                suppress_pc_inc_next_cycle <= '0';
                report "MEM_IO: Clearing suppress_pc_inc_next_cycle";
            end if;

            -- pc_was_loaded is GONE. Under the post-increment convention a
            -- loaded target is simply the next address to fetch - the fetch
            -- sends it out and increments past it like any other. The old
            -- flag was one-shot state that an interrupt jam could consume,
            -- skidding the post-handler resume one byte past a jump target.
        end if;
    end process;

    -- Control signal generation (combinational based on state and cycle)
    process(state_t1, state_t2, state_t3, state_t4, state_t5, state_t1i, state_stopped, state_half,
            status_s0, status_s1, status_s2,
            cycle_type, current_cycle, instr_is_io, instr_is_write, instr_is_mem_indirect,
            condition_met, ready_status, interrupt_pending, eval_condition,
            instr_needs_immediate, instr_needs_address,
            instr_sss_field, instr_ddd_field, instr_is_alu, ir_loaded_from_interrupt,
            instr_is_call, instr_is_ret, instr_is_rst,
            instr_writes_reg, instr_reads_reg, suppress_pc_inc_next_cycle,
            pc_carry_in)
    begin
        -- Defaults: all outputs inactive
        ir_load               <= '0';
        ir_output_enable      <= '0';
        io_buffer_enable      <= '0';
        io_buffer_direction   <= '0';
        scratchpad_select     <= (others => '0');
        scratchpad_read       <= '0';
        scratchpad_write      <= '0';
        memory_read           <= '0';
        memory_write          <= '0';
        regfile_to_bus        <= '0';
        bus_to_regfile        <= '0';
        pc_load_from_regs     <= '0';
        pc_load_from_rst      <= '0';
        stack_push            <= '0';
        stack_pop              <= '0';
        pc_increment_lower     <= '0';
        pc_increment_upper     <= '0';
        pc_load                <= '0';

        -- PC Control Logic (Two-stage increment per 1972 datasheet)
        -- T1: Increment lower byte after address bits sent out
        -- T2: If carry occurred, increment upper byte
        -- Interrupt pending does NOT gate the fetch increments: the real
        -- 8008 completes the in-flight instruction fully (including its PC
        -- advance) and the jam only replaces the NEXT fetch (T1I instead of
        -- T1 - and T1I never increments). The old interrupt_pending hold
        -- robbed the interrupted instruction of its own advance, so the
        -- post-handler resume re-fetched that instruction's last byte and
        -- executed operands as opcodes.
        -- READY no longer gates the PC either: the state machine parks in
        -- a real WAIT state between T2 and T3.

        -- PC increment logic
            -- PC increments when fetching from external memory (via PC address)
            -- PC does NOT increment when using H:L address for memory operations
            -- PC does NOT increment during I/O cycle 2 (PCC cycle uses I/O address, not PC)
            --
            -- The suppress_pc_inc_next_cycle flag is set at T5 of the previous cycle
            -- when we know the next cycle doesn't use PC address. This avoids delta
            -- cycle race conditions with current_cycle.
            --
            -- Increment PC at T1 for:
            -- - Cycle 1: Always (fetching opcode)
            -- - Cycle 2: Unless suppress_pc_inc_next_cycle (LrM/LMr uses H:L, or I/O)
            -- - Cycle 3: Unless suppress_pc_inc_next_cycle (LMI uses H:L)
            --
            -- POST-increment convention (matches the real 8008): the slot
            -- always holds the NEXT address to fetch. T1 first half sends
            -- the address out; T1 SECOND half increments past it. Loads
            -- (JMP/CALL/RST vectors) store the exact target and the next
            -- fetch uses it as-is - no pc_was_loaded suppression flag, so
            -- there is nothing for an interrupt jam to race.
            if state_t1 = '1' and state_half = '1' and state_t1i = '0' and
               suppress_pc_inc_next_cycle = '0' then
                pc_increment_lower <= '1';
            end if;

            -- T2 second half: carry into the upper byte AFTER the upper
            -- address bits went out (first half latches the pre-carry value)
            if state_t2 = '1' and state_half = '1' and pc_carry_in = '1' then
                pc_increment_upper <= '1';
            end if;

            -- PC-in-stack: NO "compute return address" increments for CALL or
            -- RST. The caller's slot holds the last-fetched address; a RET
            -- pops back to it and the next fetch's normal T1 pre-increment
            -- lands on the following instruction. One convention everywhere -
            -- the old pre-adjusted-push + suppressed-fetch pairing broke at
            -- the stack wrap (the wrapped slot was never call-frozen, so the
            -- suppressed fetch re-executed the RET forever).

            -- Load PC during T4/T5 for various instructions
            -- JMP/CALL: T5 of cycle 3 (only if unconditional OR condition met)
            -- RET/RST: T5 of cycle 1
            -- NOTE: LMI also has instr_needs_address='1' but is a write operation - PC should NOT be loaded
            if state_t5 = '1' then
                if current_cycle = 2 and instr_needs_address = '1' and instr_is_write = '0' then
                    -- JMP/CALL: Load PC from Reg.a+Reg.b during T5 of cycle 3
                    -- Only load if unconditional OR condition is met
                    if eval_condition = '0' or condition_met = '1' then
                        pc_load <= '1';
                        if instr_is_call = '1' then
                            report "MEM_IO: Setting pc_load at T5 cycle 3 for CALL";
                        else
                            report "MEM_IO: Setting pc_load at T5 cycle 3 for JMP";
                        end if;
                    end if;
                -- RET: NO pc_load. The PC lives in stack_memory[SP]; the T4
                -- stack_pop already moved SP back, and the return address is
                -- simply sitting in the now-live slot. Loading here would
                -- corrupt it.
                elsif instr_is_rst = '1' then
                    -- RST: Load PC from RST vector during T5
                    pc_load <= '1';
                end if;
            end if;

        -- State-based control
        if state_t1 = '1' then
            -- T1: Output address low byte
            -- S2=0, S1=1, S0=0

            -- Special case: During cycle 2/3 T1/T2 of memory indirect operations,
            -- output H/L registers to data bus for external address latch
            -- - LrM/LMr: cycle 2 uses H:L address
            -- - LMI (MVI M): cycle 3 uses H:L address (cycle 2 uses PC for immediate)
            -- NOTE: Use next_cycle because current_cycle hasn't updated yet at T1 start
            if instr_is_mem_indirect = '1' and
               ((next_cycle = 1 and instr_needs_address = '0') or   -- LrM/LMr: cycle 2
                (next_cycle = 2 and instr_needs_address = '1')) then  -- LMI: cycle 3
                -- Output L register during T1 (ahl_pointer selects L via final_scratchpad_addr)
                scratchpad_read     <= '1';
                regfile_to_bus      <= '1';  -- Register file drives internal bus
                io_buffer_enable    <= '1';
                io_buffer_direction <= '1';  -- Internal bus drives data bus (write direction)
            end if;

            -- Special case: I/O cycle 2 T1 - output REG.A (accumulator) to data bus
            -- Per isa.json: INP/OUT cycle 2, T1: "REG.A TO OUT"
            -- NOTE: Use next_cycle because current_cycle hasn't updated yet at T1 start
            if instr_is_io = '1' and next_cycle = 1 then
                scratchpad_select   <= "000";  -- A register (accumulator)
                scratchpad_read     <= '1';
                regfile_to_bus      <= '1';  -- Register file drives internal bus
                io_buffer_enable    <= '1';
                io_buffer_direction <= '1';  -- Internal bus drives data bus (write direction)
                report "MEM_IO: T1 cycle 2 I/O - outputting REG.A to data bus";
            end if;

        elsif state_t2 = '1' then
            -- T2: Output address high byte + cycle type on D[7:6]
            -- S2=1, S1=0, S0=0
            -- Cycle type encoding is handled by machine_cycle_control
            -- D[7:6] driven from cycle_type signal

            -- Special case: During cycle 2/3 T1/T2 of memory indirect operations,
            -- output H/L registers to data bus for external address latch
            if instr_is_mem_indirect = '1' and
               ((current_cycle = 1 and instr_needs_address = '0') or   -- LrM/LMr: cycle 2
                (current_cycle = 2 and instr_needs_address = '1')) then  -- LMI: cycle 3
                -- Output H register during T2 (ahl_pointer selects H via final_scratchpad_addr)
                scratchpad_read     <= '1';
                regfile_to_bus      <= '1';  -- Register file drives internal bus
                io_buffer_enable    <= '1';
                io_buffer_direction <= '1';  -- Internal bus drives data bus (write direction)
            end if;

            -- Special case: I/O cycle 2 T2 - output REG.b (port number) to data bus
            -- Per isa.json: INP/OUT cycle 2, T2: "REG.b TO OUT"
            -- Reg.b contains the port number from instruction bits (loaded at cycle 1 T3)
            -- This is handled by register_alu_control output_reg_b signal
            if instr_is_io = '1' and current_cycle = 1 then
                io_buffer_enable    <= '1';
                io_buffer_direction <= '1';  -- Internal bus drives data bus (write direction)
                report "MEM_IO: T2 cycle 2 I/O - outputting REG.b (port number) to data bus";
            end if;

        elsif state_t3 = '1' then
            -- T3: Data transfer state (main activity happens here)
            -- S2=0, S1=0, S0=1

            -- Register file access for single-cycle instructions
            -- NOTE: During PCI (instruction fetch), don't access register file at T3!
            -- The instruction is still being loaded, so decoder signals aren't stable yet.
            if current_cycle = 0 and cycle_type /= CYCLE_PCI then
                if instr_reads_reg = '1' then
                    -- ALU operations, MOV, etc. - read source register
                    scratchpad_select <= instr_sss_field;
                    scratchpad_read   <= '1';
                    regfile_to_bus    <= '1';  -- Register file drives internal bus
                end if;
                -- NOTE: MOV register-to-register now writes at T5, not T3 (uses T4/T5 cycle)
                -- T3 writes removed - MOV is no longer a "single-cycle" register write
            end if;

            case cycle_type is
                when CYCLE_PCI =>
                    -- Instruction fetch: read from external memory and load IR
                    -- Cycle type PCI only occurs during cycle 1 (machine_cycle_control ensures this)
                    -- IMPORTANT: Do not load IR if CPU is stopped
                    -- IMPORTANT: Do not load IR if we came from T1I (interrupt jammed instruction)
                    io_buffer_enable    <= '1';
                    io_buffer_direction <= '0';  -- Read from external
                    memory_read         <= '1';
                    if state_stopped = '0' and ir_loaded_from_interrupt = '0' then
                        ir_load <= '1';  -- Load instruction into IR
                    elsif ir_loaded_from_interrupt = '1' then
                        ir_load <= '0';  -- Don't load IR - instruction was jammed during T1I
                        report "MEM_IO: Skipping ir_load - instruction was jammed during T1I";
                    else
                        ir_load <= '0';  -- Don't load IR when stopped
                        report "MEM_IO: Blocking ir_load - CPU is stopped";
                    end if;

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
                    -- Data on internal bus comes from:
                    -- - Register file (LMr) - read from SSS register
                    -- - Reg.b (LMI) - immediate data loaded at cycle 2 T3
                    -- For LMI (3-cycle mem write with immediate), Reg.b drives bus via register_alu_control
                    if current_cycle = 2 and instr_needs_immediate = '1' then
                        -- LMI: Reg.b drives bus (handled by register_alu_control output_reg_b)
                        -- Don't enable scratchpad read - let Reg.b drive
                        null;
                    else
                        -- LMr: read from register file
                        scratchpad_select <= instr_sss_field;
                        scratchpad_read   <= '1';
                        regfile_to_bus    <= '1';
                    end if;

                when CYCLE_PCC =>
                    -- I/O operation (INP/OUT)
                    -- INP: instr_writes_reg='1' (reads from I/O port, writes to A)
                    -- OUT: instr_reads_reg='1' (reads from A, writes to I/O port)
                    io_buffer_enable <= '1';
                    if instr_reads_reg = '1' and instr_writes_reg = '0' then
                        -- OUT: write accumulator to I/O port
                        io_buffer_direction <= '1';  -- Internal to external (write)
                        scratchpad_select   <= "000";  -- A register
                        scratchpad_read     <= '1';
                        regfile_to_bus      <= '1';  -- Register file drives bus
                        report "MEM_IO: T3 CYCLE_PCC OUT - writing A register to I/O port";
                    else
                        -- INP: read from I/O port
                        io_buffer_direction <= '0';  -- External to internal (read)
                        report "MEM_IO: T3 CYCLE_PCC INP - reading from I/O port";
                    end if;

                when others =>
                    null;
            end case;

        elsif state_t4 = '1' then
            -- T4: Extended cycle processing
            -- S2=0, S1=1, S0=1
            -- Used for multi-cycle instructions

            if current_cycle = 0 then
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
                elsif instr_is_ret = '1' and (eval_condition = '0' or condition_met = '1') then
                    -- RET/RFc/RTc: the PC lives in stack_memory[SP], so a
                    -- return is ONLY the pop - SP moves back and the return
                    -- address is already in the now-live slot. No read, no
                    -- load, no data movement.
                    if state_half = '0' then
                        stack_pop           <= '1';  -- Decrement SP in first half
                        report "MEM_IO: T4 cycle 1 RET - pop (slot IS the PC)";
                    end if;
                elsif instr_is_rst = '1' then
                    -- RST: push = SP moves on; the old slot keeps the return
                    -- address it already holds. RST vector loads the NEW
                    -- slot during T5.
                    if state_half = '0' then
                        stack_push         <= '1';
                    end if;
                elsif instr_writes_reg = '1' and instr_reads_reg = '1' and instr_is_alu = '0' and instr_needs_immediate = '0' then
                    -- MOV register-to-register: Read source register (SSS) to internal bus
                    -- Per isa.json T4: "SSS TO REG. b"
                    -- Source register value goes on bus so Reg.b can load it
                    scratchpad_select <= instr_sss_field;  -- Source register
                    scratchpad_read   <= '1';
                    regfile_to_bus    <= '1';  -- Register file drives internal bus
                    report "MEM_IO: T4 cycle 1 MOV, reading SSS=" & integer'image(to_integer(unsigned(instr_sss_field))) & " to bus for Reg.b";
                end if;

            elsif current_cycle = 1 then
                -- Second cycle T4: per isa.json, T4 = "X" for LrI/LrM;
                -- INP outputs the condition flip-flops here ("COND FF
                -- OUT" - register_alu_control enables the flags onto
                -- the internal bus; this opens the buffer outward)
                if instr_is_io = '1' and instr_writes_reg = '1' then
                    io_buffer_enable    <= '1';
                    io_buffer_direction <= '1';  -- internal bus -> external
                end if;
                -- Only ALU immediate ops use T4 to read accumulator for ALU input

                -- For ALU immediate operations (CPI, ADI, etc.), read accumulator to internal bus
                -- so temp register A can load it at T4 (Reg.b already loaded immediate at T3)
                if instr_is_alu = '1' and instr_needs_immediate = '1' then
                    scratchpad_select <= "000";  -- A register (accumulator)
                    scratchpad_read   <= '1';
                    regfile_to_bus    <= '1';  -- Register file drives internal bus
                    report "MEM_IO: T4 cycle 2 ALU immediate, reading accumulator to bus for Reg.a";
                end if;

            elsif current_cycle = 2 then
                -- Third cycle of CALL - push to stack during T4 second half
                -- NOTE: We push at second half because at first half we may need to
                -- increment the PC upper byte if there was a carry from T3 lower increment.
                -- This ensures the correct return address is pushed to the stack.
                -- NOTE: Only push if unconditional OR condition is met
                if instr_is_call = '1' and (eval_condition = '0' or condition_met = '1') then
                    -- Push during second half of T4 (after PC upper increment
                    -- if any). The push is ONLY the SP move - the caller's
                    -- slot keeps the return address it already contains; the
                    -- target loads into the new slot at T5.
                    if state_half = '1' then
                        stack_push         <= '1';
                        report "MEM_IO: T4 cycle 3 CALL - push (SP moves, slot keeps return addr)";
                    end if;
                end if;
                -- JMP loads PC during T5, handled below
                -- CALL loads PC during T5, handled below
            end if;

        elsif state_t5 = '1' then
            -- T5: Final extended cycle processing
            -- S2=1, S1=0, S0=1

            -- Single-cycle ALU operations (cycle 1): Write result back to register
            if current_cycle = 0 and instr_is_alu = '1' and instr_writes_reg = '1' and instr_needs_immediate = '0' then
                -- INR, DCR, rotate, binary ALU ops - write ALU result to destination register
                scratchpad_select <= instr_ddd_field;  -- Destination register
                scratchpad_write  <= '1';
                bus_to_regfile    <= '1';  -- ALU result (on internal bus) writes to register
                report "MEM_IO: T5 cycle 1 ALU, writing result to DDD=" & integer'image(to_integer(unsigned(instr_ddd_field)));
            end if;

            -- Two-cycle ALU immediate operations (cycle 2): Write ALU result back to A register
            -- ADI, SUI, NDI, XRI, ORI - immediate value loaded in T3, ALU executes in T5
            if current_cycle = 1 and instr_is_alu = '1' and instr_writes_reg = '1' and instr_needs_immediate = '1' then
                scratchpad_select <= instr_ddd_field;  -- Destination register (A = 000)
                scratchpad_write  <= '1';
                bus_to_regfile    <= '1';  -- ALU result (on internal bus) writes to A register
                report "MEM_IO: T5 cycle 2 ALU immediate, setting scratchpad_select=" &
                       integer'image(to_integer(unsigned(instr_ddd_field))) &
                       " scratchpad_write=1 bus_to_regfile=1";
            end if;

            -- Two-cycle non-ALU register writes (cycle 2): LrI (MVI), LrM, INP
            -- Per isa.json: T3=DATA TO REG.b, T5=REG.b TO DDD
            -- Reg.b is output by register_alu_control at T5 cycle 2
            if current_cycle = 1 and instr_writes_reg = '1' and instr_is_alu = '0' and instr_needs_immediate = '1' then
                scratchpad_select <= instr_ddd_field;  -- Destination register
                scratchpad_write  <= '1';
                bus_to_regfile    <= '1';  -- Reg.b (on internal bus) writes to destination
                report "MEM_IO: T5 cycle 2 LrI/LrM/INP, writing Reg.b to DDD=" &
                       integer'image(to_integer(unsigned(instr_ddd_field)));
            end if;

            -- MOV register-to-register: Write Reg.b to destination register
            -- Per isa.json T5: "REG. b TO DDD"
            if current_cycle = 0 and instr_writes_reg = '1' and instr_reads_reg = '1' and
               instr_is_alu = '0' and instr_needs_immediate = '0' then
                -- MOV DDD,SSS - Reg.b (loaded at T4 from SSS) now writes to DDD
                scratchpad_select <= instr_ddd_field;  -- Destination register
                scratchpad_write  <= '1';
                bus_to_regfile    <= '1';  -- Reg.b (via internal bus) writes to destination
                report "MEM_IO: T5 MOV instruction, writing Reg.b to DDD=" & integer'image(to_integer(unsigned(instr_ddd_field)));
            end if;

            -- JMP/CALL: Load PC from temp registers during T5 of cycle 3
            -- NOTE: LMI also has instr_needs_address='1' but is a write operation - PC should NOT be loaded
            if current_cycle = 2 and instr_needs_address = '1' and instr_is_write = '0' then
                pc_load_from_regs  <= '1';  -- Load PC from Reg.a+Reg.b
                if instr_is_call = '1' then
                    report "MEM_IO: Setting pc_load_from_regs at T5 cycle 3 for CALL";
                else
                    report "MEM_IO: Setting pc_load_from_regs at T5 cycle 3 for JMP";
                end if;
            end if;

            -- RET does nothing at T5: SP already moved back at T4 and the
            -- live slot IS the return address (PC-in-stack).

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

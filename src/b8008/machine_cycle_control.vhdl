--------------------------------------------------------------------------------
-- machine_cycle_control.vhdl
--------------------------------------------------------------------------------
-- Machine Cycle Control for Intel 8008
--
-- Orchestrates machine cycles (PCI, PCR, PCW, PCC) and generates control signals
-- - Tracks which cycle of instruction (1st, 2nd, or 3rd)
-- - Outputs cycle type (D6, D7) during T2
-- - Signals State Timing Generator when to advance to next instruction
-- - DUMB module: just sequences cycles based on instruction decoder flags
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.b8008_types.all;

entity machine_cycle_control is
    port (
        -- State inputs from State Timing Generator
        state_t1  : in std_logic;
        state_t2  : in std_logic;
        state_t3  : in std_logic;
        state_t4  : in std_logic;
        state_t5  : in std_logic;
        state_t1i : in std_logic;

        -- Instruction decoder inputs
        instr_needs_immediate : in std_logic;  -- Instruction needs 2nd byte
        instr_needs_address   : in std_logic;  -- Instruction needs 14-bit address (2 bytes)
        instr_is_io           : in std_logic;  -- I/O operation
        instr_is_write        : in std_logic;  -- Memory write operation
        instr_is_hlt          : in std_logic;  -- HLT (halt) instruction
        instr_needs_t4t5      : in std_logic;  -- Instruction needs T4/T5 extended states
        eval_condition        : in std_logic;  -- Conditional instruction (JZ, JNZ, CALL, RET, etc.)
        condition_met         : in std_logic;  -- Condition result (1=met, 0=not met)

        -- Outputs to State Timing Generator
        advance_state : out std_logic;  -- Signal to skip to next instruction

        -- Outputs to Memory & I/O Control (cycle type)
        cycle_type : out std_logic_vector(1 downto 0);  -- D6, D7 (only valid during T2)

        -- Cycle tracking (for observation/debug)
        current_cycle : out integer range 1 to 3  -- Which cycle of instruction (1, 2, or 3)
    );
end entity machine_cycle_control;

architecture rtl of machine_cycle_control is

    -- Internal cycle counter
    signal cycle_count : integer range 1 to 3 := 1;

    -- Determine if we need to continue to next cycle
    signal needs_cycle_2 : std_logic;
    signal needs_cycle_3 : std_logic;

    -- Latched advance signal
    signal advance_latch : std_logic := '0';

    -- Latched cycle type signal
    signal cycle_type_latch : std_logic_vector(1 downto 0) := "00";

    -- Determine if current cycle needs T4/T5 (computed based on instruction and cycle)
    signal needs_t4t5_this_cycle : std_logic;

begin

    -- Output current cycle
    current_cycle <= cycle_count;

    -- Determine if instruction needs additional cycles
    -- NOTE: Conditional jumps/calls ALWAYS fetch all 3 bytes (3 cycles)
    -- The condition only affects whether T4/T5 execute in cycle 3
    needs_cycle_2 <= instr_needs_immediate or instr_needs_address;
    needs_cycle_3 <= instr_needs_address;

    -- Determine if current cycle needs T4/T5 states
    -- This depends on both the instruction type AND which cycle we're in
    -- NOTE: Cycle 1 always fetches the opcode, so we can't use instruction decoder
    --       signals during cycle 1 (they reflect the PREVIOUS instruction).
    --       Therefore, cycle 1 is always short (T1-T2-T3).
    --       T4/T5 are only needed in cycles 2-3 for certain instructions.
    -- SPECIAL: In cycle 3 of conditional branches, T4/T5 only execute if condition is met
    needs_t4t5_this_cycle <= '1' when (cycle_count = 2 and instr_needs_t4t5 = '1') else  -- Cycle 2: always if decoder says so
                             '1' when (cycle_count = 3 and instr_needs_t4t5 = '1' and
                                      (condition_met = '1' or eval_condition = '0')) else  -- Cycle 3: only if condition met (or unconditional)
                             '0';

    -- Output latched cycle type
    cycle_type <= cycle_type_latch;

    -- Output latched advance signal
    advance_state <= advance_latch;

    -- Cycle type latch - latch value during T2 rising edge
    process(state_t2)
    begin
        if rising_edge(state_t2) then
            if cycle_count = 1 then
                -- First cycle is always PCI
                cycle_type_latch <= "00";
                report "MCycle: T2 cycle_type=PCI (cycle 1)";
            elsif instr_is_io = '1' then
                -- I/O operation: PCC
                cycle_type_latch <= "10";
                report "MCycle: T2 cycle_type=PCC (I/O)";
            elsif instr_is_write = '1' then
                -- Memory write: PCW
                cycle_type_latch <= "11";
                report "MCycle: T2 cycle_type=PCW (write)";
            else
                -- Memory read: PCR
                cycle_type_latch <= "01";
                report "MCycle: T2 cycle_type=PCR (read) cycle=" & integer'image(cycle_count);
            end if;
        end if;
    end process;

    -- Advance state logic - set when instruction/cycle is complete
    -- This is checked by state_timing_generator to decide when to return to T1
    --
    -- Key insight: advance_state should ONLY be set when we're DONE with the cycle
    -- - Short cycles: Set at T3 (last state)
    -- - Extended cycles: Set at T5 (last state)
    -- - Never set between T3 and T5 for extended cycles!
    process(state_t3, state_t5, state_t1, instr_is_hlt, needs_t4t5_this_cycle, cycle_count, needs_cycle_2, needs_cycle_3)
    begin
        if rising_edge(state_t1) then
            -- Clear at start of new cycle
            advance_latch <= '0';

        elsif rising_edge(state_t3) then
            -- Only set if this is a SHORT cycle (no T4/T5) AND cycle is complete
            report "MCycle: T3 rising, cycle=" & integer'image(cycle_count) &
                   " needs_t4t5_this=" & std_logic'image(needs_t4t5_this_cycle);
            if instr_is_hlt = '0' and needs_t4t5_this_cycle = '0' and
               ((cycle_count = 1 and needs_cycle_2 = '0') or      -- Single-cycle done
                (cycle_count = 2 and needs_cycle_3 = '0') or      -- Two-cycle done
                (cycle_count = 3)) then                           -- Three-cycle done
                advance_latch <= '1';
                report "MCycle: Setting advance_latch at T3 (short cycle complete)";
            end if;

        elsif rising_edge(state_t5) then
            -- Set at T5 when cycle is complete (extended cycles end here)
            report "MCycle: T5 rising, cycle=" & integer'image(cycle_count);
            if instr_is_hlt = '0' and
               ((cycle_count = 1 and needs_cycle_2 = '0') or      -- Single-cycle done
                (cycle_count = 2 and needs_cycle_3 = '0') or      -- Two-cycle done
                (cycle_count = 3)) then                           -- Three-cycle done
                advance_latch <= '1';
                report "MCycle: Setting advance_latch at T5 (extended cycle complete)";
            end if;
        end if;
    end process;

    -- Cycle counter state machine
    -- Updates on rising edge of T1 (start of each new cycle)
    -- OR on rising edge of T1I (interrupt acknowledge - counts as cycle 1)
    process(state_t1, state_t1i)
    begin
        if rising_edge(state_t1i) then
            -- T1I is interrupt acknowledge - this is the cycle 1 instruction fetch
            -- Set cycle counter to 1 (it should already be, but ensure it)
            cycle_count <= 1;
        elsif rising_edge(state_t1) then
            -- We're entering T1 (start of new cycle or new instruction)
            report "MCycle: T1 rising, cycle=" & integer'image(cycle_count) &
                   " needs_cycle_2=" & std_logic'image(needs_cycle_2) &
                   " needs_cycle_3=" & std_logic'image(needs_cycle_3) &
                   " instr_needs_address=" & std_logic'image(instr_needs_address);
            if cycle_count = 1 and needs_cycle_2 = '1' then
                -- Continue to cycle 2
                cycle_count <= 2;
            elsif cycle_count = 2 and needs_cycle_3 = '1' then
                -- Continue to cycle 3
                cycle_count <= 3;
            else
                -- Start new instruction (reset to cycle 1)
                cycle_count <= 1;
            end if;
        end if;
    end process;

end architecture rtl;

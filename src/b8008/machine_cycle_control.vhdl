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
--
-- Uses phi1 as clock, detects state transitions via edge detection
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.b8008_types.all;

entity machine_cycle_control is
    port (
        -- Clock and reset
        phi1  : in std_logic;
        reset : in std_logic;

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
        advance_state     : out std_logic;  -- Signal to skip to next instruction
        instr_is_hlt_flag : out std_logic;  -- Latched HLT flag for state machine

        -- Outputs to Memory & I/O Control (cycle type)
        cycle_type : out std_logic_vector(1 downto 0);  -- D6, D7 (only valid during T2)

        -- Cycle tracking (for observation/debug)
        -- Cycles encoded as: 0=cycle1, 1=cycle2, 2=cycle3
        current_cycle : out integer range 0 to 3;  -- Which cycle of instruction (0, 1, or 2)

        -- Next cycle prediction (combinational, valid during T1)
        -- Use this instead of current_cycle when making decisions at T1 start
        next_cycle : out integer range 0 to 3  -- What cycle will be after T1 rising
    );
end entity machine_cycle_control;

architecture rtl of machine_cycle_control is

    -- Internal cycle counter (0=cycle1, 1=cycle2, 2=cycle3)
    signal cycle_count : integer range 0 to 3 := 0;

    -- Determine if we need to continue to next cycle
    signal needs_cycle_2 : std_logic;
    signal needs_cycle_3 : std_logic;

    -- Latched advance signal
    signal advance_latch : std_logic := '0';

    -- Latched cycle type signal
    signal cycle_type_latch : std_logic_vector(1 downto 0) := "00";

    -- Latched HLT signal (captured at T3 for state machine)
    signal instr_is_hlt_latch : std_logic := '0';

    -- Determine if current cycle needs T4/T5 (computed based on instruction and cycle)
    signal needs_t4t5_this_cycle : std_logic;

    -- Previous state values for edge detection
    signal prev_state_t1  : std_logic := '0';
    signal prev_state_t2  : std_logic := '0';
    signal prev_state_t3  : std_logic := '0';
    signal prev_state_t4  : std_logic := '0';
    signal prev_state_t5  : std_logic := '0';
    signal prev_state_t1i : std_logic := '0';

    -- Edge detection signals
    signal t1_rising  : std_logic;
    signal t2_rising  : std_logic;
    signal t3_rising  : std_logic;
    signal t4_rising  : std_logic;
    signal t5_rising  : std_logic;
    signal t1i_rising : std_logic;

begin

    -- Output current cycle (directly from registered cycle_count)
    current_cycle <= cycle_count;

    -- Determine if instruction needs additional cycles
    needs_cycle_2 <= instr_needs_immediate or instr_needs_address;
    needs_cycle_3 <= instr_needs_address;

    -- Compute next_cycle (what the cycle will be after T1 processing)
    -- This predicts the cycle counter update that happens at t1_rising
    -- Use this for decisions at the START of T1 (before cycle_count is updated)
    next_cycle <= 0 when state_t1i = '1' else  -- T1I always starts cycle 0
                  1 when (cycle_count = 0 and needs_cycle_2 = '1') else
                  2 when (cycle_count = 1 and needs_cycle_3 = '1') else
                  0;  -- Default: new instruction (cycle 0)

    -- Determine if current cycle needs T4/T5 states
    needs_t4t5_this_cycle <= '1' when (cycle_count = 0 and instr_needs_t4t5 = '1' and
                                      (condition_met = '1' or eval_condition = '0')) else
                             '1' when (cycle_count = 1 and instr_needs_t4t5 = '1') else
                             '1' when (cycle_count = 2 and instr_needs_t4t5 = '1' and
                                      (condition_met = '1' or eval_condition = '0')) else
                             '0';

    -- Output latched values
    cycle_type <= cycle_type_latch;
    advance_state <= advance_latch;
    instr_is_hlt_flag <= instr_is_hlt_latch;

    -- Edge detection (combinational)
    t1_rising  <= state_t1  and not prev_state_t1;
    t2_rising  <= state_t2  and not prev_state_t2;
    t3_rising  <= state_t3  and not prev_state_t3;
    t4_rising  <= state_t4  and not prev_state_t4;
    t5_rising  <= state_t5  and not prev_state_t5;
    t1i_rising <= state_t1i and not prev_state_t1i;

    -- Single synchronous process for all state machine logic
    process(phi1, reset)
    begin
        if reset = '1' then
            cycle_count <= 0;
            advance_latch <= '0';
            cycle_type_latch <= "00";
            instr_is_hlt_latch <= '0';
            prev_state_t1 <= '0';
            prev_state_t2 <= '0';
            prev_state_t3 <= '0';
            prev_state_t4 <= '0';
            prev_state_t5 <= '0';
            prev_state_t1i <= '0';
        elsif rising_edge(phi1) then
            -- Update previous state values for edge detection
            prev_state_t1  <= state_t1;
            prev_state_t2  <= state_t2;
            prev_state_t3  <= state_t3;
            prev_state_t4  <= state_t4;
            prev_state_t5  <= state_t5;
            prev_state_t1i <= state_t1i;

            -- Cycle type latch - set when entering T2
            if t2_rising = '1' then
                if cycle_count = 0 then
                    cycle_type_latch <= "00";  -- PCI
                    report "MCycle: T2 cycle_type=PCI (cycle 1)";
                elsif instr_is_io = '1' then
                    cycle_type_latch <= "10";  -- PCC
                    report "MCycle: T2 cycle_type=PCC (I/O)";
                elsif instr_is_write = '1' and
                      ((cycle_count = 1 and instr_needs_address = '0') or
                       (cycle_count = 2 and instr_needs_address = '1')) then
                    cycle_type_latch <= "11";  -- PCW
                    report "MCycle: T2 cycle_type=PCW (write)";
                else
                    cycle_type_latch <= "01";  -- PCR
                    report "MCycle: T2 cycle_type=PCR (read)";
                end if;
            end if;

            -- Advance state logic
            if t1i_rising = '1' then
                -- Clear when entering interrupt acknowledge
                advance_latch <= '0';
                instr_is_hlt_latch <= '0';

            elsif t1_rising = '1' then
                -- Clear at start of new cycle
                advance_latch <= '0';
                instr_is_hlt_latch <= '0';

            elsif t3_rising = '1' then
                -- Short cycle complete check
                if needs_t4t5_this_cycle = '0' and
                   ((cycle_count = 1 and needs_cycle_3 = '0') or
                    (cycle_count = 2)) then
                    advance_latch <= '1';
                    report "MCycle: Setting advance_latch at T3 (short cycle complete)";
                elsif instr_is_hlt = '1' and cycle_count = 0 then
                    advance_latch <= '1';
                    instr_is_hlt_latch <= '1';
                    report "MCycle: Setting advance_latch at T3 for HLT";
                end if;

            elsif t4_rising = '1' then
                -- Single-cycle short instruction complete
                if instr_is_hlt = '0' and cycle_count = 0 and
                   needs_t4t5_this_cycle = '0' and needs_cycle_2 = '0' then
                    advance_latch <= '1';
                    report "MCycle: Setting advance_latch at T4 (short single-cycle complete)";
                end if;

            elsif t5_rising = '1' then
                -- Extended cycle complete
                if instr_is_hlt = '0' and
                   ((cycle_count = 0 and needs_cycle_2 = '0') or
                    (cycle_count = 1 and needs_cycle_3 = '0') or
                    (cycle_count = 2)) then
                    advance_latch <= '1';
                    report "MCycle: Setting advance_latch at T5 (extended cycle complete)";
                end if;
            end if;

            -- Cycle counter update
            if t1i_rising = '1' then
                cycle_count <= 0;
            elsif t1_rising = '1' then
                report "MCycle: T1 rising, cycle=" & integer'image(cycle_count);
                if cycle_count = 0 and needs_cycle_2 = '1' then
                    cycle_count <= 1;
                elsif cycle_count = 1 and needs_cycle_3 = '1' then
                    cycle_count <= 2;
                else
                    cycle_count <= 0;
                end if;
            end if;
        end if;
    end process;

end architecture rtl;

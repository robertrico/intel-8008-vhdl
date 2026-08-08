--------------------------------------------------------------------------------
-- state_timing_generator.vhdl
--------------------------------------------------------------------------------
-- State Timing Generator for Intel 8008
--
-- Generates timing states T1, T2, T3, T4, T5, and T1I
-- - Each state lasts TWO complete phi1+phi2 clock cycles
-- - Advances through states based on control signals
-- - T1I (interrupt acknowledge) can occur after T3, T4, or T5
-- - DUMB module: just counts and sequences, no instruction knowledge
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.b8008_types.all;

entity state_timing_generator is
    port (
        -- Master clock + phi2 falling-edge pulse (one clk cycle wide)
        clk          : in std_logic;
        phi2_falling : in std_logic;

        -- Reset input for FPGA deterministic startup
        -- (The real 8008 powers up in STOPPED state; reset provides same behavior)
        reset : in std_logic;

        -- Control inputs
        advance_state         : in std_logic;  -- Instruction complete: next T1 fetches
        cycle_done            : in std_logic;  -- Machine cycle over mid-instruction: next T1 continues it
        interrupt_pending     : in std_logic;  -- Interrupt waiting to be serviced
        ready                 : in std_logic;  -- Ready signal (1=ready, 0=wait)
        transition_to_stopped : in std_logic;  -- From decoder: transition to STOPPED at T3

        -- State outputs (one-hot)
        state_t1      : out std_logic;
        state_t2      : out std_logic;
        state_t3      : out std_logic;
        state_t4      : out std_logic;
        state_t5      : out std_logic;
        state_t1i     : out std_logic;
        state_stopped : out std_logic;

        -- State half indicator (which cycle of the 2-cycle state)
        state_half : out std_logic;  -- 0 = first cycle, 1 = second cycle

        -- Status signals (for external use and internal control blocks)
        status_s0 : out std_logic;
        status_s1 : out std_logic;
        status_s2 : out std_logic
    );
end entity state_timing_generator;

architecture rtl of state_timing_generator is

    -- State type
    type state_t is (S_STOPPED, S_T1, S_T2, S_WAIT, S_T3, S_T4, S_T5, S_T1I);
    signal current_state : state_t := S_STOPPED;
    signal next_state : state_t;

    -- Cycle counter within each state (each state = 2 clock cycles)
    signal cycle_count : std_logic := '0';  -- 0 = first cycle, 1 = second cycle

begin

    -- Output current state (one-hot)
    state_t1      <= '1' when current_state = S_T1      else '0';
    state_t2      <= '1' when current_state = S_T2      else '0';
    state_t3      <= '1' when current_state = S_T3      else '0';
    state_t4      <= '1' when current_state = S_T4      else '0';
    state_t5      <= '1' when current_state = S_T5      else '0';
    state_t1i     <= '1' when current_state = S_T1I     else '0';
    state_stopped <= '1' when current_state = S_STOPPED else '0';

    -- Output which half of state we're in
    state_half <= cycle_count;

    -- Generate status signals S0, S1, S2 based on current state
    -- STOPPED: S2=0, S1=1, S0=1 (binary 011 = 3)
    -- T1:      S2=0, S1=1, S0=0 (binary 010 = 2)
    -- T2:      S2=1, S1=0, S0=0 (binary 100 = 4)
    -- T3:      S2=0, S1=0, S0=1 (binary 001 = 1)
    -- T4:      S2=1, S1=1, S0=1 (binary 111 = 7)
    -- T5:      S2=1, S1=0, S0=1 (binary 101 = 5)
    -- T1I:     S2=1, S1=1, S0=0 (binary 110 = 6)
    -- WAIT:    S2=0, S1=0, S0=0 (binary 000 = 0) - S_WAIT is in none of the
    --          three terms below, so the encoding falls out naturally
    status_s0 <= '1' when (current_state = S_STOPPED or current_state = S_T3 or current_state = S_T4 or current_state = S_T5) else '0';
    status_s1 <= '1' when (current_state = S_STOPPED or current_state = S_T1 or current_state = S_T4 or current_state = S_T1I) else '0';
    status_s2 <= '1' when (current_state = S_T2 or current_state = S_T4 or current_state = S_T5 or current_state = S_T1I) else '0';

    -- State advancement logic (combinational)
    process(current_state, advance_state, cycle_done, interrupt_pending, transition_to_stopped, cycle_count, ready)
    begin
        -- Default: stay in current state
        next_state <= current_state;

        case current_state is
            when S_STOPPED =>
                -- STOPPED state: CPU waits for interrupt to begin execution
                -- Only exit STOPPED when interrupt is pending
                if interrupt_pending = '1' then
                    next_state <= S_T1I;  -- Go directly to T1I (interrupt acknowledge)
                end if;
                -- Otherwise stay in STOPPED

            when S_T1 =>
                -- T1 always goes to T2 (after 2 cycles)
                if cycle_count = '1' then
                    next_state <= S_T2;
                end if;

            when S_T1I =>
                -- T1I always goes to T2 (after 2 cycles)
                if cycle_count = '1' then
                    next_state <= S_T2;
                end if;

            when S_T2 =>
                -- T2 goes to T3, or parks in WAIT while READY is low
                -- (real 8008: READY sampled at end of T2, WAIT stretches
                -- the memory access until the slow device catches up)
                if cycle_count = '1' then
                    if ready = '0' then
                        next_state <= S_WAIT;
                    else
                        next_state <= S_T3;
                    end if;
                end if;

            when S_WAIT =>
                -- Park until READY returns; status lines read 000 (WAIT)
                if cycle_count = '1' and ready = '1' then
                    next_state <= S_T3;
                end if;

            when S_T3 =>
                -- T3 can go to T4, back to T1/T1I, or to STOPPED based on control
                if cycle_count = '1' then
                    -- Priority 1: HLT stops immediately (combinatorial from decoder)
                    if transition_to_stopped = '1' then
                        next_state <= S_STOPPED;
                    -- Priority 2: Instruction complete at T3
                    elsif advance_state = '1' then
                        -- Short instruction complete (e.g. not-taken RFc: 3 states)
                        if interrupt_pending = '1' then
                            next_state <= S_T1I;
                        else
                            next_state <= S_T1;
                        end if;
                    -- Priority 3: machine cycle over, instruction continues
                    -- (fetch/middle cycles with empty T4/T5 per the ISA table;
                    -- NO interrupt check - mid-instruction per Figure 2)
                    elsif cycle_done = '1' then
                        next_state <= S_T1;
                    -- Priority 4: Continue to T4
                    else
                        next_state <= S_T4;
                    end if;
                end if;

            when S_T4 =>
                -- T4 can go to T5 or back to T1/T1I based on control
                if cycle_count = '1' then
                    if advance_state = '1' then
                        -- Start new instruction
                        if interrupt_pending = '1' then
                            next_state <= S_T1I;
                        else
                            next_state <= S_T1;
                        end if;
                    elsif cycle_done = '1' then
                        -- Cycle used T4 but not T5 (LMr fetch cycle);
                        -- instruction continues - no interrupt check
                        next_state <= S_T1;
                    else
                        -- Continue to T5
                        next_state <= S_T5;
                    end if;
                end if;

            when S_T5 =>
                -- T5 goes back to T1, or to T1I when an interrupt is
                -- pending AND the instruction is complete (advance_state).
                -- Without the advance_state gate a multi-cycle instruction
                -- could be hijacked between its own machine cycles - the
                -- 8008 recognizes interrupts at instruction boundaries only.
                if cycle_count = '1' then
                    if interrupt_pending = '1' and advance_state = '1' then
                        next_state <= S_T1I;
                    else
                        next_state <= S_T1;
                    end if;
                end if;

        end case;
    end process;

    -- State machine and cycle counter (sequential)
    -- Advances on falling edge of phi2 (end of each clock cycle), gated on
    -- clk domain so the whole CPU shares one clock tree.
    process(clk, reset)
    begin
        if reset = '1' then
            current_state <= S_STOPPED;
            cycle_count <= '0';
        elsif rising_edge(clk) and phi2_falling = '1' then
            -- READY handling lives in the T2/WAIT arms of the next-state
            -- logic (proper WAIT state, status 000), not as a global freeze
            if cycle_count = '0' then
                -- First cycle of state, move to second cycle
                cycle_count <= '1';
            else
                -- Second cycle of state, advance to next state and reset counter
                cycle_count <= '0';
                current_state <= next_state;
                report "STATE: " & state_t'image(current_state) & " -> " & state_t'image(next_state);
            end if;
        end if;
    end process;

end architecture rtl;

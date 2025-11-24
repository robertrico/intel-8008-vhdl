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
        -- Clock inputs from phase clock generator
        phi1 : in std_logic;
        phi2 : in std_logic;

        -- Control inputs
        advance_state    : in std_logic;  -- Advance to next state
        interrupt_pending : in std_logic;  -- Interrupt waiting to be serviced
        ready            : in std_logic;  -- Ready signal (1=ready, 0=wait)

        -- State outputs (one-hot)
        state_t1  : out std_logic;
        state_t2  : out std_logic;
        state_t3  : out std_logic;
        state_t4  : out std_logic;
        state_t5  : out std_logic;
        state_t1i : out std_logic;

        -- State half indicator (which cycle of the 2-cycle state)
        state_half : out std_logic  -- 0 = first cycle, 1 = second cycle
    );
end entity state_timing_generator;

architecture rtl of state_timing_generator is

    -- State type
    type state_t is (S_T1, S_T2, S_T3, S_T4, S_T5, S_T1I);
    signal current_state : state_t := S_T1;
    signal next_state : state_t;

    -- Cycle counter within each state (each state = 2 clock cycles)
    signal cycle_count : std_logic := '0';  -- 0 = first cycle, 1 = second cycle

begin

    -- Output current state (one-hot)
    state_t1  <= '1' when current_state = S_T1  else '0';
    state_t2  <= '1' when current_state = S_T2  else '0';
    state_t3  <= '1' when current_state = S_T3  else '0';
    state_t4  <= '1' when current_state = S_T4  else '0';
    state_t5  <= '1' when current_state = S_T5  else '0';
    state_t1i <= '1' when current_state = S_T1I else '0';

    -- Output which half of state we're in
    state_half <= cycle_count;

    -- State advancement logic (combinational)
    process(current_state, advance_state, interrupt_pending, cycle_count)
    begin
        -- Default: stay in current state
        next_state <= current_state;

        case current_state is
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
                -- T2 always goes to T3 (after 2 cycles)
                if cycle_count = '1' then
                    next_state <= S_T3;
                end if;

            when S_T3 =>
                -- T3 can go to T4 or back to T1/T1I based on control
                if cycle_count = '1' then
                    if advance_state = '1' then
                        -- Start new instruction
                        if interrupt_pending = '1' then
                            next_state <= S_T1I;
                        else
                            next_state <= S_T1;
                        end if;
                    else
                        -- Continue to T4
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
                    else
                        -- Continue to T5
                        next_state <= S_T5;
                    end if;
                end if;

            when S_T5 =>
                -- T5 always goes back to T1/T1I (after 2 cycles)
                if cycle_count = '1' then
                    if interrupt_pending = '1' then
                        next_state <= S_T1I;
                    else
                        next_state <= S_T1;
                    end if;
                end if;

        end case;
    end process;

    -- State machine and cycle counter (sequential)
    -- Advances on falling edge of phi2 (end of each clock cycle)
    process(phi2)
    begin
        if falling_edge(phi2) then
            -- Only advance if READY is high
            if ready = '1' then
                if cycle_count = '0' then
                    -- First cycle of state, move to second cycle
                    cycle_count <= '1';
                else
                    -- Second cycle of state, advance to next state and reset counter
                    cycle_count <= '0';
                    current_state <= next_state;
                end if;
            end if;
            -- If READY is low, we wait (stretch the current state)
        end if;
    end process;

end architecture rtl;

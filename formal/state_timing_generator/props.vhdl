------------------------------------------------------------------
-- props.vhdl: formal properties for state_timing_generator
--
-- The FSM the whole CPU's timing rests on. Proves:
--   P1  reset forces STOPPED, half 0
--   P2  state outputs are one-hot or all-zero (all-zero = WAIT)
--   P3  status S2S1S0 encoding matches the state, incl WAIT = 000
--   P4+ every legal transition arc, with the T3/T4 priority order
--       (transition_to_stopped > advance_state > cycle_done > default)
--   PH  state vector holds when there is no advance edge
--   PT  state_half toggles exactly on phi2_falling, holds otherwise
-- plus reachability covers for T5, WAIT, and the STOPPED exit.
--
-- A state transition is latched at rising_edge(clk) when
-- phi2_falling = 1 AND state_half = 1 (second half of the 2-cycle
-- state). adv_edge names that condition.
------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity state_timing_props is
    port (
        clk                   : in std_logic;
        phi2_falling          : in std_logic;
        reset                 : in std_logic;
        advance_state         : in std_logic;
        cycle_done            : in std_logic;
        interrupt_pending     : in std_logic;
        ready                 : in std_logic;
        instr_is_hlt_flag     : in std_logic;
        transition_to_stopped : in std_logic
    );
end entity state_timing_props;

architecture formal of state_timing_props is
    signal t1, t2, t3, t4, t5, t1i, stopped : std_logic;
    signal half, s0, s1, s2                 : std_logic;

    -- packed views for the invariants
    signal vec       : std_logic_vector(6 downto 0);
    signal stat      : std_logic_vector(2 downto 0);
    signal in_wait   : std_logic;
    signal adv_edge  : std_logic;

    -- one cycle of history for the hold/toggle properties
    signal vec_prev  : std_logic_vector(6 downto 0) := (others => '0');
    signal half_prev : std_logic := '0';
begin

    dut: entity work.state_timing_generator
        port map (
            clk => clk, phi2_falling => phi2_falling, reset => reset,
            advance_state => advance_state, cycle_done => cycle_done,
            interrupt_pending => interrupt_pending, ready => ready,
            instr_is_hlt_flag => instr_is_hlt_flag,
            transition_to_stopped => transition_to_stopped,
            state_t1 => t1, state_t2 => t2, state_t3 => t3,
            state_t4 => t4, state_t5 => t5, state_t1i => t1i,
            state_stopped => stopped, state_half => half,
            status_s0 => s0, status_s1 => s1, status_s2 => s2);

    vec      <= stopped & t1i & t5 & t4 & t3 & t2 & t1;
    stat     <= s2 & s1 & s0;
    in_wait  <= '1' when vec = "0000000" else '0';
    adv_edge <= phi2_falling and half and not reset;

    history: process(clk)
    begin
        if rising_edge(clk) then
            vec_prev  <= vec;
            half_prev <= half;
        end if;
    end process;

    default clock is rising_edge(clk);

    -- P1: reset dominates (async, visible same sample as with stack_pointer)
    assert always (reset = '1') -> (stopped = '1' and half = '0');

    -- P2: one-hot or all-zero (all-zero is the WAIT state)
    assert always (vec = "0000000" or vec = "0000001" or vec = "0000010"
                or vec = "0000100" or vec = "0001000" or vec = "0010000"
                or vec = "0100000" or vec = "1000000");

    -- P3: status encoding table (datasheet: STOPPED 011, T1 010, T2 100,
    -- T3 001, T4 111, T5 101, T1I 110, WAIT 000)
    assert always (stopped = '1') -> (stat = "011");
    assert always (t1  = '1') -> (stat = "010");
    assert always (t2  = '1') -> (stat = "100");
    assert always (t3  = '1') -> (stat = "001");
    assert always (t4  = '1') -> (stat = "111");
    assert always (t5  = '1') -> (stat = "101");
    assert always (t1i = '1') -> (stat = "110");
    assert always (in_wait = '1') -> (stat = "000");

    -- P4: transition arcs, one property per (source, condition) pair.
    -- Condition sampled at the advance edge, target checked next sample.

    -- T1 and T1I always fall through to T2
    assert (always ((adv_edge and t1)  = '1') -> next (t2 = '1'))
        abort (reset = '1');
    assert (always ((adv_edge and t1i) = '1') -> next (t2 = '1'))
        abort (reset = '1');

    -- T2: READY high proceeds to T3, READY low parks in WAIT
    assert (always ((adv_edge and t2 and ready) = '1') -> next (t3 = '1'))
        abort (reset = '1');
    assert (always ((adv_edge and t2 and not ready) = '1') -> next (in_wait = '1'))
        abort (reset = '1');

    -- WAIT: stays parked while READY low, proceeds to T3 when high
    assert (always ((adv_edge and in_wait and ready) = '1') -> next (t3 = '1'))
        abort (reset = '1');
    assert (always ((adv_edge and in_wait and not ready) = '1') -> next (in_wait = '1'))
        abort (reset = '1');

    -- T3 priority chain: STOPPED > advance_state (int steers T1I/T1)
    --                    > cycle_done > default T4
    assert (always ((adv_edge and t3 and transition_to_stopped) = '1')
            -> next (stopped = '1')) abort (reset = '1');
    assert (always ((adv_edge and t3 and not transition_to_stopped
                     and advance_state and interrupt_pending) = '1')
            -> next (t1i = '1')) abort (reset = '1');
    assert (always ((adv_edge and t3 and not transition_to_stopped
                     and advance_state and not interrupt_pending) = '1')
            -> next (t1 = '1')) abort (reset = '1');
    assert (always ((adv_edge and t3 and not transition_to_stopped
                     and not advance_state and cycle_done) = '1')
            -> next (t1 = '1')) abort (reset = '1');
    assert (always ((adv_edge and t3 and not transition_to_stopped
                     and not advance_state and not cycle_done) = '1')
            -> next (t4 = '1')) abort (reset = '1');

    -- T4 priority chain: advance_state > cycle_done > default T5
    assert (always ((adv_edge and t4 and advance_state and interrupt_pending) = '1')
            -> next (t1i = '1')) abort (reset = '1');
    assert (always ((adv_edge and t4 and advance_state and not interrupt_pending) = '1')
            -> next (t1 = '1')) abort (reset = '1');
    assert (always ((adv_edge and t4 and not advance_state and cycle_done) = '1')
            -> next (t1 = '1')) abort (reset = '1');
    assert (always ((adv_edge and t4 and not advance_state and not cycle_done) = '1')
            -> next (t5 = '1')) abort (reset = '1');

    -- T5: interrupt honored only at instruction boundary (advance_state)
    assert (always ((adv_edge and t5 and interrupt_pending and advance_state) = '1')
            -> next (t1i = '1')) abort (reset = '1');
    assert (always ((adv_edge and t5 and not (interrupt_pending and advance_state)) = '1')
            -> next (t1 = '1')) abort (reset = '1');

    -- STOPPED: only an interrupt wakes it, into T1I
    assert (always ((adv_edge and stopped and interrupt_pending) = '1')
            -> next (t1i = '1')) abort (reset = '1');
    assert (always ((adv_edge and stopped and not interrupt_pending) = '1')
            -> next (stopped = '1')) abort (reset = '1');

    -- PH: without an advance edge the state vector holds
    assert (always (adv_edge = '0') -> next (vec = vec_prev))
        abort (reset = '1');

    -- PT: half toggles exactly on phi2_falling pulses
    assert (always ((phi2_falling and not reset) = '1') -> next (half = not half_prev))
        abort (reset = '1');
    assert (always (phi2_falling = '0') -> next (half = half_prev))
        abort (reset = '1');

    -- Reachability: a full T1..T5 walk, the WAIT park, the STOPPED exit
    cover {t5 = '1'};
    cover {in_wait = '1'};
    cover {stopped = '1' and interrupt_pending = '1' and adv_edge = '1'; t1i = '1'};

end architecture formal;

------------------------------------------------------------------
-- props.vhdl: formal properties for machine_cycle_control
--
-- First assume-guarantee module: the state inputs come from
-- state_timing_generator, which we PROVED emits one-hot-or-zero
-- states. That proof licenses the assume below; without it the
-- solver drives impossible multi-hot states.
--
-- Proves:
--   P1  reset clears counter, latches
--   P2  current_cycle never reaches 3
--   P3  cycle_type latch table: PCI at cycle 0, PCC for I/O,
--       PCW for the write cycle, PCR otherwise; holds between latches
--   P4  advance_state and cycle_done never both set
--   P5  both clear at the start of a new cycle (T1/T1I entry)
--   P6  next_cycle at a T1 edge predicts current_cycle after it
--   P7  HLT at T3 of cycle 0 sets advance + latched HLT flag
------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity machine_cycle_props is
    port (
        clk                   : in std_logic;
        phi1_rising           : in std_logic;
        reset                 : in std_logic;
        state_t1              : in std_logic;
        state_t2              : in std_logic;
        state_t3              : in std_logic;
        state_t4              : in std_logic;
        state_t5              : in std_logic;
        state_t1i             : in std_logic;
        state_half            : in std_logic;
        instr_needs_immediate : in std_logic;
        instr_needs_address   : in std_logic;
        instr_is_io           : in std_logic;
        instr_is_write        : in std_logic;
        instr_is_hlt          : in std_logic;
        instr_needs_t4t5      : in std_logic;
        instr_is_mem_indirect : in std_logic;
        eval_condition        : in std_logic;
        condition_met         : in std_logic
    );
end entity machine_cycle_props;

architecture formal of machine_cycle_props is
    signal advance_state     : std_logic;
    signal cycle_done        : std_logic;
    signal cycle_type        : std_logic_vector(1 downto 0);
    signal current_cycle     : integer range 0 to 3;
    signal next_cycle        : integer range 0 to 3;

    signal svec : std_logic_vector(5 downto 0);

    -- Mirror of the DUT's edge-detection registers (same clock enable,
    -- same async reset) so properties can talk about "T2 entry" etc.
    signal p_t1, p_t2, p_t3, p_t1i : std_logic := '0';
    signal t1r, t2r, t3r, t1ir     : std_logic;

    -- History for hold/prediction properties
    signal ct_prev : std_logic_vector(1 downto 0) := "00";
    signal nc_prev : integer range 0 to 3 := 0;
    signal latch_edge : std_logic;
begin

    dut: entity work.machine_cycle_control
        port map (
            clk => clk, phi1_rising => phi1_rising, reset => reset,
            state_t1 => state_t1, state_t2 => state_t2, state_t3 => state_t3,
            state_t4 => state_t4, state_t5 => state_t5, state_t1i => state_t1i,
            state_half => state_half,
            instr_needs_immediate => instr_needs_immediate,
            instr_needs_address => instr_needs_address,
            instr_is_io => instr_is_io, instr_is_write => instr_is_write,
            instr_is_hlt => instr_is_hlt, instr_needs_t4t5 => instr_needs_t4t5,
            instr_is_mem_indirect => instr_is_mem_indirect,
            eval_condition => eval_condition, condition_met => condition_met,
            advance_state => advance_state, cycle_done => cycle_done,
            cycle_type => cycle_type,
            current_cycle => current_cycle, next_cycle => next_cycle);

    svec <= state_t1i & state_t5 & state_t4 & state_t3 & state_t2 & state_t1;

    mirror: process(clk, reset)
    begin
        if reset = '1' then
            p_t1 <= '0'; p_t2 <= '0'; p_t3 <= '0'; p_t1i <= '0';
        elsif rising_edge(clk) then
            if phi1_rising = '1' then
                p_t1 <= state_t1; p_t2 <= state_t2;
                p_t3 <= state_t3; p_t1i <= state_t1i;
            end if;
        end if;
    end process;

    t1r  <= state_t1  and not p_t1;
    t2r  <= state_t2  and not p_t2;
    t3r  <= state_t3  and not p_t3;
    t1ir <= state_t1i and not p_t1i;

    latch_edge <= phi1_rising and t2r and not reset;

    history: process(clk)
    begin
        if rising_edge(clk) then
            ct_prev <= cycle_type;
            nc_prev <= next_cycle;
        end if;
    end process;

    default clock is rising_edge(clk);

    -- Environment: states are one-hot or all-zero (proven property of
    -- state_timing_generator, formal/state_timing_generator).
    assume always (svec = "000000" or svec = "000001" or svec = "000010"
                or svec = "000100" or svec = "001000" or svec = "010000"
                or svec = "100000");

    -- P1: reset clears the observable state
    assert always (reset = '1') ->
        (current_cycle = 0 and advance_state = '0' and cycle_type = "00");

    -- P2: the cycle counter only ever takes values 0, 1, 2
    assert always (current_cycle /= 3);

    -- P3: cycle_type latch table, sampled at T2 entry
    assert (always ((latch_edge = '1') and (current_cycle = 0))
            -> next (cycle_type = "00")) abort (reset = '1');
    assert (always (((latch_edge and instr_is_io) = '1') and (current_cycle /= 0))
            -> next (cycle_type = "10")) abort (reset = '1');
    assert (always (((latch_edge and not instr_is_io and instr_is_write) = '1')
                    and (((current_cycle = 1) and (instr_needs_address = '0')) or
                         ((current_cycle = 2) and (instr_needs_address = '1'))))
            -> next (cycle_type = "11")) abort (reset = '1');
    assert (always (((latch_edge and not instr_is_io) = '1')
                    and (current_cycle /= 0)
                    and not ((instr_is_write = '1') and
                             (((current_cycle = 1) and (instr_needs_address = '0')) or
                              ((current_cycle = 2) and (instr_needs_address = '1')))))
            -> next (cycle_type = "01")) abort (reset = '1');
    -- and it holds between latch points
    assert (always (latch_edge = '0') -> next (cycle_type = ct_prev))
        abort (reset = '1');

    -- P4 (dropped): advance_state/cycle_done mutual exclusion is NOT a
    -- property of this module in isolation. Counterexample: T3 with HLT
    -- sets advance, then T4 with LMr flags sets cycle_done. That state
    -- sequence cannot occur in the composed CPU (HLT at T3 forces
    -- transition_to_stopped, and the proven state_timing_generator
    -- property sends T3 to STOPPED), but this module cannot know that.
    -- Mutual exclusion is a composition-level property; revisit if a
    -- core-level formal wrapper is ever built.

    -- P5: entering T1 or T1I clears both handshakes
    assert (always ((phi1_rising and t1r) = '1') ->
            next (advance_state = '0' and cycle_done = '0'))
        abort (reset = '1');
    assert (always ((phi1_rising and t1ir) = '1') ->
            next (advance_state = '0' and cycle_done = '0'))
        abort (reset = '1');

    -- P6: the documented contract: next_cycle sampled at a T1 edge equals
    -- current_cycle right after that edge
    assert (always ((phi1_rising and t1r) = '1') ->
            next (current_cycle = nc_prev)) abort (reset = '1');
    assert (always ((phi1_rising and t1ir) = '1') ->
            next (current_cycle = 0)) abort (reset = '1');

    -- P7: HLT at T3 entry of cycle 0 raises advance
    -- (the latched flag output was removed with its dead consumers)
    assert (always (((phi1_rising and t3r and instr_is_hlt) = '1')
                    and (current_cycle = 0))
            -> next (advance_state = '1'))
        abort (reset = '1');

    -- Reachability
    cover {current_cycle = 2};
    cover {cycle_type = "11"};
    cover {cycle_type = "10"};
    cover {advance_state = '1'};
    cover {cycle_done = '1'};

end architecture formal;

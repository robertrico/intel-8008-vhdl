------------------------------------------------------------------
-- props.vhdl: formal properties for stack pointer
-- 
-- A formal "testbench" has no stimulus process: the solver drives
-- every input, every cycle, adverserially. Our job is only to 
-- say what must always be true. Entity therefore has ONLY the DUT
-- inputs, no ouputs.
------------------------------------------------------------------
library ieee;

use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity stack_pointer_props is
	port (
		clk			: in std_logic;
		phi1_rising	: in std_logic;
		reset		: in std_logic;
		stack_push	: in std_logic;
		stack_pop	: in std_logic
	);
end entity stack_pointer_props;

architecture formal of stack_pointer_props is
    -- DUT output lands here to properties watch
    signal sp_out   : std_logic_vector(2 downto 0);
    -- One cycle of history: at any clock edge, sp_prev=SP - 1 edge
    -- Properties that say "inc" need a before/after pair.
    signal sp_prev  : std_logic_vector(2 downto 0) := "000";
    -- The counter actually steps this edge. Phi1 pulse, not reset
    signal step_en  : std_logic;
begin
    dut: entity work.stack_pointer
        port map (
            clk => clk,
            phi1_rising => phi1_rising,
            reset => reset,
            stack_push => stack_push,
            stack_pop => stack_pop,
            sp_out => sp_out
        );
        step_en <= phi1_rising and not reset;
        history: process(clk)
        begin
            if rising_edge(clk) then
                sp_prev <= sp_out;
            end if;
        end process;

    -- Everything below is sampled at this clock:
    default clock is rising_edge(clk);

    -- P1: reset dominates. Same-cycle form on purpose; prediction question.
    assert always (reset = '1') -> (sp_out = "000");

    -- P2: enabled push increments. Condition sampled at cycle N, "next"
    -- checks N+1, where sp_prev holds SP-from-N. 3-bit unsigned "+1" wraps
    -- 7 to 0 for free, so this also covers the wrap. "abort" cancels the
    -- pending N+1 obligation if reset fires in between.
    assert (always ((step_en and stack_push) = '1') ->
      next (unsigned(sp_out) = unsigned(sp_prev) + 1)) abort (reset = '1');

    -- P3: enabled pop decrements, only when push is low: push wins in the
    -- RTL (elsif at stack_pointer.vhdl:57). Drop the "not stack_push" term
    -- and the solver will instantly hand you push=pop=1 as a counterexample.
    assert (always ((step_en and not stack_push and stack_pop) = '1') ->
      next (unsigned(sp_out) = unsigned(sp_prev) - 1)) abort (reset = '1');

    -- P4: otherwise hold. No phi1 pulse OR no command both mean freeze.
    assert (always (step_en = '0' or (stack_push = '0' and stack_pop = '0')) ->
      next (sp_out = sp_prev)) abort (reset = '1');

    -- C1/C2: covers, for the "cover" run. Not obligations: requests.
    -- Braces = sequence, semicolon inside = "then next cycle".
    cover {unsigned(sp_out) = 7; unsigned(sp_out) = 0};
    cover {unsigned(sp_out) = 0 and step_en = '1' and stack_pop = '1' and stack_push = '0'; unsigned(sp_out) = 7};

end architecture formal;

------------------------------------------------------------------
-- props.vhdl: formal properties for ahl_pointer (combinational)
--
-- Proves:
--   P1  active only for mem-indirect ops in the H:L cycle at T1/T2
--   P2  T1 selects L (110), T2 selects H (101)
--   P3  the H:L cycle is next_cycle-based at T1 (counter lags),
--       current_cycle-based otherwise; cycle 2 normally, cycle 3
--       for 3-cycle instructions (instr_needs_address)
--   P4  inactive means select 000
------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity ahl_pointer_props is
    port (
        clk           : in std_logic;  -- formal sampling clock only
        state_t1      : in std_logic;
        state_t2      : in std_logic;
        current_cycle : in integer range 0 to 3;
        next_cycle    : in integer range 0 to 3;
        instr_is_mem_indirect : in std_logic;
        instr_needs_address   : in std_logic
    );
end entity ahl_pointer_props;

architecture formal of ahl_pointer_props is
    signal sel    : std_logic_vector(2 downto 0);
    signal active : std_logic;

    signal hl_cycle  : integer range 0 to 3;
    signal eff_cycle : integer range 0 to 3;
    signal in_window : std_logic;
begin

    dut: entity work.ahl_pointer
        port map (
            state_t1 => state_t1, state_t2 => state_t2,
            current_cycle => current_cycle, next_cycle => next_cycle,
            instr_is_mem_indirect => instr_is_mem_indirect,
            instr_needs_address => instr_needs_address,
            ahl_select => sel, ahl_active => active);

    hl_cycle  <= 2 when instr_needs_address = '1' else 1;
    eff_cycle <= next_cycle when state_t1 = '1' else current_cycle;
    in_window <= '1' when (instr_is_mem_indirect = '1' and eff_cycle = hl_cycle
                           and (state_t1 = '1' or state_t2 = '1'))
                 else '0';

    -- Combinational module: every formal step is a fresh input vector,
    -- sampled on a clock that exists only for the checkers.
    default clock is rising_edge(clk);

    -- P1/P4: active exactly in the window, otherwise all-zero select
    assert always (active = in_window);
    assert always (active = '0') -> (sel = "000");

    -- P2: T1 -> L, T2 -> H (T1 wins if both asserted, matching the RTL
    -- if/elsif priority)
    assert always ((in_window and state_t1) = '1') -> (sel = "110");
    assert always ((in_window and not state_t1 and state_t2) = '1') -> (sel = "101");

    -- Reachability
    cover {(active = '1') and (sel = "110")};
    cover {(active = '1') and (sel = "101")};
    cover {((instr_needs_address and active) = '1')};

end architecture formal;

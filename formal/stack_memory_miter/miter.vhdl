------------------------------------------------------------------
-- miter.vhdl: stack_memory RTL vs write_vhdl round-trip netlist
--
-- Same stimulus into both; addr_out and carry_out must match every
-- cycle. The 8x14 slot array is internal, so this is a bounded
-- proof (bmc): the depth covers load/increment/carry commits and
-- stack-pointer moves across slots. write_vhdl flattens the
-- pc_control_t record port into escaped \control[...]\ ports and
-- turns address_t into std_logic_vector; conversions below.
------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.b8008_types.all;

entity stack_memory_miter is
    port (
        clk           : in std_logic;
        phi1_rising   : in std_logic;
        reset         : in std_logic;
        sp_in         : in std_logic_vector(2 downto 0);
        ctl_inc_lower : in std_logic;
        ctl_inc_upper : in std_logic;
        ctl_load      : in std_logic;
        ctl_hold      : in std_logic;
        data_in       : in address_t
    );
end entity stack_memory_miter;

architecture formal of stack_memory_miter is
    signal control : pc_control_t;
    signal addr_gold : address_t;
    signal addr_gate : std_logic_vector(13 downto 0);
    signal carry_gold, carry_gate : std_logic;
begin

    control.increment_lower <= ctl_inc_lower;
    control.increment_upper <= ctl_inc_upper;
    control.load            <= ctl_load;
    control.hold            <= ctl_hold;

    gold: entity work.stack_memory
        port map (
            clk => clk, phi1_rising => phi1_rising, reset => reset,
            sp_in => sp_in, control => control, data_in => data_in,
            addr_out => addr_gold, carry_out => carry_gold);

    gate: entity work.stack_memory_gate
        port map (
            clk => clk, phi1_rising => phi1_rising, reset => reset,
            sp_in => sp_in,
            \control[increment_lower]\ => ctl_inc_lower,
            \control[increment_upper]\ => ctl_inc_upper,
            \control[load]\ => ctl_load,
            \control[hold]\ => ctl_hold,
            data_in => std_logic_vector(data_in),
            addr_out => addr_gate, carry_out => carry_gate);

    default clock is rising_edge(clk);

    assert always (std_logic_vector(addr_gold) = addr_gate);
    assert always (carry_gold = carry_gate);

end architecture formal;

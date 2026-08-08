------------------------------------------------------------------
-- props.vhdl: formal properties for stack_memory (PC-in-stack)
--
-- The 8x14 slot array is not directly observable, but the output
-- mux forwards in-flight operations, so every contract can be
-- phrased against addr_out history:
--   C1  load forwards data_in combinationally
--   C2  during increment_lower the carry view marks the 0xFF wrap
--   C3  reset with idle control drives addr 0, carry 0
--   S1  a committed op equals last cycle's forwarded view
--   S2  idle slot holds its value
--   S3  increment_lower view: lower byte +1, upper unchanged
--   S4  increment_upper view: upper byte +1, lower unchanged
--   S5  committed lower-increment latches carry iff it wrapped
--   S6  committed load / upper-increment clears the carry
--   S7  an op on one slot leaves the other slots untouched
------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.b8008_types.all;

entity stack_memory_props is
    port (
        clk           : in std_logic;
        phi1_rising   : in std_logic;
        reset         : in std_logic;
        sp_in         : in std_logic_vector(2 downto 0);
        ctl_inc_lower : in std_logic;
        ctl_inc_upper : in std_logic;
        ctl_load      : in std_logic;
        data_in       : in address_t
    );
end entity stack_memory_props;

architecture formal of stack_memory_props is
    signal control   : pc_control_t;
    signal addr_out  : address_t;
    signal carry_out : std_logic;

    signal ctl_none  : std_logic;
    signal commit_op : std_logic;

    -- two cycles of history (updated every clk, so induction-friendly)
    signal p_addr, pp_addr : address_t := (others => '0');
    signal p_sp, pp_sp     : std_logic_vector(2 downto 0) := "000";
    signal p_data          : address_t := (others => '0');
    signal p_load, p_il, p_iu       : std_logic := '0';
    signal p_none, pp_none          : std_logic := '1';
    signal p_commit                 : std_logic := '0';
begin

    control.increment_lower <= ctl_inc_lower;
    control.increment_upper <= ctl_inc_upper;
    control.load            <= ctl_load;

    dut: entity work.stack_memory
        port map (
            clk => clk, phi1_rising => phi1_rising, reset => reset,
            sp_in => sp_in, control => control, data_in => data_in,
            addr_out => addr_out, carry_out => carry_out);

    ctl_none  <= not ctl_load and not ctl_inc_upper and not ctl_inc_lower;
    commit_op <= phi1_rising and not ctl_none and not reset;

    history: process(clk)
    begin
        if rising_edge(clk) then
            pp_addr <= p_addr; pp_sp <= p_sp; pp_none <= p_none;
            p_addr <= addr_out; p_sp <= sp_in; p_data <= data_in;
            p_load <= ctl_load; p_il <= ctl_inc_lower; p_iu <= ctl_inc_upper;
            p_none <= ctl_none;
            p_commit <= commit_op;
        end if;
    end process;

    default clock is rising_edge(clk);

    -- C1: load is forwarded combinationally
    assert always (ctl_load = '1') -> (addr_out = data_in);

    -- C2: during a lower increment the carry view marks the wrap
    assert always ((ctl_inc_lower and not ctl_load and not ctl_inc_upper) = '1') ->
        ((carry_out = '1') = (addr_out(7 downto 0) = x"00"));

    -- C3: reset with idle control
    assert always ((reset and ctl_none) = '1') ->
        ((addr_out = to_unsigned(0, 14)) and (carry_out = '0'));

    -- S1: a committed op equals last cycle's forwarded view
    assert (always ((p_commit = '1') and (sp_in = p_sp) and (ctl_none = '1')) ->
        (addr_out = p_addr)) abort (reset = '1');

    -- S2: idle slot holds
    assert (always ((p_none = '1') and (sp_in = p_sp) and (ctl_none = '1')) ->
        (addr_out = p_addr)) abort (reset = '1');

    -- S3: increment_lower view vs prior idle view
    assert (always ((p_none = '1') and (sp_in = p_sp) and
                    ((ctl_inc_lower and not ctl_load and not ctl_inc_upper) = '1')) ->
        ((addr_out(13 downto 8) = p_addr(13 downto 8)) and
         (addr_out(7 downto 0) = p_addr(7 downto 0) + 1) and
         ((carry_out = '1') = (p_addr(7 downto 0) = x"FF")))) abort (reset = '1');

    -- S4: increment_upper view vs prior idle view
    assert (always ((p_none = '1') and (sp_in = p_sp) and
                    ((ctl_inc_upper and not ctl_load) = '1')) ->
        ((addr_out(7 downto 0) = p_addr(7 downto 0)) and
         (addr_out(13 downto 8) = p_addr(13 downto 8) + 1))) abort (reset = '1');

    -- S5: committed lower increment latches carry iff it wrapped
    assert (always (((p_commit and p_il and not p_load and not p_iu) = '1') and
                    (ctl_inc_lower = '0')) ->
        ((carry_out = '1') = (p_addr(7 downto 0) = x"00"))) abort (reset = '1');

    -- S6: committed load or upper increment clears carry
    assert (always ((p_commit = '1') and ((p_load or p_iu) = '1') and
                    (ctl_inc_lower = '0')) ->
        (carry_out = '0')) abort (reset = '1');

    -- S7: an op only touches the live slot; revisiting another slot
    --     two cycles later finds it unchanged
    assert (always ((pp_none = '1') and (p_sp /= pp_sp) and (sp_in = pp_sp) and
                    (ctl_none = '1')) ->
        (addr_out = pp_addr)) abort (reset = '1');

    -- Reachability
    cover {((commit_op and ctl_load) = '1')};
    cover {(carry_out = '1'); (carry_out = '0')};
    cover {((pp_none = '1') and (p_sp /= pp_sp) and (sp_in = pp_sp) and (ctl_none = '1'))};
    cover {(((p_commit and p_il) = '1') and (carry_out = '1'))};

end architecture formal;

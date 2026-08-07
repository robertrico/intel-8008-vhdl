--------------------------------------------------------------------------------
-- b8008_netlist_shim.vhdl
--------------------------------------------------------------------------------
-- Generic-bearing wrapper so the write_vhdl netlist can stand in for the RTL
-- b8008 core under b8008_top (issue #235 validation, B8008_CORE=netlist).
--
-- Synthesis bakes CLK_FREQ_HZ into the netlist (phase_clocks specialized at
-- 100 MHz), so the netlist entity has no generics and default binding from
-- b8008_top's component declaration fails. This shim re-exposes the generic,
-- guards against a mismatched value, and forwards every port to the renamed
-- netlist top (b8008_netlist_core).
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity b8008 is
    generic (
        CLK_FREQ_HZ : integer := 100_000_000
    );
    port (
        clk_in : in std_logic;
        reset  : in std_logic;

        run_enable : in std_logic := '1';

        phi1_out : out std_logic;
        phi2_out : out std_logic;

        phi1_rising_out  : out std_logic;
        phi1_falling_out : out std_logic;
        phi2_rising_out  : out std_logic;
        phi2_falling_out : out std_logic;

        data_bus_in  : in  std_logic_vector(7 downto 0);
        data_bus_out : out std_logic_vector(7 downto 0);
        data_bus_oe  : out std_logic;

        sync_out : out std_logic;
        s0_out   : out std_logic;
        s1_out   : out std_logic;
        s2_out   : out std_logic;

        ready_in  : in std_logic;
        interrupt : in std_logic;

        debug_reg_a           : out std_logic_vector(7 downto 0);
        debug_reg_b           : out std_logic_vector(7 downto 0);
        debug_reg_c           : out std_logic_vector(7 downto 0);
        debug_reg_d           : out std_logic_vector(7 downto 0);
        debug_reg_e           : out std_logic_vector(7 downto 0);
        debug_reg_h           : out std_logic_vector(7 downto 0);
        debug_reg_l           : out std_logic_vector(7 downto 0);
        debug_cycle           : out std_logic_vector(1 downto 0);
        debug_pc              : out std_logic_vector(13 downto 0);
        debug_ir              : out std_logic_vector(7 downto 0);
        debug_needs_address   : out std_logic;
        debug_int_pending     : out std_logic;
        cycle_type            : out std_logic_vector(1 downto 0);
        debug_flag_carry      : out std_logic;
        debug_flag_zero       : out std_logic;
        debug_flag_sign       : out std_logic;
        debug_flag_parity     : out std_logic;
        debug_state_half      : out std_logic
    );
end entity b8008;

architecture netlist_shim of b8008 is
begin

    -- The netlist was synthesized with the default 100 MHz phase timing.
    assert CLK_FREQ_HZ = 100_000_000
        report "b8008 netlist shim: netlist baked at 100 MHz, got CLK_FREQ_HZ="
               & integer'image(CLK_FREQ_HZ)
        severity failure;

    u_core : entity work.b8008_netlist_core
        port map (
            clk_in           => clk_in,
            reset            => reset,
            run_enable       => run_enable,
            phi1_out         => phi1_out,
            phi2_out         => phi2_out,
            phi1_rising_out  => phi1_rising_out,
            phi1_falling_out => phi1_falling_out,
            phi2_rising_out  => phi2_rising_out,
            phi2_falling_out => phi2_falling_out,
            data_bus_in      => data_bus_in,
            data_bus_out     => data_bus_out,
            data_bus_oe      => data_bus_oe,
            sync_out         => sync_out,
            s0_out           => s0_out,
            s1_out           => s1_out,
            s2_out           => s2_out,
            ready_in         => ready_in,
            interrupt        => interrupt,
            debug_reg_a         => debug_reg_a,
            debug_reg_b         => debug_reg_b,
            debug_reg_c         => debug_reg_c,
            debug_reg_d         => debug_reg_d,
            debug_reg_e         => debug_reg_e,
            debug_reg_h         => debug_reg_h,
            debug_reg_l         => debug_reg_l,
            debug_cycle         => debug_cycle,
            debug_pc            => debug_pc,
            debug_ir            => debug_ir,
            debug_needs_address => debug_needs_address,
            debug_int_pending   => debug_int_pending,
            cycle_type          => cycle_type,
            debug_flag_carry    => debug_flag_carry,
            debug_flag_zero     => debug_flag_zero,
            debug_flag_sign     => debug_flag_sign,
            debug_flag_parity   => debug_flag_parity,
            debug_state_half    => debug_state_half
        );

end architecture netlist_shim;

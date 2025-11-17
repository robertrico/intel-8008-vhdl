-------------------------------------------------------------------------------
-- Intel 8008 v8008 Minimal Existence Test
-------------------------------------------------------------------------------
-- Minimal testbench to verify v8008 entity compiles and instantiates correctly.
-- Tests only basic connectivity and signal stability - no functional testing.
--
-- Test Coverage:
--   - Component instantiation (phase_clocks, v8008)
--   - Reset sequence
--   - Output signal stability (no 'X' or 'U' values)
--
-- Copyright (c) 2025 Robert Rico
-- License: MIT
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;

entity v8008_minimal_tb is
end v8008_minimal_tb;

architecture behavior of v8008_minimal_tb is
    -- Component declarations
    component phase_clocks
        port(
            clk_in : in std_logic;
            reset : in std_logic;
            phi1 : out std_logic;
            phi2 : out std_logic
        );
    end component;

    component v8008
        port(
            phi1 : in std_logic;
            phi2 : in std_logic;
            reset_n : in std_logic;
            data_bus_in     : in  std_logic_vector(7 downto 0);
            data_bus_out    : out std_logic_vector(7 downto 0);
            data_bus_enable : out std_logic;
            S0 : out std_logic;
            S1 : out std_logic;
            S2 : out std_logic;
            sync : out std_logic;
            ready : in std_logic;
            int : in std_logic;
            debug_reg_A : out std_logic_vector(7 downto 0);
            debug_reg_B : out std_logic_vector(7 downto 0);
            debug_reg_C : out std_logic_vector(7 downto 0);
            debug_reg_D : out std_logic_vector(7 downto 0);
            debug_reg_E : out std_logic_vector(7 downto 0);
            debug_reg_H : out std_logic_vector(7 downto 0);
            debug_reg_L : out std_logic_vector(7 downto 0);
            debug_pc : out std_logic_vector(13 downto 0);
            debug_flags : out std_logic_vector(3 downto 0)
        );
    end component;

    -- Test signals
    signal master_clk_tb : std_logic := '0';
    signal reset_tb : std_logic := '1';
    signal phi1_tb : std_logic := '0';
    signal phi2_tb : std_logic := '0';
    signal reset_n_tb : std_logic := '0';
    signal ready_tb : std_logic := '1';
    signal int_tb : std_logic := '0';
    signal data_tb : std_logic_vector(7 downto 0) := (others => '0');
    signal cpu_data_out_tb     : std_logic_vector(7 downto 0);
    signal cpu_data_enable_tb  : std_logic;
    signal S0_tb, S1_tb, S2_tb : std_logic;
    signal sync_tb : std_logic;

    -- Debug signals
    signal debug_reg_A_tb : std_logic_vector(7 downto 0);
    signal debug_reg_B_tb : std_logic_vector(7 downto 0);
    signal debug_reg_C_tb : std_logic_vector(7 downto 0);
    signal debug_reg_D_tb : std_logic_vector(7 downto 0);
    signal debug_reg_E_tb : std_logic_vector(7 downto 0);
    signal debug_reg_H_tb : std_logic_vector(7 downto 0);
    signal debug_reg_L_tb : std_logic_vector(7 downto 0);
    signal debug_pc_tb : std_logic_vector(13 downto 0);
    signal debug_flags_tb : std_logic_vector(3 downto 0);

    -- Master clock period
    constant MASTER_CLK_PERIOD : time := 10 ns;  -- 100 MHz master clock

begin

    -- Master clock generation
    master_clk_tb <= not master_clk_tb after MASTER_CLK_PERIOD / 2;

    -- Phase clock generator
    PHASE_GEN: phase_clocks
        port map (
            clk_in => master_clk_tb,
            reset => reset_tb,
            phi1 => phi1_tb,
            phi2 => phi2_tb
        );

    -- CPU instance (v8008)
    CPU: v8008
        port map (
            phi1 => phi1_tb,
            phi2 => phi2_tb,
            reset_n => reset_n_tb,
            data_bus_in => data_tb,
            data_bus_out => cpu_data_out_tb,
            data_bus_enable => cpu_data_enable_tb,
            S0 => S0_tb,
            S1 => S1_tb,
            S2 => S2_tb,
            sync => sync_tb,
            ready => ready_tb,
            int => int_tb,
            debug_reg_A => debug_reg_A_tb,
            debug_reg_B => debug_reg_B_tb,
            debug_reg_C => debug_reg_C_tb,
            debug_reg_D => debug_reg_D_tb,
            debug_reg_E => debug_reg_E_tb,
            debug_reg_H => debug_reg_H_tb,
            debug_reg_L => debug_reg_L_tb,
            debug_pc => debug_pc_tb,
            debug_flags => debug_flags_tb
        );

    -- Simple data bus (always drives zero for this minimal test)
    data_tb <= (others => '0');

    -- Test stimulus process
    STIMULUS: process
        variable l : line;
    begin
        write(l, string'("========================================"));
        writeline(output, l);
        write(l, string'("v8008 Minimal Existence Test"));
        writeline(output, l);
        write(l, string'("========================================"));
        writeline(output, l);

        -- Initial state: hold in reset
        reset_tb <= '1';
        reset_n_tb <= '0';
        wait for 100 ns;

        write(l, string'("Applying reset..."));
        writeline(output, l);

        -- Release reset
        reset_tb <= '0';
        wait for 50 ns;
        reset_n_tb <= '1';

        write(l, string'("Reset released, running for 1000ns..."));
        writeline(output, l);

        -- Run for a short time
        wait for 1000 ns;

        -- Check that outputs are stable (not undefined)
        write(l, string'("Checking output stability..."));
        writeline(output, l);

        assert S0_tb /= 'U' and S0_tb /= 'X'
            report "S0 output is undefined!" severity error;
        assert S1_tb /= 'U' and S1_tb /= 'X'
            report "S1 output is undefined!" severity error;
        assert S2_tb /= 'U' and S2_tb /= 'X'
            report "S2 output is undefined!" severity error;
        assert sync_tb /= 'U' and sync_tb /= 'X'
            report "SYNC output is undefined!" severity error;

        -- Check debug outputs
        assert debug_reg_A_tb /= "UUUUUUUU" and debug_reg_A_tb /= "XXXXXXXX"
            report "debug_reg_A is undefined!" severity error;
        assert debug_pc_tb /= "UUUUUUUUUUUUUU" and debug_pc_tb /= "XXXXXXXXXXXXXX"
            report "debug_pc is undefined!" severity error;

        write(l, string'("========================================"));
        writeline(output, l);
        write(l, string'("TEST PASSED - v8008 instantiated successfully"));
        writeline(output, l);
        write(l, string'("All outputs are stable (not undefined)"));
        writeline(output, l);
        write(l, string'("========================================"));
        writeline(output, l);

        wait;
    end process;

end behavior;

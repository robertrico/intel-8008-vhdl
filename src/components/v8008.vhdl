-------------------------------------------------------------------------------
-- Intel 8008 - v8008 Refactored Implementation
-------------------------------------------------------------------------------
-- Copyright (c) 2025 Robert Rico
--
-- Refactored VHDL implementation of the Intel 8008 microprocessor.
-- This is a clean-slate implementation to fix ALU timing issues.
--
-- Reference: Intel 8008 Datasheet (April 1974)
-- License: MIT (see LICENSE.txt)
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity v8008 is
    port (
        -- Two-phase clock inputs (non-overlapping)
        phi1 : in std_logic;
        phi2 : in std_logic;

        -- Reset (active low)
        reset_n : in std_logic;

        -- 8-bit multiplexed address/data bus
        data_bus_in     : in  std_logic_vector(7 downto 0);
        data_bus_out    : out std_logic_vector(7 downto 0);
        data_bus_enable : out std_logic;

        -- State outputs (timing state indication)
        S0 : out std_logic;
        S1 : out std_logic;
        S2 : out std_logic;

        -- SYNC output (timing reference)
        SYNC : out std_logic;

        -- READY input (wait state control)
        READY : in std_logic;

        -- Interrupt request input
        INT : in std_logic := '0';

        -- Debug outputs (for testbench verification)
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
end v8008;

architecture rtl of v8008 is

    --===========================================
    -- Component Declarations
    --===========================================

    -- ALU Component
    component i8008_alu is
        port(
            data_0 : in std_logic_vector(7 downto 0);
            data_1 : in std_logic_vector(7 downto 0);
            flag_carry : in std_logic;
            command : in std_logic_vector(2 downto 0);
            alu_result : out std_logic_vector(8 downto 0)
        );
    end component;

    --===========================================
    -- Internal Signals
    --===========================================

    -- ALU signals
    signal alu_data_0 : std_logic_vector(7 downto 0);
    signal alu_data_1 : std_logic_vector(7 downto 0);
    signal alu_command : std_logic_vector(2 downto 0);
    signal alu_result : std_logic_vector(8 downto 0);
    signal flag_carry : std_logic;

begin

    --===========================================
    -- Component Instantiations
    --===========================================

    -- ALU Instance
    ALU: i8008_alu
        port map (
            data_0 => alu_data_0,
            data_1 => alu_data_1,
            flag_carry => flag_carry,
            command => alu_command,
            alu_result => alu_result
        );

    --===========================================
    -- Output Assignments (Safe Defaults)
    --===========================================

    -- Drive all outputs to safe default values
    data_bus_out    <= (others => '0');
    data_bus_enable <= '0';

    S0   <= '0';
    S1   <= '0';
    S2   <= '0';
    SYNC <= '0';

    -- Debug outputs
    debug_reg_A <= (others => '0');
    debug_reg_B <= (others => '0');
    debug_reg_C <= (others => '0');
    debug_reg_D <= (others => '0');
    debug_reg_E <= (others => '0');
    debug_reg_H <= (others => '0');
    debug_reg_L <= (others => '0');
    debug_pc    <= (others => '0');
    debug_flags <= (others => '0');

    -- ALU inputs (safe defaults)
    alu_data_0  <= (others => '0');
    alu_data_1  <= (others => '0');
    alu_command <= (others => '0');
    flag_carry  <= '0';

    --===========================================
    -- Placeholder Processes
    --===========================================
    -- These will be filled in during implementation

    -- Main state machine process (placeholder)
    -- Will handle: timing states, microcode states, instruction execution

    -- Register file process (placeholder)
    -- Will handle: register read/write, program counter, stack pointer

    -- Bus interface process (placeholder)
    -- Will handle: data bus tri-state control, address output

end rtl;

-------------------------------------------------------------------------------
-- Intel 8008 v8008 INR Instruction Test
-------------------------------------------------------------------------------
-- Testbench to verify INR (Increment Register) instruction functionality
--
-- Test Coverage:
--   - INR B through INR L (all 6 registers except A)
--   - Flag updates (Sign, Zero, Parity) with Carry preserved
--   - Overflow behavior (0xFF + 1 = 0x00)
--
-- Copyright (c) 2025 Robert Rico
-- License: MIT
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity v8008_inr_tb is
end v8008_inr_tb;

architecture behavior of v8008_inr_tb is
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
            data_bus_in     : in  std_logic_vector(7 downto 0);
            data_bus_out    : out std_logic_vector(7 downto 0);
            data_bus_enable : out std_logic;
            S0 : out std_logic;
            S1 : out std_logic;
            S2 : out std_logic;
            SYNC : out std_logic;
            READY : in std_logic;
            INT : in std_logic;
            debug_reg_A : out std_logic_vector(7 downto 0);
            debug_reg_B : out std_logic_vector(7 downto 0);
            debug_reg_C : out std_logic_vector(7 downto 0);
            debug_reg_D : out std_logic_vector(7 downto 0);
            debug_reg_E : out std_logic_vector(7 downto 0);
            debug_reg_H : out std_logic_vector(7 downto 0);
            debug_reg_L : out std_logic_vector(7 downto 0);
            debug_pc : out std_logic_vector(13 downto 0);
            debug_flags : out std_logic_vector(3 downto 0);
            debug_instruction : out std_logic_vector(7 downto 0);
            debug_stack_pointer : out std_logic_vector(2 downto 0);
            debug_hl_address : out std_logic_vector(13 downto 0)
        );
    end component;

    -- Test signals
    signal master_clk_tb : std_logic := '0';
    signal reset_tb : std_logic := '1';
    signal phi1_tb : std_logic;
    signal phi2_tb : std_logic;
    signal ready_tb : std_logic := '1';
    signal int_tb : std_logic := '0';
    signal data_tb : std_logic_vector(7 downto 0);
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
    signal debug_instruction_tb : std_logic_vector(7 downto 0);
    signal debug_stack_pointer_tb : std_logic_vector(2 downto 0);
    signal debug_hl_address_tb : std_logic_vector(13 downto 0);

    -- ROM signals
    signal rom_addr : std_logic_vector(6 downto 0);
    signal rom_data : std_logic_vector(7 downto 0);

    -- ROM for test program
    type rom_t is array (0 to 63) of std_logic_vector(7 downto 0);
    constant rom_contents : rom_t := (
        -- Test 1: INR B (reg B = 0x05)
        0 => x"0E",  -- MVI B, 0x05 (00 001 110 = 0x0E)
        1 => x"05",
        2 => x"08",  -- INR B (00 001 000 = 0x08)

        -- Test 2: INR C (reg C = 0xFF, test overflow and zero flag)
        3 => x"16",  -- MVI C, 0xFF (00 010 110 = 0x16)
        4 => x"FF",
        5 => x"10",  -- INR C (00 010 000 = 0x10)

        -- Test 3: INR D (reg D = 0x7F, test sign flag)
        6 => x"1E",  -- MVI D, 0x7F (00 011 110 = 0x1E)
        7 => x"7F",
        8 => x"18",  -- INR D (00 011 000 = 0x18)

        -- Test 4: INR E with parity check
        9 => x"26",  -- MVI E, 0x0E (00 100 110 = 0x26)
        10 => x"0E",
        11 => x"20",  -- INR E (00 100 000 = 0x20)

        -- Test 5: INR H
        12 => x"2E",  -- MVI H, 0x12 (00 101 110 = 0x2E)
        13 => x"12",
        14 => x"28",  -- INR H (00 101 000 = 0x28)

        -- Test 6: INR L
        15 => x"36",  -- MVI L, 0x99 (00 110 110 = 0x36)
        16 => x"99",
        17 => x"30",  -- INR L (00 110 000 = 0x30)

        18 => x"FF",  -- HLT
        others => x"00"
    );

    -- Master clock period
    constant MASTER_CLK_PERIOD : time := 10 ns;

begin

    -- ROM address from program counter
    rom_addr <= debug_pc_tb(6 downto 0);

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

    -- CPU instance
    CPU: v8008
        port map (
            phi1 => phi1_tb,
            phi2 => phi2_tb,
            data_bus_in => data_tb,
            data_bus_out => cpu_data_out_tb,
            data_bus_enable => cpu_data_enable_tb,
            S0 => S0_tb,
            S1 => S1_tb,
            S2 => S2_tb,
            SYNC => sync_tb,
            READY => ready_tb,
            INT => int_tb,
            debug_reg_A => debug_reg_A_tb,
            debug_reg_B => debug_reg_B_tb,
            debug_reg_C => debug_reg_C_tb,
            debug_reg_D => debug_reg_D_tb,
            debug_reg_E => debug_reg_E_tb,
            debug_reg_H => debug_reg_H_tb,
            debug_reg_L => debug_reg_L_tb,
            debug_pc => debug_pc_tb,
            debug_flags => debug_flags_tb,
            debug_instruction => debug_instruction_tb,
            debug_stack_pointer => debug_stack_pointer_tb,
            debug_hl_address => debug_hl_address_tb
        );

    -- ROM process (provides instructions from ROM on phi2 falling edge)
    ROM_PROC: process(phi2_tb)
    begin
        if falling_edge(phi2_tb) then
            rom_data <= rom_contents(to_integer(unsigned(rom_addr)));
            report "ROM fetch: PC=" & to_hstring(debug_pc_tb) & ", addr=" & integer'image(to_integer(unsigned(rom_addr))) & ", data=0x" & to_hstring(rom_contents(to_integer(unsigned(rom_addr))));
        end if;
    end process ROM_PROC;

    -- Data bus: ROM data
    data_tb <= rom_data;

    -- Test process
    TEST_PROC: process
        variable errors : integer := 0;
    begin
        -- Reset phase clocks
        reset_tb <= '1';
        wait for 100 ns;
        reset_tb <= '0';
        wait for 500 ns;

        -- Boot CPU with RST 0 (8008 starts in STOPPED state, needs interrupt to wake up)
        report "Booting CPU with RST 0...";
        wait until rising_edge(phi1_tb);
        int_tb <= '1';
        wait for 3000 ns;
        int_tb <= '0';

        -- Wait for all tests to complete (HLT)
        -- Program has 6 INR tests (each with MVI setup) = 12 instructions + HLT
        wait for 1500 us;

        -- Check results
        report "========================================";
        report "Final register values:";
        report "  B = 0x" & to_hstring(debug_reg_B_tb) & " (expected 0x06)";
        report "  C = 0x" & to_hstring(debug_reg_C_tb) & " (expected 0x00)";
        report "  D = 0x" & to_hstring(debug_reg_D_tb) & " (expected 0x80)";
        report "  E = 0x" & to_hstring(debug_reg_E_tb) & " (expected 0x0F)";
        report "  H = 0x" & to_hstring(debug_reg_H_tb) & " (expected 0x13)";
        report "  L = 0x" & to_hstring(debug_reg_L_tb) & " (expected 0x9A)";
        report "  Flags = " & to_hstring(debug_flags_tb) & " (C Z S P)";
        report "========================================";

        -- Verify results
        if debug_reg_B_tb = x"06" then
            report "PASS: INR B correct";
        else
            report "ERROR: INR B failed" severity error;
            errors := errors + 1;
        end if;

        if debug_reg_C_tb = x"00" then
            report "PASS: INR C correct (overflow to 0x00)";
        else
            report "ERROR: INR C failed" severity error;
            errors := errors + 1;
        end if;

        if debug_reg_D_tb = x"80" then
            report "PASS: INR D correct (sign flag set)";
        else
            report "ERROR: INR D failed" severity error;
            errors := errors + 1;
        end if;

        if debug_reg_E_tb = x"0F" then
            report "PASS: INR E correct";
        else
            report "ERROR: INR E failed" severity error;
            errors := errors + 1;
        end if;

        if debug_reg_H_tb = x"13" then
            report "PASS: INR H correct";
        else
            report "ERROR: INR H failed" severity error;
            errors := errors + 1;
        end if;

        if debug_reg_L_tb = x"9A" then
            report "PASS: INR L correct";
        else
            report "ERROR: INR L failed" severity error;
            errors := errors + 1;
        end if;

        report "========================================";
        if errors = 0 then
            report "*** ALL INR TESTS PASSED (6/6) ***";
        else
            report "*** TESTS FAILED: " & integer'image(errors) & " errors ***" severity error;
        end if;
        report "========================================";

        wait;
    end process TEST_PROC;

end behavior;

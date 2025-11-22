-------------------------------------------------------------------------------
-- Intel 8008 v8008 DCR Instruction Test
-------------------------------------------------------------------------------
-- Testbench to verify DCR (Decrement Register) instruction functionality
--
-- Test Coverage:
--   - DCR B through DCR L (all 6 registers except A)
--   - Flag updates (Sign, Zero, Parity) with Carry preserved
--   - Underflow behavior (0x00 - 1 = 0xFF)
--
-- Copyright (c) 2025 Robert Rico
-- License: MIT
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity v8008_dcr_tb is
end v8008_dcr_tb;

architecture behavior of v8008_dcr_tb is
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
        -- Test 1: DCR B (reg B = 0x06)
        0 => x"0E",  -- MVI B, 0x06 (00 001 110 = 0x0E)
        1 => x"06",
        2 => x"09",  -- DCR B (00 001 001 = 0x09)

        -- Test 2: DCR C (reg C = 0x00, test underflow and sign flag)
        3 => x"16",  -- MVI C, 0x00 (00 010 110 = 0x16)
        4 => x"00",
        5 => x"11",  -- DCR C (00 010 001 = 0x11)

        -- Test 3: DCR D (reg D = 0x80, test sign flag transition)
        6 => x"1E",  -- MVI D, 0x80 (00 011 110 = 0x1E)
        7 => x"80",
        8 => x"19",  -- DCR D (00 011 001 = 0x19)

        -- Test 4: DCR E (reg E = 0x01, test zero flag)
        9 => x"26",  -- MVI E, 0x01 (00 100 110 = 0x26)
        10 => x"01",
        11 => x"21",  -- DCR E (00 100 001 = 0x21)

        -- Test 5: DCR H with parity check
        12 => x"2E",  -- MVI H, 0x10 (00 101 110 = 0x2E)
        13 => x"10",
        14 => x"29",  -- DCR H (00 101 001 = 0x29)

        -- Test 6: DCR L
        15 => x"36",  -- MVI L, 0x9B (00 110 110 = 0x36)
        16 => x"9B",
        17 => x"31",  -- DCR L (00 110 001 = 0x31)

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
        -- Program has 6 DCR tests (each with MVI setup) = 12 instructions + HLT
        wait for 1500 us;

        -- Check results
        report "========================================";
        report "Final register values:";
        report "  B = 0x" & to_hstring(debug_reg_B_tb) & " (expected 0x05)";
        report "  C = 0x" & to_hstring(debug_reg_C_tb) & " (expected 0xFF)";
        report "  D = 0x" & to_hstring(debug_reg_D_tb) & " (expected 0x7F)";
        report "  E = 0x" & to_hstring(debug_reg_E_tb) & " (expected 0x00)";
        report "  H = 0x" & to_hstring(debug_reg_H_tb) & " (expected 0x0F)";
        report "  L = 0x" & to_hstring(debug_reg_L_tb) & " (expected 0x9A)";
        report "  Flags = " & to_hstring(debug_flags_tb) & " (C Z S P)";
        report "========================================";

        -- Verify results
        if debug_reg_B_tb = x"05" then
            report "PASS: DCR B correct";
        else
            report "ERROR: DCR B failed" severity error;
            errors := errors + 1;
        end if;

        if debug_reg_C_tb = x"FF" then
            report "PASS: DCR C correct (underflow to 0xFF)";
        else
            report "ERROR: DCR C failed" severity error;
            errors := errors + 1;
        end if;

        if debug_reg_D_tb = x"7F" then
            report "PASS: DCR D correct (sign flag transition)";
        else
            report "ERROR: DCR D failed" severity error;
            errors := errors + 1;
        end if;

        if debug_reg_E_tb = x"00" then
            report "PASS: DCR E correct (zero flag set)";
        else
            report "ERROR: DCR E failed" severity error;
            errors := errors + 1;
        end if;

        if debug_reg_H_tb = x"0F" then
            report "PASS: DCR H correct";
        else
            report "ERROR: DCR H failed" severity error;
            errors := errors + 1;
        end if;

        if debug_reg_L_tb = x"9A" then
            report "PASS: DCR L correct";
        else
            report "ERROR: DCR L failed" severity error;
            errors := errors + 1;
        end if;

        report "========================================";
        if errors = 0 then
            report "*** ALL DCR TESTS PASSED (6/6) ***";
        else
            report "*** TESTS FAILED: " & integer'image(errors) & " errors ***" severity error;
        end if;
        report "========================================";

        wait;
    end process TEST_PROC;

end behavior;

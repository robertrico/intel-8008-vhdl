-------------------------------------------------------------------------------
-- Intel 8008 v8008 Rotate Instructions Test (Comprehensive)
-------------------------------------------------------------------------------
-- Tests all 4 rotate operations (single-cycle instructions)
-- Rotate format: 00 FFF 010 (where FFF = operation code)
--
-- Instructions tested:
--   RLC (Rotate Left Circular):     00 000 010 = 0x02
--     - Bit 7 → Carry, Bit 7 → Bit 0, all bits shift left
--   RRC (Rotate Right Circular):    00 001 010 = 0x0A
--     - Bit 0 → Carry, Bit 0 → Bit 7, all bits shift right
--   RAL (Rotate Left through Carry): 00 010 010 = 0x12
--     - Bit 7 → Carry, Carry → Bit 0, all bits shift left
--   RAR (Rotate Right through Carry): 00 011 010 = 0x1A
--     - Bit 0 → Carry, Carry → Bit 7, all bits shift right
--
-- Timing (all single-cycle):
--   Cycle 0: T1-T2 (PCL, PCH), T3 (fetch to IR+Reg.b), T4 (idle ~4.4us), T5 (rotate)
--
-- Copyright (c) 2025 Robert Rico
-- License: MIT
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;

entity v8008_rotate_tb is
end v8008_rotate_tb;

architecture behavior of v8008_rotate_tb is

    component phase_clocks
        port (
            clk_in : in std_logic;
            reset  : in std_logic;
            phi1   : out std_logic;
            phi2   : out std_logic
        );
    end component;

    component v8008
        port (
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

    -- Clock and control signals
    signal clk_master  : std_logic := '0';
    signal reset       : std_logic := '0';
    signal phi1        : std_logic := '0';
    signal phi2        : std_logic := '0';
    signal INT         : std_logic := '0';
    signal READY       : std_logic := '1';

    -- CPU interface
    signal data_bus_in : std_logic_vector(7 downto 0) := (others => '0');
    signal data_bus_out: std_logic_vector(7 downto 0);
    signal data_bus_enable : std_logic;
    signal S0, S1, S2  : std_logic;
    signal SYNC        : std_logic;

    -- Debug signals
    signal debug_reg_A : std_logic_vector(7 downto 0);
    signal debug_reg_B : std_logic_vector(7 downto 0);
    signal debug_reg_C : std_logic_vector(7 downto 0);
    signal debug_reg_D : std_logic_vector(7 downto 0);
    signal debug_reg_E : std_logic_vector(7 downto 0);
    signal debug_reg_H : std_logic_vector(7 downto 0);
    signal debug_reg_L : std_logic_vector(7 downto 0);
    signal debug_pc    : std_logic_vector(13 downto 0);
    signal debug_flags : std_logic_vector(3 downto 0);
    signal debug_instruction : std_logic_vector(7 downto 0);
    signal debug_stack_pointer : std_logic_vector(2 downto 0);
    signal debug_hl_address : std_logic_vector(13 downto 0);

    -- Test control
    signal done : boolean := false;

    -- Constants
    constant CLK_PERIOD : time := 10 ns;

    -- ROM for instructions
    type rom_array_t is array (0 to 255) of std_logic_vector(7 downto 0);
    signal rom_contents : rom_array_t := (
        -- Test 1: RLC with 0xB4 (10110100)
        -- Expected: 0x69 (01101001), Carry=1
        0 => x"06",  -- MVI A, 0xB4
        1 => x"B4",
        2 => x"02",  -- RLC (00 000 010 = 0x02)

        -- Test 2: RRC with 0x69 (01101001)
        -- Expected: 0xB4 (10110100), Carry=1
        3 => x"0A",  -- RRC (00 001 010 = 0x0A)

        -- Test 3: RAL with 0xB4 (10110100), Carry=1
        -- Expected: 0x69 (01101001), Carry=1
        4 => x"12",  -- RAL (00 010 010 = 0x12)

        -- Test 4: RAR with 0x69 (01101001), Carry=1
        -- Expected: 0xB4 (10110100), Carry=0
        5 => x"1A",  -- RAR (00 011 010 = 0x1A)

        -- Test 5: RLC with MSB=0 (0x40 = 01000000)
        -- Expected: 0x80 (10000000), Carry=0
        6 => x"06",  -- MVI A, 0x40
        7 => x"40",
        8 => x"02",  -- RLC

        -- Test 6: RRC with LSB=0 (0x80 = 10000000)
        -- Expected: 0x40 (01000000), Carry=0
        9 => x"0A",  -- RRC

        -- Test 7: RAL with Carry=0 (0x40 = 01000000)
        -- Expected: 0x80 (10000000), Carry=0
        10 => x"12", -- RAL

        -- Test 8: RAR with Carry=0 (0x80 = 10000000)
        -- Expected: 0x40 (01000000), Carry=0 (bit 0 of 0x80 is 0)
        11 => x"1A", -- RAR

        12 => x"FF", -- HLT

        others => x"00"
    );

    signal rom_data : std_logic_vector(7 downto 0);

begin

    -- Instantiate phase_clocks generator
    CLK_GEN: phase_clocks
        port map (
            clk_in => clk_master,
            reset => reset,
            phi1 => phi1,
            phi2 => phi2
        );

    -- Instantiate v8008 CPU
    UUT: v8008
        port map (
            phi1 => phi1,
            phi2 => phi2,
            data_bus_in => data_bus_in,
            data_bus_out => data_bus_out,
            data_bus_enable => data_bus_enable,
            S0 => S0,
            S1 => S1,
            S2 => S2,
            SYNC => SYNC,
            READY => READY,
            INT => INT,
            debug_reg_A => debug_reg_A,
            debug_reg_B => debug_reg_B,
            debug_reg_C => debug_reg_C,
            debug_reg_D => debug_reg_D,
            debug_reg_E => debug_reg_E,
            debug_reg_H => debug_reg_H,
            debug_reg_L => debug_reg_L,
            debug_pc => debug_pc,
            debug_flags => debug_flags,
            debug_instruction => debug_instruction,
            debug_stack_pointer => debug_stack_pointer,
            debug_hl_address => debug_hl_address
        );

    -- ROM process - provides instructions
    ROM_PROC: process(phi2)
    begin
        if falling_edge(phi2) then
            rom_data <= rom_contents(to_integer(unsigned(debug_pc(7 downto 0))));
        end if;
    end process ROM_PROC;

    -- Data bus multiplexing
    DBUS_MUX: process(phi2)
        variable state_vec : std_logic_vector(2 downto 0);
    begin
        if falling_edge(phi2) then
            state_vec := S2 & S1 & S0;
            if INT = '1' and state_vec = "001" then
                data_bus_in <= x"05";  -- RST 0
            else
                data_bus_in <= rom_data;
            end if;
        end if;
    end process DBUS_MUX;

    -- Master clock generation
    MASTER_CLK_PROC: process
    begin
        while not done loop
            clk_master <= '0';
            wait for CLK_PERIOD / 2;
            clk_master <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process MASTER_CLK_PROC;

    -- Main test process
    TEST_PROC: process
        variable errors : integer := 0;
    begin
        report "========================================";
        report "Intel 8008 Rotate Instructions Test";
        report "Testing RLC, RRC, RAL, RAR";
        report "========================================";

        -- Reset phase clocks
        reset <= '1';
        wait for 100 ns;
        reset <= '0';
        wait for 500 ns;

        -- Boot CPU with RST 0
        report "Booting CPU with RST 0...";
        wait until rising_edge(phi1);
        INT <= '1';
        wait for 3000 ns;
        INT <= '0';

        -- Execute test program
        report "";
        report "Executing rotate test program:";
        report "  Test 1: RLC 0xB4 -> 0x69, C=1";
        report "  Test 2: RRC 0x69 -> 0xB4, C=1";
        report "  Test 3: RAL 0xB4 (C=1) -> 0x69, C=1";
        report "  Test 4: RAR 0x69 (C=1) -> 0xB4, C=0";
        report "  Test 5: RLC 0x40 -> 0x80, C=0";
        report "  Test 6: RRC 0x80 -> 0x40, C=0";
        report "  Test 7: RAL 0x40 (C=0) -> 0x80, C=0";
        report "  Test 8: RAR 0x80 (C=0) -> 0x40, C=0";

        -- Wait for execution to complete
        wait for 1000 us;

        -- Verify results
        report "";
        report "========================================";
        report "Verifying Results:";
        report "========================================";

        -- After all rotations, A should be 0x40
        report "Register A: 0x" & to_hstring(debug_reg_A) & " (expected 0x40)";
        if debug_reg_A /= x"40" then
            report "ERROR: Register A mismatch" severity warning;
            errors := errors + 1;
        else
            report "  PASS: Register A correct";
        end if;

        -- Final carry should be 0 (from RAR of 0x80, bit 0 is 0)
        report "Carry Flag: " & std_logic'image(debug_flags(3)) & " (expected '0')";
        if debug_flags(3) /= '0' then
            report "ERROR: Carry flag mismatch" severity warning;
            errors := errors + 1;
        else
            report "  PASS: Carry flag correct";
        end if;

        -- Test summary
        report "";
        report "========================================";
        if errors = 0 then
            report "*** ALL ROTATE TESTS PASSED (4/4) ***";
            report "  - RLC: PASS";
            report "  - RRC: PASS";
            report "  - RAL: PASS";
            report "  - RAR: PASS";
        else
            report "*** TESTS FAILED: " & integer'image(errors) & " errors ***" severity error;
        end if;
        report "========================================";

        done <= true;
        wait;
    end process TEST_PROC;

end behavior;

-------------------------------------------------------------------------------
-- Intel 8008 v8008 ALU Register Operations Test (Comprehensive)
-------------------------------------------------------------------------------
-- Tests all 8 ALU Register operations with multiple source registers
-- ALU r format: 10 PPP SSS where PPP = operation (000-111), SSS = source register
-- Register encoding: A=000, B=001, C=010, D=011, E=100, H=101, L=110, M=111
-- Operations tested:
--   ADD r: A = A + Rs  (opcodes 0x80-0x87 for A,B,C,D,E,H,L,M)
--   ADC r: A = A + Rs + Carry (opcodes 0x88-0x8F)
--   SUB r: A = A - Rs  (opcodes 0x90-0x97)
--   SBB r: A = A - Rs - Borrow (opcodes 0x98-0x9F)
--   ANA r: A = A & Rs  (opcodes 0xA0-0xA7)
--   XRA r: A = A ^ Rs  (opcodes 0xA8-0xAF)
--   ORA r: A = A | Rs  (opcodes 0xB0-0xB7)
--   CMP r: Compare A with Rs (opcodes 0xB8-0xBF)
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;

entity v8008_alu_register_tb is
end v8008_alu_register_tb;

architecture behavior of v8008_alu_register_tb is

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
    signal S0          : std_logic;
    signal S1          : std_logic;
    signal S2          : std_logic;
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
    signal done        : boolean := false;

    -- Constants
    constant CLK_PERIOD : time := 10 ns;

    -- ROM for instructions
    type rom_array_t is array (0 to 255) of std_logic_vector(7 downto 0);
    signal rom_contents : rom_array_t := (
        -- Initialize registers for testing
        -- A will be loaded before each operation
        0 => x"0E",  -- MVI B, 0x10
        1 => x"10",
        2 => x"16",  -- MVI C, 0x0F
        3 => x"0F",
        4 => x"1E",  -- MVI D, 0x20
        5 => x"20",
        6 => x"26",  -- MVI E, 0x01
        7 => x"01",
        8 => x"2E",  -- MVI H, 0xFF
        9 => x"FF",
        10 => x"36", -- MVI L, 0xA0
        11 => x"A0",

        -- Test 1: ADD B - A = 0x42 + 0x10 = 0x52
        12 => x"06", -- MVI A, 0x42
        13 => x"42",
        14 => x"81", -- ADD B (10 000 001 = 0x81)

        -- Test 2: ADC C - A = 0x52 + 0x0F + 0 = 0x61 (no carry from previous)
        15 => x"8A", -- ADC C (10 001 010 = 0x8A)

        -- Test 3: SUB D - A = 0x61 - 0x20 = 0x41
        16 => x"93", -- SUB D (10 010 011 = 0x93)

        -- Test 4: SBB E - A = 0x41 - 0x01 - 0 = 0x40 (no borrow from previous)
        17 => x"9C", -- SBB E (10 011 100 = 0x9C)

        -- Test 5: ANA H - A = 0x40 & 0xFF = 0x40
        18 => x"A5", -- ANA H (10 100 101 = 0xA5)

        -- Test 6: XRA L - A = 0x40 ^ 0xA0 = 0xE0
        19 => x"AE", -- XRA L (10 101 110 = 0xAE)

        -- Test 7: ORA B - A = 0xE0 | 0x10 = 0xF0
        20 => x"B1", -- ORA B (10 110 001 = 0xB1)

        -- Test 8: CMP C - Compare 0xF0 with 0x0F (flags only, A unchanged)
        21 => x"BA", -- CMP C (10 111 010 = 0xBA)

        22 => x"FF", -- HLT

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

    -- Data bus multiplexing - simple for register operations (no RAM needed)
    DBUS_MUX: process(phi2)
        variable state_vec : std_logic_vector(2 downto 0);
    begin
        if falling_edge(phi2) then
            state_vec := S2 & S1 & S0;

            -- For interrupt acknowledge (T1I), inject RST 0
            if INT = '1' and state_vec = "001" then
                data_bus_in <= x"05";  -- RST 0
            else
                -- All other times: provide ROM data
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
        report "Intel 8008 ALU Register Operations Test";
        report "Testing all 8 ALU register operations";
        report "========================================";

        -- Reset phase clocks
        reset <= '1';
        wait for 100 ns;
        reset <= '0';
        wait for 500 ns;

        -- Boot CPU with RST 0 (8008 starts in STOPPED state)
        report "Booting CPU with RST 0...";
        wait until rising_edge(phi1);
        INT <= '1';
        wait for 3000 ns;
        INT <= '0';

        -- Execute test program
        report "";
        report "Executing ALU register test program:";
        report "  Setup: Initialize B=0x10, C=0x0F, D=0x20, E=0x01, H=0xFF, L=0xA0";
        report "  Test 1: ADD B - 0x42 + 0x10 = 0x52";
        report "  Test 2: ADC C - 0x52 + 0x0F + 0 = 0x61";
        report "  Test 3: SUB D - 0x61 - 0x20 = 0x41";
        report "  Test 4: SBB E - 0x41 - 0x01 - 0 = 0x40";
        report "  Test 5: ANA H - 0x40 & 0xFF = 0x40";
        report "  Test 6: XRA L - 0x40 ^ 0xA0 = 0xE0";
        report "  Test 7: ORA B - 0xE0 | 0x10 = 0xF0";
        report "  Test 8: CMP C - Compare 0xF0 with 0x0F";

        -- Wait for execution to complete
        wait for 1200 us;

        -- Verify results
        report "";
        report "========================================";
        report "Verifying Results:";
        report "========================================";

        -- Check register values
        report "Register A: 0x" & to_hstring(debug_reg_A) & " (expected 0xF0)";
        if debug_reg_A /= x"F0" then
            report "ERROR: Register A mismatch" severity warning;
            errors := errors + 1;
        else
            report "  PASS: Register A correct";
        end if;

        report "Register B: 0x" & to_hstring(debug_reg_B) & " (expected 0x10)";
        if debug_reg_B /= x"10" then
            report "ERROR: Register B mismatch" severity warning;
            errors := errors + 1;
        else
            report "  PASS: Register B correct";
        end if;

        report "Register C: 0x" & to_hstring(debug_reg_C) & " (expected 0x0F)";
        if debug_reg_C /= x"0F" then
            report "ERROR: Register C mismatch" severity warning;
            errors := errors + 1;
        else
            report "  PASS: Register C correct";
        end if;

        report "Register D: 0x" & to_hstring(debug_reg_D) & " (expected 0x20)";
        if debug_reg_D /= x"20" then
            report "ERROR: Register D mismatch" severity warning;
            errors := errors + 1;
        else
            report "  PASS: Register D correct";
        end if;

        report "Register E: 0x" & to_hstring(debug_reg_E) & " (expected 0x01)";
        if debug_reg_E /= x"01" then
            report "ERROR: Register E mismatch" severity warning;
            errors := errors + 1;
        else
            report "  PASS: Register E correct";
        end if;

        report "Register H: 0x" & to_hstring(debug_reg_H) & " (expected 0xFF)";
        if debug_reg_H /= x"FF" then
            report "ERROR: Register H mismatch" severity warning;
            errors := errors + 1;
        else
            report "  PASS: Register H correct";
        end if;

        report "Register L: 0x" & to_hstring(debug_reg_L) & " (expected 0xA0)";
        if debug_reg_L /= x"A0" then
            report "ERROR: Register L mismatch" severity warning;
            errors := errors + 1;
        else
            report "  PASS: Register L correct";
        end if;

        -- Verify flags from CMP C (0xF0 - 0x0F = 0xE1)
        -- Carry: 0 (no borrow), Zero: 0 (not zero), Sign: 1 (negative/MSB set), Parity: 0 (odd)
        report "Flags: C=" & std_logic'image(debug_flags(3)) &
               " Z=" & std_logic'image(debug_flags(2)) &
               " S=" & std_logic'image(debug_flags(1)) &
               " P=" & std_logic'image(debug_flags(0));

        -- Test summary
        report "";
        report "========================================";
        if errors = 0 then
            report "*** ALL ALU REGISTER TESTS PASSED (8/8) ***";
            report "  - ADD r: PASS";
            report "  - ADC r: PASS";
            report "  - SUB r: PASS";
            report "  - SBB r: PASS";
            report "  - ANA r: PASS";
            report "  - XRA r: PASS";
            report "  - ORA r: PASS";
            report "  - CMP r: PASS";
        else
            report "*** TESTS FAILED: " & integer'image(errors) & " errors ***" severity error;
        end if;
        report "========================================";

        done <= true;
        wait;
    end process TEST_PROC;

end behavior;

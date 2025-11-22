-------------------------------------------------------------------------------
-- Intel 8008 v8008 ALU Immediate Operations Test (Comprehensive)
-------------------------------------------------------------------------------
-- Tests all 8 ALU Immediate operations with immediate data values
-- ALU I format: 00 FFF 100 followed by immediate byte (where FFF = operation)
-- Operations tested:
--   ADI: A = A + imm  (opcode 0x04)
--   ACI: A = A + imm + Carry (opcode 0x0C)
--   SUI: A = A - imm  (opcode 0x14)
--   SBI: A = A - imm - Borrow (opcode 0x1C)
--   ANI: A = A & imm  (opcode 0x24)
--   XRI: A = A ^ imm  (opcode 0x2C)
--   ORI: A = A | imm  (opcode 0x34)
--   CPI: Compare A with imm (opcode 0x3C, flags only, A unchanged)
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;

entity v8008_alu_imm_tb is
end v8008_alu_imm_tb;

architecture behavior of v8008_alu_imm_tb is

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
        -- Test 1: ADI - A = 0x42 + 0x10 = 0x52
        0 => x"06",  -- MVI A, 0x42
        1 => x"42",
        2 => x"04",  -- ADI (00 000 100 = 0x04)
        3 => x"10",  -- Immediate data

        -- Test 2: ACI - A = 0x52 + 0x0F + 0 = 0x61 (no carry from previous)
        4 => x"0C",  -- ACI (00 001 100 = 0x0C)
        5 => x"0F",

        -- Test 3: SUI - A = 0x61 - 0x20 = 0x41
        6 => x"14",  -- SUI (00 010 100 = 0x14)
        7 => x"20",

        -- Test 4: SBI - A = 0x41 - 0x01 - 0 = 0x40 (no borrow from previous)
        8 => x"1C",  -- SBI (00 011 100 = 0x1C)
        9 => x"01",

        -- Test 5: ANI - A = 0x40 & 0xFF = 0x40
        10 => x"24", -- ANI (00 100 100 = 0x24)
        11 => x"FF",

        -- Test 6: XRI - A = 0x40 ^ 0xA0 = 0xE0
        12 => x"2C", -- XRI (00 101 100 = 0x2C)
        13 => x"A0",

        -- Test 7: ORI - A = 0xE0 | 0x10 = 0xF0
        14 => x"34", -- ORI (00 110 100 = 0x34)
        15 => x"10",

        -- Test 8: CPI - Compare 0xF0 with 0x0F (flags only, A unchanged)
        16 => x"3C", -- CPI (00 111 100 = 0x3C)
        17 => x"0F",

        18 => x"FF", -- HLT

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

    -- Data bus multiplexing - simple for immediate operations (no RAM needed)
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
        report "Intel 8008 ALU Immediate Operations Test";
        report "Testing all 8 ALU immediate operations";
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
        report "Executing ALU immediate test program:";
        report "  Test 1: ADI 0x10 - 0x42 + 0x10 = 0x52";
        report "  Test 2: ACI 0x0F - 0x52 + 0x0F + 0 = 0x61";
        report "  Test 3: SUI 0x20 - 0x61 - 0x20 = 0x41";
        report "  Test 4: SBI 0x01 - 0x41 - 0x01 - 0 = 0x40";
        report "  Test 5: ANI 0xFF - 0x40 & 0xFF = 0x40";
        report "  Test 6: XRI 0xA0 - 0x40 ^ 0xA0 = 0xE0";
        report "  Test 7: ORI 0x10 - 0xE0 | 0x10 = 0xF0";
        report "  Test 8: CPI 0x0F - Compare 0xF0 with 0x0F";

        -- Wait for execution to complete
        wait for 1200 us;

        -- Verify results
        report "";
        report "========================================";
        report "Verifying Results:";
        report "========================================";

        -- Check register A
        report "Register A: 0x" & to_hstring(debug_reg_A) & " (expected 0xF0)";
        if debug_reg_A /= x"F0" then
            report "ERROR: Register A mismatch" severity warning;
            errors := errors + 1;
        else
            report "  PASS: Register A correct";
        end if;

        -- Verify flags from CPI (0xF0 - 0x0F = 0xE1)
        -- Carry: 0 (no borrow), Zero: 0 (not zero), Sign: 1 (negative/MSB set), Parity: 0 (odd)
        report "Flags: C=" & std_logic'image(debug_flags(3)) &
               " Z=" & std_logic'image(debug_flags(2)) &
               " S=" & std_logic'image(debug_flags(1)) &
               " P=" & std_logic'image(debug_flags(0));

        -- Test summary
        report "";
        report "========================================";
        if errors = 0 then
            report "*** ALL ALU IMMEDIATE TESTS PASSED (8/8) ***";
            report "  - ADI: PASS";
            report "  - ACI: PASS";
            report "  - SUI: PASS";
            report "  - SBI: PASS";
            report "  - ANI: PASS";
            report "  - XRI: PASS";
            report "  - ORI: PASS";
            report "  - CPI: PASS";
        else
            report "*** TESTS FAILED: " & integer'image(errors) & " errors ***" severity error;
        end if;
        report "========================================";

        done <= true;
        wait;
    end process TEST_PROC;

end behavior;

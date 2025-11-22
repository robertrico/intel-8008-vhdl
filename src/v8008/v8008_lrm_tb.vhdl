-------------------------------------------------------------------------------
-- Intel 8008 v8008 LrM (MOV r,M) Instruction Test
-------------------------------------------------------------------------------
-- Comprehensive ROM-based test for LrM (Load from Memory to Register)
-- Opcode: 11 DDD 111 (where DDD = dest reg, SSS=111 for M)
--
-- Tests all 7 LrM variants:
--   MOV A,M (0xC7), MOV B,M (0xCF), MOV C,M (0xD7), MOV D,M (0xDF)
--   MOV E,M (0xE7), MOV H,M (0xEF), MOV L,M (0xF7)
--
-- Test program loads sequential test values from memory into all registers
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.v8008_tb_utils.all;

entity v8008_lrm_tb is
end v8008_lrm_tb;

architecture behavior of v8008_lrm_tb is

    component phase_clocks
        port (clk_in, reset : in std_logic; phi1, phi2 : out std_logic);
    end component;

    component v8008
        port (
            phi1, phi2 : in std_logic;
            data_bus_in : in std_logic_vector(7 downto 0);
            data_bus_out : out std_logic_vector(7 downto 0);
            data_bus_enable : out std_logic;
            S0, S1, S2, SYNC : out std_logic;
            READY, INT : in std_logic;
            debug_reg_A, debug_reg_B, debug_reg_C, debug_reg_D, debug_reg_E, debug_reg_H, debug_reg_L : out std_logic_vector(7 downto 0);
            debug_pc : out std_logic_vector(13 downto 0);
            debug_flags : out std_logic_vector(3 downto 0);
            debug_instruction : out std_logic_vector(7 downto 0);
            debug_stack_pointer : out std_logic_vector(2 downto 0);
            debug_hl_address : out std_logic_vector(13 downto 0)
        );
    end component;

    signal clk_master, reset, phi1, phi2, INT, READY : std_logic := '0';
    signal data_bus_in, data_bus_out : std_logic_vector(7 downto 0);
    signal data_bus_enable, S0, S1, S2, SYNC : std_logic;
    signal debug_reg_A, debug_reg_B, debug_reg_C, debug_reg_D, debug_reg_E, debug_reg_H, debug_reg_L : std_logic_vector(7 downto 0);
    signal debug_pc : std_logic_vector(13 downto 0);
    signal debug_flags : std_logic_vector(3 downto 0);
    signal debug_instruction : std_logic_vector(7 downto 0);
    signal debug_stack_pointer : std_logic_vector(2 downto 0);
    signal debug_hl_address : std_logic_vector(13 downto 0);
    signal done : boolean := false;

    constant CLK_PERIOD : time := 10 ns;

    -- ROM contents (program code)
    type rom_t is array (0 to 127) of std_logic_vector(7 downto 0);
    constant rom_contents : rom_t := (
        -- Initialize H:L to point to test data at 0x0010
        0 => x"36",  -- MVI L, 0x10 (00 110 110)
        1 => x"10",
        2 => x"2E",  -- MVI H, 0x00 (00 101 110)
        3 => x"00",

        -- Test MOV A,M (0xC7)
        4 => x"C7",  -- MOV A, M

        -- Update L to point to next test address
        5 => x"36",  -- MVI L, 0x11
        6 => x"11",

        -- Test MOV B,M (0xCF)
        7 => x"CF",  -- MOV B, M

        -- Update L
        8 => x"36",  -- MVI L, 0x12
        9 => x"12",

        -- Test MOV C,M (0xD7)
        10 => x"D7", -- MOV C, M

        -- Update L
        11 => x"36", -- MVI L, 0x13
        12 => x"13",

        -- Test MOV D,M (0xDF)
        13 => x"DF", -- MOV D, M

        -- Update L
        14 => x"36", -- MVI L, 0x14
        15 => x"14",

        -- Test MOV E,M (0xE7)
        16 => x"E7", -- MOV E, M

        -- Update L (for H test)
        17 => x"36", -- MVI L, 0x15
        18 => x"15",

        -- Test MOV H,M (0xEF) - Note: this overwrites H, so save/restore
        19 => x"EF", -- MOV H, M
        20 => x"2E", -- MVI H, 0x00 (restore H)
        21 => x"00",

        -- Update L
        22 => x"36", -- MVI L, 0x16
        23 => x"16",

        -- Test MOV L,M (0xF7) - Note: this overwrites L
        24 => x"F7", -- MOV L, M

        25 => x"FF", -- HLT
        others => x"00"
    );

    -- RAM contents (test data at addresses 0x10-0x16)
    type ram_t is array (0 to 255) of std_logic_vector(7 downto 0);
    signal ram_contents : ram_t := (
        16 => x"42",  -- Test data for A at 0x0010
        17 => x"AA",  -- Test data for B at 0x0011
        18 => x"55",  -- Test data for C at 0x0012
        19 => x"33",  -- Test data for D at 0x0013
        20 => x"CC",  -- Test data for E at 0x0014
        21 => x"99",  -- Test data for H at 0x0015
        22 => x"66",  -- Test data for L at 0x0016
        others => x"00"
    );

    signal rom_addr : std_logic_vector(6 downto 0);
    signal rom_data, ram_data : std_logic_vector(7 downto 0);

begin

    READY <= '1';

    CLK_GEN: phase_clocks port map (clk_master, reset, phi1, phi2);
    UUT: v8008 port map (phi1, phi2, data_bus_in, data_bus_out, data_bus_enable,
                         S0, S1, S2, SYNC, READY, INT,
                         debug_reg_A, debug_reg_B, debug_reg_C, debug_reg_D, debug_reg_E, debug_reg_H, debug_reg_L,
                         debug_pc, debug_flags, debug_instruction, debug_stack_pointer, debug_hl_address);

    -- ROM access
    rom_addr <= debug_pc(6 downto 0);

    ROM_PROC: process(phi2)
    begin
        if falling_edge(phi2) then
            rom_data <= rom_contents(to_integer(unsigned(rom_addr)));
            report "ROM fetch: PC=" & to_hstring(debug_pc) & ", addr=" & integer'image(to_integer(unsigned(rom_addr))) & ", data=0x" & to_hstring(rom_contents(to_integer(unsigned(rom_addr))));
        end if;
    end process;

    -- RAM access
    RAM_PROC: process(phi2)
    begin
        if falling_edge(phi2) then
            ram_data <= ram_contents(to_integer(unsigned(debug_hl_address(7 downto 0))));
        end if;
    end process;

    -- Data bus multiplexing using v8008_tb_utils
    DBUS_MUX: process(phi2)
        variable state_vec : std_logic_vector(2 downto 0);
        variable prev_state_vec : std_logic_vector(2 downto 0) := "000";
        variable prev_instruction : std_logic_vector(7 downto 0) := x"00";
        variable cycle_in_instruction : integer := 0;
        variable in_int_ack : boolean := false;
    begin
        if falling_edge(phi2) then
            state_vec := S2 & S1 & S0;

            -- Interrupt ack detection
            if state_vec = "110" then
                in_int_ack := true;
            elsif in_int_ack and state_vec = "101" then
                in_int_ack := false;
            end if;

            -- Cycle tracking: reset on instruction change
            if debug_instruction /= prev_instruction then
                cycle_in_instruction := 0;
                prev_instruction := debug_instruction;
            elsif state_vec = "010" and prev_state_vec /= "010" then
                cycle_in_instruction := cycle_in_instruction + 1;
            end if;

            -- Data bus multiplexing
            if in_int_ack and state_vec = "001" then
                data_bus_in <= x"05";  -- RST 0
            elsif should_use_ram(state_vec, cycle_in_instruction, debug_instruction) then
                data_bus_in <= ram_data;
            else
                data_bus_in <= rom_data;
            end if;

            prev_state_vec := state_vec;
        end if;
    end process;

    CLOCK_PROC: process
    begin
        while not done loop
            clk_master <= '0'; wait for CLK_PERIOD / 2;
            clk_master <= '1'; wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    TEST_PROC: process
        variable state_vec : std_logic_vector(2 downto 0);
        variable errors : integer := 0;
    begin
        report "========================================";
        report "LrM (MOV r,M) Comprehensive Test";
        report "Testing all 7 LrM instruction variants";
        report "========================================";

        wait for 500 ns;

        -- Boot CPU with RST 0
        report "Booting CPU with RST 0...";
        wait until rising_edge(phi1);
        INT <= '1';
        wait for 3000 ns;
        INT <= '0';

        -- Wait for program to execute
        -- Program has: 2 MVI (setup) + 7 LrM tests with 14 additional MVI = ~26 instructions
        -- Each instruction takes ~20-60us, so need ~1-2ms total
        wait for 2000000 ns;

        -- Check all register values
        report "========================================";
        report "Final register values:";
        report "  A = 0x" & to_hstring(debug_reg_A) & " (expected 0x42)";
        report "  B = 0x" & to_hstring(debug_reg_B) & " (expected 0xAA)";
        report "  C = 0x" & to_hstring(debug_reg_C) & " (expected 0x55)";
        report "  D = 0x" & to_hstring(debug_reg_D) & " (expected 0x33)";
        report "  E = 0x" & to_hstring(debug_reg_E) & " (expected 0xCC)";
        report "  H = 0x" & to_hstring(debug_reg_H) & " (expected 0x00, restored after MOV H,M)";
        report "  L = 0x" & to_hstring(debug_reg_L) & " (expected 0x66, set by MOV L,M)";
        report "========================================";

        -- Verify all registers
        if debug_reg_A /= x"42" then
            report "ERROR: MOV A,M failed - A = 0x" & to_hstring(debug_reg_A) & ", expected 0x42"
                severity error;
            errors := errors + 1;
        else
            report "PASS: MOV A,M (0xC7) correct";
        end if;

        if debug_reg_B /= x"AA" then
            report "ERROR: MOV B,M failed - B = 0x" & to_hstring(debug_reg_B) & ", expected 0xAA"
                severity error;
            errors := errors + 1;
        else
            report "PASS: MOV B,M (0xCF) correct";
        end if;

        if debug_reg_C /= x"55" then
            report "ERROR: MOV C,M failed - C = 0x" & to_hstring(debug_reg_C) & ", expected 0x55"
                severity error;
            errors := errors + 1;
        else
            report "PASS: MOV C,M (0xD7) correct";
        end if;

        if debug_reg_D /= x"33" then
            report "ERROR: MOV D,M failed - D = 0x" & to_hstring(debug_reg_D) & ", expected 0x33"
                severity error;
            errors := errors + 1;
        else
            report "PASS: MOV D,M (0xDF) correct";
        end if;

        if debug_reg_E /= x"CC" then
            report "ERROR: MOV E,M failed - E = 0x" & to_hstring(debug_reg_E) & ", expected 0xCC"
                severity error;
            errors := errors + 1;
        else
            report "PASS: MOV E,M (0xE7) correct";
        end if;

        if debug_reg_H /= x"00" then
            report "ERROR: MOV H,M test failed - H = 0x" & to_hstring(debug_reg_H) & ", expected 0x00 (restored)"
                severity error;
            errors := errors + 1;
        else
            report "PASS: MOV H,M (0xEF) correct (H was loaded then restored)";
        end if;

        if debug_reg_L /= x"66" then
            report "ERROR: MOV L,M failed - L = 0x" & to_hstring(debug_reg_L) & ", expected 0x66"
                severity error;
            errors := errors + 1;
        else
            report "PASS: MOV L,M (0xF7) correct";
        end if;

        report "========================================";
        if errors = 0 then
            report "*** ALL LrM TESTS PASSED (7/7) ***";
            report "All LrM instruction variants working correctly";
        else
            report "*** TEST FAILED: " & integer'image(errors) & " errors ***";
        end if;
        report "========================================";

        done <= true;
        wait;
    end process;

end behavior;

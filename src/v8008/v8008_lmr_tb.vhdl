-------------------------------------------------------------------------------
-- Intel 8008 v8008 LMr (MOV M,r) Instruction Test
-------------------------------------------------------------------------------
-- Testbench to verify MOV M,r (LMr - Load Memory from Register) instruction
--
-- Instruction format: 11 111 SSS (where SSS = source register)
-- Opcodes:
--   MOV M,A (0xF8), MOV M,B (0xF9), MOV M,C (0xFA), MOV M,D (0xFB)
--   MOV M,E (0xFC), MOV M,H (0xFD), MOV M,L (0xFE)
--
-- This is a 2-cycle instruction:
--   Cycle 0: Fetch instruction
--   Cycle 1: Write register value to memory at HL address
--
-- Test Coverage:
--   - All 7 source registers (A, B, C, D, E, H, L)
--   - Different memory addresses
--   - Verification of memory writes
--   - Note: MOV M,H and MOV M,L modify the address during write
--
-- Copyright (c) 2025 Robert Rico
-- License: MIT
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;

library work;
use work.v8008_tb_utils.all;

entity v8008_lmr_tb is
end v8008_lmr_tb;

architecture behavior of v8008_lmr_tb is

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
        -- Initialize registers with test values
        0 => x"06",  -- MVI A, 0xAA
        1 => x"AA",
        2 => x"0E",  -- MVI B, 0xBB
        3 => x"BB",
        4 => x"16",  -- MVI C, 0xCC
        5 => x"CC",
        6 => x"1E",  -- MVI D, 0xDD
        7 => x"DD",
        8 => x"26",  -- MVI E, 0xEE
        9 => x"EE",

        -- Test 1: MOV M,A - Write A (0xAA) to memory at HL=0x0040
        10 => x"2E", -- MVI H, 0x00
        11 => x"00",
        12 => x"36", -- MVI L, 0x40
        13 => x"40",
        14 => x"F8", -- MOV M,A (11 111 000 = 0xF8)

        -- Test 2: MOV M,B - Write B (0xBB) to memory at HL=0x0041
        15 => x"36", -- MVI L, 0x41
        16 => x"41",
        17 => x"F9", -- MOV M,B (11 111 001 = 0xF9)

        -- Test 3: MOV M,C - Write C (0xCC) to memory at HL=0x0042
        18 => x"36", -- MVI L, 0x42
        19 => x"42",
        20 => x"FA", -- MOV M,C (11 111 010 = 0xFA)

        -- Test 4: MOV M,D - Write D (0xDD) to memory at HL=0x0043
        21 => x"36", -- MVI L, 0x43
        22 => x"43",
        23 => x"FB", -- MOV M,D (11 111 011 = 0xFB)

        -- Test 5: MOV M,E - Write E (0xEE) to memory at HL=0x0044
        24 => x"36", -- MVI L, 0x44
        25 => x"44",
        26 => x"FC", -- MOV M,E (11 111 100 = 0xFC)

        -- Test 6: MOV M,H - Write H (0x00) to memory at HL=0x0045
        27 => x"36", -- MVI L, 0x45
        28 => x"45",
        29 => x"FD", -- MOV M,H (11 111 101 = 0xFD)

        -- Test 7: MOV M,L - Write L (0x45) to memory at HL=0x0046
        -- Note: L changes during the write, so this is tricky
        30 => x"36", -- MVI L, 0x46
        31 => x"46",
        32 => x"FE", -- MOV M,L (11 111 110 = 0xFE)

        33 => x"FF", -- HLT
        others => x"00"
    );

    -- RAM for testing
    type ram_t is array (0 to 255) of std_logic_vector(7 downto 0);
    signal ram_contents : ram_t := (others => x"00");
    signal rom_data, ram_data : std_logic_vector(7 downto 0);
    signal rom_addr : std_logic_vector(6 downto 0);
    signal mem_addr : std_logic_vector(7 downto 0);

begin

    clk_master <= not clk_master after CLK_PERIOD / 2;
    READY <= '1';

    PHASE_GEN: phase_clocks
        port map (
            clk_in => clk_master,
            reset => reset,
            phi1 => phi1,
            phi2 => phi2
        );

    CPU: v8008
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

    -- ROM address from program counter
    rom_addr <= debug_pc(6 downto 0);

    -- Memory address from HL or data bus
    mem_addr <= debug_hl_address(7 downto 0);

    -- ROM process (provides instructions)
    ROM_PROC: process(phi2)
    begin
        if falling_edge(phi2) then
            rom_data <= rom_contents(to_integer(unsigned(rom_addr)));
        end if;
    end process;

    -- RAM process (read/write data memory)
    RAM_PROC: process(phi2)
    begin
        if falling_edge(phi2) then
            -- Read RAM
            ram_data <= ram_contents(to_integer(unsigned(mem_addr)));

            -- Write RAM (when CPU is writing to data bus during T3)
            -- External RAM must decode T-state from S0/S1/S2 pins (just like real hardware would)
            -- T3 state: S2='0', S1='0', S0='1' (S2S1S0 = 001) - this is the data transfer state
            -- data_bus_enable ensures CPU is actively driving the bus
            if data_bus_enable = '1' and (S2 = '0' and S1 = '0' and S0 = '1') then
                ram_contents(to_integer(unsigned(mem_addr))) <= data_bus_out;
                report "RAM WRITE: addr=0x" & to_hstring(mem_addr) & ", data=0x" & to_hstring(data_bus_out);
            end if;
        end if;
    end process;

    -- Data bus multiplexer process
    MUX_PROC: process(phi1)
        variable state_vec : std_logic_vector(2 downto 0);
        variable prev_state_vec : std_logic_vector(2 downto 0) := "000";
        variable cycle_in_instruction : integer := 0;
    begin
        if rising_edge(phi1) then
            state_vec := S2 & S1 & S0;

            -- Track instruction cycles
            if state_vec /= prev_state_vec and state_vec = "000" then
                cycle_in_instruction := 0;
            elsif state_vec /= prev_state_vec then
                cycle_in_instruction := cycle_in_instruction + 1;
            end if;

            -- Multiplex data bus
            if INT = '1' then
                data_bus_in <= x"05";  -- RST 0
            elsif should_use_ram(state_vec, cycle_in_instruction, debug_instruction) then
                data_bus_in <= ram_data;
            else
                data_bus_in <= rom_data;
            end if;

            prev_state_vec := state_vec;
        end if;
    end process;

    -- Test process
    TEST_PROC: process
        variable errors : integer := 0;
    begin
        reset <= '1';
        wait for 100 ns;
        reset <= '0';

        report "========================================";
        report "Testing MOV M,r (LMr) for all 7 registers";
        report "========================================";

        wait for 500 ns;

        -- Boot CPU with RST 0
        report "Booting CPU with RST 0...";
        wait until rising_edge(phi1);
        INT <= '1';
        wait for 3000 ns;
        INT <= '0';

        -- Wait for program to execute
        -- Program has: 5 MVI (init) + 7 LMr tests with HL setup = ~20 instructions
        wait for 2000000 ns;

        -- Check RAM contents
        report "========================================";
        report "Final RAM contents at test addresses:";
        report "  RAM[0x40] = 0x" & to_hstring(ram_contents(16#40#)) & " (expected 0xAA from MOV M,A)";
        report "  RAM[0x41] = 0x" & to_hstring(ram_contents(16#41#)) & " (expected 0xBB from MOV M,B)";
        report "  RAM[0x42] = 0x" & to_hstring(ram_contents(16#42#)) & " (expected 0xCC from MOV M,C)";
        report "  RAM[0x43] = 0x" & to_hstring(ram_contents(16#43#)) & " (expected 0xDD from MOV M,D)";
        report "  RAM[0x44] = 0x" & to_hstring(ram_contents(16#44#)) & " (expected 0xEE from MOV M,E)";
        report "  RAM[0x45] = 0x" & to_hstring(ram_contents(16#45#)) & " (expected 0x00 from MOV M,H)";
        report "  RAM[0x46] = 0x" & to_hstring(ram_contents(16#46#)) & " (expected 0x46 from MOV M,L)";
        report "========================================";

        -- Verify all writes
        if ram_contents(16#40#) /= x"AA" then
            report "ERROR: MOV M,A failed - RAM[0x40] = 0x" & to_hstring(ram_contents(16#40#)) & ", expected 0xAA"
                severity error;
            errors := errors + 1;
        else
            report "PASS: MOV M,A (0xF8) correct";
        end if;

        if ram_contents(16#41#) /= x"BB" then
            report "ERROR: MOV M,B failed - RAM[0x41] = 0x" & to_hstring(ram_contents(16#41#)) & ", expected 0xBB"
                severity error;
            errors := errors + 1;
        else
            report "PASS: MOV M,B (0xF9) correct";
        end if;

        if ram_contents(16#42#) /= x"CC" then
            report "ERROR: MOV M,C failed - RAM[0x42] = 0x" & to_hstring(ram_contents(16#42#)) & ", expected 0xCC"
                severity error;
            errors := errors + 1;
        else
            report "PASS: MOV M,C (0xFA) correct";
        end if;

        if ram_contents(16#43#) /= x"DD" then
            report "ERROR: MOV M,D failed - RAM[0x43] = 0x" & to_hstring(ram_contents(16#43#)) & ", expected 0xDD"
                severity error;
            errors := errors + 1;
        else
            report "PASS: MOV M,D (0xFB) correct";
        end if;

        if ram_contents(16#44#) /= x"EE" then
            report "ERROR: MOV M,E failed - RAM[0x44] = 0x" & to_hstring(ram_contents(16#44#)) & ", expected 0xEE"
                severity error;
            errors := errors + 1;
        else
            report "PASS: MOV M,E (0xFC) correct";
        end if;

        if ram_contents(16#45#) /= x"00" then
            report "ERROR: MOV M,H failed - RAM[0x45] = 0x" & to_hstring(ram_contents(16#45#)) & ", expected 0x00"
                severity error;
            errors := errors + 1;
        else
            report "PASS: MOV M,H (0xFD) correct";
        end if;

        if ram_contents(16#46#) /= x"46" then
            report "ERROR: MOV M,L failed - RAM[0x46] = 0x" & to_hstring(ram_contents(16#46#)) & ", expected 0x46"
                severity error;
            errors := errors + 1;
        else
            report "PASS: MOV M,L (0xFE) correct";
        end if;

        report "========================================";
        if errors = 0 then
            report "*** ALL LMr TESTS PASSED (7/7) ***";
        else
            report "*** TESTS FAILED: " & integer'image(errors) & " errors ***" severity error;
        end if;
        report "========================================";

        done <= true;
        wait;
    end process;

end behavior;

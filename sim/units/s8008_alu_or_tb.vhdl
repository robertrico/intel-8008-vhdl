-------------------------------------------------------------------------------
-- Intel 8008 ALU OR Operation Comprehensive Unit Test
-------------------------------------------------------------------------------
-- Comprehensive test of OR operations (both register and immediate)
-- Tests bit patterns, edge cases, and flag behavior
--
-- Test Coverage:
--   Register OR (Class 10 110 SSS):
--     - OR r: Logical OR register with A
--     - All bit positions (individual bits, nibbles, bytes)
--     - Identity tests (OR with 0x00, OR with 0xFF)
--     - Self-OR operations
--     - Flag verification (Zero, Sign, Parity)
--
--   Immediate OR (Class 00 110 100):
--     - ORI data: Logical OR immediate with A
--     - All bit positions (individual bits, nibbles, bytes)
--     - Identity tests (ORI 0x00, ORI 0xFF)
--     - Flag verification (Zero, Sign, Parity)
--
--   Edge Cases:
--     - Setting specific bits while preserving others
--     - Creating masks
--     - Zero result detection
--     - Sign bit behavior
--     - Parity flag verification
--
-- Copyright (c) 2025 Robert Rico
-- License: MIT
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.STD_LOGIC_TEXTIO.ALL;
use STD.TEXTIO.ALL;

entity s8008_alu_or_tb is
end s8008_alu_or_tb;

architecture behavior of s8008_alu_or_tb is
    -- Component declarations
    component phase_clocks
        port(
            clk_in : in std_logic;
            reset : in std_logic;
            phi1 : out std_logic;
            phi2 : out std_logic
        );
    end component;

    component s8008
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

    -- Master clock period
    constant MASTER_CLK_PERIOD : time := 10 ns;  -- 100 MHz master clock

    -- ROM for test program
    type rom_array is array (0 to 255) of std_logic_vector(7 downto 0);
    constant ROM : rom_array := (
        -- ========================================
        -- TEST 1: OR Basic Operation (0xF0 | 0x0F = 0xFF)
        -- ========================================
        0 => x"06", -- LrI A,0xF0
        1 => x"F0",
        2 => x"0E", -- LrI B,0x0F
        3 => x"0F",
        4 => x"B1", -- OR B (A = 0xF0 | 0x0F = 0xFF)
        5 => x"16", -- LrI C,0x01 (marker 1)
        6 => x"01",

        -- ========================================
        -- TEST 2: OR with Zero (Identity - 0xAA | 0x00 = 0xAA)
        -- ========================================
        7 => x"06", -- LrI A,0xAA
        8 => x"AA",
        9 => x"0E", -- LrI B,0x00
        10 => x"00",
        11 => x"B1", -- OR B (A = 0xAA | 0x00 = 0xAA)
        12 => x"16", -- LrI C,0x02 (marker 2)
        13 => x"02",

        -- ========================================
        -- TEST 3: OR with 0xFF (0x55 | 0xFF = 0xFF)
        -- ========================================
        14 => x"06", -- LrI A,0x55
        15 => x"55",
        16 => x"0E", -- LrI B,0xFF
        17 => x"FF",
        18 => x"B1", -- OR B (A = 0x55 | 0xFF = 0xFF)
        19 => x"16", -- LrI C,0x03 (marker 3)
        20 => x"03",

        -- ========================================
        -- TEST 4: OR Self (Idempotent - 0x3C | 0x3C = 0x3C)
        -- ========================================
        21 => x"06", -- LrI A,0x3C
        22 => x"3C",
        23 => x"0E", -- LrI B,0x3C
        24 => x"3C",
        25 => x"B1", -- OR B (A = 0x3C | 0x3C = 0x3C)
        26 => x"16", -- LrI C,0x04 (marker 4)
        27 => x"04",

        -- ========================================
        -- TEST 5: OR Setting Individual Bits (0x01 | 0x02 = 0x03)
        -- ========================================
        28 => x"06", -- LrI A,0x01
        29 => x"01",
        30 => x"0E", -- LrI B,0x02
        31 => x"02",
        32 => x"B1", -- OR B (A = 0x01 | 0x02 = 0x03)
        33 => x"16", -- LrI C,0x05 (marker 5)
        34 => x"05",

        -- ========================================
        -- TEST 6: OR Creating Bit Mask (0x80 | 0x01 = 0x81)
        -- ========================================
        35 => x"06", -- LrI A,0x80
        36 => x"80",
        37 => x"0E", -- LrI B,0x01
        38 => x"01",
        39 => x"B1", -- OR B (A = 0x80 | 0x01 = 0x81)
        40 => x"16", -- LrI C,0x06 (marker 6)
        41 => x"06",

        -- ========================================
        -- TEST 7: OR Zero Result Test (0x00 | 0x00 = 0x00, Z flag)
        -- ========================================
        42 => x"06", -- LrI A,0x00
        43 => x"00",
        44 => x"0E", -- LrI B,0x00
        45 => x"00",
        46 => x"B1", -- OR B (A = 0x00 | 0x00 = 0x00, Z=1)
        47 => x"16", -- LrI C,0x07 (marker 7)
        48 => x"07",

        -- ========================================
        -- TEST 8: OR Sign Flag Test (0x80 | 0x00 = 0x80, S flag)
        -- ========================================
        49 => x"06", -- LrI A,0x80
        50 => x"80",
        51 => x"0E", -- LrI B,0x00
        52 => x"00",
        53 => x"B1", -- OR B (A = 0x80, S=1 because bit 7 is set)
        54 => x"16", -- LrI C,0x08 (marker 8)
        55 => x"08",

        -- ========================================
        -- TEST 9: ORI (immediate) Basic (0x50 | 0x05 = 0x55)
        -- ========================================
        56 => x"06", -- LrI A,0x50
        57 => x"50",
        58 => x"34", -- ORI 0x05 (A = 0x50 | 0x05 = 0x55)
        59 => x"05",
        60 => x"16", -- LrI C,0x09 (marker 9)
        61 => x"09",

        -- ========================================
        -- TEST 10: ORI with 0x00 (Identity - 0xCC | 0x00 = 0xCC)
        -- ========================================
        62 => x"06", -- LrI A,0xCC
        63 => x"CC",
        64 => x"34", -- ORI 0x00 (A = 0xCC | 0x00 = 0xCC)
        65 => x"00",
        66 => x"16", -- LrI C,0x0A (marker 10)
        67 => x"0A",

        -- ========================================
        -- TEST 11: ORI with 0xFF (0x33 | 0xFF = 0xFF)
        -- ========================================
        68 => x"06", -- LrI A,0x33
        69 => x"33",
        70 => x"34", -- ORI 0xFF (A = 0x33 | 0xFF = 0xFF)
        71 => x"FF",
        72 => x"16", -- LrI C,0x0B (marker 11)
        73 => x"0B",

        -- ========================================
        -- TEST 12: ORI Setting Low Nibble (0xA0 | 0x0F = 0xAF)
        -- ========================================
        74 => x"06", -- LrI A,0xA0
        75 => x"A0",
        76 => x"34", -- ORI 0x0F (A = 0xA0 | 0x0F = 0xAF)
        77 => x"0F",
        78 => x"16", -- LrI C,0x0C (marker 12)
        79 => x"0C",

        -- ========================================
        -- TEST 13: ORI Setting High Nibble (0x0A | 0xF0 = 0xFA)
        -- ========================================
        80 => x"06", -- LrI A,0x0A
        81 => x"0A",
        82 => x"34", -- ORI 0xF0 (A = 0x0A | 0xF0 = 0xFA)
        83 => x"F0",
        84 => x"16", -- LrI C,0x0D (marker 13)
        85 => x"0D",

        -- ========================================
        -- TEST 14: ORI Parity Flag Test (0x00 | 0x07 = 0x07, even parity)
        -- 0x07 = 0b00000111 has 3 ones (odd parity, P=0)
        -- ========================================
        86 => x"06", -- LrI A,0x00
        87 => x"00",
        88 => x"34", -- ORI 0x07 (A = 0x07, P=0 for odd parity)
        89 => x"07",
        90 => x"16", -- LrI C,0x0E (marker 14)
        91 => x"0E",

        -- ========================================
        -- TEST 15: ORI Parity Flag Test (0x00 | 0x03 = 0x03, even parity)
        -- 0x03 = 0b00000011 has 2 ones (even parity, P=1)
        -- ========================================
        92 => x"06", -- LrI A,0x00
        93 => x"00",
        94 => x"34", -- ORI 0x03 (A = 0x03, P=1 for even parity)
        95 => x"03",
        96 => x"16", -- LrI C,0x0F (marker 15)
        97 => x"0F",

        -- ========================================
        -- TEST 16: OR with All Registers (verify all source registers work)
        -- ========================================
        98 => x"06", -- LrI A,0x10
        99 => x"10",
        100 => x"0E", -- LrI B,0x01
        101 => x"01",
        102 => x"B1", -- OR B (A = 0x11)

        103 => x"16", -- LrI C,0x02
        104 => x"02",
        105 => x"B2", -- OR C (A = 0x11 | 0x02 = 0x13)

        106 => x"1E", -- LrI D,0x04
        107 => x"04",
        108 => x"B3", -- OR D (A = 0x13 | 0x04 = 0x17)

        109 => x"26", -- LrI E,0x08
        110 => x"08",
        111 => x"B4", -- OR E (A = 0x17 | 0x08 = 0x1F)

        112 => x"2E", -- LrI H,0x20
        113 => x"20",
        114 => x"B5", -- OR H (A = 0x1F | 0x20 = 0x3F)

        115 => x"36", -- LrI L,0x40
        116 => x"40",
        117 => x"B6", -- OR L (A = 0x3F | 0x40 = 0x7F)

        118 => x"16", -- LrI C,0x10 (marker 16)
        119 => x"10",

        -- ========================================
        -- TEST 17: OR Carry Flag Behavior (OR should clear carry)
        -- ========================================
        -- First set carry flag
        120 => x"06", -- LrI A,0xFF
        121 => x"FF",
        122 => x"04", -- ADI 0x01 (A = 0x00, Carry = 1)
        123 => x"01",

        -- Now do OR - should clear carry
        124 => x"06", -- LrI A,0xAA
        125 => x"AA",
        126 => x"0E", -- LrI B,0x55
        127 => x"55",
        128 => x"B1", -- OR B (A = 0xFF, Carry should be cleared)
        129 => x"16", -- LrI C,0x11 (marker 17)
        130 => x"11",

        -- ========================================
        -- TEST 18: OR Bit Combining (0x18 | 0x24 = 0x3C)
        -- 0x18 = 0b00011000
        -- 0x24 = 0b00100100
        -- Result = 0b00111100 = 0x3C
        -- ========================================
        131 => x"06", -- LrI A,0x18
        132 => x"18",
        133 => x"0E", -- LrI B,0x24
        134 => x"24",
        135 => x"B1", -- OR B (A = 0x3C)
        136 => x"16", -- LrI C,0x12 (marker 18)
        137 => x"12",

        -- Final marker
        138 => x"0E", -- LrI B,0xFF (final marker: all tests complete)
        139 => x"FF",

        140 => x"00", -- HLT

        others => x"00"
    );

    -- Memory controller signals
    signal rom_data : std_logic_vector(7 downto 0) := (others => 'Z');
    signal rom_enable : std_logic := '0';

begin
    -- Instantiate the CPU
    uut: s8008
        port map (
            phi1 => phi1_tb,
            phi2 => phi2_tb,
            reset_n => reset_n_tb,
            data_bus_in     => data_tb,
            data_bus_out    => cpu_data_out_tb,
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

    -- Instantiate phase clock generator
    clk_gen: phase_clocks
        port map (
            clk_in => master_clk_tb,
            reset => reset_tb,
            phi1 => phi1_tb,
            phi2 => phi2_tb
        );

    -- Master clock generation
    master_clk_process: process
    begin
        master_clk_tb <= '0';
        wait for MASTER_CLK_PERIOD / 2;
        master_clk_tb <= '1';
        wait for MASTER_CLK_PERIOD / 2;
    end process;

    -- Memory controller (ROM interface)
    memory_controller: process(phi1_tb)
        variable captured_address : std_logic_vector(13 downto 0) := (others => '0');
        variable cycle_type : std_logic_vector(1 downto 0) := "00";
        variable is_write : boolean := false;
    begin
        if rising_edge(phi1_tb) then
            -- T1: Capture low address byte
            if S2_tb = '0' and S1_tb = '1' and S0_tb = '0' then
                if data_tb /= "ZZZZZZZZ" then
                    captured_address(7 downto 0) := data_tb;
                end if;
            end if;

            -- T2: Capture high address bits and cycle type
            if S2_tb = '1' and S1_tb = '0' and S0_tb = '0' then
                if data_tb /= "ZZZZZZZZ" then
                    cycle_type := data_tb(7 downto 6);
                    captured_address(13 downto 8) := data_tb(5 downto 0);
                    is_write := (cycle_type = "10");
                end if;
            end if;

            -- T3: Provide data for reads
            if S2_tb = '0' and S1_tb = '0' and S0_tb = '1' then
                if not is_write and cycle_type /= "11" then
                    rom_data <= ROM(to_integer(unsigned(captured_address)));
                    rom_enable <= '1';
                else
                    rom_enable <= '0';
                end if;
            else
                rom_enable <= '0';
            end if;
        end if;
    end process;

    -- Tri-state data bus: CPU drives when enabled, otherwise ROM drives
    data_tb <= cpu_data_out_tb when cpu_data_enable_tb = '1' else
               rom_data when rom_enable = '1' else
               (others => 'Z');

    -- Test stimulus and verification
    stim_proc: process
        variable test_count : integer := 0;
        variable pass_count : integer := 0;

        -- Helper procedure for test verification
        procedure check_test(
            test_num : integer;
            test_name : string;
            expected_A : std_logic_vector(7 downto 0);
            check_flags : boolean := false;
            expected_Z : std_logic := '-';
            expected_S : std_logic := '-';
            expected_P : std_logic := '-';
            expected_C : std_logic := '-'
        ) is
        begin
            test_count := test_count + 1;
            report "========================================";
            report "TEST " & integer'image(test_num) & ": " & test_name;
            report "========================================";
            report "  A = 0x" & to_hstring(debug_reg_A_tb) & " (expected 0x" & to_hstring(expected_A) & ")";

            if check_flags then
                report "  Flags = " & to_string(debug_flags_tb) & " [C Z S P]";
                report "  Expected: C=" & std_logic'image(expected_C) &
                       " Z=" & std_logic'image(expected_Z) &
                       " S=" & std_logic'image(expected_S) &
                       " P=" & std_logic'image(expected_P);
            end if;

            assert debug_reg_A_tb = expected_A
                report "FAIL: A mismatch! Got 0x" & to_hstring(debug_reg_A_tb) &
                       ", expected 0x" & to_hstring(expected_A)
                severity error;

            if check_flags then
                if expected_Z /= '-' then
                    assert debug_flags_tb(1) = expected_Z
                        report "FAIL: Zero flag mismatch! Got " & std_logic'image(debug_flags_tb(1)) &
                               ", expected " & std_logic'image(expected_Z)
                        severity error;
                end if;

                if expected_S /= '-' then
                    assert debug_flags_tb(2) = expected_S
                        report "FAIL: Sign flag mismatch! Got " & std_logic'image(debug_flags_tb(2)) &
                               ", expected " & std_logic'image(expected_S)
                        severity error;
                end if;

                if expected_P /= '-' then
                    assert debug_flags_tb(3) = expected_P
                        report "FAIL: Parity flag mismatch! Got " & std_logic'image(debug_flags_tb(3)) &
                               ", expected " & std_logic'image(expected_P)
                        severity error;
                end if;

                if expected_C /= '-' then
                    assert debug_flags_tb(0) = expected_C
                        report "FAIL: Carry flag mismatch! Got " & std_logic'image(debug_flags_tb(0)) &
                               ", expected " & std_logic'image(expected_C)
                        severity error;
                end if;
            end if;

            if debug_reg_A_tb = expected_A then
                if not check_flags or
                   ((expected_Z = '-' or debug_flags_tb(1) = expected_Z) and
                   (expected_S = '-' or debug_flags_tb(2) = expected_S) and
                   (expected_P = '-' or debug_flags_tb(3) = expected_P) and
                   (expected_C = '-' or debug_flags_tb(0) = expected_C)) then
                    report "  PASS";
                    pass_count := pass_count + 1;
                end if;
            end if;
        end procedure;

    begin
        report "========================================";
        report "Intel 8008 OR Operations Unit Test";
        report "========================================";

        -- Apply reset
        reset_tb <= '1';
        reset_n_tb <= '0';
        wait for 100 ns;

        -- Release reset
        reset_tb <= '0';
        reset_n_tb <= '1';
        report "Reset released, waiting for CPU to clear internal state...";

        -- Per Intel 8008 User's Manual: CPU enters STOPPED state on power-up
        -- Requires 16 clock periods to clear memories, then INT pulse to start
        wait for 2 us;  -- Wait for internal clearing (16 clocks @ ~2.2us/clock)

        -- Pulse interrupt to escape STOPPED state and begin execution
        int_tb <= '1';
        wait for 10 us;  -- Hold longer to ensure it's sampled
        int_tb <= '0';
        report "Interrupt pulse sent - starting OR tests";

        -- Test 1: Basic OR
        wait until debug_reg_C_tb = x"01";
        check_test(1, "OR Basic (0xF0 | 0x0F = 0xFF)", x"FF");

        -- Test 2: OR with Zero (Identity)
        wait until debug_reg_C_tb = x"02";
        check_test(2, "OR with Zero Identity (0xAA | 0x00 = 0xAA)", x"AA");

        -- Test 3: OR with 0xFF
        wait until debug_reg_C_tb = x"03";
        check_test(3, "OR with 0xFF (0x55 | 0xFF = 0xFF)", x"FF");

        -- Test 4: OR Self (Idempotent)
        wait until debug_reg_C_tb = x"04";
        check_test(4, "OR Self Idempotent (0x3C | 0x3C = 0x3C)", x"3C");

        -- Test 5: OR Setting Individual Bits
        wait until debug_reg_C_tb = x"05";
        check_test(5, "OR Individual Bits (0x01 | 0x02 = 0x03)", x"03");

        -- Test 6: OR Creating Bit Mask
        wait until debug_reg_C_tb = x"06";
        check_test(6, "OR Bit Mask (0x80 | 0x01 = 0x81)", x"81", true, '0', '1', '-', '-');

        -- Test 7: OR Zero Result
        wait until debug_reg_C_tb = x"07";
        check_test(7, "OR Zero Result (0x00 | 0x00 = 0x00)", x"00", true, '1', '0', '1', '-');

        -- Test 8: OR Sign Flag
        wait until debug_reg_C_tb = x"08";
        check_test(8, "OR Sign Flag (0x80 | 0x00 = 0x80)", x"80", true, '0', '1', '-', '-');

        -- Test 9: ORI Basic
        wait until debug_reg_C_tb = x"09";
        check_test(9, "ORI Basic (0x50 | 0x05 = 0x55)", x"55");

        -- Test 10: ORI with 0x00 (Identity)
        wait until debug_reg_C_tb = x"0A";
        check_test(10, "ORI with Zero Identity (0xCC | 0x00 = 0xCC)", x"CC");

        -- Test 11: ORI with 0xFF
        wait until debug_reg_C_tb = x"0B";
        check_test(11, "ORI with 0xFF (0x33 | 0xFF = 0xFF)", x"FF");

        -- Test 12: ORI Setting Low Nibble
        wait until debug_reg_C_tb = x"0C";
        check_test(12, "ORI Low Nibble (0xA0 | 0x0F = 0xAF)", x"AF");

        -- Test 13: ORI Setting High Nibble
        wait until debug_reg_C_tb = x"0D";
        check_test(13, "ORI High Nibble (0x0A | 0xF0 = 0xFA)", x"FA");

        -- Test 14: ORI Parity Odd
        wait until debug_reg_C_tb = x"0E";
        check_test(14, "ORI Parity Odd (0x00 | 0x07 = 0x07, 3 bits)", x"07", true, '0', '0', '0', '-');

        -- Test 15: ORI Parity Even
        wait until debug_reg_C_tb = x"0F";
        check_test(15, "ORI Parity Even (0x00 | 0x03 = 0x03, 2 bits)", x"03", true, '0', '0', '1', '-');

        -- Test 16: OR with All Registers
        wait until debug_reg_C_tb = x"10";
        check_test(16, "OR All Registers (0x10|0x01|0x02|0x04|0x08|0x20|0x40 = 0x7F)", x"7F");

        -- Test 17: OR Carry Flag Behavior
        wait until debug_reg_C_tb = x"11";
        check_test(17, "OR Clears Carry (0xAA | 0x55 = 0xFF, C=0)", x"FF", true, '0', '1', '1', '0');

        -- Test 18: OR Bit Combining
        wait until debug_reg_C_tb = x"12";
        check_test(18, "OR Bit Combining (0x18 | 0x24 = 0x3C)", x"3C");

        -- Wait for final marker
        wait until debug_reg_B_tb = x"FF";
        wait for 200 us;

        -- Verify STOPPED state
        assert S2_tb = '0' and S1_tb = '1' and S0_tb = '1'
            report "FAIL: CPU should be in STOPPED state after HLT"
            severity error;

        report "========================================";
        report "=== OR TEST RESULTS ===";
        report "  Tests run: " & integer'image(test_count);
        report "  Tests passed: " & integer'image(pass_count);
        if pass_count = test_count then
            report "  ALL OR TESTS PASSED (" & integer'image(pass_count) & "/" & integer'image(test_count) & ")";
        else
            report "  SOME TESTS FAILED (" & integer'image(pass_count) & "/" & integer'image(test_count) & ")";
        end if;
        report "========================================";

        wait;
    end process;

end behavior;

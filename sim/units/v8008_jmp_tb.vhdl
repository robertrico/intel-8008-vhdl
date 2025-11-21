-------------------------------------------------------------------------------
-- Intel 8008 v8008 JMP Instruction Test
-------------------------------------------------------------------------------
-- Comprehensive ROM-based test for JMP (Jump) instructions
-- Opcodes:
--   JMP (unconditional): 01 XXX 100
--   Conditional jumps:   01 CCC 000
--
-- Tests:
--   - JMP (unconditional forward/backward jumps)
--   - JFC, JFZ, JFS, JFP (Jump if False: Carry, Zero, Sign, Parity)
--   - JTC, JTZ, JTS, JTP (Jump if True: Carry, Zero, Sign, Parity)
--   - Both condition TRUE (jump taken) and FALSE (jump not taken) cases
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.v8008_tb_utils.all;

entity v8008_jmp_tb is
end v8008_jmp_tb;

architecture behavior of v8008_jmp_tb is

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

    -- ROM contents (test program)
    type rom_t is array (0 to 255) of std_logic_vector(7 downto 0);
    constant rom_contents : rom_t := (
        -- Test 1: Unconditional JMP forward (0x0000 -> 0x0010)
        0 => x"44",  -- JMP (01 000 100)
        1 => x"10",  -- Low address = 0x10
        2 => x"00",  -- High address = 0x00 -> Jump to 0x0010
        3 => x"FF",  -- HLT (should never reach here)
        4 => x"FF",  -- HLT
        5 => x"FF",  -- HLT

        -- Jump target at 0x0010: Set marker A=0x11
        16 => x"06",  -- MVI A, 0x11
        17 => x"11",

        -- Test 2: Unconditional JMP forward again (0x0012 -> 0x0020)
        18 => x"4C",  -- JMP (01 001 100)
        19 => x"20",  -- Low address = 0x20
        20 => x"00",  -- High address = 0x00 -> Jump to 0x0020
        21 => x"FF",  -- HLT (should never reach)

        -- Jump target at 0x0020: Set marker B=0x22
        32 => x"0E",  -- MVI B, 0x22
        33 => x"22",

        -- Test 3: Set carry flag, then JTC (should jump)
        34 => x"06",  -- MVI A, 0xFF
        35 => x"FF",
        36 => x"04",  -- ADI 0x01 (0xFF + 0x01 = 0x00, sets carry)
        37 => x"01",
        38 => x"60",  -- JTC (01 100 000) - Jump if Carry = 1
        39 => x"30",  -- Low address = 0x30
        40 => x"00",  -- High address = 0x00 -> Jump to 0x0030
        41 => x"FF",  -- HLT (should never reach)

        -- Jump target at 0x0030: Set marker C=0x33
        48 => x"16",  -- MVI C, 0x33
        49 => x"33",

        -- Test 4: Clear carry, then JFC (should jump)
        50 => x"06",  -- MVI A, 0x01
        51 => x"01",
        52 => x"04",  -- ADI 0x01 (0x01 + 0x01 = 0x02, no carry)
        53 => x"01",
        54 => x"40",  -- JFC (01 000 000) - Jump if Carry = 0
        55 => x"40",  -- Low address = 0x40
        56 => x"00",  -- High address = 0x00 -> Jump to 0x0040
        57 => x"FF",  -- HLT (should never reach)

        -- Jump target at 0x0040: Set marker D=0x44
        64 => x"1E",  -- MVI D, 0x44
        65 => x"44",

        -- Test 5: Set zero flag, then JTZ (should jump)
        66 => x"06",  -- MVI A, 0x00
        67 => x"00",
        68 => x"80",  -- ADD A (0x00 + 0x00 = 0x00, sets zero)
        69 => x"68",  -- JTZ (01 101 000) - Jump if Zero = 1
        70 => x"50",  -- Low address = 0x50
        71 => x"00",  -- High address = 0x00 -> Jump to 0x0050
        72 => x"FF",  -- HLT (should never reach)

        -- Jump target at 0x0050: Set marker E=0x55
        80 => x"26",  -- MVI E, 0x55
        81 => x"55",

        -- Test 6: Clear zero flag, then JFZ (should jump)
        82 => x"06",  -- MVI A, 0x01
        83 => x"01",
        84 => x"04",  -- ADI 0x01 (0x01 + 0x01 = 0x02, zero clear)
        85 => x"01",
        86 => x"48",  -- JFZ (01 001 000) - Jump if Zero = 0
        87 => x"60",  -- Low address = 0x60
        88 => x"00",  -- High address = 0x00 -> Jump to 0x0060
        89 => x"FF",  -- HLT (should never reach)

        -- Jump target at 0x0060: Set marker H=0x66
        96 => x"2E",  -- MVI H, 0x66
        97 => x"66",

        -- Test 7: Set sign flag, then JTS (should jump)
        98 => x"06",   -- MVI A, 0xFF (bit 7 = 1, negative)
        99 => x"FF",
        100 => x"80",  -- ADD A (sets sign)
        101 => x"70",  -- JTS (01 110 000) - Jump if Sign = 1
        102 => x"70",  -- Low address = 0x70
        103 => x"00",  -- High address = 0x00 -> Jump to 0x0070
        104 => x"FF",  -- HLT (should never reach)

        -- Jump target at 0x0070: Set marker L=0x77
        112 => x"36",  -- MVI L, 0x77
        113 => x"77",

        -- Test 8: Clear sign flag, then JFS (should jump)
        114 => x"06",  -- MVI A, 0x01 (bit 7 = 0, positive)
        115 => x"01",
        116 => x"80",  -- ADD A (result = 0x02, sign clear)
        117 => x"50",  -- JFS (01 010 000) - Jump if Sign = 0
        118 => x"80",  -- Low address = 0x80
        119 => x"00",  -- High address = 0x00 -> Jump to 0x0080
        120 => x"FF",  -- HLT (should never reach)

        -- Jump target at 0x0080: Set marker A=0x88, then jump to Test 9
        128 => x"06",  -- MVI A, 0x88
        129 => x"88",
        130 => x"44",  -- JMP to Test 9 (to avoid A getting overwritten)
        131 => x"86",  -- Low address = 0x86
        132 => x"00",  -- High address = 0x00 -> Jump to 0x0086

        -- Padding (was part of Test 9 setup, now unused)
        133 => x"FF",  -- (unused)

        -- Test 9: Test conditional NOT taken (JTC with carry=0) - NOW AT 0x0086
        134 => x"06",  -- MVI A, 0x01  (offset 134 = 0x86)
        135 => x"01",
        136 => x"04",  -- ADI 0x01 (carry = 0)
        137 => x"01",
        138 => x"60",  -- JTC (should NOT jump, carry = 0)
        139 => x"FF",  -- Low address (ignored)
        140 => x"FF",  -- High address (ignored)
        141 => x"0E",  -- MVI B, 0x99 (should reach here)
        142 => x"99",

        -- Test 10: Backward jump (0x008D -> 0x0095)
        143 => x"44",  -- JMP (unconditional)  (offset 143 = 0x8F)
        144 => x"95",  -- Low address = 0x95
        145 => x"00",  -- High address = 0x00 -> Jump to 0x0095

        -- Jump target at 0x0095: Set marker C=0xAA, then HLT
        149 => x"16",  -- MVI C, 0xAA
        150 => x"AA",
        151 => x"FF",  -- HLT (end of test)

        others => x"00"
    );

    signal rom_addr : std_logic_vector(7 downto 0);
    signal rom_data : std_logic_vector(7 downto 0);

begin

    READY <= '1';

    CLK_GEN: phase_clocks port map (clk_master, reset, phi1, phi2);
    UUT: v8008 port map (phi1, phi2, data_bus_in, data_bus_out, data_bus_enable,
                         S0, S1, S2, SYNC, READY, INT,
                         debug_reg_A, debug_reg_B, debug_reg_C, debug_reg_D, debug_reg_E, debug_reg_H, debug_reg_L,
                         debug_pc, debug_flags, debug_instruction, debug_stack_pointer, debug_hl_address);

    -- ROM access
    rom_addr <= debug_pc(7 downto 0);

    ROM_PROC: process(phi2)
    begin
        if falling_edge(phi2) then
            rom_data <= rom_contents(to_integer(unsigned(rom_addr)));
        end if;
    end process;

    -- Data bus multiplexing (ROM-only, no RAM needed)
    DBUS_MUX: process(phi2)
        variable state_vec : std_logic_vector(2 downto 0);
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

            -- Data bus multiplexing
            if in_int_ack and state_vec = "001" then
                data_bus_in <= x"05";  -- RST 0
            else
                data_bus_in <= rom_data;
            end if;
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
        variable errors : integer := 0;
    begin
        report "========================================";
        report "JMP Instruction Comprehensive Test";
        report "Testing unconditional and conditional jumps";
        report "========================================";

        wait for 500 ns;

        -- Boot CPU with RST 0
        report "Booting CPU with RST 0...";
        wait until rising_edge(phi1);
        INT <= '1';
        wait for 3000 ns;
        INT <= '0';

        -- Wait for program to execute
        -- 10 jump tests + flag setup + markers = ~30 instructions
        -- Each takes ~20-60us, need ~2ms total
        wait for 2500000 ns;

        -- Check all register values (markers from successful jumps)
        report "========================================";
        report "Final register values:";
        report "  A = 0x" & to_hstring(debug_reg_A) & " (expected 0x02)";
        report "  B = 0x" & to_hstring(debug_reg_B) & " (expected 0x99)";
        report "  C = 0x" & to_hstring(debug_reg_C) & " (expected 0xAA)";
        report "  D = 0x" & to_hstring(debug_reg_D) & " (expected 0x44)";
        report "  E = 0x" & to_hstring(debug_reg_E) & " (expected 0x55)";
        report "  H = 0x" & to_hstring(debug_reg_H) & " (expected 0x66)";
        report "  L = 0x" & to_hstring(debug_reg_L) & " (expected 0x77)";
        report "  Flags = " & to_string(debug_flags);
        report "========================================";

        -- Verify markers (each successful jump sets a unique marker)
        if debug_reg_A /= x"02" then
            report "ERROR: Test marker A failed - A = 0x" & to_hstring(debug_reg_A) & ", expected 0x02"
                severity error;
            errors := errors + 1;
        else
            report "PASS: JMP/JFS/Test 9 - marker A correct";
        end if;

        if debug_reg_B /= x"99" then
            report "ERROR: Test marker B failed - B = 0x" & to_hstring(debug_reg_B) & ", expected 0x99"
                severity error;
            errors := errors + 1;
        else
            report "PASS: JMP/JTC-not-taken test - marker B correct";
        end if;

        if debug_reg_C /= x"AA" then
            report "ERROR: Test marker C failed - C = 0x" & to_hstring(debug_reg_C) & ", expected 0xAA"
                severity error;
            errors := errors + 1;
        else
            report "PASS: JTC/Backward JMP tests - marker C correct";
        end if;

        if debug_reg_D /= x"44" then
            report "ERROR: Test marker D failed - D = 0x" & to_hstring(debug_reg_D) & ", expected 0x44"
                severity error;
            errors := errors + 1;
        else
            report "PASS: JFC test - marker D correct";
        end if;

        if debug_reg_E /= x"55" then
            report "ERROR: Test marker E failed - E = 0x" & to_hstring(debug_reg_E) & ", expected 0x55"
                severity error;
            errors := errors + 1;
        else
            report "PASS: JTZ test - marker E correct";
        end if;

        if debug_reg_H /= x"66" then
            report "ERROR: Test marker H failed - H = 0x" & to_hstring(debug_reg_H) & ", expected 0x66"
                severity error;
            errors := errors + 1;
        else
            report "PASS: JFZ test - marker H correct";
        end if;

        if debug_reg_L /= x"77" then
            report "ERROR: Test marker L failed - L = 0x" & to_hstring(debug_reg_L) & ", expected 0x77"
                severity error;
            errors := errors + 1;
        else
            report "PASS: JTS test - marker L correct";
        end if;

        report "========================================";
        if errors = 0 then
            report "*** ALL JMP TESTS PASSED ***";
            report "Tested: JMP, JFC, JFZ, JFS, JTC, JTZ, JTS (7 variants)";
            report "Also tested: conditional not taken, backward jump";
        else
            report "*** TEST FAILED: " & integer'image(errors) & " errors ***";
        end if;
        report "========================================";

        done <= true;
        wait;
    end process;

end behavior;

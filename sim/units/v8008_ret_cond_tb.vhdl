-------------------------------------------------------------------------------
-- Intel 8008 v8008 Conditional RET Instruction Test
-------------------------------------------------------------------------------
-- Test for RFc (Return if False) and RTc (Return if True) instructions
-- RFc opcodes: 00 0CC 011 (0x03, 0x0B, 0x13, 0x1B - return if condition false)
-- RTc opcodes: 00 1CC 011 (0x23, 0x2B, 0x33, 0x3B - return if condition true)
--
-- Tests:
--   - RFC (Return if Carry=0): Should return when carry flag = 0
--   - RFC (Return if Carry=0): Should NOT return when carry flag = 1
--   - RTC (Return if Carry=1): Should return when carry flag = 1
--   - RTC (Return if Carry=1): Should NOT return when carry flag = 0
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.v8008_tb_utils.all;

entity v8008_ret_cond_tb is
end v8008_ret_cond_tb;

architecture behavior of v8008_ret_cond_tb is

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

    signal clk_master, reset, phi1, phi2, INT : std_logic := '0';
    signal READY : std_logic := '1';
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

    -- ROM contents
    type rom_array_t is array (0 to 255) of std_logic_vector(7 downto 0);
    signal rom_contents : rom_array_t := (
        -- Test 1: CALL to subroutine with RFC (Return if Carry=0)
        -- Carry should be clear, so RFC should return
        0 => x"0E",  -- MVI B, 0x11  (marker before CALL, also clears carry)
        1 => x"11",
        2 => x"46",  -- CALL (01 000 110 = 0x46)
        3 => x"20",  -- Low address = 0x20
        4 => x"00",  -- High address = 0x00 -> Call to 0x0020
        -- After RFC returns, PC should return to 0x0005
        5 => x"16",  -- MVI C, 0x22  (marker after return from first subroutine)
        6 => x"22",

        -- Test 2: Set carry flag, CALL to subroutine with RFC
        -- Carry=1, so RFC should NOT return (fall through to next instruction)
        7 => x"1E",  -- MVI D, 0x33  (marker before setting carry)
        8 => x"33",
        9 => x"04",  -- ADI 0xFF - Add 255 to set carry flag
        10 => x"FF",
        11 => x"46",  -- CALL (01 000 110 = 0x46)
        12 => x"30",  -- Low address = 0x30
        13 => x"00",  -- High address = 0x00 -> Call to 0x0030
        -- After falling through RFC, execution continues in subroutine
        14 => x"26",  -- MVI E, 0x44  (marker after call to subroutine that doesn't return)
        15 => x"44",

        -- Test 3: CALL to subroutine with RTC (Return if Carry=1)
        -- Carry should still be set from previous ADI, so RTC should return
        16 => x"46",  -- CALL (01 000 110 = 0x46)
        17 => x"40",  -- Low address = 0x40
        18 => x"00",  -- High address = 0x00 -> Call to 0x0040
        -- After RTC returns, PC should return to 0x0013
        19 => x"2E",  -- MVI H, 0x55  (marker after return from third subroutine)
        20 => x"55",
        21 => x"FF",  -- HLT

        -- Subroutine at 0x0020 (with RFC - should return since carry=0)
        32 => x"06",  -- MVI A, 0xAA  (marker in first subroutine)
        33 => x"AA",
        34 => x"03",  -- RFC (00 000 011 = 0x03) - Return if Carry=0
        35 => x"FF",  -- HLT (should not reach - RFC should return)

        -- Subroutine at 0x0030 (with RFC - should NOT return since carry=1)
        48 => x"0E",  -- MVI B, 0xBB  (marker in second subroutine)
        49 => x"BB",
        50 => x"03",  -- RFC (00 000 011 = 0x03) - Return if Carry=0 (won't return)
        51 => x"36",  -- MVI L, 0xCC  (should execute since RFC doesn't return)
        52 => x"CC",
        53 => x"07",  -- RET (unconditional return)
        54 => x"FF",  -- HLT (should not reach)

        -- Subroutine at 0x0040 (with RTC - should return since carry=1)
        64 => x"1E",  -- MVI D, 0xDD  (marker in third subroutine)
        65 => x"DD",
        66 => x"23",  -- RTC (00 100 011 = 0x23) - Return if Carry=1
        67 => x"FF",  -- HLT (should not reach - RTC should return)

        -- Padding
        others => x"00"
    );

    signal rom_data : std_logic_vector(7 downto 0);

begin

    CLK_GEN: phase_clocks
        port map (
            clk_in => clk_master,
            reset => reset,
            phi1 => phi1,
            phi2 => phi2
        );

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

    -- ROM process
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

    -- Master clock
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
        report "Intel 8008 Conditional RET Test";
        report "Testing RFc (Return if False) and RTc (Return if True)";
        report "========================================";

        -- Reset
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
        report "Executing conditional RET test program:";
        report "  1. MVI B, 0x11 (marker before CALL, clears carry)";
        report "  2. CALL 0x0020 (subroutine with RFC)";
        report "  3. Subroutine: MVI A, 0xAA";
        report "  4. RFC (carry=0, should return to 0x0005)";
        report "  5. MVI C, 0x22 (should execute after RFC)";
        report "  6. MVI D, 0x33";
        report "  7. ADI 0xFF (sets carry)";
        report "  8. CALL 0x0030 (subroutine with RFC)";
        report "  9. Subroutine: MVI B, 0xBB";
        report " 10. RFC (carry=1, should NOT return, fall through)";
        report " 11. MVI L, 0xCC (should execute since RFC didn't return)";
        report " 12. RET (unconditional return to 0x000E)";
        report " 13. MVI E, 0x44";
        report " 14. CALL 0x0040 (subroutine with RTC)";
        report " 15. Subroutine: MVI D, 0xDD";
        report " 16. RTC (carry=1, should return to 0x0013)";
        report " 17. MVI H, 0x55";

        -- Wait for execution
        wait for 3500 us;

        -- Verify results
        report "";
        report "========================================";
        report "Verifying Results:";
        report "========================================";

        -- Check that A was set by first subroutine (RFC returned)
        -- Then modified by ADI 0xFF: 0xAA + 0xFF = 0x1A9 -> 0xA9
        report "Register A: 0x" & to_hstring(debug_reg_A) & " (expected 0xA9)";
        if debug_reg_A /= x"A9" then
            report "ERROR: Register A mismatch" severity warning;
            errors := errors + 1;
        else
            report "  PASS: Register A correct (0xAA from RFC subroutine, modified by ADI to 0xA9)";
        end if;

        -- Check that B was overwritten in second subroutine (RFC didn't return)
        report "Register B: 0x" & to_hstring(debug_reg_B) & " (expected 0xBB)";
        if debug_reg_B /= x"BB" then
            report "ERROR: Register B mismatch" severity warning;
            errors := errors + 1;
        else
            report "  PASS: Register B correct (overwritten in second subroutine)";
        end if;

        -- Check that C was set after first RFC returned
        report "Register C: 0x" & to_hstring(debug_reg_C) & " (expected 0x22)";
        if debug_reg_C /= x"22" then
            report "ERROR: Register C mismatch" severity warning;
            errors := errors + 1;
        else
            report "  PASS: Register C correct (RFC returned, code after CALL executed)";
        end if;

        -- Check that D was overwritten in third subroutine
        report "Register D: 0x" & to_hstring(debug_reg_D) & " (expected 0xDD)";
        if debug_reg_D /= x"DD" then
            report "ERROR: Register D mismatch" severity warning;
            errors := errors + 1;
        else
            report "  PASS: Register D correct (set in third subroutine before RTC)";
        end if;

        -- Check that E was set after second subroutine returned
        report "Register E: 0x" & to_hstring(debug_reg_E) & " (expected 0x44)";
        if debug_reg_E /= x"44" then
            report "ERROR: Register E mismatch" severity warning;
            errors := errors + 1;
        else
            report "  PASS: Register E correct (set after second subroutine returned)";
        end if;

        -- Check that L was set in second subroutine (RFC didn't return)
        report "Register L: 0x" & to_hstring(debug_reg_L) & " (expected 0xCC)";
        if debug_reg_L /= x"CC" then
            report "ERROR: Register L mismatch - RFC incorrectly returned" severity warning;
            errors := errors + 1;
        else
            report "  PASS: Register L correct (second RFC did not return)";
        end if;

        -- Check that H was set after third subroutine (RTC returned)
        report "Register H: 0x" & to_hstring(debug_reg_H) & " (expected 0x55)";
        if debug_reg_H /= x"55" then
            report "ERROR: Register H mismatch - RTC did not return" severity warning;
            errors := errors + 1;
        else
            report "  PASS: Register H correct (RTC returned)";
        end if;

        -- Check stack pointer (should be back to 0 after all calls/returns)
        report "Stack Pointer: " & integer'image(to_integer(unsigned(debug_stack_pointer))) & " (expected 0)";
        if debug_stack_pointer /= "000" then
            report "ERROR: Stack pointer mismatch" severity warning;
            errors := errors + 1;
        else
            report "  PASS: Stack pointer correct";
        end if;

        -- Test summary
        report "";
        report "========================================";
        if errors = 0 then
            report "*** ALL CONDITIONAL RET TESTS PASSED ***";
            report "  - RFC with carry=0: PASS (returned)";
            report "  - RFC with carry=1: PASS (not returned)";
            report "  - RTC with carry=1: PASS (returned)";
            report "  - Stack management: PASS";
        else
            report "*** TESTS FAILED: " & integer'image(errors) & " errors ***" severity error;
        end if;
        report "========================================";

        done <= true;
        wait;
    end process TEST_PROC;

end behavior;

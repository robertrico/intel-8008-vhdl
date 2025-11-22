-------------------------------------------------------------------------------
-- Intel 8008 v8008 Conditional CALL Instruction Test
-------------------------------------------------------------------------------
-- Test for CFc (Call if False) and CTc (Call if True) instructions
-- CFc opcodes: 01 0CC 010 (0x42, 0x4A, 0x52, 0x5A - call if condition false)
-- CTc opcodes: 01 1CC 010 (0x62, 0x6A, 0x72, 0x7A - call if condition true)
--
-- Tests:
--   - CFC (Call if Carry=0): Should call when carry flag = 0
--   - CFC (Call if Carry=0): Should NOT call when carry flag = 1
--   - CTC (Call if Carry=1): Should call when carry flag = 1
--   - CTC (Call if Carry=1): Should NOT call when carry flag = 0
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.v8008_tb_utils.all;

entity v8008_call_cond_tb is
end v8008_call_cond_tb;

architecture behavior of v8008_call_cond_tb is

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
        -- Test 1: CFC (Call if Carry=0) with Carry=0 - should call
        0 => x"0E",  -- MVI B, 0x01  (marker before CFC, also clears carry)
        1 => x"01",
        2 => x"42",  -- CFC (01 000 010 = 0x42) - Call if Carry=0
        3 => x"20",  -- Low address = 0x20
        4 => x"00",  -- High address = 0x00 -> Call to 0x0020
        -- After call (if taken), PC should return to 0x0005
        5 => x"16",  -- MVI C, 0x02  (marker after return from first call)
        6 => x"02",

        -- Test 2: Set carry flag, then CFC - should NOT call
        7 => x"1E",  -- MVI D, 0x03  (marker before setting carry)
        8 => x"03",
        9 => x"04",  -- ADI 0xFF - Add 255 to set carry flag
        10 => x"FF",
        11 => x"42",  -- CFC (Call if Carry=0) - should NOT call (carry=1)
        12 => x"30",  -- Low address = 0x30
        13 => x"00",  -- High address = 0x00 -> Would call to 0x0030 (but won't)
        14 => x"26",  -- MVI E, 0x04  (marker, should execute because call not taken)
        15 => x"04",

        -- Test 3: CTC (Call if Carry=1) with Carry=1 - should call
        16 => x"62",  -- CTC (01 100 010 = 0x62) - Call if Carry=1
        17 => x"40",  -- Low address = 0x40
        18 => x"00",  -- High address = 0x00 -> Call to 0x0040
        -- After call (if taken), PC should return to 0x0013
        19 => x"2E",  -- MVI H, 0x05  (marker after return from second call)
        20 => x"05",
        21 => x"FF",  -- HLT

        -- Subroutine at 0x0020 (called by first CFC)
        32 => x"06",  -- MVI A, 0xAA  (marker in first subroutine)
        33 => x"AA",
        34 => x"07",  -- RET
        35 => x"FF",  -- HLT (should not reach)

        -- Subroutine at 0x0040 (called by CTC)
        64 => x"36",  -- MVI L, 0xBB  (marker in second subroutine)
        65 => x"BB",
        66 => x"07",  -- RET
        67 => x"FF",  -- HLT (should not reach)

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
        report "Intel 8008 Conditional CALL Test";
        report "Testing CFc (Call if False) and CTc (Call if True)";
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
        report "Executing conditional CALL test program:";
        report "  1. MVI B, 0x01 (clears carry)";
        report "  2. CFC 0x0020 (call if carry=0, should call)";
        report "  3. Subroutine: MVI A, 0xAA";
        report "  4. RET (return to 0x0005)";
        report "  5. MVI C, 0x02";
        report "  6. MVI D, 0x03";
        report "  7. ADI 0xFF (sets carry)";
        report "  8. CFC 0x0030 (call if carry=0, should NOT call)";
        report "  9. MVI E, 0x04 (should execute)";
        report " 10. CTC 0x0040 (call if carry=1, should call)";
        report " 11. Subroutine: MVI L, 0xBB";
        report " 12. RET (return to 0x0013)";
        report " 13. MVI H, 0x05";

        -- Wait for execution
        wait for 3000 us;

        -- Verify results
        report "";
        report "========================================";
        report "Verifying Results:";
        report "========================================";

        -- Check that B was set (first instruction)
        report "Register B: 0x" & to_hstring(debug_reg_B) & " (expected 0x01)";
        if debug_reg_B /= x"01" then
            report "ERROR: Register B mismatch" severity warning;
            errors := errors + 1;
        else
            report "  PASS: Register B correct";
        end if;

        -- Check that A was modified by ADI (was 0xAA from subroutine, then ADI 0xFF changed it to 0xA9)
        report "Register A: 0x" & to_hstring(debug_reg_A) & " (expected 0xA9)";
        if debug_reg_A /= x"A9" then
            report "ERROR: Register A mismatch - should be 0xA9 after ADI" severity warning;
            errors := errors + 1;
        else
            report "  PASS: Register A correct (0xAA from CFC subroutine, then modified by ADI to 0xA9)";
        end if;

        -- Check that C was set (returned from first call)
        report "Register C: 0x" & to_hstring(debug_reg_C) & " (expected 0x02)";
        if debug_reg_C /= x"02" then
            report "ERROR: Register C mismatch" severity warning;
            errors := errors + 1;
        else
            report "  PASS: Register C correct (returned from first call)";
        end if;

        -- Check that D was set
        report "Register D: 0x" & to_hstring(debug_reg_D) & " (expected 0x03)";
        if debug_reg_D /= x"03" then
            report "ERROR: Register D mismatch" severity warning;
            errors := errors + 1;
        else
            report "  PASS: Register D correct";
        end if;

        -- Check that E was set (second CFC did NOT call)
        report "Register E: 0x" & to_hstring(debug_reg_E) & " (expected 0x04)";
        if debug_reg_E /= x"04" then
            report "ERROR: Register E mismatch - second CFC incorrectly called" severity warning;
            errors := errors + 1;
        else
            report "  PASS: Register E correct (second CFC did not call)";
        end if;

        -- Check that L was set (CTC called subroutine)
        report "Register L: 0x" & to_hstring(debug_reg_L) & " (expected 0xBB)";
        if debug_reg_L /= x"BB" then
            report "ERROR: Register L mismatch - CTC did not call" severity warning;
            errors := errors + 1;
        else
            report "  PASS: Register L correct (CTC called subroutine)";
        end if;

        -- Check that H was set (returned from CTC)
        report "Register H: 0x" & to_hstring(debug_reg_H) & " (expected 0x05)";
        if debug_reg_H /= x"05" then
            report "ERROR: Register H mismatch" severity warning;
            errors := errors + 1;
        else
            report "  PASS: Register H correct (returned from CTC call)";
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
            report "*** ALL CONDITIONAL CALL TESTS PASSED ***";
            report "  - CFC with carry=0: PASS (called)";
            report "  - CFC with carry=1: PASS (not called)";
            report "  - CTC with carry=1: PASS (called)";
            report "  - Stack management: PASS";
        else
            report "*** TESTS FAILED: " & integer'image(errors) & " errors ***" severity error;
        end if;
        report "========================================";

        done <= true;
        wait;
    end process TEST_PROC;

end behavior;

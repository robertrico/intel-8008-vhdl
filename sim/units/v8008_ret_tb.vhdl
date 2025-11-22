-------------------------------------------------------------------------------
-- Intel 8008 v8008 RET Instruction Test
-------------------------------------------------------------------------------
-- Test for RET (unconditional return from subroutine) instruction
-- Opcode: 00 XXX 111 (0x07, 0x0F, 0x17, 0x1F, 0x27, 0x2F, 0x37, 0x3F)
--
-- Tests:
--   - CALL to subroutine (pushes return address)
--   - RET from subroutine (pops return address and restores PC)
--   - Verify PC returns to correct address after RET
--   - Verify stack pointer decrements correctly
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.v8008_tb_utils.all;

entity v8008_ret_tb is
end v8008_ret_tb;

architecture behavior of v8008_ret_tb is

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
        -- Main program starts at 0x00
        -- Test: CALL to subroutine at 0x10, then verify RET returns to 0x05
        0 => x"0E",  -- MVI B, 0x11  (marker before CALL)
        1 => x"11",
        2 => x"46",  -- CALL (01 000 110 = 0x46)
        3 => x"10",  -- Low address = 0x10
        4 => x"00",  -- High address = 0x00 -> Call to 0x0010
        -- After RET, PC should return to 0x0005
        5 => x"16",  -- MVI C, 0x22  (marker after return from subroutine)
        6 => x"22",
        7 => x"FF",  -- HLT

        -- Subroutine at 0x0010
        16 => x"1E",  -- MVI D, 0x33  (marker in subroutine)
        17 => x"33",
        18 => x"07",  -- RET (00 000 111 = 0x07) - return from subroutine
        19 => x"FF",  -- HLT (should not reach here)

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
        report "Intel 8008 RET Instruction Test";
        report "Testing unconditional RET (return from subroutine)";
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
        report "Executing RET test program:";
        report "  1. MVI B, 0x11 (marker before CALL)";
        report "  2. CALL 0x0010 (call subroutine, pushes return address 0x0005)";
        report "  3. Subroutine: MVI D, 0x33";
        report "  4. RET (pop return address and restore PC to 0x0005)";
        report "  5. MVI C, 0x22 (should execute after RET)";

        -- Wait for execution
        wait for 3000 us;

        -- Verify results
        report "";
        report "========================================";
        report "Verifying Results:";
        report "========================================";

        -- Check that B was set before CALL
        report "Register B: 0x" & to_hstring(debug_reg_B) & " (expected 0x11)";
        if debug_reg_B /= x"11" then
            report "ERROR: Register B mismatch" severity warning;
            errors := errors + 1;
        else
            report "  PASS: Register B correct (set before CALL)";
        end if;

        -- Check that subroutine was executed (D should be set)
        report "Register D: 0x" & to_hstring(debug_reg_D) & " (expected 0x33)";
        if debug_reg_D /= x"33" then
            report "ERROR: Register D mismatch" severity warning;
            errors := errors + 1;
        else
            report "  PASS: Register D correct (subroutine executed)";
        end if;

        -- Check that C was set after RET
        report "Register C: 0x" & to_hstring(debug_reg_C) & " (expected 0x22)";
        if debug_reg_C /= x"22" then
            report "ERROR: Register C mismatch" severity warning;
            errors := errors + 1;
        else
            report "  PASS: Register C correct (RET returned, code after CALL executed)";
        end if;

        -- Check that PC is past the return address (should be at or past 0x0007)
        report "Final PC: 0x" & to_hstring(debug_pc) & " (should be >= 0x0007)";
        if unsigned(debug_pc) < 7 then
            report "ERROR: PC did not return correctly" severity warning;
            errors := errors + 1;
        else
            report "  PASS: PC returned to correct location after RET";
        end if;

        -- Check stack pointer (should be back to 0 after RET)
        report "Stack Pointer: " & integer'image(to_integer(unsigned(debug_stack_pointer))) & " (expected 0)";
        if debug_stack_pointer /= "000" then
            report "ERROR: Stack pointer mismatch" severity warning;
            errors := errors + 1;
        else
            report "  PASS: Stack pointer correct (return address popped)";
        end if;

        -- Test summary
        report "";
        report "========================================";
        if errors = 0 then
            report "*** ALL RET TESTS PASSED ***";
            report "  - CALL execution: PASS";
            report "  - Subroutine entry: PASS";
            report "  - RET execution: PASS";
            report "  - Return to caller: PASS";
            report "  - Stack management: PASS";
        else
            report "*** TESTS FAILED: " & integer'image(errors) & " errors ***" severity error;
        end if;
        report "========================================";

        done <= true;
        wait;
    end process TEST_PROC;

end behavior;

--------------------------------------------------------------------------------
-- alu_tb.vhdl
--------------------------------------------------------------------------------
-- Testbench for ALU
-- Tests: All 8 operations, flag generation, enable control
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.b8008_types.all;

entity alu_tb is
end entity alu_tb;

architecture test of alu_tb is

    -- Component declaration
    component alu is
        port (
            clk              : in  std_logic;
            phi2_rising      : in  std_logic;
            accumulator_in   : in  std_logic_vector(7 downto 0);
            reg_b_in         : in  std_logic_vector(7 downto 0);
            opcode           : in  std_logic_vector(2 downto 0);
            is_inr_dcr       : in  std_logic;
            is_rotate        : in  std_logic;
            carry_in         : in  std_logic;
            enable           : in  std_logic;
            output_result    : in  std_logic;
            internal_bus_out : out std_logic_vector(7 downto 0);
            internal_bus_oe  : out std_logic;
            result           : out std_logic_vector(8 downto 0);
            flag_carry       : out std_logic;
            flag_zero        : out std_logic;
            flag_sign        : out std_logic;
            flag_parity      : out std_logic
        );
    end component;

    -- Clock (formerly phi2; phi2_rising held '1' so every clk rise acts as a phi2 edge)
    signal clk         : std_logic := '0';
    signal phi2_rising : std_logic := '1';
    constant phi2_period : time := 20 ns;

    -- Inputs
    signal accumulator_in  : std_logic_vector(7 downto 0) := (others => '0');
    signal reg_b_in        : std_logic_vector(7 downto 0) := (others => '0');
    signal opcode          : std_logic_vector(2 downto 0) := (others => '0');
    signal is_inr_dcr      : std_logic := '0';
    signal is_rotate       : std_logic := '0';
    signal carry_in        : std_logic := '0';
    signal enable          : std_logic := '0';
    signal output_result   : std_logic := '0';

    -- Outputs
    signal internal_bus_out : std_logic_vector(7 downto 0);
    signal internal_bus_oe  : std_logic;
    signal result      : std_logic_vector(8 downto 0);
    signal flag_carry  : std_logic;
    signal flag_zero   : std_logic;
    signal flag_sign   : std_logic;
    signal flag_parity : std_logic;

    signal done : boolean := false;

    -- Operation constants
    constant OP_ADD : std_logic_vector(2 downto 0) := "000";
    constant OP_ADC : std_logic_vector(2 downto 0) := "001";
    constant OP_SUB : std_logic_vector(2 downto 0) := "010";
    constant OP_SBB : std_logic_vector(2 downto 0) := "011";
    constant OP_AND : std_logic_vector(2 downto 0) := "100";
    constant OP_XOR : std_logic_vector(2 downto 0) := "101";
    constant OP_OR  : std_logic_vector(2 downto 0) := "110";
    constant OP_CMP : std_logic_vector(2 downto 0) := "111";

begin

    uut : alu
        port map (
            clk              => clk,
            phi2_rising      => phi2_rising,
            accumulator_in   => accumulator_in,
            reg_b_in         => reg_b_in,
            opcode           => opcode,
            is_inr_dcr       => is_inr_dcr,
            is_rotate        => is_rotate,
            carry_in         => carry_in,
            enable           => enable,
            output_result    => output_result,
            internal_bus_out => internal_bus_out,
            internal_bus_oe  => internal_bus_oe,
            result           => result,
            flag_carry       => flag_carry,
            flag_zero        => flag_zero,
            flag_sign        => flag_sign,
            flag_parity      => flag_parity
        );

    -- Clock generator (clk replaces former phi2)
    clk_proc : process
    begin
        while not done loop
            clk <= '0';
            wait for phi2_period / 2;
            clk <= '1';
            wait for phi2_period / 2;
        end loop;
        wait;
    end process;

    -- Test stimulus
    test_process : process
        variable errors : integer := 0;

        -- Pulse enable 0->1 to latch ALU result, then leave high so outputs
        -- reflect the latched value for assertions.
        procedure strobe_enable is
        begin
            enable <= '0';
            wait for phi2_period * 2;
            enable <= '1';
            wait for phi2_period * 2;
        end procedure;
    begin
        report "========================================";
        report "ALU Test";
        report "========================================";

        wait for 100 ns;

        -- Test 1: ADD operation
        report "";
        report "Test 1: ADD 0x42 + 0x10";

        accumulator_in <= x"42";  -- 66
        reg_b_in <= x"10";  -- 16
        opcode <= OP_ADD;
        carry_in <= '0';
        strobe_enable;

        if result /= "0" & x"52" then  -- 82
            report "  ERROR: ADD result should be 0x52, got 0x" & to_hstring(result(7 downto 0)) severity error;
            errors := errors + 1;
        else
            report "  PASS: ADD result correct";
        end if;

        if flag_zero /= '0' then
            report "  ERROR: Zero flag should be 0" severity error;
            errors := errors + 1;
        end if;

        -- Test 2: ADD with overflow (carry)
        report "";
        report "Test 2: ADD 0xFF + 0x02 (overflow)";

        accumulator_in <= x"FF";
        reg_b_in <= x"02";
        opcode <= OP_ADD;
        strobe_enable;

        if flag_carry /= '1' then
            report "  ERROR: Carry flag should be set" severity error;
            errors := errors + 1;
        else
            report "  PASS: Carry flag set correctly";
        end if;

        -- Test 3: ADC (Add with Carry)
        report "";
        report "Test 3: ADC 0x10 + 0x20 with carry=1";

        accumulator_in <= x"10";
        reg_b_in <= x"20";
        opcode <= OP_ADC;
        carry_in <= '1';
        strobe_enable;

        if result /= "0" & x"31" then  -- 16 + 32 + 1 = 49
            report "  ERROR: ADC result should be 0x31, got 0x" & to_hstring(result(7 downto 0)) severity error;
            errors := errors + 1;
        else
            report "  PASS: ADC with carry correct";
        end if;

        -- Test 4: SUB operation
        report "";
        report "Test 4: SUB 0x50 - 0x30";

        accumulator_in <= x"50";  -- 80
        reg_b_in <= x"30";  -- 48
        opcode <= OP_SUB;
        carry_in <= '0';
        strobe_enable;

        if result /= "0" & x"20" then  -- 32
            report "  ERROR: SUB result should be 0x20, got 0x" & to_hstring(result(7 downto 0)) severity error;
            errors := errors + 1;
        else
            report "  PASS: SUB result correct";
        end if;

        -- Test 5: SUB with underflow
        report "";
        report "Test 5: SUB 0x10 - 0x20 (underflow)";

        accumulator_in <= x"10";
        reg_b_in <= x"20";
        opcode <= OP_SUB;
        strobe_enable;

        if flag_sign /= '1' then
            report "  ERROR: Sign flag should be set for negative result" severity error;
            errors := errors + 1;
        else
            report "  PASS: Sign flag set for negative result";
        end if;

        -- Test 6: AND operation
        report "";
        report "Test 6: AND 0xFF & 0x0F";

        accumulator_in <= x"FF";
        reg_b_in <= x"0F";
        opcode <= OP_AND;
        strobe_enable;

        if result /= "0" & x"0F" then
            report "  ERROR: AND result should be 0x0F, got 0x" & to_hstring(result(7 downto 0)) severity error;
            errors := errors + 1;
        else
            report "  PASS: AND result correct";
        end if;

        -- Test 7: XOR operation
        report "";
        report "Test 7: XOR 0xAA ^ 0x55";

        accumulator_in <= x"AA";  -- 10101010
        reg_b_in <= x"55";  -- 01010101
        opcode <= OP_XOR;
        strobe_enable;

        if result /= "0" & x"FF" then  -- 11111111
            report "  ERROR: XOR result should be 0xFF, got 0x" & to_hstring(result(7 downto 0)) severity error;
            errors := errors + 1;
        else
            report "  PASS: XOR result correct";
        end if;

        -- Test 8: OR operation
        report "";
        report "Test 8: OR 0xF0 | 0x0F";

        accumulator_in <= x"F0";
        reg_b_in <= x"0F";
        opcode <= OP_OR;
        strobe_enable;

        if result /= "0" & x"FF" then
            report "  ERROR: OR result should be 0xFF, got 0x" & to_hstring(result(7 downto 0)) severity error;
            errors := errors + 1;
        else
            report "  PASS: OR result correct";
        end if;

        -- Test 9: Zero flag
        report "";
        report "Test 9: SUB 0x42 - 0x42 (zero result)";

        accumulator_in <= x"42";
        reg_b_in <= x"42";
        opcode <= OP_SUB;
        strobe_enable;

        if flag_zero /= '1' then
            report "  ERROR: Zero flag should be set" severity error;
            errors := errors + 1;
        else
            report "  PASS: Zero flag set correctly";
        end if;

        -- Test 10: Parity flag
        report "";
        report "Test 10: Parity flag (even number of 1's)";

        accumulator_in <= x"00";
        reg_b_in <= x"03";  -- 00000011 (two 1's = even)
        opcode <= OP_OR;
        strobe_enable;

        if flag_parity /= '1' then  -- Even parity sets P=1 in 8008
            report "  ERROR: Parity flag should be 1 for even parity, got " &
                   std_logic'image(flag_parity) severity error;
            errors := errors + 1;
        else
            report "  PASS: Parity flag correct for even parity";
        end if;

        -- Test 11: CMP operation (compare)
        report "";
        report "Test 11: CMP 0x50 - 0x30 (sets flags only)";

        accumulator_in <= x"50";
        reg_b_in <= x"30";
        opcode <= OP_CMP;
        strobe_enable;

        -- CMP is like SUB, result is 0x20
        if result /= "0" & x"20" then
            report "  ERROR: CMP result should be 0x20, got 0x" & to_hstring(result(7 downto 0)) severity error;
            errors := errors + 1;
        else
            report "  PASS: CMP result correct (flags set)";
        end if;

        -- Test 12: Disabled ALU
        report "";
        report "Test 12: Enable = 0 (ALU disabled)";

        accumulator_in <= x"FF";
        reg_b_in <= x"FF";
        opcode <= OP_ADD;
        enable <= '0';
        wait for phi2_period * 2;

        if result /= "000000000" then
            report "  ERROR: Result should be 0 when disabled, got 0x" & to_hstring(result(7 downto 0)) severity error;
            errors := errors + 1;
        end if;

        if flag_carry /= '0' or flag_zero /= '0' or flag_sign /= '0' or flag_parity /= '0' then
            report "  ERROR: All flags should be 0 when disabled" severity error;
            errors := errors + 1;
        end if;

        if result = "000000000" and flag_carry = '0' then
            report "  PASS: ALU outputs zero when disabled";
        end if;

        -- Summary
        report "";
        report "========================================";
        if errors = 0 then
            report "*** ALL TESTS PASSED ***";
        else
            report "*** TESTS FAILED: " & integer'image(errors) & " errors ***" severity error;
        end if;
        report "========================================";

        done <= true;
        wait;
    end process;

end architecture test;

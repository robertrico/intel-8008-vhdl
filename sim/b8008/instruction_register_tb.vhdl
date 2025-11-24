--------------------------------------------------------------------------------
-- instruction_register_tb.vhdl
--------------------------------------------------------------------------------
-- Testbench for Instruction Register
-- Tests: Load from bus, output to bus, bidirectional behavior, bit outputs
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.b8008_types.all;

entity instruction_register_tb is
end entity instruction_register_tb;

architecture test of instruction_register_tb is

    component instruction_register is
        port (
            phi1         : in std_logic;
            reset        : in std_logic;
            internal_bus : inout std_logic_vector(7 downto 0);
            load_ir      : in std_logic;
            output_ir    : in std_logic;
            ir_bit_7     : out std_logic;
            ir_bit_6     : out std_logic;
            ir_bit_5     : out std_logic;
            ir_bit_4     : out std_logic;
            ir_bit_3     : out std_logic;
            ir_bit_2     : out std_logic;
            ir_bit_1     : out std_logic;
            ir_bit_0     : out std_logic
        );
    end component;

    -- Clock
    signal phi1 : std_logic := '0';
    constant phi1_period : time := 500 ns;

    -- Inputs
    signal reset     : std_logic := '0';
    signal load_ir   : std_logic := '0';
    signal output_ir : std_logic := '0';

    -- Bidirectional bus
    signal internal_bus : std_logic_vector(7 downto 0);
    signal bus_driver   : std_logic_vector(7 downto 0) := (others => 'Z');

    -- Outputs
    signal ir_bit_7 : std_logic;
    signal ir_bit_6 : std_logic;
    signal ir_bit_5 : std_logic;
    signal ir_bit_4 : std_logic;
    signal ir_bit_3 : std_logic;
    signal ir_bit_2 : std_logic;
    signal ir_bit_1 : std_logic;
    signal ir_bit_0 : std_logic;

    -- Reconstruct full byte for checking
    signal ir_byte : std_logic_vector(7 downto 0);

begin

    -- Clock generation
    phi1 <= not phi1 after phi1_period / 2;

    -- Drive internal bus from testbench when needed
    internal_bus <= bus_driver;

    -- Reconstruct IR byte from individual bits
    ir_byte <= ir_bit_7 & ir_bit_6 & ir_bit_5 & ir_bit_4 &
               ir_bit_3 & ir_bit_2 & ir_bit_1 & ir_bit_0;

    uut : instruction_register
        port map (
            phi1         => phi1,
            reset        => reset,
            internal_bus => internal_bus,
            load_ir      => load_ir,
            output_ir    => output_ir,
            ir_bit_7     => ir_bit_7,
            ir_bit_6     => ir_bit_6,
            ir_bit_5     => ir_bit_5,
            ir_bit_4     => ir_bit_4,
            ir_bit_3     => ir_bit_3,
            ir_bit_2     => ir_bit_2,
            ir_bit_1     => ir_bit_1,
            ir_bit_0     => ir_bit_0
        );

    test_process : process
        variable errors : integer := 0;
    begin
        report "========================================";
        report "Instruction Register Test";
        report "========================================";

        -- Test 1: Reset clears IR
        report "";
        report "Test 1: Reset clears IR";

        reset <= '1';
        wait for phi1_period;
        reset <= '0';
        wait for phi1_period;

        if ir_byte /= x"00" then
            report "  ERROR: IR should be 0x00 after reset" severity error;
            errors := errors + 1;
        else
            report "  PASS: IR cleared after reset";
        end if;

        -- Test 2: Load from internal bus
        report "";
        report "Test 2: Load 0x42 from internal bus";

        bus_driver <= x"42";
        load_ir    <= '1';
        wait until rising_edge(phi1);
        wait for 10 ns;
        load_ir    <= '0';
        bus_driver <= (others => 'Z');

        if ir_byte /= x"42" then
            report "  ERROR: IR should be 0x42, got 0x" & to_hstring(ir_byte) severity error;
            errors := errors + 1;
        else
            report "  PASS: Loaded from internal bus";
        end if;

        -- Test 3: Check individual bit outputs
        report "";
        report "Test 3: Check individual bit outputs for 0x42 (01000010)";

        if ir_bit_7 /= '0' or ir_bit_6 /= '1' or ir_bit_5 /= '0' or ir_bit_4 /= '0' or
           ir_bit_3 /= '0' or ir_bit_2 /= '0' or ir_bit_1 /= '1' or ir_bit_0 /= '0' then
            report "  ERROR: Individual bits incorrect" severity error;
            errors := errors + 1;
        else
            report "  PASS: Individual bits correct";
        end if;

        -- Test 4: Output IR to bus
        report "";
        report "Test 4: Output IR (0x42) to internal bus";

        output_ir <= '1';
        wait for 10 ns;

        if internal_bus /= x"42" then
            report "  ERROR: Internal bus should be 0x42, got 0x" & to_hstring(internal_bus) severity error;
            errors := errors + 1;
        else
            report "  PASS: IR output to bus correctly";
        end if;

        output_ir <= '0';
        wait for 10 ns;

        -- Test 5: Load new value (0xAA)
        report "";
        report "Test 5: Load 0xAA from internal bus";

        bus_driver <= x"AA";
        load_ir    <= '1';
        wait until rising_edge(phi1);
        wait for 10 ns;
        load_ir    <= '0';
        bus_driver <= (others => 'Z');

        if ir_byte /= x"AA" then
            report "  ERROR: IR should be 0xAA, got 0x" & to_hstring(ir_byte) severity error;
            errors := errors + 1;
        else
            report "  PASS: Loaded new value";
        end if;

        -- Test 6: IR holds value when not loading
        report "";
        report "Test 6: IR holds 0xAA when load_ir=0";

        bus_driver <= x"FF";
        load_ir    <= '0';
        wait until rising_edge(phi1);
        wait for phi1_period;
        bus_driver <= (others => 'Z');

        if ir_byte /= x"AA" then
            report "  ERROR: IR should hold 0xAA, got 0x" & to_hstring(ir_byte) severity error;
            errors := errors + 1;
        else
            report "  PASS: IR holds value";
        end if;

        -- Test 7: Tri-state when output disabled
        report "";
        report "Test 7: Bus tri-stated when output_ir=0";

        output_ir <= '0';
        wait for 10 ns;

        if internal_bus /= "ZZZZZZZZ" then
            report "  ERROR: Bus should be tri-stated" severity error;
            errors := errors + 1;
        else
            report "  PASS: Bus correctly tri-stated";
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

        wait;
    end process;

end architecture test;

--------------------------------------------------------------------------------
-- temp_registers_tb.vhdl
--------------------------------------------------------------------------------
-- Testbench for Temporary Registers (Reg.a and Reg.b)
-- Tests: Loading from internal bus, holding values, independent operation
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.b8008_types.all;

entity temp_registers_tb is
end entity temp_registers_tb;

architecture test of temp_registers_tb is

    -- Component declaration
    component temp_registers is
        port (
            phi2         : in std_logic;
            load_reg_a   : in std_logic;
            load_reg_b   : in std_logic;
            output_reg_a : in std_logic;
            output_reg_b : in std_logic;
            internal_bus : inout std_logic_vector(7 downto 0);
            reg_a_out    : out std_logic_vector(7 downto 0);
            reg_b_out    : out std_logic_vector(7 downto 0)
        );
    end component;

    -- Clock
    signal phi2 : std_logic := '0';
    constant phi2_period : time := 500 ns;

    -- Inputs
    signal load_reg_a   : std_logic := '0';
    signal load_reg_b   : std_logic := '0';
    signal output_reg_a : std_logic := '0';
    signal output_reg_b : std_logic := '0';

    -- Bidirectional bus
    signal internal_bus : std_logic_vector(7 downto 0) := (others => 'Z');
    signal bus_driver   : std_logic_vector(7 downto 0) := (others => 'Z');
    signal bus_drive_enable : std_logic := '0';

    -- Outputs
    signal reg_a_out : std_logic_vector(7 downto 0);
    signal reg_b_out : std_logic_vector(7 downto 0);

    -- Test control
    signal done : boolean := false;

begin

    -- External bus driver (simulates other blocks driving the bus)
    internal_bus <= bus_driver when bus_drive_enable = '1' else (others => 'Z');

    uut : temp_registers
        port map (
            phi2         => phi2,
            load_reg_a   => load_reg_a,
            load_reg_b   => load_reg_b,
            output_reg_a => output_reg_a,
            output_reg_b => output_reg_b,
            internal_bus => internal_bus,
            reg_a_out    => reg_a_out,
            reg_b_out    => reg_b_out
        );

    -- Clock generation
    phi2_process : process
    begin
        while not done loop
            phi2 <= '0';
            wait for phi2_period / 2;
            phi2 <= '1';
            wait for phi2_period / 2;
        end loop;
        wait;
    end process;

    -- Test stimulus
    test_process : process
        variable errors : integer := 0;
    begin
        report "========================================";
        report "Temporary Registers Test";
        report "========================================";

        wait for 100 ns;

        -- Test 1: Load Reg.a
        report "";
        report "Test 1: Load value into Reg.a";

        bus_driver <= x"42";
        bus_drive_enable <= '1';
        load_reg_a <= '1';
        wait until rising_edge(phi2);
        wait for 10 ns;  -- Allow signal to settle

        if reg_a_out /= x"42" then
            report "  ERROR: Reg.a should contain 0x42, got 0x" &
                   to_hstring(reg_a_out) severity error;
            errors := errors + 1;
        else
            report "  PASS: Reg.a loaded 0x42";
        end if;

        load_reg_a <= '0';
        bus_drive_enable <= '0';
        wait for phi2_period;

        -- Test 2: Load Reg.b
        report "";
        report "Test 2: Load value into Reg.b";

        bus_driver <= x"A5";
        bus_drive_enable <= '1';
        load_reg_b <= '1';
        wait until rising_edge(phi2);
        wait for 10 ns;

        if reg_b_out /= x"A5" then
            report "  ERROR: Reg.b should contain 0xA5, got 0x" &
                   to_hstring(reg_b_out) severity error;
            errors := errors + 1;
        else
            report "  PASS: Reg.b loaded 0xA5";
        end if;

        load_reg_b <= '0';
        bus_drive_enable <= '0';
        wait for phi2_period;

        -- Test 3: Registers hold values when not enabled
        report "";
        report "Test 3: Registers hold values when disabled";

        bus_driver <= x"FF";
        bus_drive_enable <= '1';
        load_reg_a <= '0';
        load_reg_b <= '0';
        wait for phi2_period * 3;

        if reg_a_out /= x"42" then
            report "  ERROR: Reg.a should still contain 0x42, got 0x" &
                   to_hstring(reg_a_out) severity error;
            errors := errors + 1;
        end if;

        if reg_b_out /= x"A5" then
            report "  ERROR: Reg.b should still contain 0xA5, got 0x" &
                   to_hstring(reg_b_out) severity error;
            errors := errors + 1;
        end if;

        if reg_a_out = x"42" and reg_b_out = x"A5" then
            report "  PASS: Both registers held their values";
        end if;

        bus_drive_enable <= '0';

        -- Test 4: Load both registers simultaneously
        report "";
        report "Test 4: Load both registers simultaneously";

        bus_driver <= x"12";
        bus_drive_enable <= '1';
        load_reg_a <= '1';
        load_reg_b <= '1';
        wait until rising_edge(phi2);
        wait for 10 ns;

        if reg_a_out /= x"12" then
            report "  ERROR: Reg.a should contain 0x12, got 0x" &
                   to_hstring(reg_a_out) severity error;
            errors := errors + 1;
        end if;

        if reg_b_out /= x"12" then
            report "  ERROR: Reg.b should contain 0x12, got 0x" &
                   to_hstring(reg_b_out) severity error;
            errors := errors + 1;
        end if;

        if reg_a_out = x"12" and reg_b_out = x"12" then
            report "  PASS: Both registers loaded 0x12 simultaneously";
        end if;

        load_reg_a <= '0';
        load_reg_b <= '0';
        bus_drive_enable <= '0';
        wait for phi2_period;

        -- Test 5: Independent operation
        report "";
        report "Test 5: Registers operate independently";

        -- Load only Reg.a
        bus_driver <= x"34";
        bus_drive_enable <= '1';
        load_reg_a <= '1';
        load_reg_b <= '0';
        wait until rising_edge(phi2);
        wait for 10 ns;

        if reg_a_out /= x"34" then
            report "  ERROR: Reg.a should contain 0x34" severity error;
            errors := errors + 1;
        end if;

        if reg_b_out /= x"12" then
            report "  ERROR: Reg.b should still contain 0x12" severity error;
            errors := errors + 1;
        end if;

        if reg_a_out = x"34" and reg_b_out = x"12" then
            report "  PASS: Reg.a updated, Reg.b unchanged";
        end if;

        load_reg_a <= '0';
        bus_drive_enable <= '0';
        wait for phi2_period;

        -- Load only Reg.b
        bus_driver <= x"56";
        bus_drive_enable <= '1';
        load_reg_a <= '0';
        load_reg_b <= '1';
        wait until rising_edge(phi2);
        wait for 10 ns;

        if reg_a_out /= x"34" then
            report "  ERROR: Reg.a should still contain 0x34" severity error;
            errors := errors + 1;
        end if;

        if reg_b_out /= x"56" then
            report "  ERROR: Reg.b should contain 0x56" severity error;
            errors := errors + 1;
        end if;

        if reg_a_out = x"34" and reg_b_out = x"56" then
            report "  PASS: Reg.b updated, Reg.a unchanged";
        end if;

        load_reg_b <= '0';
        bus_drive_enable <= '0';
        wait for phi2_period;

        -- Test 6: Output Reg.a to bus
        report "";
        report "Test 6: Output Reg.a to internal bus";

        output_reg_a <= '1';
        wait for 50 ns;  -- Allow bus to settle

        if internal_bus /= x"34" then
            report "  ERROR: Internal bus should contain 0x34 from Reg.a, got 0x" &
                   to_hstring(internal_bus) severity error;
            errors := errors + 1;
        else
            report "  PASS: Reg.a driving bus with 0x34";
        end if;

        output_reg_a <= '0';
        wait for phi2_period;

        -- Test 7: Output Reg.b to bus
        report "";
        report "Test 7: Output Reg.b to internal bus";

        output_reg_b <= '1';
        wait for 50 ns;

        if internal_bus /= x"56" then
            report "  ERROR: Internal bus should contain 0x56 from Reg.b, got 0x" &
                   to_hstring(internal_bus) severity error;
            errors := errors + 1;
        else
            report "  PASS: Reg.b driving bus with 0x56";
        end if;

        output_reg_b <= '0';
        wait for phi2_period;

        -- Test 8: Bus tri-state when no outputs enabled
        report "";
        report "Test 8: Bus is high-impedance when no outputs enabled";

        output_reg_a <= '0';
        output_reg_b <= '0';
        bus_drive_enable <= '0';
        wait for 50 ns;

        -- Internal bus should be all Z's
        if internal_bus /= "ZZZZZZZZ" then
            report "  WARNING: Bus should be high-impedance, got 0x" &
                   to_hstring(internal_bus);
        else
            report "  PASS: Bus is high-impedance";
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

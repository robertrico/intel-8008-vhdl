-------------------------------------------------------------------------------
-- v8008_test Testbench
-------------------------------------------------------------------------------
-- Tests the complete v8008_test system running search.asm
-- Expected behavior:
--   - CPU boots with RST 0
--   - Searches for '.' in "Hello, world. 8008!!"
--   - When found at position 213 (0xD5), copies to H and halts
--   - Final accumulator = 0x2E (ASCII period)
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity v8008_test_tb is
end entity v8008_test_tb;

architecture behavior of v8008_test_tb is

    -- Component declaration
    component v8008_test_top is
        port (
            clk         : in  std_logic;
            rst         : in  std_logic;
            led_E16     : out std_logic;
            led_D17     : out std_logic;
            led_D18     : out std_logic;
            led_E18     : out std_logic;
            led_D19     : out std_logic;
            led_E19     : out std_logic;
            led_A20     : out std_logic;
            led_B20     : out std_logic;
            cpu_d       : out std_logic_vector(7 downto 0);
            cpu_phi1    : out std_logic;
            cpu_phi2    : out std_logic;
            cpu_sync    : out std_logic;
            cpu_s0      : out std_logic;
            cpu_s1      : out std_logic;
            cpu_s2      : out std_logic;
            cpu_int     : out std_logic;
            cpu_ready   : out std_logic
        );
    end component;

    -- Clock and control signals
    signal clk          : std_logic := '0';
    signal rst          : std_logic := '0';

    -- LED signals
    signal led_E16, led_D17, led_D18, led_E18 : std_logic;
    signal led_D19, led_E19, led_A20, led_B20 : std_logic;
    signal led_value : std_logic_vector(7 downto 0);

    -- Debug signals
    signal cpu_d        : std_logic_vector(7 downto 0);
    signal cpu_phi1     : std_logic;
    signal cpu_phi2     : std_logic;
    signal cpu_sync     : std_logic;
    signal cpu_s0       : std_logic;
    signal cpu_s1       : std_logic;
    signal cpu_s2       : std_logic;
    signal cpu_int      : std_logic;
    signal cpu_ready    : std_logic;

    -- Test control
    signal done         : boolean := false;
    constant CLK_PERIOD : time := 10 ns;

begin

    -- Instantiate Unit Under Test
    UUT: v8008_test_top
        port map (
            clk         => clk,
            rst         => rst,
            led_E16     => led_E16,
            led_D17     => led_D17,
            led_D18     => led_D18,
            led_E18     => led_E18,
            led_D19     => led_D19,
            led_E19     => led_E19,
            led_A20     => led_A20,
            led_B20     => led_B20,
            cpu_d       => cpu_d,
            cpu_phi1    => cpu_phi1,
            cpu_phi2    => cpu_phi2,
            cpu_sync    => cpu_sync,
            cpu_s0      => cpu_s0,
            cpu_s1      => cpu_s1,
            cpu_s2      => cpu_s2,
            cpu_int     => cpu_int,
            cpu_ready   => cpu_ready
        );

    -- Reconstruct LED value (invert because LEDs are active-low)
    led_value <= not (led_B20 & led_A20 & led_E19 & led_D19 & led_E18 & led_D18 & led_D17 & led_E16);

    -- Clock generation
    CLK_PROC: process
    begin
        while not done loop
            clk <= '0';
            wait for CLK_PERIOD / 2;
            clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process CLK_PROC;

    -- Test process
    TEST_PROC: process
    begin
        report "========================================";
        report "v8008_test - search.asm Test";
        report "========================================";
        report "";
        report "Test Procedure:";
        report "  1. Assert reset";
        report "  2. Release reset (CPU boots with RST 0)";
        report "  3. CPU executes search.asm";
        report "  4. Searches for '.' in string at 0xC8";
        report "  5. When found, H=L=address, accumulator=0x2E";
        report "  6. CPU halts";
        report "";

        -- Assert reset
        rst <= '1';
        wait for 200 ns;

        -- Release reset
        rst <= '0';
        report "Reset released - CPU starting...";
        report "";

        -- Wait for program to complete
        -- search.asm takes some time to search through the string
        wait for 500 us;

        report "========================================";
        report "Simulation Complete";
        report "========================================";
        report "";
        report "Final State:";
        report "  LED Display (Accumulator): 0x" & to_hstring(led_value);
        report "  Data Bus: 0x" & to_hstring(cpu_d);
        report "  SYNC: " & std_logic'image(cpu_sync);
        report "  INT: " & std_logic'image(cpu_int);
        report "";

        -- Check for expected result
        if led_value = x"2E" then
            report "*** TEST PASSED ***";
            report "  Accumulator = 0x2E (ASCII period '.')";
            report "  Search completed successfully!";
        else
            report "*** TEST FAILED ***" severity error;
            report "  Expected accumulator = 0x2E";
            report "  Actual accumulator   = 0x" & to_hstring(led_value);
        end if;

        report "========================================";

        done <= true;
        wait;
    end process TEST_PROC;

end architecture behavior;

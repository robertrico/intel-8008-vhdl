--------------------------------------------------------------------------------
-- Interrupt Controller Testbench
--------------------------------------------------------------------------------
-- Tests the interrupt controller for the Intel 8008 Blinky project
--
-- Test Coverage:
--   1. Startup interrupt generation
--   2. Button debouncing logic
--   3. Edge detection (rising and falling)
--   4. Interrupt request (INT assertion)
--   5. T1I acknowledge detection
--   6. RST opcode drive timing
--   7. Interrupt clear after acknowledge
--
-- Copyright (c) 2025 Robert Rico
-- License: MIT
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity interrupt_controller_tb is
end entity interrupt_controller_tb;

architecture behavior of interrupt_controller_tb is

    -- Component declaration
    component interrupt_controller is
        generic (
            CLK_FREQ_HZ   : positive := 100_000_000;
            DEBOUNCE_MS   : positive := 50
        );
        port (
            clk         : in  std_logic;
            reset_n     : in  std_logic;
            S2          : in  std_logic;
            S1          : in  std_logic;
            S0          : in  std_logic;
            SYNC        : in  std_logic;
            data_bus    : inout std_logic_vector(7 downto 0);
            INT         : out std_logic;
            button_raw  : in  std_logic
        );
    end component;

    -- Testbench signals
    signal clk         : std_logic := '0';
    signal reset_n     : std_logic := '0';
    signal S2          : std_logic := '0';
    signal S1          : std_logic := '0';
    signal S0          : std_logic := '0';
    signal SYNC        : std_logic := '0';
    signal data_bus    : std_logic_vector(7 downto 0);
    signal INT         : std_logic;
    signal button_raw  : std_logic := '0';

    -- Clock period (100 MHz = 10ns period)
    constant CLK_PERIOD : time := 10 ns;

    -- Reduced debounce time for faster testing (1ms instead of 50ms)
    constant TEST_DEBOUNCE_MS : positive := 1;
    constant TEST_DEBOUNCE_CYCLES : positive := 100_000;  -- 1ms at 100MHz

    -- Test control
    signal test_running : boolean := true;
    signal test_phase : integer := 0;

    -- Expected values
    constant RST_0_OPCODE : std_logic_vector(7 downto 0) := "00000101";  -- 0x05

begin

    -- Instantiate the Unit Under Test (UUT)
    uut: interrupt_controller
        generic map (
            CLK_FREQ_HZ => 100_000_000,
            DEBOUNCE_MS => TEST_DEBOUNCE_MS
        )
        port map (
            clk        => clk,
            reset_n    => reset_n,
            S2         => S2,
            S1         => S1,
            S0         => S0,
            SYNC       => SYNC,
            data_bus   => data_bus,
            INT        => INT,
            button_raw => button_raw
        );

    -- Clock generation
    clk_process: process
    begin
        while test_running loop
            clk <= '0';
            wait for CLK_PERIOD / 2;
            clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process clk_process;

    -- Main test stimulus
    test_proc: process
        variable all_passed : boolean := true;

        -- Helper procedure to simulate T1I state
        procedure simulate_t1i is
        begin
            -- Enter T1I state: S2=1, S1=1, S0=0
            wait until rising_edge(clk);
            S2   <= '1';
            S1   <= '1';
            S0   <= '0';
            SYNC <= '1';
            wait for CLK_PERIOD;

            -- Exit T1I (go to T2: S2=1, S1=0, S0=0)
            S2   <= '1';
            S1   <= '0';
            S0   <= '0';
            SYNC <= '0';
            wait for CLK_PERIOD;

            -- Return to idle
            S2   <= '0';
            S1   <= '0';
            S0   <= '0';
            SYNC <= '0';
        end procedure;

    begin
        report "========================================";
        report "Starting Interrupt Controller Tests";
        report "========================================";

        -----------------------------------------------------------------------
        -- TEST 1: Reset behavior
        -----------------------------------------------------------------------
        test_phase <= 1;
        report " ";
        report "TEST 1: Reset Behavior";
        report "-----------------------";

        reset_n <= '0';
        button_raw <= '0';
        wait for CLK_PERIOD * 10;

        if INT /= '0' then
            report "FAIL: INT should be low during reset" severity error;
            all_passed := false;
        else
            report "PASS: INT correctly low during reset";
        end if;

        -----------------------------------------------------------------------
        -- TEST 2: Startup interrupt
        -----------------------------------------------------------------------
        test_phase <= 2;
        report " ";
        report "TEST 2: Startup Interrupt";
        report "--------------------------";

        -- Release reset
        reset_n <= '1';
        wait for CLK_PERIOD * 10;

        -- Startup interrupt should be asserted
        if INT /= '1' then
            report "FAIL: Startup interrupt not asserted" severity error;
            all_passed := false;
        else
            report "PASS: Startup interrupt asserted";
        end if;

        -- Simulate CPU acknowledging interrupt
        simulate_t1i;
        wait for CLK_PERIOD * 2;

        -- Check that data bus had RST opcode during T1I
        report "INFO: Check simulation waveform - RST opcode should have been driven during T1I";

        -- INT should be cleared after acknowledge
        wait for CLK_PERIOD * 5;
        if INT /= '0' then
            report "FAIL: INT not cleared after startup interrupt acknowledge" severity error;
            all_passed := false;
        else
            report "PASS: INT cleared after startup interrupt";
        end if;

        -----------------------------------------------------------------------
        -- TEST 3: Button debouncing
        -----------------------------------------------------------------------
        test_phase <= 3;
        report " ";
        report "TEST 3: Button Debouncing";
        report "--------------------------";

        -- Create glitches on button (should be ignored)
        for i in 1 to 5 loop
            button_raw <= '1';
            wait for CLK_PERIOD * 10;
            button_raw <= '0';
            wait for CLK_PERIOD * 10;
        end loop;

        -- INT should NOT be asserted (glitches filtered)
        wait for CLK_PERIOD * 10;
        if INT /= '0' then
            report "FAIL: Glitches not filtered (INT asserted incorrectly)" severity error;
            all_passed := false;
        else
            report "PASS: Button glitches correctly filtered";
        end if;

        -----------------------------------------------------------------------
        -- TEST 4: Rising edge detection
        -----------------------------------------------------------------------
        test_phase <= 4;
        report " ";
        report "TEST 4: Rising Edge Detection";
        report "------------------------------";

        -- Press button and hold for full debounce period
        button_raw <= '1';
        wait for CLK_PERIOD * (TEST_DEBOUNCE_CYCLES + 100);

        -- INT should be asserted
        if INT /= '1' then
            report "FAIL: INT not asserted after rising edge" severity error;
            all_passed := false;
        else
            report "PASS: INT asserted after rising edge";
        end if;

        -- Acknowledge interrupt
        simulate_t1i;
        wait for CLK_PERIOD * 5;

        if INT /= '0' then
            report "FAIL: INT not cleared after acknowledge" severity error;
            all_passed := false;
        else
            report "PASS: INT cleared after acknowledge";
        end if;

        -----------------------------------------------------------------------
        -- TEST 5: Falling edge detection
        -----------------------------------------------------------------------
        test_phase <= 5;
        report " ";
        report "TEST 5: Falling Edge Detection";
        report "-------------------------------";

        -- Release button and hold for full debounce period
        button_raw <= '0';
        wait for CLK_PERIOD * (TEST_DEBOUNCE_CYCLES + 100);

        -- INT should be asserted (falling edge also triggers)
        if INT /= '1' then
            report "FAIL: INT not asserted after falling edge" severity error;
            all_passed := false;
        else
            report "PASS: INT asserted after falling edge";
        end if;

        -- Acknowledge interrupt
        simulate_t1i;
        wait for CLK_PERIOD * 5;

        -----------------------------------------------------------------------
        -- TEST 6: RST opcode timing
        -----------------------------------------------------------------------
        test_phase <= 6;
        report " ";
        report "TEST 6: RST Opcode Timing";
        report "--------------------------";

        -- Generate another interrupt
        button_raw <= '1';
        wait for CLK_PERIOD * (TEST_DEBOUNCE_CYCLES + 100);

        -- Check that INT is asserted
        if INT /= '1' then
            report "FAIL: INT not asserted after button press in Test 6" severity error;
            all_passed := false;
        else
            report "INFO: INT asserted, simulating T1I...";
        end if;

        -- Enter T1I and check data bus
        wait until rising_edge(clk);
        S2   <= '1';
        S1   <= '1';
        S0   <= '0';
        SYNC <= '1';
        wait until rising_edge(clk);  -- Wait for controller to respond

        -- Check that RST opcode is being driven
        wait for CLK_PERIOD / 2;  -- Half cycle for signal stability
        if data_bus /= RST_0_OPCODE then
            report "FAIL: RST opcode not driven during T1I. Data bus = 0x" &
                   to_hstring(unsigned(data_bus)) & " (expected 0x05)" severity error;
            all_passed := false;
        else
            report "PASS: RST opcode correctly driven during T1I";
        end if;

        -- Exit T1I
        wait until rising_edge(clk);
        S2   <= '0';
        S1   <= '0';
        S0   <= '0';
        SYNC <= '0';
        wait for CLK_PERIOD * 5;

        -- Data bus should be tri-stated
        if data_bus /= "ZZZZZZZZ" then
            report "FAIL: Data bus not tri-stated after T1I" severity error;
            all_passed := false;
        else
            report "PASS: Data bus tri-stated after T1I";
        end if;

        -----------------------------------------------------------------------
        -- Test Complete
        -----------------------------------------------------------------------
        test_phase <= 99;
        report " ";
        report "========================================";
        report "Interrupt Controller Tests Complete";
        report "========================================";

        if all_passed then
            report "*** ALL TESTS PASSED ***" severity note;
        else
            report "*** SOME TESTS FAILED ***" severity error;
        end if;

        test_running <= false;
        wait;
    end process test_proc;

end architecture behavior;

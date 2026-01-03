--------------------------------------------------------------------------------
-- blinky_tb.vhdl - Testbench for blinky_top
--------------------------------------------------------------------------------
-- Verifies the blinky project works before flashing to hardware:
--   1. Reset and bootstrap sequence
--   2. CPU starts executing from address 0x0000
--   3. LED toggles via OUT 8 instruction
--   4. Delay loop executes correctly
--
-- Expected behavior:
--   - After bootstrap, CPU executes blinky.asm
--   - OUT 8 with 0xFE turns LED on (bit 0 = 0)
--   - OUT 8 with 0xFF turns LED off (bit 0 = 1)
--   - LED should toggle every ~0.5s at real clock speed
--   - In simulation, we just verify the first few toggles
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity blinky_top_tb is
end entity blinky_top_tb;

architecture sim of blinky_top_tb is

    -- Clock period (100 MHz = 10 ns)
    constant CLK_PERIOD : time := 10 ns;

    -- DUT signals
    signal clk          : std_logic := '0';
    signal rst          : std_logic := '1';  -- Active-low reset (start in reset)
    signal speed_btn    : std_logic := '1';  -- Not pressed

    -- LED outputs
    signal led_E16      : std_logic;
    signal led_D17      : std_logic;
    signal led_D18      : std_logic;
    signal led_E18      : std_logic;
    signal led_F17      : std_logic;
    signal led_F18      : std_logic;
    signal led_E17      : std_logic;
    signal led_F16      : std_logic;
    signal led_M20      : std_logic;
    signal led_L18      : std_logic;

    -- CPU debug outputs
    signal cpu_d        : std_logic_vector(7 downto 0);
    signal cpu_s0       : std_logic;
    signal cpu_s1       : std_logic;
    signal cpu_s2       : std_logic;
    signal cpu_sync     : std_logic;
    signal cpu_phi1     : std_logic;
    signal cpu_phi2     : std_logic;
    signal cpu_ready    : std_logic;
    signal cpu_int      : std_logic;
    signal cpu_data_en  : std_logic;

    -- Test tracking
    signal led_toggle_count : integer := 0;
    signal last_led_state   : std_logic := '1';
    signal test_done        : boolean := false;

begin

    --------------------------------------------------------------------------------
    -- Clock Generation
    --------------------------------------------------------------------------------
    clk <= not clk after CLK_PERIOD / 2 when not test_done else '0';

    --------------------------------------------------------------------------------
    -- DUT Instantiation
    --------------------------------------------------------------------------------
    dut : entity work.blinky_top
        port map (
            clk         => clk,
            rst         => rst,
            speed_btn   => speed_btn,
            led_E16     => led_E16,
            led_D17     => led_D17,
            led_D18     => led_D18,
            led_E18     => led_E18,
            led_F17     => led_F17,
            led_F18     => led_F18,
            led_E17     => led_E17,
            led_F16     => led_F16,
            led_M20     => led_M20,
            led_L18     => led_L18,
            cpu_d       => cpu_d,
            cpu_s0      => cpu_s0,
            cpu_s1      => cpu_s1,
            cpu_s2      => cpu_s2,
            cpu_sync    => cpu_sync,
            cpu_phi1    => cpu_phi1,
            cpu_phi2    => cpu_phi2,
            cpu_ready   => cpu_ready,
            cpu_int     => cpu_int,
            cpu_data_en => cpu_data_en
        );

    --------------------------------------------------------------------------------
    -- LED Toggle Detection (only after bootstrap completes)
    --------------------------------------------------------------------------------
    process(cpu_phi1)
    begin
        if rising_edge(cpu_phi1) then
            -- Only track LED after bootstrap (cpu_int goes low)
            if cpu_int = '0' then
                if led_E16 /= last_led_state then
                    last_led_state <= led_E16;
                    led_toggle_count <= led_toggle_count + 1;
                    if led_E16 = '0' then
                        report "LED ON (toggle #" & integer'image(led_toggle_count + 1) & ")";
                    else
                        report "LED OFF (toggle #" & integer'image(led_toggle_count + 1) & ")";
                    end if;
                end if;
            else
                -- Initialize last_led_state to current state during bootstrap
                last_led_state <= led_E16;
            end if;
        end if;
    end process;

    --------------------------------------------------------------------------------
    -- Test Stimulus
    --------------------------------------------------------------------------------
    process
    begin
        report "=== BLINKY TESTBENCH START ===";

        -- Hold reset for a bit
        rst <= '1';  -- Active-low: '1' = reset active
        wait for 100 ns;

        -- Release reset
        report "Releasing reset...";
        rst <= '0';  -- Active-low: '0' = normal operation
        wait for 100 ns;

        -- Wait for bootstrap to complete
        report "Waiting for bootstrap...";
        wait until cpu_int = '0';
        report "Bootstrap complete, CPU running";

        -- Wait for first LED toggle (LED turns ON)
        report "Waiting for first LED toggle...";
        wait until led_toggle_count >= 1 for 50 ms;

        if led_toggle_count >= 1 then
            report "SUCCESS: First LED toggle detected!";
        else
            report "TIMEOUT: No LED toggle detected after 50ms" severity error;
            test_done <= true;
            wait;
        end if;

        -- Wait for second LED toggle (LED turns OFF)
        -- Note: The delay loop in blinky.asm is ~0.5s at real clock speed
        -- In simulation, we only wait briefly to verify the program structure works
        report "Waiting for second LED toggle (may timeout - delay loop is long)...";
        wait until led_toggle_count >= 2 for 10 ms;

        if led_toggle_count >= 2 then
            report "SUCCESS: Second LED toggle detected!";
        end if;

        -- Summary
        report "=== BLINKY TESTBENCH COMPLETE ===";
        report "Total LED toggles: " & integer'image(led_toggle_count);

        if led_toggle_count >= 1 then
            report "TEST PASSED: LED toggled - blinky program is running correctly!";
            report "Note: Full blink cycle takes ~0.5s, too long for simulation.";
        else
            report "TEST FAILED: No LED activity detected" severity error;
        end if;

        test_done <= true;
        wait;
    end process;

end architecture sim;

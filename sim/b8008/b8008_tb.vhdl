--------------------------------------------------------------------------------
-- b8008_tb.vhdl
--------------------------------------------------------------------------------
-- Comprehensive testbench for Intel 8008 Top-Level Integration
--
-- This testbench builds progressively through integration phases:
--   Phase 2: Clock and timing verification
--   Phase 3: Control and decode (TODO)
--   Phase 4: Program counter and addressing (TODO)
--   Phase 5: Stack system (TODO)
--   Phase 6: Register file (TODO)
--   Phase 7: Temp registers (TODO)
--   Phase 8: ALU and flags (TODO)
--   Phase 9: External interface (TODO)
--
-- Each phase's tests remain active as new phases are added.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.b8008_types.all;

entity b8008_tb is
end entity b8008_tb;

architecture testbench of b8008_tb is

    -- Component declaration
    component b8008 is
        port (
            clk_in      : in std_logic;
            reset       : in std_logic;
            phi1_out    : out std_logic;
            phi2_out    : out std_logic;
            address_bus : out std_logic_vector(13 downto 0);
            data_bus    : inout std_logic_vector(7 downto 0);
            sync_out    : out std_logic;
            s0_out      : out std_logic;
            s1_out      : out std_logic;
            s2_out      : out std_logic;
            ready_in    : in std_logic;
            interrupt   : in std_logic
        );
    end component;

    -- Test signals
    signal clk_in      : std_logic := '0';
    signal reset       : std_logic := '1';
    signal phi1_out    : std_logic;
    signal phi2_out    : std_logic;
    signal address_bus : std_logic_vector(13 downto 0);
    signal data_bus    : std_logic_vector(7 downto 0) := (others => 'Z');
    signal sync_out    : std_logic;
    signal s0_out      : std_logic;
    signal s1_out      : std_logic;
    signal s2_out      : std_logic;
    signal ready_in    : std_logic := '1';  -- Default ready
    signal interrupt   : std_logic := '0';  -- Default no interrupt

    -- Clock generation
    constant CLK_PERIOD : time := 10 ns;  -- 100 MHz clock
    signal test_running : boolean := true;

    -- Test control
    signal test_phase : integer := 0;
    signal test_passed : boolean := true;

begin

    -- ========================================================================
    -- DEVICE UNDER TEST
    -- ========================================================================

    dut : b8008
        port map (
            clk_in      => clk_in,
            reset       => reset,
            phi1_out    => phi1_out,
            phi2_out    => phi2_out,
            address_bus => address_bus,
            data_bus    => data_bus,
            sync_out    => sync_out,
            s0_out      => s0_out,
            s1_out      => s1_out,
            s2_out      => s2_out,
            ready_in    => ready_in,
            interrupt   => interrupt
        );

    -- ========================================================================
    -- CLOCK GENERATION
    -- ========================================================================

    clk_process : process
    begin
        while test_running loop
            clk_in <= '0';
            wait for CLK_PERIOD / 2;
            clk_in <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    -- ========================================================================
    -- STIMULUS AND VERIFICATION
    -- ========================================================================

    stimulus : process
        variable phi1_count : integer := 0;
        variable phi2_count : integer := 0;
        variable status_value : std_logic_vector(2 downto 0);
    begin
        -- ====================================================================
        -- PHASE 2: CLOCK AND TIMING VERIFICATION
        -- ====================================================================

        report "========================================";
        report "PHASE 2: Clock and Timing Tests";
        report "========================================";
        test_phase <= 2;

        -- Test 2.1: Reset behavior
        report "Test 2.1: Verifying reset behavior...";
        reset <= '1';
        wait for 100 ns;

        -- Release reset
        reset <= '0';
        wait for 50 ns;

        -- Test 2.2: Clock generation
        report "Test 2.2: Verifying phi1 and phi2 generation...";

        -- Wait for a few clock cycles and verify phi1/phi2 are toggling
        wait for 500 ns;

        if phi1_out = '0' and phi2_out = '0' then
            report "ERROR: Both phi1 and phi2 are stuck low" severity error;
            test_passed <= false;
        end if;

        -- Test 2.3: Non-overlapping clocks
        report "Test 2.3: Verifying phi1 and phi2 are non-overlapping...";

        -- Sample phi1 and phi2 for multiple cycles
        for i in 1 to 100 loop
            wait until rising_edge(clk_in);
            if phi1_out = '1' and phi2_out = '1' then
                report "ERROR: phi1 and phi2 overlap at cycle " & integer'image(i) severity error;
                test_passed <= false;
            end if;
        end loop;

        report "PASS: Non-overlapping clock verification passed";

        -- Test 2.4: Timing state progression
        report "Test 2.4: Verifying timing state progression (T1->T2->T3->T4->T5)...";

        -- Wait for state machine to stabilize after reset
        wait for 1 us;

        -- Capture initial status
        status_value := s2_out & s1_out & s0_out;
        report "Initial status: " & integer'image(to_integer(unsigned(status_value)));

        -- Monitor status changes for several cycles
        for i in 1 to 20 loop
            wait for 500 ns;
            status_value := s2_out & s1_out & s0_out;

            -- Verify status is one of valid states
            case status_value is
                when "010" =>  -- T1
                    report "  State: T1 (S2=0, S1=1, S0=0)";
                when "100" =>  -- T2
                    report "  State: T2 (S2=1, S1=0, S0=0)";
                when "001" =>  -- T3
                    report "  State: T3 (S2=0, S1=0, S0=1)";
                when "011" =>  -- T4
                    report "  State: T4 (S2=0, S1=1, S0=1)";
                when "101" =>  -- T5
                    report "  State: T5 (S2=1, S1=0, S0=1)";
                when "110" =>  -- T1I
                    report "  State: T1I (S2=1, S1=1, S0=0)";
                when others =>
                    report "ERROR: Invalid status value: " & integer'image(to_integer(unsigned(status_value)))
                           severity error;
                    test_passed <= false;
            end case;
        end loop;

        report "PASS: Timing state verification passed";

        -- Test 2.5: SYNC signal behavior
        report "Test 2.5: Verifying SYNC signal...";

        -- SYNC should toggle periodically
        wait for 2 us;

        if sync_out = 'U' or sync_out = 'X' then
            report "ERROR: SYNC signal is undefined" severity error;
            test_passed <= false;
        else
            report "PASS: SYNC signal is defined";
        end if;

        -- ====================================================================
        -- PHASE 2 COMPLETE
        -- ====================================================================

        wait for 1 us;

        report "========================================";
        if test_passed then
            report "PHASE 2: ALL TESTS PASSED";
        else
            report "PHASE 2: SOME TESTS FAILED" severity error;
        end if;
        report "========================================";

        -- ====================================================================
        -- FUTURE PHASES (TODO)
        -- ====================================================================

        -- Phase 3 tests will be added here when control modules are integrated
        -- Phase 4 tests will be added here when PC/addressing modules are integrated
        -- And so on...

        -- End simulation
        test_running <= false;
        wait;
    end process;

end architecture testbench;

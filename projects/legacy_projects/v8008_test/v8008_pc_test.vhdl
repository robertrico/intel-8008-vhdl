--------------------------------------------------------------------------------
-- v8008 PC Increment Test
--------------------------------------------------------------------------------
-- This testbench tests PC increment timing within a multi-cycle instruction.
-- It does NOT use any peripherals - only the v8008 CPU and direct observation
-- of its external signals (SYNC, S0, S1, S2, data bus).
--
-- Expected behavior per Intel 8008 datasheet:
-- "The program counter is incremented immediately after the lower order
--  address bits are sent out. The higher order address bits are sent out
--  at T2 and then incremented if a carry resulted from T1."
--
-- This means for a 3-cycle instruction like JMP (opcode at 0x00):
-- - CYCLE 0 T1: PCL=0x00 sent out (opcode fetch), then PC increments to 0x0001
-- - CYCLE 1 T1: PCL=0x01 sent out (low byte fetch), then PC increments to 0x0002
-- - CYCLE 2 T1: PCL=0x02 sent out (high byte fetch), then PC increments to 0x0003
--
-- This test captures the PC value on the data bus during T1 of each CYCLE
-- within a single multi-cycle instruction and verifies it increments properly.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity v8008_pc_test is
end entity v8008_pc_test;

architecture test of v8008_pc_test is
    -- v8008 component (CPU under test)
    component v8008 is
        port (
            phi1            : in    std_logic;
            phi2            : in    std_logic;
            data_bus_in     : in    std_logic_vector(7 downto 0);
            data_bus_out    : out   std_logic_vector(7 downto 0);
            data_bus_enable : out   std_logic;
            S0              : out   std_logic;
            S1              : out   std_logic;
            S2              : out   std_logic;
            SYNC            : out   std_logic;
            READY           : in    std_logic;
            INT             : in    std_logic;
            debug_reg_A     : out   std_logic_vector(7 downto 0);
            debug_reg_B     : out   std_logic_vector(7 downto 0);
            debug_reg_C     : out   std_logic_vector(7 downto 0);
            debug_reg_D     : out   std_logic_vector(7 downto 0);
            debug_reg_E     : out   std_logic_vector(7 downto 0);
            debug_reg_H     : out   std_logic_vector(7 downto 0);
            debug_reg_L     : out   std_logic_vector(7 downto 0);
            debug_pc        : out   std_logic_vector(13 downto 0);
            debug_instruction : out std_logic_vector(7 downto 0);
            debug_stack_pointer : out std_logic_vector(2 downto 0);
            debug_hl_address    : out std_logic_vector(13 downto 0)
        );
    end component;

    -- Phase clock generator
    component phase_clocks is
        port (
            clk_in  : in  std_logic;
            reset   : in  std_logic;
            phi1    : out std_logic;
            phi2    : out std_logic
        );
    end component;

    -- Clock and reset
    signal clk_100mhz : std_logic := '0';
    signal reset : std_logic := '1';
    signal phi1, phi2 : std_logic;

    -- CPU signals
    signal data_bus_in : std_logic_vector(7 downto 0) := (others => 'Z');
    signal data_bus_out : std_logic_vector(7 downto 0);
    signal data_bus_enable : std_logic;
    signal S0, S1, S2 : std_logic;
    signal SYNC : std_logic;
    signal READY : std_logic := '1';
    signal INT : std_logic := '0';

    -- Debug signals
    signal debug_pc : std_logic_vector(13 downto 0);
    signal debug_reg_A, debug_reg_B, debug_reg_C, debug_reg_D : std_logic_vector(7 downto 0);
    signal debug_reg_E, debug_reg_H, debug_reg_L : std_logic_vector(7 downto 0);
    signal debug_instruction : std_logic_vector(7 downto 0);
    signal debug_stack_pointer : std_logic_vector(2 downto 0);
    signal debug_hl_address : std_logic_vector(13 downto 0);

    -- State detection
    signal is_t1, is_t2, is_t3, is_t1i : std_logic;

    -- Cycle tracking
    signal cycle_type : std_logic_vector(1 downto 0);

    -- Test variables
    type pc_capture_array is array (0 to 9) of std_logic_vector(13 downto 0);
    signal captured_pc_values : pc_capture_array := (others => (others => '0'));
    signal capture_count : integer := 0;
    signal last_state : std_logic_vector(2 downto 0) := "000";

    -- Simplified: Just count T3 states to know which byte to provide next
    signal t3_count : integer := 0;
    signal rst_complete : boolean := false;

    -- Test status
    signal test_complete : boolean := false;
    signal test_passed : boolean := false;

begin
    -- Clock generation (100 MHz)
    clk_100mhz <= not clk_100mhz after 5 ns;

    -- Phase clock generator
    u_phase_clocks : phase_clocks
        port map (
            clk_in => clk_100mhz,
            reset  => reset,
            phi1   => phi1,
            phi2   => phi2
        );

    -- CPU under test
    u_cpu : v8008
        port map (
            phi1            => phi1,
            phi2            => phi2,
            data_bus_in     => data_bus_in,
            data_bus_out    => data_bus_out,
            data_bus_enable => data_bus_enable,
            S0              => S0,
            S1              => S1,
            S2              => S2,
            SYNC            => SYNC,
            READY           => READY,
            INT             => INT,
            debug_reg_A     => debug_reg_A,
            debug_reg_B     => debug_reg_B,
            debug_reg_C     => debug_reg_C,
            debug_reg_D     => debug_reg_D,
            debug_reg_E     => debug_reg_E,
            debug_reg_H     => debug_reg_H,
            debug_reg_L     => debug_reg_L,
            debug_pc        => debug_pc,
            debug_instruction => debug_instruction,
            debug_stack_pointer => debug_stack_pointer,
            debug_hl_address => debug_hl_address
        );

    -- State detection
    is_t1 <= '1' when (S2 = '0' and S1 = '1' and S0 = '0') else '0';
    is_t2 <= '1' when (S2 = '1' and S1 = '0' and S0 = '0') else '0';
    is_t3 <= '1' when (S2 = '0' and S1 = '0' and S0 = '1') else '0';
    is_t1i <= '1' when (S2 = '1' and S1 = '1' and S0 = '0') else '0';

    -- Instruction provider for multi-cycle instruction test
    -- During T1I (interrupt acknowledge): provide RST 0 instruction (0x05)
    -- First instruction after RST: JMP 0x1234 (3 cycles: opcode 0x44, low byte 0x34, high byte 0x12)
    -- The CPU reads data during T3, so we track T3 states to know which byte to provide
    data_bus_in <= X"05" when is_t1i = '1' else  -- T1I: RST 0 (byte 0)
                   X"44" when t3_count = 1 else  -- JMP opcode (byte 1, first instruction after RST)
                   X"34" when t3_count = 2 else  -- JMP low byte (byte 2)
                   X"12" when t3_count = 3 else  -- JMP high byte (byte 3)
                   X"FF";  -- HLT after JMP completes

    -- Capture and tracking process
    -- Capture when SYNC=0 (second half of T-state) AND in T1
    -- This ensures the T1 state has stabilized and PC has been incremented
    process(SYNC, is_t1)
    begin
        -- When SYNC is low AND we're in T1, capture the PC
        if SYNC = '0' and is_t1 = '1' and rst_complete and capture_count < 10 then
            -- Only capture once per T1 by checking if we haven't already captured this value
            if capture_count = 0 or data_bus_out /= captured_pc_values(capture_count - 1)(7 downto 0) then
                captured_pc_values(capture_count)(7 downto 0) <= data_bus_out;

                report "CAPTURE #" & integer'image(capture_count) &
                       ": T1 SYNC=0 (sub_phase 1), PCL on bus=0x" & to_hstring(unsigned(data_bus_out));

                capture_count <= capture_count + 1;
            end if;
        end if;
    end process;

    -- T3 counting process (separate, simpler)
    process(SYNC)
        variable current_state : std_logic_vector(2 downto 0);
    begin
        if rising_edge(SYNC) then
            current_state := S2 & S1 & S0;

            if current_state /= last_state then
                last_state <= current_state;

                -- Count T3 states
                if is_t3 = '1' then
                    t3_count <= t3_count + 1;

                    if t3_count = 0 then
                        rst_complete <= true;
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- Test stimulus
    process
        variable passed : boolean;
    begin
        report "========================================";
        report "v8008 PC Increment Test";
        report "========================================";
        report "";
        report "This test verifies that PC increments correctly between CYCLES";
        report "of a multi-cycle instruction (JMP).";
        report "";
        report "We provide JMP 0x1234 instruction (opcode 0x44).";
        report "JMP has 3 cycles: CYCLE 0 (opcode), CYCLE 1 (low byte), CYCLE 2 (high byte).";
        report "";
        report "Expected per datasheet:";
        report "  CYCLE 0 T1: PCL=0x00 (opcode at addr 0x00), PC increments to 0x01";
        report "  CYCLE 1 T1: PCL=0x01 (low byte at addr 0x01), PC increments to 0x02";
        report "  CYCLE 2 T1: PCL=0x02 (high byte at addr 0x02), PC increments to 0x03";
        report "";

        -- Assert reset
        reset <= '1';
        INT <= '0';
        wait for 200 ns;

        -- Release reset
        reset <= '0';
        wait for 10 ns;

        -- Assert INT to boot CPU from STOPPED state (needs rising edge)
        INT <= '1';
        report "INT asserted - CPU should boot with interrupt...";
        report "";

        -- Wait for CPU to acknowledge interrupt and start running
        wait for 20 us;
        INT <= '0';
        report "INT cleared";
        report "";

        -- Wait for captures to complete (need at least 3 for the JMP instruction)
        wait until capture_count >= 3;
        wait for 100 ns;

        -- Analyze results
        report "========================================";
        report "Test Results - JMP Instruction Cycles";
        report "========================================";
        report "";

        passed := true;

        -- Check the first 3 captures (should be CYCLE 0, 1, 2 of JMP instruction)
        for i in 0 to 2 loop
            report "JMP CYCLE " & integer'image(i) & " T1: PCL = 0x" &
                   to_hstring(unsigned(captured_pc_values(i)(7 downto 0)));

            -- Expected values: 0x00, 0x01, 0x02
            if captured_pc_values(i)(7 downto 0) /= std_logic_vector(to_unsigned(i, 8)) then
                report "  ERROR: Expected PCL=0x" & to_hstring(to_unsigned(i, 8)) &
                       " but got 0x" & to_hstring(unsigned(captured_pc_values(i)(7 downto 0)))
                       severity error;
                passed := false;
            else
                report "  OK: PCL matches expected value 0x" & to_hstring(to_unsigned(i, 8));
            end if;
        end loop;

        test_passed <= passed;
        wait for 1 ns;  -- Let test_passed signal update

        report "";
        report "========================================";
        if passed then
            report "*** TEST PASSED ***";
            report "";
            report "PC correctly increments between cycles of the JMP instruction.";
            report "Each cycle's T1 shows the incremented PC value as expected.";
        else
            report "*** TEST FAILED ***" severity error;
            report "";
            report "Bug confirmed: PC value on data bus during T1 does not increment";
            report "correctly between cycles of a multi-cycle instruction.";
            report "";
            report "Per datasheet: 'The program counter is incremented immediately";
            report "after the lower order address bits are sent out.'";
            report "";
            report "This means each cycle's T1 should show an incremented PC value,";
            report "but v8008 is not incrementing correctly between cycles.";
        end if;
        report "========================================";

        test_complete <= true;
        wait;
    end process;

    -- Timeout watchdog
    process
    begin
        wait for 500 us;
        if not test_complete then
            report "*** TEST TIMEOUT ***" severity error;
            std.env.stop;
        end if;
        wait;
    end process;

end architecture test;

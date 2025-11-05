--------------------------------------------------------------------------------
-- Intel 8008 Interrupt System Testbench
--------------------------------------------------------------------------------
-- Purpose: Comprehensive test of 8008 interrupt mechanism
-- Tests:
--   1. T1/T1I mutual exclusivity
--   2. Mid-instruction interrupt rejection
--   3. PC preservation during interrupt
--   4. Complete interrupt flow with RST injection
--
-- This testbench WILL FAIL with v1.0 implementation to expose bugs.
-- It should PASS after fixes are applied.
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity s8008_interrupt_tb is
end s8008_interrupt_tb;

architecture behavior of s8008_interrupt_tb is

    -- Component declaration for the Unit Under Test (UUT)
    component s8008
        port (
            phi1 : in std_logic;
            phi2 : in std_logic;
            SYNC : out std_logic;
            READY : in std_logic;
            INT : in std_logic;
            data_bus : inout std_logic_vector(7 downto 0);
            S0 : out std_logic;
            S1 : out std_logic;
            S2 : out std_logic;
            reset_n : in std_logic
        );
    end component;

    -- Testbench signals
    signal phi1 : std_logic := '0';
    signal phi2 : std_logic := '0';
    signal SYNC : std_logic;
    signal READY : std_logic := '1';
    signal INT : std_logic := '0';
    signal data_bus : std_logic_vector(7 downto 0);
    signal S0, S1, S2 : std_logic;
    signal reset_n : std_logic := '0';

    -- Clock period
    constant phi1_period : time := 500 ns;  -- 1 MHz clock
    constant phi2_period : time := 500 ns;

    -- Memory for test program and interrupt handlers
    type memory_array is array(0 to 16383) of std_logic_vector(7 downto 0);
    signal memory : memory_array := (others => X"00");

    -- Test control
    signal test_running : boolean := true;
    signal mem_enable : std_logic := '1';  -- Enable memory bus drive
    signal inject_rst : std_logic := '0';  -- Interrupt controller RST injection flag
    signal rst_opcode : std_logic_vector(7 downto 0) := X"00";  -- RST opcode to inject

    -- State tracking for debugging
    signal state_code : std_logic_vector(2 downto 0);
    signal prev_state_code : std_logic_vector(2 downto 0) := "000";
    signal t1i_detected : boolean := false;
    signal t1_before_t1i : boolean := false;  -- BUG DETECTOR!

    -- PC tracking (reconstructed from bus)
    signal pc_low : std_logic_vector(7 downto 0) := X"00";
    signal pc_high : std_logic_vector(5 downto 0) := "000000";
    signal pc_full : unsigned(13 downto 0) := (others => '0');

    -- Cycle counting
    signal cycle_count : integer := 0;

    -- Test phase control
    type test_phase_type is (
        INIT,
        TEST1_SETUP,      -- T1/T1I mutual exclusivity
        TEST1_INTERRUPT,
        TEST1_VERIFY,
        TEST2_SETUP,      -- Mid-instruction interrupt rejection
        TEST2_INTERRUPT,
        TEST2_VERIFY,
        TEST3_SETUP,      -- PC preservation
        TEST3_INTERRUPT,
        TEST3_VERIFY,
        TEST4_SETUP,      -- Complete interrupt flow
        TEST4_INTERRUPT,
        TEST4_VERIFY,
        TESTS_COMPLETE
    );
    signal test_phase : test_phase_type := INIT;

begin

    -- Instantiate the Unit Under Test (UUT)
    uut: s8008
        port map (
            phi1 => phi1,
            phi2 => phi2,
            SYNC => SYNC,
            READY => READY,
            INT => INT,
            data_bus => data_bus,
            S0 => S0,
            S1 => S1,
            S2 => S2,
            reset_n => reset_n
        );

    -- State code tracking
    state_code <= S2 & S1 & S0;

    -- Clock generation
    phi1_process: process
    begin
        while test_running loop
            phi1 <= '0';
            wait for phi1_period/2;
            phi1 <= '1';
            wait for phi1_period/2;
        end loop;
        wait;
    end process;

    phi2_process: process
    begin
        wait for phi1_period/4;  -- Phase shift phi2 by 90 degrees
        while test_running loop
            phi2 <= '0';
            wait for phi2_period/2;
            phi2 <= '1';
            wait for phi2_period/2;
        end loop;
        wait;
    end process;

    -- Initialize memory with test programs
    memory_init: process
    begin
        -- RST 0 handler at 0x0000
        memory(16#0000#) <= X"06";  -- MVI A, 0xA0
        memory(16#0001#) <= X"A0";
        memory(16#0002#) <= X"07";  -- RET
        memory(16#0003#) <= X"00";  -- NOP (padding)
        memory(16#0004#) <= X"00";  -- NOP
        memory(16#0005#) <= X"00";  -- NOP
        memory(16#0006#) <= X"00";  -- NOP
        memory(16#0007#) <= X"00";  -- NOP

        -- RST 1 handler at 0x0008
        memory(16#0008#) <= X"06";  -- MVI A, 0xA1
        memory(16#0009#) <= X"A1";
        memory(16#000A#) <= X"07";  -- RET
        memory(16#000B#) <= X"00";  -- NOP
        memory(16#000C#) <= X"00";  -- NOP
        memory(16#000D#) <= X"00";  -- NOP
        memory(16#000E#) <= X"00";  -- NOP
        memory(16#000F#) <= X"00";  -- NOP

        -- RST 2 handler at 0x0010
        memory(16#0010#) <= X"06";  -- MVI A, 0xA2
        memory(16#0011#) <= X"A2";
        memory(16#0012#) <= X"07";  -- RET
        memory(16#0013#) <= X"00";  -- NOP
        memory(16#0014#) <= X"00";  -- NOP
        memory(16#0015#) <= X"00";  -- NOP
        memory(16#0016#) <= X"00";  -- NOP
        memory(16#0017#) <= X"00";  -- NOP

        -- Test 1 Program at 0x0100: Simple NOP sequence for T1/T1I test
        memory(16#0100#) <= X"00";  -- NOP
        memory(16#0101#) <= X"00";  -- NOP
        memory(16#0102#) <= X"00";  -- NOP
        memory(16#0103#) <= X"00";  -- NOP
        memory(16#0104#) <= X"FF";  -- HLT

        -- Test 2 Program at 0x0120: Multi-byte instruction for mid-instruction test
        memory(16#0120#) <= X"06";  -- MVI A, 0x42
        memory(16#0121#) <= X"42";
        memory(16#0122#) <= X"00";  -- NOP
        memory(16#0123#) <= X"00";  -- NOP
        memory(16#0124#) <= X"FF";  -- HLT

        -- Test 3 Program at 0x0140: PC preservation test
        memory(16#0140#) <= X"00";  -- NOP
        memory(16#0141#) <= X"00";  -- NOP
        memory(16#0142#) <= X"00";  -- NOP  <-- Interrupt here, should return here
        memory(16#0143#) <= X"00";  -- NOP
        memory(16#0144#) <= X"FF";  -- HLT

        -- Test 4 Program at 0x0160: Complete interrupt flow test
        memory(16#0160#) <= X"06";  -- MVI A, 0x99
        memory(16#0161#) <= X"99";
        memory(16#0162#) <= X"00";  -- NOP  <-- Interrupt here
        memory(16#0163#) <= X"00";  -- NOP
        memory(16#0164#) <= X"FF";  -- HLT

        wait;
    end process;

    -- Address capture process (clocked)
    addr_capture: process(phi2)
        variable addr_low : unsigned(7 downto 0);
        variable addr_high : unsigned(5 downto 0);
        variable full_addr : integer;
    begin
        if rising_edge(phi2) then
            -- Capture during T1 or T1I (both output PC low byte)
            if (SYNC = '1' and state_code = "000") or state_code = "001" then  -- T1 or T1I
                -- Capture address low byte from data bus
                pc_low <= data_bus;
                addr_low := unsigned(data_bus);
            end if;

            if state_code = "010" then  -- T2
                -- Capture address high bits
                pc_high <= data_bus(5 downto 0);
                pc_full <= unsigned(data_bus(5 downto 0)) & unsigned(pc_low);
                addr_high := unsigned(data_bus(5 downto 0));

                -- Compute full address for memory access
                full_addr := to_integer(addr_high & addr_low);
            end if;
        end if;
    end process;

    -- Memory bus driver (combinatorial, but no feedback loop)
    mem_bus_driver: process(state_code, inject_rst, rst_opcode, pc_full)
        variable addr : integer;
    begin
        -- Compute address from registered pc_full
        addr := to_integer(pc_full);

        if inject_rst = '1' then
            -- Interrupt controller is injecting RST instruction
            if state_code = "100" then  -- T3
                data_bus <= rst_opcode;
            else
                data_bus <= (others => 'Z');
            end if;
        elsif state_code = "100" then  -- T3: drive data for reads
            -- Normal memory read
            data_bus <= memory(addr);
        else
            data_bus <= (others => 'Z');
        end if;
    end process;

    -- State change detector (for T1/T1I bug detection)
    state_monitor: process(phi1)
    begin
        if rising_edge(phi1) then
            prev_state_code <= state_code;

            -- Detect T1I
            if state_code = "001" then
                t1i_detected <= true;
                report "T1I detected at time " & time'image(now);

                -- BUG CHECK: Was the previous state T1?
                if prev_state_code = "000" and SYNC = '1' then
                    t1_before_t1i <= true;
                    report "*** BUG DETECTED: T1 occurred before T1I! ***" severity error;
                end if;
            end if;

            -- Count cycles for debugging
            if SYNC = '1' then
                cycle_count <= cycle_count + 1;
            end if;
        end if;
    end process;

    -- Interrupt controller model
    interrupt_controller: process
    begin
        -- Wait for testbench to trigger interrupt injection
        wait until inject_rst = '1';

        report "Interrupt controller: Waiting for T1I acknowledge...";

        -- Wait for T1I (state = 001)
        wait until state_code = "001" and rising_edge(phi1);
        report "Interrupt controller: T1I acknowledged";

        -- Wait for next PCI cycle (state = 000, SYNC = '1')
        wait until state_code = "000" and SYNC = '1' and rising_edge(phi1);
        report "Interrupt controller: Next PCI detected, will inject on T3";

        -- Continue injection during this cycle
        -- (inject_rst is controlled by test stimulus process)

        wait;
    end process;

    -- Test stimulus and verification
    stim_proc: process
        variable pc_before_int : unsigned(13 downto 0);
    begin
        -- Reset
        reset_n <= '0';
        INT <= '0';
        test_phase <= INIT;
        wait for phi1_period * 4;
        reset_n <= '1';
        wait for phi1_period * 2;

        report "========================================";
        report "Starting Interrupt Tests";
        report "========================================";

        -----------------------------------------------------------------------
        -- TEST 1: T1/T1I Mutual Exclusivity
        -----------------------------------------------------------------------
        report " ";
        report "TEST 1: T1/T1I Mutual Exclusivity";
        report "-----------------------------------";
        test_phase <= TEST1_SETUP;

        -- Program starts at 0x0000, let it execute a few NOPs
        -- Wait until we're at 0x0100 (first test program)
        wait for phi1_period * 10;  -- Let reset sequence complete

        -- Manually load PC to 0x0100 by waiting for specific cycles
        -- In real test, we'd jump here, but for simplicity, wait for NOP execution
        wait for phi1_period * 20;

        test_phase <= TEST1_INTERRUPT;

        -- Assert interrupt
        report "Asserting INT signal...";
        INT <= '1';

        -- Wait for interrupt to be recognized (should see T1I without prior T1)
        wait for phi1_period * 10;

        test_phase <= TEST1_VERIFY;

        -- Check results
        if t1_before_t1i then
            report "TEST 1 FAILED: T1 occurred before T1I (mutual exclusivity violated)" severity error;
        else
            report "TEST 1 PASSED: T1I occurred without prior T1";
        end if;

        -- Deassert interrupt
        INT <= '0';
        wait for phi1_period * 10;

        -----------------------------------------------------------------------
        -- TEST 2: Mid-Instruction Interrupt Rejection
        -----------------------------------------------------------------------
        report " ";
        report "TEST 2: Mid-Instruction Interrupt Rejection";
        report "---------------------------------------------";
        test_phase <= TEST2_SETUP;

        -- Reset to start fresh
        reset_n <= '0';
        wait for phi1_period * 2;
        reset_n <= '1';
        wait for phi1_period * 2;

        -- Wait for multi-byte instruction (MVI) to begin
        wait for phi1_period * 10;

        test_phase <= TEST2_INTERRUPT;

        -- Assert interrupt during immediate byte fetch (WRONG timing for interrupt)
        report "Asserting INT during multi-byte instruction...";
        INT <= '1';

        -- Wait and observe
        wait for phi1_period * 20;

        test_phase <= TEST2_VERIFY;

        -- If implementation is correct, interrupt should NOT trigger during immediate fetch
        -- If buggy, we'll see T1I during immediate fetch
        -- This requires monitoring microcode_state which isn't exposed
        -- For now, we'll note that this test needs internal signal access
        report "TEST 2: Requires microcode_state monitoring (not implemented in this version)";

        INT <= '0';
        wait for phi1_period * 10;

        -----------------------------------------------------------------------
        -- TEST 3: PC Preservation
        -----------------------------------------------------------------------
        report " ";
        report "TEST 3: PC Preservation During Interrupt";
        report "------------------------------------------";
        test_phase <= TEST3_SETUP;

        -- Reset
        reset_n <= '0';
        wait for phi1_period * 2;
        reset_n <= '1';
        wait for phi1_period * 2;

        -- Wait for MVI instruction to complete
        wait for phi1_period * 6;

        -- Assert interrupt early
        INT <= '1';

        test_phase <= TEST3_INTERRUPT;

        -- Wait for the T1 cycle before interrupt occurs
        -- This will be the FETCH of the RET instruction at 0x0002
        wait until state_code = "000" and SYNC = '1' and rising_edge(phi1);  -- T1
        -- Wait for T2 to capture full address
        wait until state_code = "010" and rising_edge(phi1);  -- T2
        wait for phi1_period * 0.5;  -- Let pc_full update

        -- Capture PC of the cycle that's about to be interrupted
        pc_before_int := pc_full;
        report "PC of cycle about to be interrupted: 0x" & to_hstring(pc_before_int);

        -- Wait for T1I
        wait until state_code = "001" and rising_edge(phi1);
        report "T1I detected at time " & time'image(now);
        report "  Data bus during T1I (PC low): 0x" & to_hstring(unsigned(data_bus));

        -- Wait for the T2 after T1I to complete address output
        wait until state_code = "010" and rising_edge(phi1);
        report "T2 after T1I detected, checking PC value...";
        report "  Data bus during T2 (PC high): 0x" & to_hstring(unsigned(data_bus(5 downto 0)));

        -- Wait one more cycle for pc_full to be updated
        wait for phi1_period * 1;

        -- PC should still be the same
        if pc_full /= pc_before_int then
            report "TEST 3 FAILED: PC changed during T1I (was 0x" &
                   to_hstring(pc_before_int) & ", now 0x" & to_hstring(pc_full) & ")" severity error;
        else
            report "TEST 3 PASSED: PC preserved during T1I (PC = 0x" & to_hstring(pc_full) & ")";
        end if;

        test_phase <= TEST3_VERIFY;
        INT <= '0';
        wait for phi1_period * 10;

        -----------------------------------------------------------------------
        -- TEST 4: Complete Interrupt Flow with RST Injection
        -----------------------------------------------------------------------
        report " ";
        report "TEST 4: Complete Interrupt Flow";
        report "---------------------------------";
        test_phase <= TEST4_SETUP;

        -- Reset
        reset_n <= '0';
        wait for phi1_period * 2;
        reset_n <= '1';
        wait for phi1_period * 2;

        -- Wait for program execution
        wait for phi1_period * 15;

        test_phase <= TEST4_INTERRUPT;

        -- Trigger interrupt and inject RST 1
        report "Triggering interrupt with RST 1 injection...";
        rst_opcode <= X"0D";  -- RST 1
        INT <= '1';
        inject_rst <= '1';

        -- Wait for interrupt sequence
        wait for phi1_period * 50;

        test_phase <= TEST4_VERIFY;

        -- Note: Full verification requires register inspection (not exposed in ports)
        report "TEST 4: Complete flow test executed (full verification requires internal access)";

        INT <= '0';
        inject_rst <= '0';

        -----------------------------------------------------------------------
        -- Tests Complete
        -----------------------------------------------------------------------
        test_phase <= TESTS_COMPLETE;

        report " ";
        report "========================================";
        report "Interrupt Tests Complete";
        report "========================================";
        report " ";
        report "Summary:";
        report "  - These tests are designed to FAIL with v1.0 implementation";
        report "  - They will PASS after bugs are fixed";
        report "  - Additional internal signal monitoring needed for complete verification";

        wait for phi1_period * 10;
        test_running <= false;
        wait;
    end process;

end behavior;

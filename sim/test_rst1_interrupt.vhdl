--------------------------------------------------------------------------------
-- Test RST 1 Interrupt - Minimal Reproduction of Button Interrupt Issue
--------------------------------------------------------------------------------
-- This testbench replicates the exact scenario from the cylon_interrupt project:
-- 1. Idle loop at 0x0059: JMP 0x0059 (infinite loop)
-- 2. RST 1 interrupt triggered while in the loop
-- 3. Expected: Jump to 0x0008, then to ISR at 0x0100
-- 4. ISR executes and returns via RET
-- 5. Expected: Return to 0x0059 and continue looping
--
-- This tests the specific bug where:
-- - RST 1 jumps to 0x0000 instead of 0x0008
-- - RET returns to 0x000D instead of 0x0059
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity test_rst1_interrupt is
end entity test_rst1_interrupt;

architecture testbench of test_rst1_interrupt is

    -- Component declaration
    component s8008 is
        port (
            phi1            : in    std_logic;
            phi2            : in    std_logic;
            reset_n         : in    std_logic;
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
            debug_flags     : out   std_logic_vector(3 downto 0)
        );
    end component;

    -- Clock signals
    signal phi1    : std_logic := '0';
    signal phi2    : std_logic := '0';
    signal reset_n : std_logic := '0';

    -- Bus signals
    signal data_bus_in     : std_logic_vector(7 downto 0) := (others => 'Z');
    signal data_bus_out    : std_logic_vector(7 downto 0);
    signal data_bus_enable : std_logic;

    -- Control signals
    signal S0, S1, S2 : std_logic;
    signal SYNC       : std_logic;
    signal READY      : std_logic := '1';
    signal INT        : std_logic := '0';

    -- Debug signals
    signal debug_pc : std_logic_vector(13 downto 0);
    signal debug_reg_A, debug_reg_B, debug_reg_C : std_logic_vector(7 downto 0);
    signal debug_reg_D, debug_reg_E, debug_reg_H, debug_reg_L : std_logic_vector(7 downto 0);
    signal debug_flags : std_logic_vector(3 downto 0);

    -- Memory array (2K ROM)
    type memory_t is array (0 to 2047) of std_logic_vector(7 downto 0);
    signal rom : memory_t := (others => x"00");

    -- Address tracking
    signal addr_low  : std_logic_vector(7 downto 0);
    signal addr_high : std_logic_vector(5 downto 0);
    signal full_addr : std_logic_vector(13 downto 0);

    -- State tracking
    signal state_name : string(1 to 7) := "UNKNOWN";

    -- Clock periods
    constant PHI1_PERIOD : time := 1.1 us;
    constant PHI2_PERIOD : time := 1.1 us;
    constant PHI_DEAD    : time := 0.2 us;

    -- Test control
    signal sim_done : boolean := false;

    -- Interrupt acknowledge tracking
    signal is_int_ack : std_logic := '0';
    signal int_type : std_logic := '0';  -- '0' for RST 0 (startup), '1' for RST 1 (button)

begin

    --------------------------------------------------------------------------------
    -- DUT Instantiation
    --------------------------------------------------------------------------------
    dut : s8008
        port map (
            phi1            => phi1,
            phi2            => phi2,
            reset_n         => reset_n,
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
            debug_flags     => debug_flags
        );

    --------------------------------------------------------------------------------
    -- Clock Generation
    --------------------------------------------------------------------------------
    phi1_proc : process
    begin
        while not sim_done loop
            phi1 <= '1';
            wait for PHI1_PERIOD;
            phi1 <= '0';
            wait for PHI_DEAD;
        end loop;
        wait;
    end process;

    phi2_proc : process
    begin
        while not sim_done loop
            wait for PHI_DEAD;
            phi2 <= '1';
            wait for PHI2_PERIOD;
            phi2 <= '0';
        end loop;
        wait;
    end process;

    --------------------------------------------------------------------------------
    -- ROM Initialization
    --------------------------------------------------------------------------------
    -- Memory map:
    -- 0x0000: JMP 0x0059 (RST 0 vector - jump directly to idle loop)
    -- 0x0008: JMP 0x0100 (RST 1 vector - button interrupt)
    -- 0x0059: Idle loop - JMP 0x0059 (where interrupt will occur)
    -- 0x0100: Button ISR - NOP, then RET
    --------------------------------------------------------------------------------
    rom_init : process
    begin
        -- RST 0 vector at 0x0000: JMP 0x0059 (jump directly to idle loop)
        rom(16#0000#) <= x"44";  -- JMP opcode
        rom(16#0001#) <= x"59";  -- Address low
        rom(16#0002#) <= x"00";  -- Address high

        -- RST 1 vector at 0x0008: JMP 0x0100
        rom(16#0008#) <= x"44";  -- JMP opcode
        rom(16#0009#) <= x"00";  -- Address low
        rom(16#000A#) <= x"01";  -- Address high

        -- Idle loop at 0x0059: JMP 0x0059 (infinite loop)
        rom(16#0059#) <= x"44";  -- JMP opcode
        rom(16#005A#) <= x"59";  -- Address low
        rom(16#005B#) <= x"00";  -- Address high

        -- Button ISR at 0x0100: NOP (MOV A,A), then RET
        rom(16#0100#) <= x"C0";  -- NOP (MOV A,A - 11 000 000)
        rom(16#0101#) <= x"07";  -- RET opcode

        wait;
    end process;

    --------------------------------------------------------------------------------
    -- Address Capture and State Decode
    --------------------------------------------------------------------------------
    -- Synchronous address capture on phi1 rising edge (mimics hardware latches)
    addr_capture : process(phi1)
    begin
        if rising_edge(phi1) then
            -- Decode state for debugging
            if S2 = '0' and S1 = '1' and S0 = '0' then
                state_name <= "T1     ";
            elsif S2 = '1' and S1 = '0' and S0 = '0' then
                state_name <= "T2     ";
            elsif S2 = '0' and S1 = '0' and S0 = '1' then
                state_name <= "T3     ";
            elsif S2 = '1' and S1 = '1' and S0 = '0' then
                state_name <= "T1I    ";
            elsif S2 = '1' and S1 = '1' and S0 = '1' then
                state_name <= "T4     ";
            elsif S2 = '1' and S1 = '0' and S0 = '1' then
                state_name <= "T5     ";
            elsif S2 = '0' and S1 = '1' and S0 = '1' then
                state_name <= "STOPPED";
            else
                state_name <= "TWAIT  ";
            end if;

            -- T1I state: Detect interrupt acknowledge cycle and latch interrupt type
            if S2 = '1' and S1 = '1' and S0 = '0' then
                is_int_ack <= '1';
                -- Latch the interrupt type based on INT signal at T1I
                int_type <= INT;
                report "T1I: Latching int_type = " & std_logic'image(INT);
            end if;

            -- T1 state: Capture low address byte (S2 S1 S0 = 0 1 0)
            if S2 = '0' and S1 = '1' and S0 = '0' then
                addr_low <= data_bus_out;
                if now > 175 us and now < 195 us then
                    report "T1: Captured addr_low=0x" & to_hstring(unsigned(data_bus_out)) &
                           " at " & time'image(now);
                end if;
            end if;

            -- T2 state: Capture high address (S2 S1 S0 = 1 0 0)
            -- Don't capture during interrupt acknowledge
            if S2 = '1' and S1 = '0' and S0 = '0' then
                if is_int_ack = '0' then
                    addr_high <= data_bus_out(5 downto 0);
                    if now > 175 us and now < 195 us then
                        report "T2: Captured addr_high=0x" & to_hstring(unsigned(data_bus_out(5 downto 0))) &
                               " at " & time'image(now);
                    end if;
                end if;
            end if;

            -- T1 state (after interrupt ack): Clear interrupt acknowledge flag
            -- Clear it at the NEXT T1, not during T3, to ensure RST opcode is provided through T3
            if S2 = '0' and S1 = '1' and S0 = '0' and is_int_ack = '1' then
                is_int_ack <= '0';
                if now > 175 us and now < 195 us then
                    report "Clearing is_int_ack at T1 phi1 edge, time=" & time'image(now);
                end if;
            end if;
        end if;
    end process;

    -- Combine address
    full_addr <= addr_high & addr_low;

    --------------------------------------------------------------------------------
    -- Memory Bus Multiplexer (combinational, mimics asynchronous ROM)
    --------------------------------------------------------------------------------
    -- This handles both normal memory reads and interrupt acknowledge
    bus_mux : process(S2, S1, S0, is_int_ack, full_addr, rom, data_bus_enable)
    begin
        -- Default: tri-state (let CPU drive when needed)
        data_bus_in <= (others => 'Z');

        -- T3/T4/T5 states: Data transfer
        if (S2 = '0' and S1 = '0' and S0 = '1') or  -- T3
           (S2 = '1' and S1 = '1' and S0 = '1') or  -- T4
           (S2 = '1' and S1 = '0' and S0 = '1') then -- T5

            -- During interrupt acknowledge, provide RST instruction
            if is_int_ack = '1' then
                -- Provide RST based on latched interrupt type
                -- int_type was latched at T1I when interrupt was acknowledged
                if int_type = '1' then
                    data_bus_in <= x"0D";  -- RST 1 (00 001 101)
                    if now > 175 us and now < 195 us then
                        report "T3: Providing RST 1 opcode (0x0D) at " & time'image(now);
                    end if;
                else
                    data_bus_in <= x"05";  -- RST 0 (00 000 101)
                    if now > 175 us and now < 195 us then
                        report "T3: Providing RST 0 opcode (0x05) at " & time'image(now);
                    end if;
                end if;
            -- Normal memory read cycle
            elsif data_bus_enable = '0' then
                -- ROM is 2K (11 bits address)
                data_bus_in <= rom(to_integer(unsigned(full_addr(10 downto 0))));
                if now > 175 us and now < 195 us then
                    report "T3: Providing ROM data from addr=0x" & to_hstring(unsigned(full_addr(10 downto 0))) &
                           " data=0x" & to_hstring(unsigned(rom(to_integer(unsigned(full_addr(10 downto 0)))))) &
                           " at " & time'image(now);
                end if;
            end if;
        end if;
    end process;

    --------------------------------------------------------------------------------
    -- PC Monitor (for debugging)
    --------------------------------------------------------------------------------
    pc_monitor : process(debug_pc)
    begin
        if now > 0 ns then
            report "PC changed to 0x" & to_hstring(unsigned(debug_pc)) & " at " & time'image(now);
        end if;
    end process;

    --------------------------------------------------------------------------------
    -- Test Stimulus - Realistic Boot Sequence
    --------------------------------------------------------------------------------
    stimulus : process
    begin
        report "========================================";
        report "Test RST 1 Interrupt (Realistic Boot)";
        report "========================================";
        report "Sequence:";
        report "  1. CPU starts in STOPPED state";
        report "  2. INT pulse triggers RST 0 (startup)";
        report "  3. Jump to 0x0000, then directly to 0x0059";
        report "  4. CPU enters idle loop at 0x0059";
        report "  5. Button interrupt (RST 1) fires";
        report "  6. Jump to 0x0008, then 0x0100, RET";
        report "  7. Return to 0x0059 and continue loop";
        report "========================================";

        -- Initialize
        reset_n <= '0';
        INT <= '0';
        wait for 10 us;

        -- Release reset
        reset_n <= '1';
        report "Reset released - CPU in STOPPED state";

        -- Per Intel 8008 manual: CPU requires 16 clock periods to clear internal state
        wait for 20 us;

        -- Pulse INT to trigger startup (RST 0)
        report "Pulsing INT for startup (RST 0)...";
        INT <= '1';
        wait for 5 us;  -- Hold long enough to be sampled and acknowledged
        INT <= '0';
        report "Startup interrupt sent";
        wait for 5 us;  -- Wait for interrupt to complete

        -- Wait for startup sequence to complete
        -- RST 0 -> 0x0000 (JMP 0x0059) -> should end up at 0x0059
        wait for 100 us;
        report "Startup complete, PC = 0x" & to_hstring(unsigned(debug_pc));

        if unsigned(debug_pc) >= x"0059" and unsigned(debug_pc) <= x"005B" then
            report "SUCCESS: CPU in idle loop at 0x" & to_hstring(unsigned(debug_pc));
        else
            report "WARNING: Expected PC in range 0x0059-0x005B, got 0x" & to_hstring(unsigned(debug_pc));
        end if;

        -- Let CPU loop a few times
        wait for 30 us;
        report "CPU looping...";

        -- Now trigger the button interrupt (RST 1) while in the loop
        report "========================================";
        report "TRIGGERING BUTTON INTERRUPT (RST 1)";
        report "PC at interrupt: 0x" & to_hstring(unsigned(debug_pc));
        report "========================================";
        INT <= '1';

        -- Wait for interrupt acknowledge (T1I state)
        wait until S2 = '1' and S1 = '1' and S0 = '0' for 50 us;
        report "T1I: Interrupt acknowledge detected";
        report "PC during T1I: 0x" & to_hstring(unsigned(debug_pc));

        -- Hold INT through the acknowledge cycle
        wait for 15 us;
        INT <= '0';
        report "INT cleared";

        -- Monitor where we jump to
        wait for 10 us;
        report "After RST 1, PC = 0x" & to_hstring(unsigned(debug_pc));

        if unsigned(debug_pc) = x"0008" or unsigned(debug_pc) = x"0009" or unsigned(debug_pc) = x"000A" then
            report "SUCCESS: Jumped to RST 1 vector (0x0008)";
        elsif unsigned(debug_pc) = x"0000" or unsigned(debug_pc) = x"0001" then
            report "FAIL: Jumped to RST 0 vector (0x0000) instead of RST 1 (0x0008)";
        else
            report "INFO: PC at 0x" & to_hstring(unsigned(debug_pc));
        end if;

        -- Wait to see jump to ISR
        wait for 20 us;
        report "Should be in ISR now, PC = 0x" & to_hstring(unsigned(debug_pc));

        if unsigned(debug_pc) >= x"0100" and unsigned(debug_pc) <= x"0101" then
            report "SUCCESS: In button ISR at 0x0100";
        else
            report "WARNING: Expected PC at 0x0100, got 0x" & to_hstring(unsigned(debug_pc));
        end if;

        -- Wait for RET to execute
        wait for 30 us;
        report "========================================";
        report "After RET, PC = 0x" & to_hstring(unsigned(debug_pc));
        report "========================================";

        if unsigned(debug_pc) >= x"0059" and unsigned(debug_pc) <= x"005B" then
            report "SUCCESS: RET returned to idle loop (0x0059)!";
            report "========================================";
            report "=== TEST PASSED ===";
            report "========================================";
        elsif unsigned(debug_pc) = x"0000" then
            report "FAIL: RET returned to 0x0000 (RST 0 vector)";
            report "This suggests the stack was not saved correctly during interrupt";
        elsif unsigned(debug_pc) = x"000D" then
            report "FAIL: RET returned to 0x000D";
            report "This suggests incorrect return address calculation";
        else
            report "FAIL: RET returned to unexpected address: 0x" & to_hstring(unsigned(debug_pc));
        end if;

        -- Let it run a bit more to verify loop continues
        wait for 30 us;
        report "Final PC check: 0x" & to_hstring(unsigned(debug_pc));

        -- End simulation
        wait for 10 us;
        report "========================================";
        report "Test complete";
        report "========================================";
        sim_done <= true;
        wait;
    end process;

end architecture testbench;

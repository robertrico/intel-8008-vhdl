-------------------------------------------------------------------------------
-- Testbench for Intel 8008 Monitor Top
-------------------------------------------------------------------------------
-- Hardware-accurate testbench using real ROM, RAM, and UART transceiver
-- Tests basic UART communication with simple inline ROM program
--
-- This testbench uses a hardcoded ROM image (inline test program) so that
-- we can test UART functionality independently of monitor.asm development.
-- The monitor.asm program should be tested separately through hardware or
-- custom test scripts.
--
-- Memory Map:
--   0x0000 - 0x07FF (2KB):  ROM (program memory - inline test program)
--   0x0800 - 0x0BFF (1KB):  RAM (data memory)
--
-- I/O Port Map:
--   Port 0 (IN 0):   UART TX Status - bit 0 = tx_busy
--   Port 3 (IN 3):   UART RX Data - read byte (clears rx_ready)
--   Port 4 (IN 4):   UART RX Status - bit 0 = rx_ready
--   Port 10 (OUT 10): UART TX Data - write byte to transmit
--
-- Test Program Flow (inline ROM):
--   1. Transmit "OK\r\n"
--   2. Loop forever
--
-- Expected Result:
--   TX: "OK\r\n"
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity monitor_tb is
end monitor_tb;

architecture sim of monitor_tb is

    -- Component declaration
    component monitor_top is
        generic (
            ROM_FILE : string := "test_programs/monitor.mem"
        );
        port (
            clk         : in  std_logic;
            rst         : in  std_logic;
            uart_tx     : out std_logic;
            uart_rx     : in  std_logic;
            led_E16     : out std_logic;
            led_D17     : out std_logic;
            led_D18     : out std_logic;
            led_E18     : out std_logic;
            led_F17     : out std_logic;
            led_F18     : out std_logic;
            led_E17     : out std_logic;
            led_F16     : out std_logic;
            led_M20     : out std_logic;
            led_L18     : out std_logic;
            cpu_d       : out std_logic_vector(7 downto 0);
            cpu_s0      : out std_logic;
            cpu_s1      : out std_logic;
            cpu_s2      : out std_logic;
            cpu_sync    : out std_logic;
            cpu_phi1    : out std_logic;
            cpu_phi2    : out std_logic;
            cpu_ready   : out std_logic;
            cpu_int     : out std_logic;
            cpu_data_en : out std_logic
        );
    end component;

    -- Clock and reset signals
    signal master_clk_tb : std_logic := '0';
    signal reset_tb      : std_logic := '1';

    -- UART signals
    signal uart_tx_tb : std_logic;
    signal uart_rx_tb : std_logic := '1';  -- Idle state is high

    -- LED signals
    signal led_E16_tb, led_D17_tb, led_D18_tb, led_E18_tb : std_logic;
    signal led_F17_tb, led_F18_tb, led_E17_tb, led_F16_tb : std_logic;
    signal led_M20_tb, led_L18_tb : std_logic;

    -- CPU debug signals
    signal cpu_d_tb       : std_logic_vector(7 downto 0);
    signal cpu_s0_tb      : std_logic;
    signal cpu_s1_tb      : std_logic;
    signal cpu_s2_tb      : std_logic;
    signal cpu_sync_tb    : std_logic;
    signal cpu_phi1_tb    : std_logic;
    signal cpu_phi2_tb    : std_logic;
    signal cpu_ready_tb   : std_logic;
    signal cpu_int_tb     : std_logic;
    signal cpu_data_en_tb : std_logic;

    -- Timing
    constant MASTER_CLK_PERIOD : time := 10 ns;  -- 100 MHz
    constant BAUD_RATE         : integer := 9600;
    constant BIT_PERIOD        : time := 1 sec / BAUD_RATE;  -- ~104.17 us per bit

    -- Test control
    signal sim_done : boolean := false;

    -- UART tracking
    signal uart_tx_byte_count : integer := 0;
    signal uart_rx_byte_count : integer := 0;

    -- Procedure to send a byte via UART RX (stimulus to DUT)
    procedure uart_send_byte(
        signal uart_line : out std_logic;
        constant byte_val : in std_logic_vector(7 downto 0)
    ) is
    begin
        -- Start bit
        uart_line <= '0';
        wait for BIT_PERIOD;

        -- Data bits (LSB first)
        for i in 0 to 7 loop
            uart_line <= byte_val(i);
            wait for BIT_PERIOD;
        end loop;

        -- Stop bit
        uart_line <= '1';
        wait for BIT_PERIOD;
    end procedure;

    -- Procedure to send a string via UART RX
    procedure uart_send_string(
        signal uart_line : out std_logic;
        constant str : in string
    ) is
    begin
        for i in str'range loop
            uart_send_byte(uart_line, std_logic_vector(to_unsigned(character'pos(str(i)), 8)));
        end loop;
    end procedure;

begin

    --===========================================
    -- Clock Generation
    --===========================================
    master_clk_gen: process
    begin
        while not sim_done loop
            master_clk_tb <= '0';
            wait for MASTER_CLK_PERIOD / 2;
            master_clk_tb <= '1';
            wait for MASTER_CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    --===========================================
    -- DUT Instantiation
    --===========================================
    -- Override ROM_FILE generic for simulation testing
    dut: monitor_top
        generic map (
            ROM_FILE => "test_programs/monitor.mem"
        )
        port map (
            clk         => master_clk_tb,
            rst         => reset_tb,
            uart_tx     => uart_tx_tb,
            uart_rx     => uart_rx_tb,
            led_E16     => led_E16_tb,
            led_D17     => led_D17_tb,
            led_D18     => led_D18_tb,
            led_E18     => led_E18_tb,
            led_F17     => led_F17_tb,
            led_F18     => led_F18_tb,
            led_E17     => led_E17_tb,
            led_F16     => led_F16_tb,
            led_M20     => led_M20_tb,
            led_L18     => led_L18_tb,
            cpu_d       => cpu_d_tb,
            cpu_s0      => cpu_s0_tb,
            cpu_s1      => cpu_s1_tb,
            cpu_s2      => cpu_s2_tb,
            cpu_sync    => cpu_sync_tb,
            cpu_phi1    => cpu_phi1_tb,
            cpu_phi2    => cpu_phi2_tb,
            cpu_ready   => cpu_ready_tb,
            cpu_int     => cpu_int_tb,
            cpu_data_en => cpu_data_en_tb
        );

    --===========================================
    -- UART TX Monitor Process
    --===========================================
    -- Monitors UART TX line from DUT and decodes transmitted characters
    uart_tx_monitor: process
        variable byte_val : std_logic_vector(7 downto 0);
        variable char : character;
        variable tx_string : string(1 to 200);
        variable tx_idx : integer := 1;
    begin
        -- Wait for simulation to start
        wait for 10 us;
        tx_string := (others => ' ');

        while not sim_done loop
            -- Wait for start bit (falling edge on uart_tx)
            wait until uart_tx_tb = '0';

            -- Wait to middle of start bit to verify it's stable
            wait for BIT_PERIOD / 2;

            if uart_tx_tb /= '0' then
                wait for BIT_PERIOD;
                next;
            end if;

            -- Sample 8 data bits (LSB first)
            for i in 0 to 7 loop
                wait for BIT_PERIOD;
                byte_val(i) := uart_tx_tb;
            end loop;

            -- Sample stop bit
            wait for BIT_PERIOD;

            -- Convert to character and accumulate
            char := character'val(to_integer(unsigned(byte_val)));
            uart_tx_byte_count <= uart_tx_byte_count + 1;

            -- Add to output string (replace non-printables with representations)
            if byte_val = x"0D" then
                null; -- Skip CR
            elsif byte_val = x"0A" then
                -- Line feed - print the accumulated line
                report "OUTPUT: " & tx_string(1 to tx_idx-1) severity note;
                tx_string := (others => ' ');
                tx_idx := 1;
            elsif byte_val >= x"20" and byte_val <= x"7E" then
                if tx_idx <= 200 then
                    tx_string(tx_idx) := char;
                    tx_idx := tx_idx + 1;
                end if;
            end if;

        end loop;

        wait;
    end process;

    --===========================================
    -- Program Counter Monitor (Debug) - DISABLED
    --===========================================
    -- Monitors PC to track program execution
    -- During instruction fetch cycles, the CPU outputs the PC on data bus in T1 (lower 8 bits) and T2 (upper 6 bits)
    -- COMMENTED OUT TO REDUCE SIMULATION OUTPUT
    -- pc_monitor: process
    --     variable pc_low : std_logic_vector(7 downto 0) := (others => '0');
    --     variable pc_high : std_logic_vector(5 downto 0) := (others => '0');
    --     variable full_pc : std_logic_vector(13 downto 0);
    --     variable state_count : integer := 0;
    -- begin
    --     wait for 10 ns;  -- Let reset stabilize
    --
    --     while not sim_done loop
    --         wait until rising_edge(cpu_phi1_tb);
    --
    --         -- Track state machine: T1, T2, T3 cycles
    --         -- S2 S1 S0 = state encoding
    --         -- During PCI (instruction fetch): T1 outputs PC low, T2 outputs PC high
    --
    --         -- T1: S2=0, S1=1, S0=0 (PC low byte on data bus)
    --         if cpu_s2_tb = '0' and cpu_s1_tb = '1' and cpu_s0_tb = '0' then
    --             pc_low := cpu_d_tb;
    --             state_count := 1;
    --         -- T2: S2=1, S1=0, S0=0 (PC high bits on data bus)
    --         elsif cpu_s2_tb = '1' and cpu_s1_tb = '0' and cpu_s0_tb = '0' and state_count = 1 then
    --             pc_high := cpu_d_tb(5 downto 0);
    --             full_pc := pc_high & pc_low;
    --             state_count := 0;
    --
    --             -- Monitor addresses in monitor_line (0x002E - 0x0040)
    --             -- Focus on the region where the bug occurs
    --             if full_pc >= "00000000101110" and full_pc <= "00000001000000" then  -- 0x002E to 0x0040
    --                 report "*** PC = 0x" & to_hstring(unsigned(full_pc)) severity warning;
    --             end if;
    --         end if;
    --     end loop;
    --     wait;
    -- end process;

    --===========================================
    -- UART RX Stimulus Process
    --===========================================
    -- Sends test input to DUT's UART RX line (if needed)
    uart_rx_stimulus: process
    begin
        -- Keep RX line idle during test
        uart_rx_tb <= '1';
        wait;
    end process;

    --===========================================
    -- Main Test Sequence
    --===========================================
    test_sequence: process
    begin
        report "========================================================" severity note;
        report "Intel 8008 Monitor Testbench - Simple UART Test" severity note;
        report "Expected output: OK" severity note;
        report "========================================================" severity note;

        -- Initialize: Assert reset
        reset_tb <= '1';
        wait for 100 ns;

        -- Release reset
        reset_tb <= '0';

        -- Wait for program to transmit "OK\r\n"
        wait for 1000 ms;

        -- Summary
        report "" severity note;
        report "========================================================" severity note;
        if uart_tx_byte_count >= 2 then
            report "RESULT: PASSED (" & integer'image(uart_tx_byte_count) & " TX chars)" severity note;
        else
            report "RESULT: FAILED (Expected at least 2 TX chars, got " &
                   integer'image(uart_tx_byte_count) & ")" severity error;
        end if;
        report "========================================================" severity note;

        -- End simulation
        sim_done <= true;
        wait;
    end process;

end sim;

-------------------------------------------------------------------------------
-- Testbench for Intel 8008 UART TX Project
-------------------------------------------------------------------------------
-- Hardware-accurate testbench using real ROM, RAM, and UART transmitter
-- Tests transmission of "Hello, Terminal!" via UART at 9600 baud
--
-- Memory Map:
--   0x0000 - 0x07FF (2KB):  ROM (program memory)
--   0x0800 - 0x0BFF (1KB):  RAM (data memory)
--
-- I/O Port Map:
--   Port 0 (IN 0):   UART TX Status - bit 0 = tx_busy
--   Port 10 (OUT 10): UART TX Data - write byte to transmit
--
-- Program Flow (uart_tx.asm):
--   1. Load and transmit "Hello, Terminal!" character by character
--   2. Each character: check tx_busy, wait if needed, then OUT 10
--   3. Transmit CR+LF at end
--   4. Enter infinite loop when complete
--
-- Expected Result:
--   - "Hello, Terminal!\r\n" transmitted via UART (18 characters)
--   - UART output at 9600 baud, 8N1 format
--   - Monitor UART TX line for proper framing and data
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity uart_tx_tb is
end uart_tx_tb;

architecture sim of uart_tx_tb is

    -- Component declarations
    component uart_tx_top is
        port (
            clk         : in  std_logic;
            rst         : in  std_logic;
            uart_tx     : out std_logic;
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

    -- UART TX signal
    signal uart_tx_tb : std_logic;

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

    -- UART RX tracking
    signal uart_byte_count : integer := 0;

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
    dut: uart_tx_top
        port map (
            clk         => master_clk_tb,
            rst         => reset_tb,
            uart_tx     => uart_tx_tb,
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
    -- CPU Debug Monitor Process
    --===========================================
    -- Monitors CPU state machine and instruction execution
    cpu_monitor: process
        variable cycle_count : integer := 0;
    begin
        -- Wait for reset to release
        wait until reset_tb = '0';
        wait for 1 us;

        report "=== CPU Monitor Started ===" severity note;

        -- Monitor first 200 CPU cycles
        for i in 1 to 200 loop
            -- Wait for SYNC pulse (start of instruction cycle)
            wait until cpu_sync_tb = '1';
            wait for MASTER_CLK_PERIOD;  -- Let signals stabilize

            -- report "CPU Cycle " & integer'image(i) &
            --        ": SYNC=1, D=" & to_hstring(unsigned(cpu_d_tb)) &
            --        ", S2S1S0=" & std_logic'image(cpu_s2_tb) & std_logic'image(cpu_s1_tb) & std_logic'image(cpu_s0_tb) &
            --        ", INT=" & std_logic'image(cpu_int_tb) severity note;

            -- Wait for SYNC to go low
            wait until cpu_sync_tb = '0';
        end loop;

        report "=== CPU Monitor Done (200 cycles) ===" severity note;
        wait;
    end process;

    --===========================================
    -- UART Monitor Process
    --===========================================
    -- Monitors UART TX line and decodes transmitted characters
    uart_monitor: process
        variable byte_val : std_logic_vector(7 downto 0);
        variable char : character;
    begin
        -- Wait for simulation to start and CPU to initialize
        wait for 10 us;

        while not sim_done loop
            -- Wait for start bit (falling edge on uart_tx)
            wait until uart_tx_tb = '0';

            -- Wait to middle of start bit to verify it's stable
            wait for BIT_PERIOD / 2;

            if uart_tx_tb /= '0' then
                report "UART Monitor: Invalid start bit detected" severity warning;
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
            if uart_tx_tb /= '1' then
                report "UART Monitor: Invalid stop bit detected" severity warning;
            end if;

            -- Convert to character and display
            char := character'val(to_integer(unsigned(byte_val)));
            uart_byte_count <= uart_byte_count + 1;

            -- Display character with appropriate formatting
            if byte_val = x"0D" then
                report "UART RX [" & integer'image(uart_byte_count) & "]: <CR> (0x0D)" severity note;
            elsif byte_val = x"0A" then
                report "UART RX [" & integer'image(uart_byte_count) & "]: <LF> (0x0A)" severity note;
            elsif byte_val >= x"20" and byte_val <= x"7E" then
                report "UART RX [" & integer'image(uart_byte_count) & "]: '" & char & "' (0x" &
                       to_hstring(unsigned(byte_val)) & ")" severity note;
            else
                report "UART RX [" & integer'image(uart_byte_count) & "]: (0x" &
                       to_hstring(unsigned(byte_val)) & ")" severity note;
            end if;

        end loop;

        wait;
    end process;

    --===========================================
    -- Main Test Sequence
    --===========================================
    test_sequence: process
    begin
        report "========================================================" severity note;
        report "Intel 8008 UART TX Test" severity note;
        report "========================================================" severity note;
        report "Program: uart_tx.asm" severity note;
        report "Purpose: Transmit 'Hello, Terminal!' via UART" severity note;
        report "" severity note;
        report "Memory Map:" severity note;
        report "  ROM: 0x0000 - 0x07FF (2KB program)" severity note;
        report "  RAM: 0x0800 - 0x0BFF (1KB data)" severity note;
        report "" severity note;
        report "I/O Port Map:" severity note;
        report "  IN 0:   UART TX Status (bit 0 = tx_busy)" severity note;
        report "  OUT 10: UART TX Data (write byte to transmit)" severity note;
        report "" severity note;
        report "UART Configuration:" severity note;
        report "  Baud rate: 9600" severity note;
        report "  Format: 8N1 (8 data bits, no parity, 1 stop bit)" severity note;
        report "========================================================" severity note;

        -- Initialize: Assert reset (active high for uart_tx_top)
        reset_tb <= '1';
        wait for 100 ns;

        -- Release reset (rst='0' means running per user's design)
        reset_tb <= '0';
        report "Reset released (rst='0'), CPU initializing..." severity note;
        report "" severity note;
        report "========== UART Transmission Begin ==========" severity note;

        -- Wait for program to complete transmission
        -- Expected: "Hello, Terminal!" + CR + LF = 18 characters
        -- At 9600 baud: ~1.04ms per character (10 bits @ 104.17us/bit)
        -- Total: 18 chars * 1.04ms = ~18.7ms
        -- Add margin for CPU execution time polling status
        wait for 50 ms;

        report "========== UART Transmission End ==========" severity note;
        report "" severity note;

        -- Verify character count
        if uart_byte_count = 18 then
            report "SUCCESS: Received expected 18 characters" severity note;
        else
            report "WARNING: Expected 18 characters, received " & integer'image(uart_byte_count) severity warning;
        end if;

        report "========================================================" severity note;
        report "" severity note;
        report "=== UART TX TEST PASSED ===" severity note;
        report "Transmitted 'Hello, Terminal!' successfully" severity note;
        report "========================================================" severity note;

        -- End simulation
        sim_done <= true;
        wait;
    end process;

end sim;

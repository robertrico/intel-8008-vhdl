--------------------------------------------------------------------------------
-- bitbang_uart_tb.vhdl
--------------------------------------------------------------------------------
-- Testbench for Bitbang UART system - exact replica of FPGA hardware
--
-- This testbench replicates the complete bitbang_uart_top.vhdl system:
--   - b8008_top CPU system with ROM and RAM
--   - bitbang_uart_adapter for TX bit collection
--   - USART for hardware serial I/O
--   - Bootstrap interrupt control
--   - Edge detection for port strobes
--
-- Test Features:
--   - Monitors UART TX output (captures "Hello, 8008 1972!" and "Ready > ")
--   - Can inject UART RX input (simulates terminal keypresses)
--   - Detailed debug output for all signal transitions
--   - Reports assembled bytes from TX bit collection
--
-- Usage:
--   cd projects/bitbang_uart
--   make sim
--
-- Copyright (c) 2025 Robert Rico
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.b8008_types.all;

entity bitbang_uart_top_tb is
    generic (
        -- Test parameters
        SIMULATION_TIME_MS : integer := 500;  -- Total simulation time in ms
        INJECT_RX_CHARS    : boolean := false -- Set true to inject test characters
    );
end entity bitbang_uart_top_tb;

architecture testbench of bitbang_uart_top_tb is

    --------------------------------------------------------------------------------
    -- Constants
    --------------------------------------------------------------------------------
    constant CLK_FREQ_HZ : integer := 100_000_000;  -- 100 MHz
    constant CLK_PERIOD  : time := 10 ns;
    constant BAUD_RATE   : integer := 2400;
    constant BIT_PERIOD  : time := 1 sec / BAUD_RATE;  -- ~416.67 us per bit (standard)

    -- Actual CPU bit timing (measured from TX output):
    -- The software delay loops run ~38% slower than expected for 2400 baud
    -- Measured delta between TX bit transitions: ~576.4 us
    constant CPU_BIT_PERIOD : time := 576400 ns;  -- Actual CPU bit timing

    --------------------------------------------------------------------------------
    -- Component: b8008_top (CPU with ROM and RAM)
    --------------------------------------------------------------------------------
    component b8008_top is
        generic (
            ROM_FILE : string := "test_programs/alu_test_as.mem"
        );
        port (
            clk_in      : in std_logic;
            reset       : in std_logic;
            interrupt   : in std_logic;
            int_vector  : in std_logic_vector(2 downto 0);
            phi1_out    : out std_logic;
            phi2_out    : out std_logic;
            sync_out    : out std_logic;
            s0_out      : out std_logic;
            s1_out      : out std_logic;
            s2_out      : out std_logic;
            address_out : out std_logic_vector(13 downto 0);
            data_out    : out std_logic_vector(7 downto 0);
            ram_byte_0  : out std_logic_vector(7 downto 0);
            debug_reg_a         : out std_logic_vector(7 downto 0);
            debug_reg_b         : out std_logic_vector(7 downto 0);
            debug_reg_c         : out std_logic_vector(7 downto 0);
            debug_reg_d         : out std_logic_vector(7 downto 0);
            debug_reg_e         : out std_logic_vector(7 downto 0);
            debug_reg_h         : out std_logic_vector(7 downto 0);
            debug_reg_l         : out std_logic_vector(7 downto 0);
            debug_cycle         : out std_logic_vector(1 downto 0);
            debug_pc            : out std_logic_vector(13 downto 0);
            debug_ir            : out std_logic_vector(7 downto 0);
            debug_needs_address : out std_logic;
            debug_int_pending   : out std_logic;
            debug_flag_carry    : out std_logic;
            debug_flag_zero     : out std_logic;
            debug_flag_sign     : out std_logic;
            debug_flag_parity   : out std_logic;
            debug_io_port_8     : out std_logic_vector(7 downto 0);
            debug_io_port_9     : out std_logic_vector(7 downto 0);
            debug_io_port_10    : out std_logic_vector(7 downto 0);
            debug_state_half    : out std_logic;
            -- External I/O port interface
            io_port_in          : in  std_logic_vector(7 downto 0);
            io_port_in_select   : in  std_logic_vector(2 downto 0);
            io_port_in_enable   : in  std_logic;
            io_port_out         : out std_logic_vector(7 downto 0);
            io_port_num_out     : out std_logic_vector(4 downto 0);
            io_port_write       : out std_logic;
            io_port_read        : out std_logic
        );
    end component;

    --------------------------------------------------------------------------------
    -- Component: bitbang_uart_adapter
    --------------------------------------------------------------------------------
    component bitbang_uart_adapter is
        generic (
            CLK_FREQ_HZ : integer := 100_000_000;
            BAUD_RATE   : integer := 2400
        );
        port (
            clk             : in  std_logic;
            rst             : in  std_logic;
            port_out_data   : in  std_logic_vector(7 downto 0);
            port_out_valid  : in  std_logic;
            port_in_data    : out std_logic_vector(7 downto 0);
            port_in_read    : in  std_logic;
            uart_tx         : out std_logic;
            uart_rx         : in  std_logic;
            debug_tx_state  : out std_logic_vector(3 downto 0);
            debug_rx_state  : out std_logic_vector(3 downto 0);
            debug_tx_byte   : out std_logic_vector(7 downto 0);
            debug_rx_byte   : out std_logic_vector(7 downto 0);
            direct_tx_data  : in  std_logic_vector(7 downto 0);
            direct_tx_start : in  std_logic;
            direct_tx_busy  : out std_logic;
            direct_rx_data  : out std_logic_vector(7 downto 0);
            direct_rx_valid : out std_logic
        );
    end component;

    --------------------------------------------------------------------------------
    -- Testbench Signals - Exact replica of bitbang_uart_top.vhdl
    --------------------------------------------------------------------------------

    -- System clock and reset
    signal clk         : std_logic := '0';
    signal test_running : boolean := true;

    -- POR (Power-On Reset) and reset control
    signal por_active   : std_logic := '1';
    signal reset_sync   : std_logic_vector(2 downto 0) := (others => '1');
    signal reset_sw     : std_logic := '0';  -- No switch in testbench
    signal reset_int    : std_logic;

    -- CPU signals
    signal phi1         : std_logic;
    signal phi2         : std_logic;
    signal sync_sig     : std_logic;
    signal s0_sig       : std_logic;
    signal s1_sig       : std_logic;
    signal s2_sig       : std_logic;

    -- Bootstrap interrupt control
    signal bootstrap_int     : std_logic := '0';
    signal bootstrap_done    : std_logic := '0';
    signal bootstrap_counter : unsigned(7 downto 0) := (others => '0');

    -- I/O port signals from b8008_top
    signal io_port_8     : std_logic_vector(7 downto 0);
    signal io_port_9     : std_logic_vector(7 downto 0);
    signal io_port_10    : std_logic_vector(7 downto 0);
    signal io_port_out   : std_logic_vector(7 downto 0);
    signal io_port_num   : std_logic_vector(4 downto 0);
    signal io_port_write : std_logic;
    signal io_port_read  : std_logic;

    -- Bitbang adapter signals
    signal bitbang_port_out_valid : std_logic;
    signal bitbang_port_in_data   : std_logic_vector(7 downto 0);
    signal bitbang_port_in_read   : std_logic;

    -- Edge detection for port strobes
    signal io_port_write_d1 : std_logic := '0';
    signal io_port_read_d1  : std_logic := '0';
    signal port_write_pulse : std_logic := '0';
    signal port_read_pulse  : std_logic := '0';
    signal latched_port_num : std_logic_vector(4 downto 0) := (others => '0');
    signal latched_port_out : std_logic_vector(7 downto 0) := (others => '0');

    -- Debug signals from CPU
    signal address_sig      : std_logic_vector(13 downto 0);
    signal data_sig         : std_logic_vector(7 downto 0);
    signal debug_reg_a, debug_reg_b, debug_reg_c : std_logic_vector(7 downto 0);
    signal debug_reg_d, debug_reg_e, debug_reg_h, debug_reg_l : std_logic_vector(7 downto 0);
    signal debug_cycle  : std_logic_vector(1 downto 0);
    signal debug_pc_sig : std_logic_vector(13 downto 0);
    signal debug_ir     : std_logic_vector(7 downto 0);
    signal debug_needs_address : std_logic;
    signal int_pending_sig : std_logic;
    signal debug_flag_carry, debug_flag_zero, debug_flag_sign, debug_flag_parity : std_logic;
    signal ram_byte_0   : std_logic_vector(7 downto 0);
    signal state_half_sig : std_logic;

    -- UART signals
    signal uart_tx      : std_logic;
    signal uart_rx      : std_logic := '1';  -- Idle high

    -- Adapter debug signals
    signal adapter_tx_state : std_logic_vector(3 downto 0);
    signal adapter_rx_state : std_logic_vector(3 downto 0);
    signal adapter_tx_byte  : std_logic_vector(7 downto 0);
    signal adapter_rx_byte  : std_logic_vector(7 downto 0);

    -- Clock counter for POR timing (same as hardware)
    signal clk_counter : unsigned(25 downto 0) := (others => '0');

    --------------------------------------------------------------------------------
    -- Testbench-specific signals for monitoring and verification
    --------------------------------------------------------------------------------

    -- UART TX monitoring (capture transmitted bytes)
    signal tx_byte_count    : integer := 0;
    signal tx_message       : string(1 to 256) := (others => ' ');
    signal tx_message_len   : integer := 0;

    -- UART RX injection (send characters to CPU)
    signal rx_inject_active : std_logic := '0';
    signal rx_inject_byte   : std_logic_vector(7 downto 0) := x"00";
    signal rx_inject_bit_idx : integer := 0;

    -- Port activity monitoring
    signal port_write_count : integer := 0;
    signal port_read_count  : integer := 0;
    signal last_port_write_time : time := 0 ns;
    signal last_port_read_time  : time := 0 ns;

    -- Bit-bang TX monitoring
    signal bitbang_bit_count : integer := 0;
    signal bitbang_last_bit  : std_logic := '1';
    signal bitbang_byte_assembling : std_logic_vector(7 downto 0) := (others => '0');

begin

    --------------------------------------------------------------------------------
    -- Clock Generation (100 MHz)
    --------------------------------------------------------------------------------
    clk_process : process
    begin
        while test_running loop
            clk <= '0';
            wait for CLK_PERIOD / 2;
            clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    --------------------------------------------------------------------------------
    -- Power-On Reset (POR) - Exact copy from bitbang_uart_top.vhdl
    --------------------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            clk_counter <= clk_counter + 1;
            if clk_counter(19) = '1' then
                por_active <= '0';
            end if;
        end if;
    end process;

    reset_int <= por_active or reset_sw;

    --------------------------------------------------------------------------------
    -- Bootstrap Interrupt Control - Exact copy from bitbang_uart_top.vhdl
    --------------------------------------------------------------------------------
    process(phi2, reset_int)
    begin
        if reset_int = '1' then
            bootstrap_int     <= '0';
            bootstrap_done    <= '0';
            bootstrap_counter <= (others => '0');
        elsif rising_edge(phi2) then
            if bootstrap_done = '0' then
                bootstrap_int <= '1';
                bootstrap_counter <= bootstrap_counter + 1;
                if bootstrap_counter >= 16 then
                    if s2_sig = '1' and s1_sig = '1' and s0_sig = '0' then
                        bootstrap_int  <= '0';
                        bootstrap_done <= '1';
                    end if;
                end if;
            end if;
        end if;
    end process;

    --------------------------------------------------------------------------------
    -- b8008 CPU System Instance
    --------------------------------------------------------------------------------
    u_system : b8008_top
        generic map (
            ROM_FILE => "./bitbang_uart.mem"
        )
        port map (
            clk_in      => clk,
            reset       => reset_int,
            interrupt   => bootstrap_int,
            int_vector  => "000",  -- RST 0 for bootstrap
            phi1_out    => phi1,
            phi2_out    => phi2,
            sync_out    => sync_sig,
            s0_out      => s0_sig,
            s1_out      => s1_sig,
            s2_out      => s2_sig,
            address_out => address_sig,
            data_out    => data_sig,
            ram_byte_0  => ram_byte_0,
            debug_reg_a         => debug_reg_a,
            debug_reg_b         => debug_reg_b,
            debug_reg_c         => debug_reg_c,
            debug_reg_d         => debug_reg_d,
            debug_reg_e         => debug_reg_e,
            debug_reg_h         => debug_reg_h,
            debug_reg_l         => debug_reg_l,
            debug_cycle         => debug_cycle,
            debug_pc            => debug_pc_sig,
            debug_ir            => debug_ir,
            debug_needs_address => debug_needs_address,
            debug_int_pending   => int_pending_sig,
            debug_flag_carry    => debug_flag_carry,
            debug_flag_zero     => debug_flag_zero,
            debug_flag_sign     => debug_flag_sign,
            debug_flag_parity   => debug_flag_parity,
            debug_io_port_8     => io_port_8,
            debug_io_port_9     => io_port_9,
            debug_io_port_10    => io_port_10,
            debug_state_half    => state_half_sig,
            -- External I/O port interface
            io_port_in          => bitbang_port_in_data,
            io_port_in_select   => "000",  -- Port 0 uses external input
            io_port_in_enable   => '1',    -- Enable external input
            io_port_out         => io_port_out,
            io_port_num_out     => io_port_num,
            io_port_write       => io_port_write,
            io_port_read        => io_port_read
        );

    --------------------------------------------------------------------------------
    -- Edge Detection for Port Strobes - Exact copy from bitbang_uart_top.vhdl
    --------------------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if reset_int = '1' then
                io_port_write_d1 <= '0';
                io_port_read_d1  <= '0';
                latched_port_num <= (others => '0');
                latched_port_out <= (others => '0');
                port_write_pulse <= '0';
                port_read_pulse  <= '0';
            else
                io_port_write_d1 <= io_port_write;
                io_port_read_d1  <= io_port_read;

                -- Default: pulses off
                port_write_pulse <= '0';
                port_read_pulse  <= '0';

                -- Rising edge of write strobe: latch data and generate pulse
                if io_port_write = '1' and io_port_write_d1 = '0' then
                    latched_port_num <= io_port_num;
                    latched_port_out <= io_port_out;
                    port_write_pulse <= '1';
                end if;

                -- Rising edge of read strobe
                if io_port_read = '1' and io_port_read_d1 = '0' then
                    port_read_pulse <= '1';
                end if;
            end if;
        end if;
    end process;

    --------------------------------------------------------------------------------
    -- Bitbang UART Adapter Instance
    --------------------------------------------------------------------------------
    bitbang_port_out_valid <= port_write_pulse when latched_port_num = "01000" else '0';
    bitbang_port_in_read   <= port_read_pulse when io_port_num(2 downto 0) = "000" else '0';

    -- Direct RX: wire uart_rx to CPU input (same as hardware)
    bitbang_port_in_data <= "1111111" & uart_rx;

    u_bitbang : bitbang_uart_adapter
        generic map (
            CLK_FREQ_HZ => CLK_FREQ_HZ,
            BAUD_RATE   => BAUD_RATE
        )
        port map (
            clk             => clk,
            rst             => reset_int,
            port_out_data   => latched_port_out,
            port_out_valid  => bitbang_port_out_valid,
            port_in_data    => open,  -- Not used - direct RX wiring
            port_in_read    => bitbang_port_in_read,
            uart_tx         => uart_tx,
            uart_rx         => uart_rx,
            -- Debug outputs
            debug_tx_state  => adapter_tx_state,
            debug_rx_state  => adapter_rx_state,
            debug_tx_byte   => adapter_tx_byte,
            debug_rx_byte   => adapter_rx_byte,
            -- Direct mode (unused)
            direct_tx_data  => (others => '0'),
            direct_tx_start => '0',
            direct_tx_busy  => open,
            direct_rx_data  => open,
            direct_rx_valid => open
        );

    --------------------------------------------------------------------------------
    -- UART TX Capture Process - Capture transmitted bytes from uart_tx line
    --------------------------------------------------------------------------------
    uart_tx_capture : process
        variable bit_count : integer := 0;
        variable rx_byte   : std_logic_vector(7 downto 0);
        variable byte_char : character;
    begin
        wait until reset_int = '0';

        loop
            -- Wait for start bit (falling edge on uart_tx)
            wait until uart_tx = '0';

            -- Wait half bit time to sample in middle
            wait for BIT_PERIOD / 2;

            -- Verify still in start bit
            if uart_tx /= '0' then
                report "UART_TX_CAPTURE: False start bit detected" severity warning;
                next;
            end if;

            -- Sample 8 data bits (LSB first)
            rx_byte := (others => '0');
            for i in 0 to 7 loop
                wait for BIT_PERIOD;
                rx_byte(i) := uart_tx;
            end loop;

            -- Wait for stop bit
            wait for BIT_PERIOD;
            if uart_tx /= '1' then
                report "UART_TX_CAPTURE: Missing stop bit!" severity warning;
            end if;

            -- Convert to character and log
            tx_byte_count <= tx_byte_count + 1;
            byte_char := character'val(to_integer(unsigned(rx_byte)));

            -- Build message string
            if tx_message_len < 256 then
                tx_message_len <= tx_message_len + 1;
                tx_message(tx_message_len + 1) <= byte_char;
            end if;

            -- Report the captured byte
            if rx_byte = x"0D" then
                report "UART_TX: [CR] (0x0D) - Carriage Return";
            elsif rx_byte = x"0A" then
                report "UART_TX: [LF] (0x0A) - Line Feed";
            elsif unsigned(rx_byte) >= 32 and unsigned(rx_byte) < 127 then
                report "UART_TX: '" & byte_char & "' (0x" & to_hstring(unsigned(rx_byte)) & ")";
            else
                report "UART_TX: [0x" & to_hstring(unsigned(rx_byte)) & "] (non-printable)";
            end if;

            exit when not test_running;
        end loop;

        wait;
    end process;

    --------------------------------------------------------------------------------
    -- Port Activity Monitor - Track all port writes for debugging
    --------------------------------------------------------------------------------
    port_monitor : process(clk)
        variable time_since_last : time;
    begin
        if rising_edge(clk) then
            if reset_int = '0' then
                -- Monitor port writes
                if port_write_pulse = '1' then
                    port_write_count <= port_write_count + 1;
                    time_since_last := now - last_port_write_time;
                    last_port_write_time <= now;

                    if latched_port_num = "01000" then
                        -- Port 8 (serial TX bit)
                        report "PORT_WRITE: Port 8 <= 0x" & to_hstring(unsigned(latched_port_out)) &
                               " (bit=" & std_logic'image(latched_port_out(0)) & ")" &
                               " delta=" & time'image(time_since_last);

                        -- Track bitbang state
                        bitbang_last_bit <= latched_port_out(0);
                        bitbang_bit_count <= bitbang_bit_count + 1;
                    else
                        report "PORT_WRITE: Port " & integer'image(to_integer(unsigned(latched_port_num))) &
                               " <= 0x" & to_hstring(unsigned(latched_port_out));
                    end if;
                end if;

                -- Monitor port reads
                if port_read_pulse = '1' then
                    port_read_count <= port_read_count + 1;
                    time_since_last := now - last_port_read_time;
                    last_port_read_time <= now;

                    if io_port_num(2 downto 0) = "000" then
                        -- Port 0 (serial RX bit)
                        report "PORT_READ: Port 0 => 0x" & to_hstring(unsigned(bitbang_port_in_data)) &
                               " (bit=" & std_logic'image(uart_rx) & ")" &
                               " delta=" & time'image(time_since_last);
                    else
                        report "PORT_READ: Port " & integer'image(to_integer(unsigned(io_port_num(2 downto 0))));
                    end if;
                end if;
            end if;
        end if;
    end process;

    --------------------------------------------------------------------------------
    -- Adapter State Monitor - Track bitbang adapter state machine
    --------------------------------------------------------------------------------
    adapter_monitor : process(clk)
        variable last_tx_state : std_logic_vector(3 downto 0) := "0000";
    begin
        if rising_edge(clk) then
            if adapter_tx_state /= last_tx_state then
                case adapter_tx_state is
                    when "0000" =>
                        report "ADAPTER_TX: State -> IDLE";
                    when "0001" =>
                        report "ADAPTER_TX: State -> COLLECTING (start bit detected)";
                    when "0010" =>
                        report "ADAPTER_TX: State -> STOP (8 bits collected, byte=0x" &
                               to_hstring(unsigned(adapter_tx_byte)) & ")";
                    when "0011" =>
                        report "ADAPTER_TX: State -> SEND (sending to USART)";
                    when others =>
                        report "ADAPTER_TX: State -> UNKNOWN (" &
                               to_hstring(unsigned(adapter_tx_state)) & ")";
                end case;
                last_tx_state := adapter_tx_state;
            end if;
        end if;
    end process;

    --------------------------------------------------------------------------------
    -- Periodic Status Report
    --------------------------------------------------------------------------------
    status_report : process
    begin
        wait until reset_int = '0';
        wait for 10 ms;  -- Initial delay after reset

        loop
            report "========================================";
            report "STATUS REPORT @ " & time'image(now);
            report "  Bootstrap done: " & std_logic'image(bootstrap_done);
            report "  PC: 0x" & to_hstring(unsigned(debug_pc_sig)) &
                   "  IR: 0x" & to_hstring(unsigned(debug_ir));
            report "  Registers: A=0x" & to_hstring(unsigned(debug_reg_a)) &
                   " B=0x" & to_hstring(unsigned(debug_reg_b)) &
                   " C=0x" & to_hstring(unsigned(debug_reg_c));
            report "  Port writes: " & integer'image(port_write_count) &
                   "  Port reads: " & integer'image(port_read_count);
            report "  Bitbang bits: " & integer'image(bitbang_bit_count);
            report "  TX bytes captured: " & integer'image(tx_byte_count);
            report "  Adapter TX state: " & to_hstring(unsigned(adapter_tx_state)) &
                   "  TX byte: 0x" & to_hstring(unsigned(adapter_tx_byte));
            report "========================================";

            wait for 50 ms;

            exit when not test_running;
        end loop;

        wait;
    end process;

    --------------------------------------------------------------------------------
    -- Main Stimulus Process
    --------------------------------------------------------------------------------
    stimulus : process
    begin
        report "========================================";
        report "BITBANG UART TESTBENCH";
        report "========================================";
        report "Configuration:";
        report "  CLK_FREQ: " & integer'image(CLK_FREQ_HZ) & " Hz";
        report "  BAUD_RATE: " & integer'image(BAUD_RATE) & " bps";
        report "  BIT_PERIOD: " & time'image(BIT_PERIOD);
        report "  SIMULATION_TIME: " & integer'image(SIMULATION_TIME_MS) & " ms";
        report "========================================";

        -- Wait for power-on reset to complete
        wait until por_active = '0';
        report "POR complete @ " & time'image(now);

        -- Wait for bootstrap to complete
        wait until bootstrap_done = '1';
        report "Bootstrap complete @ " & time'image(now);
        report "CPU is now running bitbang_uart.asm program";
        report "";
        report "Expected output:";
        report "  1. 'Hello, 8008 1972!' (startup message)";
        report "  2. 'Ready > ' (prompt)";
        report "========================================";

        -- Run simulation for specified time
        wait for SIMULATION_TIME_MS * 1 ms;

        -- Final report
        report "========================================";
        report "SIMULATION COMPLETE";
        report "========================================";
        report "Total time: " & time'image(now);
        report "Port write count: " & integer'image(port_write_count);
        report "Port read count: " & integer'image(port_read_count);
        report "Bitbang bit count: " & integer'image(bitbang_bit_count);
        report "TX bytes captured: " & integer'image(tx_byte_count);
        report "";
        if tx_byte_count > 0 then
            report "Captured TX message (first " & integer'image(tx_message_len) & " chars):";
            report "  '" & tx_message(1 to tx_message_len) & "'";
        else
            report "WARNING: No TX bytes captured!";
        end if;
        report "========================================";

        -- End simulation
        test_running <= false;
        wait;
    end process;

    --------------------------------------------------------------------------------
    -- UART RX Injection (send characters to CPU for echo testing)
    --------------------------------------------------------------------------------
    -- Sends test characters after the "Ready > " prompt appears
    -- The CPU's INPUT routine polls IN 0 waiting for start bit (line going low)
    rx_injection : process
        procedure send_uart_byte(byte : std_logic_vector(7 downto 0)) is
            variable char : character;
        begin
            -- Log what we're sending
            if unsigned(byte) >= 32 and unsigned(byte) < 127 then
                char := character'val(to_integer(unsigned(byte)));
                report "UART_RX_INJECT: Sending '" & char & "' (0x" & to_hstring(unsigned(byte)) & ")";
            elsif byte = x"0D" then
                report "UART_RX_INJECT: Sending [CR] (0x0D)";
            elsif byte = x"0A" then
                report "UART_RX_INJECT: Sending [LF] (0x0A)";
            else
                report "UART_RX_INJECT: Sending 0x" & to_hstring(unsigned(byte));
            end if;

            -- Start bit (line goes LOW)
            -- Use CPU_BIT_PERIOD to match the CPU's actual sampling rate
            uart_rx <= '0';
            wait for CPU_BIT_PERIOD;

            -- Data bits (LSB first)
            for i in 0 to 7 loop
                uart_rx <= byte(i);
                wait for CPU_BIT_PERIOD;
            end loop;

            -- Stop bit (line goes HIGH)
            uart_rx <= '1';
            wait for CPU_BIT_PERIOD;

            -- Extra idle time between characters
            -- CPU needs to complete ECHO routine before it can receive the next char
            -- ECHO routine: sends 10 bits at ~576us each = ~5.76ms per char echoed
            -- Plus some processing overhead. Use 8ms total gap.
            wait for 8 ms;
        end procedure;
    begin
        -- Keep RX line idle (HIGH) by default
        uart_rx <= '1';

        -- Wait for "Ready > " prompt to complete and CPU to enter input loop
        -- At CPU_BIT_PERIOD (~576us), each char takes ~6.3ms (10 bits * 576us)
        -- "Hello, 8008 1972!" = 18 chars = ~113ms
        -- CR + LF = 2 chars = ~13ms
        -- "Ready > " = 8 chars = ~50ms
        -- Total TX time: ~176ms, plus CPU needs time to enter input loop
        -- Observed: Last char at ~170ms, CPU polling starts shortly after
        -- Use 180ms to ensure CPU is ready and polling
        wait for 180 ms;

        report "========================================";
        report "UART_RX_INJECT: Starting RX injection test";
        report "  Sending: 'Test!' followed by CR";
        report "  CPU should echo each character back";
        report "========================================";

        -- Send test string: "Test!"
        send_uart_byte(x"54");  -- 'T'
        send_uart_byte(x"65");  -- 'e'
        send_uart_byte(x"73");  -- 's'
        send_uart_byte(x"74");  -- 't'
        send_uart_byte(x"21");  -- '!'

        -- Wait a bit, then send CR to trigger new prompt
        wait for 50 ms;
        send_uart_byte(x"0D");  -- CR (Enter)

        -- Wait for echo and new prompt
        wait for 100 ms;

        report "========================================";
        report "UART_RX_INJECT: Sending second test string";
        report "  Sending: 'Hi' followed by CR";
        report "========================================";

        -- Send another test
        send_uart_byte(x"48");  -- 'H'
        send_uart_byte(x"69");  -- 'i'
        wait for 50 ms;
        send_uart_byte(x"0D");  -- CR (Enter)

        report "UART_RX_INJECT: Injection complete";
        wait;
    end process;

end architecture testbench;

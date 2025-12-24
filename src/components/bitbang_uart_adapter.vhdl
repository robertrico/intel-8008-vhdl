--------------------------------------------------------------------------------
-- Bit-Bang UART Adapter
--------------------------------------------------------------------------------
-- Bridges software bit-banged serial I/O to hardware UART
--
-- The Intel 8008 programs from the 1970s implement serial I/O by bit-banging:
-- - TX: Multiple OUT instructions, each outputting one bit (LSB of accumulator)
-- - RX: Multiple IN instructions, each reading one bit (returned in LSB)
--
-- This adapter:
-- - TX: Detects start bit, collects 8 data bits from consecutive port writes,
--       then sends the assembled byte via hardware UART
-- - RX: Receives bytes from hardware UART, presents them bit-by-bit on port reads
--
-- Protocol (2400 baud, 8N1):
--   Start bit: 0
--   Data bits: 8 bits, LSB first
--   Stop bit:  1
--
-- Port mapping (matching original SCELBI/8008 conventions):
--   Port 0: Serial input  (IN 0 reads bit 0)
--   Port 8: Serial output (OUT 8 writes bit 0)
--
-- Copyright (c) 2025 Robert Rico
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity bitbang_uart_adapter is
    generic (
        CLK_FREQ_HZ : integer := 100_000_000;  -- System clock frequency
        BAUD_RATE   : integer := 2400          -- Must match software timing
    );
    port (
        clk         : in  std_logic;
        rst         : in  std_logic;

        -- Port I/O interface (directly connects to 8008 I/O system)
        -- TX: triggered by OUT to port 8
        port_out_data   : in  std_logic_vector(7 downto 0);  -- Data from CPU
        port_out_valid  : in  std_logic;  -- Pulse when OUT 8 executed

        -- RX: provides data for IN from port 0
        port_in_data    : out std_logic_vector(7 downto 0);  -- Data to CPU
        port_in_read    : in  std_logic;  -- Pulse when IN 0 executed

        -- Hardware UART interface
        uart_tx         : out std_logic;
        uart_rx         : in  std_logic;

        -- Debug outputs
        debug_tx_state  : out std_logic_vector(3 downto 0);
        debug_rx_state  : out std_logic_vector(3 downto 0);
        debug_tx_byte   : out std_logic_vector(7 downto 0);
        debug_rx_byte   : out std_logic_vector(7 downto 0);

        -- Direct UART access (for new programs using ports 1/9)
        -- These bypass the bit-bang logic and talk directly to USART
        direct_tx_data  : in  std_logic_vector(7 downto 0);  -- Byte to send
        direct_tx_start : in  std_logic;                     -- Pulse to start TX
        direct_tx_busy  : out std_logic;                     -- USART TX busy
        direct_rx_data  : out std_logic_vector(7 downto 0);  -- Received byte
        direct_rx_valid : out std_logic                      -- Pulse when byte received
    );
end entity bitbang_uart_adapter;

architecture rtl of bitbang_uart_adapter is

    -- USART component
    component usart is
        generic (
            CLK_FREQ_HZ : integer;
            BAUD_RATE   : integer
        );
        port (
            clk         : in  std_logic;
            rst         : in  std_logic;
            tx_data     : in  std_logic_vector(7 downto 0);
            tx_start    : in  std_logic;
            tx_busy     : out std_logic;
            rx_data     : out std_logic_vector(7 downto 0);
            rx_valid    : out std_logic;
            uart_tx     : out std_logic;
            uart_rx     : in  std_logic
        );
    end component;

    -- Calculate timing: software sends bits at BAUD_RATE
    -- We need a timeout to detect end of byte (or start of next)
    -- Bit time = CLK_FREQ_HZ / BAUD_RATE clocks
    -- Use 1.5 bit times as timeout (allows for some timing variation)
    constant BIT_CLOCKS     : integer := CLK_FREQ_HZ / BAUD_RATE;
    constant TIMEOUT_CLOCKS : integer := (BIT_CLOCKS * 3) / 2;

    -- TX bit collector state machine
    type tx_state_t is (
        TX_IDLE,        -- Waiting for start bit (0)
        TX_COLLECTING,  -- Collecting data bits
        TX_STOP,        -- Waiting for stop bit
        TX_SEND         -- Sending byte via UART
    );
    signal tx_state     : tx_state_t := TX_IDLE;
    signal tx_bit_count : integer range 0 to 8 := 0;
    signal tx_shift_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_timeout   : integer range 0 to TIMEOUT_CLOCKS := 0;
    signal tx_last_bit  : std_logic := '1';

    -- USART TX interface (directly from USART)
    signal usart_tx_data  : std_logic_vector(7 downto 0) := (others => '0');
    signal usart_tx_start : std_logic := '0';
    signal usart_tx_busy  : std_logic;

    -- Bitbang TX interface (from state machine)
    signal bitbang_tx_data  : std_logic_vector(7 downto 0) := (others => '0');
    signal bitbang_tx_start : std_logic := '0';

    -- RX bit presenter state machine
    type rx_state_t is (
        RX_IDLE,        -- No byte available, return '1' (idle line)
        RX_START,       -- Presenting start bit
        RX_DATA,        -- Presenting data bits
        RX_STOP         -- Presenting stop bit
    );
    signal rx_state     : rx_state_t := RX_IDLE;
    signal rx_bit_count : integer range 0 to 8 := 0;
    signal rx_shift_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal rx_bit_timer : integer range 0 to BIT_CLOCKS := 0;

    -- USART RX interface
    signal usart_rx_data  : std_logic_vector(7 downto 0);
    signal usart_rx_valid : std_logic;

    -- RX byte buffer (FIFO would be better, but single buffer for simplicity)
    signal rx_byte_ready  : std_logic := '0';
    signal rx_byte_buffer : std_logic_vector(7 downto 0) := (others => '0');

begin

    -- Instantiate USART
    u_usart : usart
        generic map (
            CLK_FREQ_HZ => CLK_FREQ_HZ,
            BAUD_RATE   => BAUD_RATE
        )
        port map (
            clk      => clk,
            rst      => rst,
            tx_data  => usart_tx_data,
            tx_start => usart_tx_start,
            tx_busy  => usart_tx_busy,
            rx_data  => usart_rx_data,
            rx_valid => usart_rx_valid,
            uart_tx  => uart_tx,
            uart_rx  => uart_rx
        );

    -- ========================================================================
    -- TX MUX: Combine bitbang and direct TX sources
    -- ========================================================================
    -- Priority: direct_tx_start takes precedence (direct mode is immediate)
    -- Bitbang mode only triggers when it has collected a full byte
    usart_tx_data  <= direct_tx_data when direct_tx_start = '1' else bitbang_tx_data;
    usart_tx_start <= direct_tx_start or bitbang_tx_start;

    -- Direct TX busy output (pass through USART busy)
    direct_tx_busy <= usart_tx_busy;

    -- ========================================================================
    -- RX: Direct access to received bytes
    -- ========================================================================
    -- Direct mode gets the raw byte immediately when USART receives it
    -- Bitbang mode buffers and presents bit-by-bit (handled in RX process)
    direct_rx_data  <= usart_rx_data;
    direct_rx_valid <= usart_rx_valid;

    -- ========================================================================
    -- TX: Bit Collector
    -- ========================================================================
    -- Collects bits from software OUT instructions, assembles into byte,
    -- then sends via hardware UART

    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                tx_state     <= TX_IDLE;
                tx_bit_count <= 0;
                tx_shift_reg <= (others => '0');
                tx_timeout   <= 0;
                tx_last_bit  <= '1';
                bitbang_tx_start <= '0';
                bitbang_tx_data  <= (others => '0');
            else
                bitbang_tx_start <= '0';  -- Default: no TX trigger

                case tx_state is
                    when TX_IDLE =>
                        tx_bit_count <= 0;
                        tx_timeout   <= 0;
                        -- Wait for start bit (0) from software
                        if port_out_valid = '1' then
                            tx_last_bit <= port_out_data(0);
                            if port_out_data(0) = '0' then
                                -- Start bit detected!
                                tx_state <= TX_COLLECTING;
                                report "BITBANG TX: Start bit detected";
                            end if;
                        end if;

                    when TX_COLLECTING =>
                        -- Timeout counter - reset on each bit
                        if port_out_valid = '1' then
                            tx_timeout <= 0;
                            -- Shift in the new bit (LSB first)
                            tx_shift_reg <= port_out_data(0) & tx_shift_reg(7 downto 1);
                            tx_bit_count <= tx_bit_count + 1;
                            tx_last_bit  <= port_out_data(0);

                            if tx_bit_count = 7 then
                                -- Got all 8 data bits, wait for stop bit
                                tx_state <= TX_STOP;
                                report "BITBANG TX: Collected 8 bits = 0x" &
                                       to_hstring(unsigned(port_out_data(0) & tx_shift_reg(7 downto 1)));
                            end if;
                        else
                            -- Timeout check
                            if tx_timeout < TIMEOUT_CLOCKS then
                                tx_timeout <= tx_timeout + 1;
                            else
                                -- Timeout - abort and return to idle
                                tx_state <= TX_IDLE;
                                report "BITBANG TX: Timeout during collection";
                            end if;
                        end if;

                    when TX_STOP =>
                        if port_out_valid = '1' then
                            if port_out_data(0) = '1' then
                                -- Stop bit received, send the byte
                                bitbang_tx_data  <= tx_shift_reg;
                                bitbang_tx_start <= '1';
                                tx_state <= TX_SEND;
                                report "BITBANG TX: Stop bit, sending 0x" &
                                       to_hstring(unsigned(tx_shift_reg));
                            else
                                -- Framing error - got 0 instead of stop bit
                                tx_state <= TX_IDLE;
                                report "BITBANG TX: Framing error (no stop bit)";
                            end if;
                        else
                            if tx_timeout < TIMEOUT_CLOCKS then
                                tx_timeout <= tx_timeout + 1;
                            else
                                tx_state <= TX_IDLE;
                            end if;
                        end if;

                    when TX_SEND =>
                        -- Wait for UART to accept the byte
                        if usart_tx_busy = '0' then
                            tx_state <= TX_IDLE;
                        end if;

                end case;
            end if;
        end if;
    end process;

    -- ========================================================================
    -- RX: Bit Presenter
    -- ========================================================================
    -- Receives bytes from hardware UART, presents them bit-by-bit to software
    -- The software polls with IN instructions, expecting bit-banged timing

    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                rx_state      <= RX_IDLE;
                rx_bit_count  <= 0;
                rx_shift_reg  <= (others => '0');
                rx_bit_timer  <= 0;
                rx_byte_ready <= '0';
                rx_byte_buffer <= (others => '0');
            else
                -- Buffer incoming UART bytes
                if usart_rx_valid = '1' then
                    rx_byte_buffer <= usart_rx_data;
                    rx_byte_ready  <= '1';
                    report "BITBANG RX: Received byte 0x" & to_hstring(unsigned(usart_rx_data));
                end if;

                case rx_state is
                    when RX_IDLE =>
                        rx_bit_count <= 0;
                        rx_bit_timer <= 0;
                        -- If we have a byte ready, start presenting it
                        if rx_byte_ready = '1' then
                            rx_shift_reg  <= rx_byte_buffer;
                            rx_byte_ready <= '0';
                            rx_state      <= RX_START;
                            report "BITBANG RX: Starting to present byte";
                        end if;

                    when RX_START =>
                        -- Present start bit (0) for one bit time
                        -- The software reads via IN 0, we count clock cycles
                        if rx_bit_timer < BIT_CLOCKS - 1 then
                            rx_bit_timer <= rx_bit_timer + 1;
                        else
                            rx_bit_timer <= 0;
                            rx_state <= RX_DATA;
                        end if;

                    when RX_DATA =>
                        -- Present data bits, one bit time each
                        if rx_bit_timer < BIT_CLOCKS - 1 then
                            rx_bit_timer <= rx_bit_timer + 1;
                        else
                            rx_bit_timer <= 0;
                            rx_shift_reg <= '1' & rx_shift_reg(7 downto 1);  -- Shift out LSB
                            rx_bit_count <= rx_bit_count + 1;
                            if rx_bit_count = 7 then
                                rx_state <= RX_STOP;
                            end if;
                        end if;

                    when RX_STOP =>
                        -- Present stop bit (1) for one bit time
                        if rx_bit_timer < BIT_CLOCKS - 1 then
                            rx_bit_timer <= rx_bit_timer + 1;
                        else
                            rx_bit_timer <= 0;
                            rx_state <= RX_IDLE;
                        end if;

                end case;
            end if;
        end if;
    end process;

    -- Output the current bit value to the CPU
    -- Port 0 returns: bit 0 = current serial bit, other bits = 1 (idle)
    port_in_data <= "1111111" & rx_shift_reg(0) when rx_state = RX_DATA else
                    "11111110" when rx_state = RX_START else
                    "11111111";  -- Idle or stop bit = high

    -- Debug outputs
    debug_tx_state <= "0000" when tx_state = TX_IDLE else
                      "0001" when tx_state = TX_COLLECTING else
                      "0010" when tx_state = TX_STOP else
                      "0011";
    debug_rx_state <= "0000" when rx_state = RX_IDLE else
                      "0001" when rx_state = RX_START else
                      "0010" when rx_state = RX_DATA else
                      "0011";
    debug_tx_byte <= tx_shift_reg;
    debug_rx_byte <= rx_shift_reg;

end architecture rtl;

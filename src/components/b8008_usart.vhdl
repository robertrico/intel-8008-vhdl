--------------------------------------------------------------------------------
-- B8008_USART - UART with 8008 CPU Handshaking
--------------------------------------------------------------------------------
-- Wraps the generic USART module with 8008-style port I/O handshaking.
-- Handles both RX and TX with automatic triggering from b8008_top signals.
--
-- RX Interface (for IN instruction):
--   rx_port_data(7)   = Ready flag (1 = data available)
--   rx_port_data(6:0) = Received character (7-bit ASCII)
--   Ready flag clears on falling edge of io_port_read when port matches
--
-- TX Interface (for OUT instruction):
--   Automatically triggers TX when io_port_write strobes with matching port
--   tx_busy output indicates transmission in progress
--
-- Usage: Just wire io_port_read, io_port_write, io_port_num, and io_port_out
--        from b8008_top. The wrapper handles all the handshaking logic.
--
-- Copyright (c) 2025 Robert Rico
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity b8008_usart is
    generic (
        CLK_FREQ_HZ  : integer := 100_000_000;  -- System clock frequency
        BAUD_RATE    : integer := 115200;       -- UART baud rate
        RX_PORT_NUM  : std_logic_vector(2 downto 0) := "001";  -- Port 1 for RX (INP 1)
        TX_PORT_NUM  : std_logic_vector(4 downto 0) := "01001" -- Port 9 for TX (OUT 9)
    );
    port (
        clk             : in  std_logic;
        rst             : in  std_logic;

        -- 8008 I/O interface (directly from b8008_top)
        io_port_read    : in  std_logic;       -- Strobe from b8008_top during INP T3
        io_port_write   : in  std_logic;       -- Strobe from b8008_top during OUT T3
        io_port_num     : in  std_logic_vector(4 downto 0);  -- Port number (from b8008)
        io_port_out     : in  std_logic_vector(7 downto 0);  -- Data from OUT instruction

        -- RX data output (directly wire to io_port_in_data)
        rx_port_data    : out std_logic_vector(7 downto 0);

        -- TX status (optional - for LED indicators or flow control)
        tx_busy         : out std_logic;

        -- UART pins
        uart_tx         : out std_logic;
        uart_rx         : in  std_logic
    );
end entity b8008_usart;

architecture rtl of b8008_usart is

    -- Internal USART signals
    signal usart_tx_data  : std_logic_vector(7 downto 0) := (others => '0');
    signal usart_tx_start : std_logic := '0';
    signal usart_tx_busy  : std_logic;
    signal usart_rx_data  : std_logic_vector(7 downto 0);
    signal usart_rx_valid : std_logic;

    -- Ready flag handshaking
    signal rx_latch       : std_logic_vector(7 downto 0) := (others => '0');
    signal rx_ready       : std_logic := '0';

    -- Falling edge detection for clearing ready flag
    signal io_port_read_d1   : std_logic := '0';
    signal io_port_read_d2   : std_logic := '0';
    signal io_port_num_latch : std_logic_vector(4 downto 0) := (others => '0');

begin

    -- Instantiate the generic USART
    usart_inst : entity work.usart
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

    -- TX busy status output
    tx_busy <= usart_tx_busy;

    ----------------------------------------------------------------------------
    -- TX Control: Trigger transmission on OUT to TX_PORT_NUM
    ----------------------------------------------------------------------------
    process(clk, rst)
    begin
        if rst = '1' then
            usart_tx_data  <= (others => '0');
            usart_tx_start <= '0';
        elsif rising_edge(clk) then
            -- Default: clear start strobe
            usart_tx_start <= '0';

            -- Check for OUT to our TX port
            if io_port_write = '1' and io_port_num = TX_PORT_NUM then
                usart_tx_data  <= io_port_out;
                usart_tx_start <= '1';
            end if;
        end if;
    end process;

    ----------------------------------------------------------------------------
    -- RX Control: Latch data and manage ready flag
    ----------------------------------------------------------------------------
    process(clk, rst)
    begin
        if rst = '1' then
            rx_latch         <= (others => '0');
            rx_ready         <= '0';
            io_port_read_d1  <= '0';
            io_port_read_d2  <= '0';
            io_port_num_latch <= (others => '0');
        elsif rising_edge(clk) then
            -- Delay io_port_read to allow CPU to read data before clearing
            -- The CPU reads during T3; we clear on falling edge (after T3 ends)
            io_port_read_d1 <= io_port_read;
            io_port_read_d2 <= io_port_read_d1;

            -- Latch port number when io_port_read goes high
            if io_port_read = '1' and io_port_read_d1 = '0' then
                io_port_num_latch <= io_port_num;
            end if;

            -- When UART receives a byte, latch it and set ready flag
            if usart_rx_valid = '1' then
                rx_latch <= usart_rx_data;
                rx_ready <= '1';
            -- Clear on falling edge of io_port_read when our port was read
            elsif io_port_read_d1 = '0' and io_port_read_d2 = '1' and
                  io_port_num_latch(2 downto 0) = RX_PORT_NUM then
                rx_ready <= '0';
            end if;
        end if;
    end process;

    -- Output: Ready flag in bit 7, data in bits 6:0
    rx_port_data <= rx_ready & rx_latch(6 downto 0);

end architecture rtl;

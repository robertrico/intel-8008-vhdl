--------------------------------------------------------------------------------
-- USART - Combined UART TX/RX Module
--------------------------------------------------------------------------------
-- Unified UART module combining transmitter and receiver
-- Standard 8N1 format (8 data bits, no parity, 1 stop bit)
--
-- Copyright (c) 2025 Robert Rico
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity usart is
    generic (
        CLK_FREQ_HZ : integer := 100_000_000;  -- System clock frequency
        BAUD_RATE   : integer := 2400          -- UART baud rate (2400 for 8008 programs)
    );
    port (
        clk         : in  std_logic;
        rst         : in  std_logic;

        -- Transmit interface
        tx_data     : in  std_logic_vector(7 downto 0);
        tx_start    : in  std_logic;
        tx_busy     : out std_logic;

        -- Receive interface
        rx_data     : out std_logic_vector(7 downto 0);
        rx_valid    : out std_logic;  -- Pulses high for one clock when byte received

        -- UART pins
        uart_tx     : out std_logic;
        uart_rx     : in  std_logic
    );
end entity usart;

architecture rtl of usart is

    -- TX constants and signals
    constant CLKS_PER_BIT : integer := CLK_FREQ_HZ / BAUD_RATE;

    type tx_state_t is (TX_ST_IDLE, TX_ST_START, TX_ST_DATA, TX_ST_STOP);
    signal tx_state     : tx_state_t := TX_ST_IDLE;
    signal tx_timer     : integer range 0 to CLKS_PER_BIT - 1 := 0;
    signal tx_bit_idx   : integer range 0 to 7 := 0;
    signal tx_shift_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_busy_i    : std_logic := '0';

    -- RX constants and signals
    constant OVERSAMPLE : integer := 16;
    constant TICKS_16X  : integer := CLK_FREQ_HZ / (BAUD_RATE * OVERSAMPLE);
    constant SAMPLE_PT  : integer := 8;

    type rx_state_t is (RX_ST_IDLE, RX_ST_START, RX_ST_DATA, RX_ST_STOP);
    signal rx_state       : rx_state_t := RX_ST_IDLE;
    signal rx_tick_cnt    : integer range 0 to TICKS_16X - 1 := 0;
    signal rx_sample_cnt  : integer range 0 to OVERSAMPLE - 1 := 0;
    signal rx_bit_cnt     : integer range 0 to 7 := 0;
    signal rx_shift_reg   : std_logic_vector(7 downto 0) := (others => '0');

    -- RX synchronizer
    signal rx_sync1, rx_sync2 : std_logic := '1';

begin

    tx_busy <= tx_busy_i;

    -- Two-stage synchronizer for RX input
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                rx_sync1 <= '1';
                rx_sync2 <= '1';
            else
                rx_sync1 <= uart_rx;
                rx_sync2 <= rx_sync1;
            end if;
        end if;
    end process;

    -- TX state machine
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                tx_state     <= TX_ST_IDLE;
                tx_timer     <= 0;
                tx_bit_idx   <= 0;
                tx_shift_reg <= (others => '0');
                uart_tx      <= '1';
                tx_busy_i    <= '0';
            else
                case tx_state is
                    when TX_ST_IDLE =>
                        uart_tx   <= '1';
                        tx_busy_i <= '0';
                        tx_timer  <= 0;
                        tx_bit_idx <= 0;
                        if tx_start = '1' then
                            tx_shift_reg <= tx_data;
                            tx_busy_i    <= '1';
                            tx_state     <= TX_ST_START;
                        end if;

                    when TX_ST_START =>
                        uart_tx <= '0';  -- Start bit
                        if tx_timer = CLKS_PER_BIT - 1 then
                            tx_timer <= 0;
                            tx_state <= TX_ST_DATA;
                        else
                            tx_timer <= tx_timer + 1;
                        end if;

                    when TX_ST_DATA =>
                        uart_tx <= tx_shift_reg(tx_bit_idx);
                        if tx_timer = CLKS_PER_BIT - 1 then
                            tx_timer <= 0;
                            if tx_bit_idx = 7 then
                                tx_bit_idx <= 0;
                                tx_state   <= TX_ST_STOP;
                            else
                                tx_bit_idx <= tx_bit_idx + 1;
                            end if;
                        else
                            tx_timer <= tx_timer + 1;
                        end if;

                    when TX_ST_STOP =>
                        uart_tx <= '1';  -- Stop bit
                        if tx_timer = CLKS_PER_BIT - 1 then
                            tx_timer <= 0;
                            tx_state <= TX_ST_IDLE;
                        else
                            tx_timer <= tx_timer + 1;
                        end if;
                end case;
            end if;
        end if;
    end process;

    -- RX state machine
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                rx_state      <= RX_ST_IDLE;
                rx_tick_cnt   <= 0;
                rx_sample_cnt <= 0;
                rx_bit_cnt    <= 0;
                rx_shift_reg  <= (others => '0');
                rx_data       <= (others => '0');
                rx_valid      <= '0';
            else
                rx_valid <= '0';  -- Default: no valid byte

                case rx_state is
                    when RX_ST_IDLE =>
                        rx_tick_cnt   <= 0;
                        rx_sample_cnt <= 0;
                        rx_bit_cnt    <= 0;
                        if rx_sync2 = '0' then  -- Start bit detected
                            rx_state <= RX_ST_START;
                        end if;

                    when RX_ST_START =>
                        if rx_tick_cnt = TICKS_16X - 1 then
                            rx_tick_cnt <= 0;
                            if rx_sample_cnt = OVERSAMPLE - 1 then
                                rx_sample_cnt <= 0;
                            else
                                rx_sample_cnt <= rx_sample_cnt + 1;
                            end if;
                            if rx_sample_cnt = SAMPLE_PT then
                                if rx_sync2 = '0' then
                                    rx_state <= RX_ST_DATA;
                                else
                                    rx_state <= RX_ST_IDLE;  -- False start
                                end if;
                            end if;
                        else
                            rx_tick_cnt <= rx_tick_cnt + 1;
                        end if;

                    when RX_ST_DATA =>
                        if rx_tick_cnt = TICKS_16X - 1 then
                            rx_tick_cnt <= 0;
                            if rx_sample_cnt = OVERSAMPLE - 1 then
                                rx_sample_cnt <= 0;
                            else
                                rx_sample_cnt <= rx_sample_cnt + 1;
                            end if;
                            if rx_sample_cnt = SAMPLE_PT then
                                rx_shift_reg <= rx_sync2 & rx_shift_reg(7 downto 1);
                                if rx_bit_cnt = 7 then
                                    rx_bit_cnt <= 0;
                                    rx_state   <= RX_ST_STOP;
                                else
                                    rx_bit_cnt <= rx_bit_cnt + 1;
                                end if;
                            end if;
                        else
                            rx_tick_cnt <= rx_tick_cnt + 1;
                        end if;

                    when RX_ST_STOP =>
                        if rx_tick_cnt = TICKS_16X - 1 then
                            rx_tick_cnt <= 0;
                            if rx_sample_cnt = OVERSAMPLE - 1 then
                                rx_sample_cnt <= 0;
                            else
                                rx_sample_cnt <= rx_sample_cnt + 1;
                            end if;
                            if rx_sample_cnt = SAMPLE_PT then
                                if rx_sync2 = '1' then
                                    rx_data  <= rx_shift_reg;
                                    rx_valid <= '1';
                                end if;
                                rx_state <= RX_ST_IDLE;
                            end if;
                        else
                            rx_tick_cnt <= rx_tick_cnt + 1;
                        end if;
                end case;
            end if;
        end if;
    end process;

end architecture rtl;

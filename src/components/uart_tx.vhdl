--------------------------------------------------------------------------------
-- UART TX - Generic UART Transmitter
--------------------------------------------------------------------------------
-- Generic UART transmitter for Intel 8008 FPGA implementation
--
-- Features:
--   - Configurable baud rate via generic
--   - Standard 8N1 format (8 data bits, no parity, 1 stop bit)
--   - Simple write interface: write byte when tx_busy = '0'
--   - Busy flag indicates transmission in progress
--   - Fully synchronous design with clock enable
--
-- Usage:
--   1. Wait for tx_busy = '0'
--   2. Set tx_data to desired byte
--   3. Pulse tx_start for one clock cycle
--   4. Monitor tx_busy or wait for completion
--
-- Generics:
--   CLK_FREQ_HZ  : System clock frequency in Hz
--   BAUD_RATE    : Desired baud rate (e.g., 9600, 115200)
--
-- Copyright (c) 2025 Robert Rico
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_tx is
    generic (
        CLK_FREQ_HZ : integer := 100_000_000;  -- Default 100 MHz
        BAUD_RATE   : integer := 9600           -- Default 9600 baud
    );
    port (
        clk      : in  std_logic;
        rst      : in  std_logic;

        -- Transmit interface
        tx_data  : in  std_logic_vector(7 downto 0);
        tx_start : in  std_logic;
        tx_busy  : out std_logic;

        -- UART output
        uart_tx  : out std_logic
    );
end entity uart_tx;

architecture rtl of uart_tx is

    -- Calculate clock divider for baud rate generation
    constant CLKS_PER_BIT : integer := CLK_FREQ_HZ / BAUD_RATE;

    -- State machine for UART transmission
    type uart_state_t is (
        IDLE,       -- Waiting for data
        START_BIT,  -- Transmitting start bit
        DATA_BITS,  -- Transmitting 8 data bits
        STOP_BIT    -- Transmitting stop bit
    );

    signal state      : uart_state_t := IDLE;
    signal bit_timer  : integer range 0 to CLKS_PER_BIT - 1 := 0;
    signal bit_index  : integer range 0 to 7 := 0;
    signal tx_data_sr : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_busy_i  : std_logic := '0';

begin

    -- Output assignments
    tx_busy <= tx_busy_i;

    -- UART TX state machine
    process(clk, rst)
    begin
        if rst = '1' then
            state      <= IDLE;
            bit_timer  <= 0;
            bit_index  <= 0;
            tx_data_sr <= (others => '0');
            uart_tx    <= '1';  -- UART idle is high
            tx_busy_i  <= '0';

        elsif rising_edge(clk) then
            case state is

                when IDLE =>
                    uart_tx   <= '1';  -- UART idle is high
                    tx_busy_i <= '0';
                    bit_timer <= 0;
                    bit_index <= 0;

                    if tx_start = '1' then
                        tx_data_sr <= tx_data;  -- Latch data
                        tx_busy_i  <= '1';
                        state      <= START_BIT;
                    end if;

                when START_BIT =>
                    uart_tx <= '0';  -- Start bit is low

                    if bit_timer < CLKS_PER_BIT - 1 then
                        bit_timer <= bit_timer + 1;
                    else
                        bit_timer <= 0;
                        state     <= DATA_BITS;
                    end if;

                when DATA_BITS =>
                    uart_tx <= tx_data_sr(bit_index);  -- Transmit LSB first

                    if bit_timer < CLKS_PER_BIT - 1 then
                        bit_timer <= bit_timer + 1;
                    else
                        bit_timer <= 0;

                        if bit_index < 7 then
                            bit_index <= bit_index + 1;
                        else
                            bit_index <= 0;
                            state     <= STOP_BIT;
                        end if;
                    end if;

                when STOP_BIT =>
                    uart_tx <= '1';  -- Stop bit is high

                    if bit_timer < CLKS_PER_BIT - 1 then
                        bit_timer <= bit_timer + 1;
                    else
                        bit_timer <= 0;
                        state     <= IDLE;
                    end if;

            end case;
        end if;
    end process;

end architecture rtl;

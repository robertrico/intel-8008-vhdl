-- uart_rx.vhdl
-- Generic UART Receiver
-- Configurable baud rate with 16x oversampling for robust start bit detection
-- Standard 8N1 format (8 data bits, no parity, 1 stop bit), LSB first

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_rx is
    generic (
        CLK_FREQ_HZ : integer := 100_000_000;  -- System clock frequency
        BAUD_RATE   : integer := 9600           -- UART baud rate
    );
    port (
        clk         : in  std_logic;
        rst         : in  std_logic;            -- '0' = running, '1' = reset

        -- Receive interface
        rx_data     : out std_logic_vector(7 downto 0);
        rx_valid    : out std_logic;            -- Pulse when byte received

        -- UART input (must be synchronized externally)
        uart_rx_i   : in  std_logic
    );
end entity uart_rx;

architecture rtl of uart_rx is
    -- 16x oversampling for robust start bit detection and bit centering
    constant OVERSAMPLE_FACTOR : integer := 16;
    constant TICKS_PER_BIT_16X : integer := CLK_FREQ_HZ / (BAUD_RATE * OVERSAMPLE_FACTOR);
    constant SAMPLE_POINT      : integer := 8;  -- Sample at middle (8/16)

    -- State machine
    type state_t is (IDLE, START_BIT, DATA_BITS, STOP_BIT);
    signal state : state_t := IDLE;

    -- Timing counters
    signal tick_counter : integer range 0 to TICKS_PER_BIT_16X-1 := 0;
    signal sample_counter : integer range 0 to OVERSAMPLE_FACTOR-1 := 0;
    signal bit_counter : integer range 0 to 7 := 0;

    -- Data shift register
    signal shift_reg : std_logic_vector(7 downto 0) := (others => '0');

    -- Synchronized RX input (2-stage synchronizer for metastability)
    signal uart_rx_sync1 : std_logic := '1';
    signal uart_rx_sync2 : std_logic := '1';

begin
    -- Two-stage synchronizer to prevent metastability
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                uart_rx_sync1 <= '1';
                uart_rx_sync2 <= '1';
            else
                uart_rx_sync1 <= uart_rx_i;
                uart_rx_sync2 <= uart_rx_sync1;
            end if;
        end if;
    end process;

    -- Main RX state machine
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state <= IDLE;
                tick_counter <= 0;
                sample_counter <= 0;
                bit_counter <= 0;
                shift_reg <= (others => '0');
                rx_data <= (others => '0');
                rx_valid <= '0';

            else
                -- Default: no new data
                rx_valid <= '0';

                case state is
                    when IDLE =>
                        tick_counter <= 0;
                        sample_counter <= 0;
                        bit_counter <= 0;

                        -- Detect start bit (falling edge on RX line)
                        if uart_rx_sync2 = '0' then
                            state <= START_BIT;
                        end if;

                    when START_BIT =>
                        -- Generate 16x oversampling ticks
                        if tick_counter = TICKS_PER_BIT_16X-1 then
                            tick_counter <= 0;

                            -- Increment sample counter (wraps at 16)
                            if sample_counter = OVERSAMPLE_FACTOR-1 then
                                sample_counter <= 0;
                            else
                                sample_counter <= sample_counter + 1;
                            end if;

                            -- Sample at middle of start bit to confirm it's valid
                            if sample_counter = SAMPLE_POINT then
                                if uart_rx_sync2 = '0' then
                                    -- Valid start bit, move to data reception
                                    state <= DATA_BITS;
                                    -- Don't reset sample_counter - let it continue for proper bit timing
                                else
                                    -- False start bit, return to idle
                                    state <= IDLE;
                                end if;
                            end if;
                        else
                            tick_counter <= tick_counter + 1;
                        end if;

                    when DATA_BITS =>
                        if tick_counter = TICKS_PER_BIT_16X-1 then
                            tick_counter <= 0;

                            -- Increment sample counter (wraps at 16)
                            if sample_counter = OVERSAMPLE_FACTOR-1 then
                                sample_counter <= 0;
                            else
                                sample_counter <= sample_counter + 1;
                            end if;

                            -- Sample at middle of each data bit
                            if sample_counter = SAMPLE_POINT then
                                -- Shift in LSB first
                                shift_reg <= uart_rx_sync2 & shift_reg(7 downto 1);

                                if bit_counter = 7 then
                                    -- All 8 bits received, move to stop bit
                                    state <= STOP_BIT;
                                    bit_counter <= 0;
                                    -- Don't reset sample_counter - let it continue
                                else
                                    bit_counter <= bit_counter + 1;
                                    -- Don't reset sample_counter - let it wrap naturally
                                end if;
                            end if;
                        else
                            tick_counter <= tick_counter + 1;
                        end if;

                    when STOP_BIT =>
                        if tick_counter = TICKS_PER_BIT_16X-1 then
                            tick_counter <= 0;

                            -- Increment sample counter (wraps at 16)
                            if sample_counter = OVERSAMPLE_FACTOR-1 then
                                sample_counter <= 0;
                            else
                                sample_counter <= sample_counter + 1;
                            end if;

                            -- Sample stop bit at middle
                            if sample_counter = SAMPLE_POINT then
                                if uart_rx_sync2 = '1' then
                                    -- Valid stop bit, output received byte
                                    rx_data <= shift_reg;
                                    rx_valid <= '1';
                                end if;
                                -- Return to idle regardless (framing error or success)
                                state <= IDLE;
                            end if;
                        else
                            tick_counter <= tick_counter + 1;
                        end if;

                end case;
            end if;
        end if;
    end process;

end architecture rtl;

--------------------------------------------------------------------------------
-- Serial Capture - Bitbang UART Decoder for Simulation
--------------------------------------------------------------------------------
-- Captures bit-banged serial output and decodes it into characters.
-- Designed to work with 8008 programs that use software UART at 2400 baud.
--
-- This is a simulation-only component that:
-- 1. Monitors OUT 8 operations (port 8 writes)
-- 2. Detects start bit (0) and collects 8 data bits + stop bit
-- 3. Reports decoded characters via VHDL report statements
--
-- The timing is based on counting output operations rather than clock cycles,
-- since the 8008 bit-bang routines use specific instruction timing.
--
-- Port 8 bit-bang protocol (LSB of accumulator):
--   Start bit (0) -> 8 data bits LSB first -> Stop bit (1)
--
-- Copyright (c) 2025 Robert Rico
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity serial_capture is
    generic (
        OUTPUT_FILE : string := "serial_output.txt"
    );
    port (
        clk         : in std_logic;
        reset       : in std_logic;

        -- Port 8 output interface
        port_8_data  : in std_logic_vector(7 downto 0);  -- Data written to port 8
        port_8_write : in std_logic;  -- Pulse when OUT 8 executed

        -- Decoded character output (optional, for testbench monitoring)
        char_valid   : out std_logic;
        char_data    : out std_logic_vector(7 downto 0);

        -- Statistics
        char_count   : out integer
    );
end entity serial_capture;

architecture sim of serial_capture is

    -- State machine for bit collection
    type state_t is (
        IDLE,           -- Waiting for start bit (0)
        COLLECTING,     -- Collecting 8 data bits
        STOP_BIT        -- Expecting stop bit (1)
    );
    signal state : state_t := IDLE;

    -- Bit collection
    signal bit_count    : integer range 0 to 8 := 0;
    signal shift_reg    : std_logic_vector(7 downto 0) := (others => '0');
    signal last_bit     : std_logic := '1';

    -- Edge detection for port_8_write
    signal port_8_write_d : std_logic := '0';
    signal port_8_write_rising : std_logic;

    -- Character output
    signal decoded_char : std_logic_vector(7 downto 0) := (others => '0');
    signal char_ready   : std_logic := '0';
    signal total_chars  : integer := 0;

    -- Output file (not currently used, but could be for file logging)
    -- file serial_out_file : text;
    -- signal file_opened : boolean := false;

begin

    char_valid <= char_ready;
    char_data  <= decoded_char;
    char_count <= total_chars;

    -- Edge detection: detect rising edge of port_8_write
    port_8_write_rising <= port_8_write and not port_8_write_d;

    -- Main capture process
    capture_proc : process(clk)
        variable current_bit : std_logic;
    begin
        if rising_edge(clk) then
            -- Delay port_8_write for edge detection
            port_8_write_d <= port_8_write;

            if reset = '1' then
                state       <= IDLE;
                bit_count   <= 0;
                shift_reg   <= (others => '0');
                last_bit    <= '1';
                char_ready  <= '0';
                total_chars <= 0;
                port_8_write_d <= '0';

            else
                char_ready <= '0';  -- Default: no character this cycle

                -- Process port 8 writes - only on RISING EDGE
                if port_8_write_rising = '1' then
                    current_bit := port_8_data(0);  -- LSB is the serial bit
                    last_bit <= current_bit;

                    case state is
                        when IDLE =>
                            -- Waiting for start bit (0)
                            if current_bit = '0' then
                                state     <= COLLECTING;
                                bit_count <= 0;
                                shift_reg <= (others => '0');
                                report "SERIAL_CAPTURE: Start bit detected";
                            end if;

                        when COLLECTING =>
                            -- Shift in data bits (LSB first)
                            shift_reg <= current_bit & shift_reg(7 downto 1);
                            bit_count <= bit_count + 1;

                            if bit_count = 7 then
                                -- Got all 8 data bits, expect stop bit next
                                state <= STOP_BIT;
                            end if;

                        when STOP_BIT =>
                            if current_bit = '1' then
                                -- Valid stop bit - character complete!
                                decoded_char <= shift_reg;
                                char_ready   <= '1';
                                total_chars  <= total_chars + 1;

                                -- Report the character
                                if to_integer(unsigned(shift_reg)) >= 32 and
                                   to_integer(unsigned(shift_reg)) < 127 then
                                    report "SERIAL_OUT: '" &
                                           character'val(to_integer(unsigned(shift_reg))) &
                                           "' (0x" & to_hstring(unsigned(shift_reg)) &
                                           ") [char #" & integer'image(total_chars + 1) & "]";
                                elsif shift_reg = x"0D" then
                                    report "SERIAL_OUT: <CR> (0x0D) [char #" &
                                           integer'image(total_chars + 1) & "]";
                                elsif shift_reg = x"0A" then
                                    report "SERIAL_OUT: <LF> (0x0A) [char #" &
                                           integer'image(total_chars + 1) & "]";
                                else
                                    report "SERIAL_OUT: <0x" & to_hstring(unsigned(shift_reg)) &
                                           "> [char #" & integer'image(total_chars + 1) & "]";
                                end if;

                                state <= IDLE;
                            else
                                -- Framing error - got 0 instead of stop bit
                                report "SERIAL_CAPTURE: Framing error! Expected stop bit (1), got 0"
                                       severity warning;
                                state <= IDLE;
                            end if;
                    end case;
                end if;
            end if;
        end if;
    end process;

end architecture sim;

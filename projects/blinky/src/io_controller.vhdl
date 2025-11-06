--------------------------------------------------------------------------------
-- I/O Controller for Intel 8008 Blinky Project
--------------------------------------------------------------------------------
-- Handles I/O port decoding and management for the 8008 CPU
--
-- Port Map:
--   Port 0x00 (OUT): LED bank (8 bits, active low)
--   Port 0x01 (INP): Button input (8 bits, active high)
--   Port 0x02-0x1F: Reserved for future expansion
--
-- I/O Cycle Detection:
--   - S2,S1,S0 = 100 (INP) or 010 (OUT) during T2 state
--   - D5-D0 during T2 = I/O port address (lower 5 bits used by 8008)
--   - D7-D0 during T3 = data (OUT writes) or data to provide (INP reads)
--
-- Copyright (c) 2025 Robert Rico
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity io_controller is
    port (
        -- Clock and reset
        clk       : in  std_logic;
        reset_n   : in  std_logic;

        -- CPU interface (state signals)
        S2        : in  std_logic;
        S1        : in  std_logic;
        S0        : in  std_logic;
        SYNC      : in  std_logic;

        -- Data bus (bidirectional, connected to CPU)
        data_bus  : inout std_logic_vector(7 downto 0);

        -- Physical I/O pins
        leds      : out std_logic_vector(7 downto 0);  -- Active low
        buttons   : in  std_logic_vector(7 downto 0)   -- Active high
    );
end entity io_controller;

architecture rtl of io_controller is
    -- State machine for I/O cycle tracking
    type state_t is (IDLE, T1, T2, T3);
    signal io_state : state_t;

    -- I/O cycle detection
    signal cycle_type : std_logic_vector(1 downto 0);
    signal is_io_cycle : std_logic;

    -- Port address latch
    signal port_addr : std_logic_vector(4 downto 0);

    -- Output port registers
    signal led_reg : std_logic_vector(7 downto 0);

    -- Data bus control
    signal data_bus_drive : std_logic;
    signal data_bus_out   : std_logic_vector(7 downto 0);

begin
    -- I/O cycle detection: PCC = "10" (I/O cycle)
    is_io_cycle <= '1' when cycle_type = "10" else '0';

    -- Data bus control: Drive bus only during INP T3 cycle
    data_bus <= data_bus_out when data_bus_drive = '1' else (others => 'Z');

    -- LED output (connect register to physical pins)
    leds <= led_reg;

    -- Main I/O controller process
    process(clk, reset_n)
    begin
        if reset_n = '0' then
            io_state       <= IDLE;
            led_reg        <= (others => '1');  -- LEDs off (active low)
            port_addr      <= (others => '0');
            cycle_type     <= (others => '0');
            data_bus_drive <= '0';
            data_bus_out   <= (others => '0');

        elsif rising_edge(clk) then
            -- Default: Don't drive data bus
            data_bus_drive <= '0';

            case io_state is
                when IDLE =>
                    -- Wait for SYNC to indicate start of new cycle
                    if SYNC = '1' then
                        io_state <= T1;
                    end if;

                when T1 =>
                    -- T1 state: Just advance to T2
                    io_state <= T2;
                when T2 =>
                    -- T2 state: Latch cycle type and port address from data bus
                    cycle_type <= data_bus(7 downto 6);
                    port_addr  <= data_bus(4 downto 0);

                    -- Check if this is an I/O cycle
                    if data_bus(7 downto 6) = "10" then
                        io_state <= T3;
                    else
                        -- Not an I/O cycle, return to idle
                        io_state <= IDLE;
                    end if;

                when T3 =>
                    -- T3 state: Perform actual I/O operation

                    -- Check if this is INP or OUT based on port address bit 3
                    -- INP uses ports 0-7 (bit 3 = 0), OUT uses ports 8-23 (bit 3 = 1)
                    if port_addr(3) = '0' then
                        -- INP operation: Drive data bus with input value
                        data_bus_drive <= '1';

                        case port_addr is
                            when "00001" =>  -- Port 1: Button input
                                data_bus_out <= buttons;

                            when others =>
                                -- Reserved ports: return 0xFF
                                data_bus_out <= (others => '1');
                        end case;
                    else
                        -- OUT operation: Write data bus to output register
                        case port_addr is
                            when "01000" =>  -- Port 8: LED output
                                led_reg <= data_bus;

                            when others =>
                                -- Reserved ports: no action
                                null;
                        end case;
                    end if;

                    -- Return to idle after T3
                    io_state <= IDLE;

                when others =>
                    io_state <= IDLE;

            end case;
        end if;
    end process;

end architecture rtl;

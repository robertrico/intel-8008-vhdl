--------------------------------------------------------------------------------
-- Simple I/O Controller for Intel 8008 Blinky Project
--------------------------------------------------------------------------------
-- Handles LED output only - simplified design
--
-- Operation:
--   1. Detects I/O cycles (cycle type "11" in T2)
--   2. Captures port address from T2 data bus bits[4:0]
--   3. Latches LED data from T3 data bus when port 8 is addressed
--
-- This controller does NOT drive the data bus - it only reads from it
-- and controls LED outputs based on OUT instructions to port 8
--
-- Copyright (c) 2025 Robert Rico
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity io_controller_simple is
    port (
        -- Clock and reset
        phi1      : in  std_logic;
        reset_n   : in  std_logic;

        -- CPU state signals
        S2        : in  std_logic;
        S1        : in  std_logic;
        S0        : in  std_logic;

        -- Data bus (read-only for this controller)
        data_bus  : in std_logic_vector(7 downto 0);

        -- LED outputs (active low)
        leds      : out std_logic_vector(7 downto 0)
    );
end entity io_controller_simple;

architecture rtl of io_controller_simple is
    -- State detection signals
    signal is_t2 : std_logic;
    signal is_t3 : std_logic;

    -- Captured I/O cycle information
    signal cycle_type : std_logic_vector(1 downto 0);
    signal port_addr  : std_logic_vector(4 downto 0);
    signal is_io_cycle : std_logic;

    -- LED register
    signal led_reg : std_logic_vector(7 downto 0);

begin
    -- Detect CPU states
    is_t2 <= '1' when (S2 = '1' and S1 = '0' and S0 = '0') else '0';
    is_t3 <= '1' when (S2 = '0' and S1 = '0' and S0 = '1') else '0';

    -- I/O cycle detection: cycle type "11" means PCC (I/O)
    is_io_cycle <= '1' when cycle_type = "11" else '0';

    -- Output LED register to physical pins
    leds <= led_reg;

    -- Main control process
    process(phi1, reset_n)
    begin
        if reset_n = '0' then
            led_reg <= (others => '1');  -- LEDs off (active low)
            cycle_type <= "00";
            port_addr <= (others => '0');

        elsif rising_edge(phi1) then
            -- T2 state: Capture cycle type and port address from data bus
            if is_t2 = '1' then
                cycle_type <= data_bus(7 downto 6);  -- Bits [7:6] = cycle type
                port_addr  <= data_bus(4 downto 0);  -- Bits [4:0] = port address
            end if;

            -- T3 state: If this is an I/O cycle to port 8, latch LED data
            -- Check the cycle type captured during the PREVIOUS T2 state
            if is_t3 = '1' then
                -- Check if previous cycle was I/O (cycle_type = "11")
                -- and port address is port 8 (OUT ports are 8-15, port 8 = "01000")
                if cycle_type = "11" and port_addr = "01000" then
                    led_reg <= data_bus;
                end if;
            end if;
        end if;
    end process;

end architecture rtl;

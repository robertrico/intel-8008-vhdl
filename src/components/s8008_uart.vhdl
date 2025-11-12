--------------------------------------------------------------------------------
-- s8008_uart - Silicon 8008 UART Interface Component
--------------------------------------------------------------------------------
-- UART peripheral with integrated 8008 I/O bus interface
--
-- Features:
--   - Automatic I/O cycle detection for specific port addresses
--   - Transmitter with configurable baud rate
--   - Status and data registers accessible via 8008 I/O ports
--   - Handles duplicate character transmission correctly
--
-- I/O Port Configuration:
--   TX_DATA_PORT (default 10): OUT - Write byte to transmit
--   TX_STATUS_PORT (default 0): IN  - Read status (bit 0 = tx_busy)
--
-- Usage from 8008 assembly:
--   ; Check if UART is ready
--   INP TX_STATUS_PORT
--   ANI 0x01            ; Check tx_busy bit
--   JNZ wait_ready      ; Loop if busy
--
--   ; Send character
--   MVI A, 'H'
--   OUT TX_DATA_PORT
--
-- The component automatically detects writes to TX_DATA_PORT by monitoring
-- the 8008 bus state signals and triggers transmission.
--
-- Copyright (c) 2025 Robert Rico
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity s8008_uart is
    generic (
        CLK_FREQ_HZ      : integer := 100_000_000;  -- System clock frequency
        BAUD_RATE        : integer := 9600;         -- UART baud rate
        TX_DATA_PORT     : integer := 10;           -- Output port for TX data (8-31)
        TX_STATUS_PORT   : integer := 0             -- Input port for status (0-7)
    );
    port (
        -- System interface
        clk      : in  std_logic;
        rst      : in  std_logic;      -- Active high reset

        -- Intel 8008 CPU interface
        phi1     : in  std_logic;      -- Phase 1 clock
        reset_n  : in  std_logic;      -- Active low reset for CPU logic
        S2       : in  std_logic;      -- CPU state signals
        S1       : in  std_logic;
        S0       : in  std_logic;
        data_bus : in  std_logic_vector(7 downto 0);

        -- I/O port interface
        tx_status_out  : out std_logic_vector(7 downto 0);  -- To io_controller port_in

        -- UART physical interface
        uart_tx : out std_logic
    );
end entity s8008_uart;

architecture rtl of s8008_uart is

    -- Signals for UART TX engine
    signal tx_start       : std_logic := '0';
    signal tx_busy        : std_logic;
    signal tx_data_latched : std_logic_vector(7 downto 0) := (others => '0');

    -- Write detection signals
    signal port_write_pending : std_logic := '0';

    -- Reset stabilization counter - wait for system to stabilize after reset
    signal reset_stable_counter : unsigned(3 downto 0) := (others => '0');
    signal reset_stable : std_logic := '0';

begin

    --------------------------------------------------------------------------------
    -- UART TX Engine
    --------------------------------------------------------------------------------
    -- Use direct entity instantiation to avoid component declaration naming conflict
    --------------------------------------------------------------------------------
    u_uart_tx_engine : entity work.uart_tx(rtl)
        generic map (
            CLK_FREQ_HZ => CLK_FREQ_HZ,
            BAUD_RATE   => BAUD_RATE
        )
        port map (
            clk      => clk,
            rst      => rst,
            tx_data  => tx_data_latched,
            tx_start => tx_start,
            tx_busy  => tx_busy,
            uart_tx  => uart_tx
        );

    -- Status output: bit 0 = tx_busy, rest = 0
    tx_status_out <= "0000000" & tx_busy;

    --------------------------------------------------------------------------------
    -- 8008 I/O Write Detection
    --------------------------------------------------------------------------------
    -- Detects writes to TX_DATA_PORT by monitoring I/O cycles
    --
    -- Strategy:
    --   1. At T2: Check if data_bus indicates cycle_type="11" (I/O) and
    --      port_addr = TX_DATA_PORT
    --   2. Set flag port_write_pending
    --   3. At T3: If flag is set, latch data and pulse tx_start
    --   4. Clear flag after use
    --
    -- This approach detects EVERY write, including duplicate values.
    --------------------------------------------------------------------------------
    process(phi1, reset_n)
        variable is_t2 : std_logic;
        variable is_t3 : std_logic;
    begin
        if reset_n = '0' then
            tx_start <= '0';
            port_write_pending <= '0';
            tx_data_latched <= (others => '0');
            reset_stable_counter <= (others => '0');
            reset_stable <= '0';

        elsif rising_edge(phi1) then
            -- Default: clear tx_start unless we set it this cycle
            tx_start <= '0';

            -- Wait for system to stabilize after reset (count 15 cycles)
            if reset_stable_counter < 15 then
                reset_stable_counter <= reset_stable_counter + 1;
            else
                reset_stable <= '1';
            end if;

            -- Only process I/O cycles after reset is stable
            if reset_stable = '1' then
                -- Decode CPU states
                is_t2 := '0';
                is_t3 := '0';

                if S2 = '1' and S1 = '0' and S0 = '0' then
                    is_t2 := '1';  -- T2: cycle type + address on data bus
                elsif S2 = '0' and S1 = '0' and S0 = '1' then
                    is_t3 := '1';  -- T3: data transfer happens
                end if;

                -- At T2: Check if this is an output to TX_DATA_PORT
                -- data_bus bits [7:6] = cycle type ("11" for I/O)
                -- data_bus bits [4:0] = port address
                if is_t2 = '1' then
                    if data_bus(7 downto 6) = "11" and
                       unsigned(data_bus(4 downto 0)) = TX_DATA_PORT then
                        port_write_pending <= '1';
                    else
                        -- Clear pending if T2 is NOT for our port
                        port_write_pending <= '0';
                    end if;
                end if;

                -- At T3: If pending write to TX_DATA_PORT, latch data from bus and start TX
                if is_t3 = '1' and port_write_pending = '1' then
                    tx_data_latched <= data_bus;  -- Latch directly from data bus during T3
                    tx_start <= '1';
                    port_write_pending <= '0';  -- Clear flag after use
                end if;
            end if;
        end if;
    end process;

end architecture rtl;

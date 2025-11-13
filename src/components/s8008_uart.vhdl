--------------------------------------------------------------------------------
-- s8008_uart - Silicon 8008 UART Interface Component
--------------------------------------------------------------------------------
-- UART peripheral with integrated 8008 I/O bus interface
--
-- Features:
--   - Automatic I/O cycle detection for specific port addresses
--   - Transmitter with configurable baud rate
--   - Receiver with configurable baud rate (optional)
--   - Status and data registers accessible via 8008 I/O ports
--   - Handles duplicate character transmission correctly
--   - Read-clear mechanism for RX data
--
-- I/O Port Configuration:
--   TX_DATA_PORT (default 10): OUT - Write byte to transmit
--   TX_STATUS_PORT (default 0): IN  - Read status (bit 0 = tx_busy)
--   RX_DATA_PORT (default 1): IN  - Read received byte (clears rx_ready)
--   RX_STATUS_PORT (default 2): IN  - Read status (bit 0 = rx_ready)
--
-- Usage from 8008 assembly:
--   ; Transmit
--   INP TX_STATUS_PORT
--   ANI 0x01            ; Check tx_busy bit
--   JNZ wait_ready      ; Loop if busy
--   MVI A, 'H'
--   OUT TX_DATA_PORT
--
--   ; Receive
--   INP RX_STATUS_PORT
--   ANI 0x01            ; Check rx_ready bit
--   JZ wait_rx          ; Loop if no data
--   INP RX_DATA_PORT    ; Read byte (clears rx_ready)
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
        TX_STATUS_PORT   : integer := 0;            -- Input port for TX status (0-7)
        RX_DATA_PORT     : integer := 1;            -- Input port for RX data (0-7)
        RX_STATUS_PORT   : integer := 2;            -- Input port for RX status (0-7)
        ENABLE_RX        : boolean := false         -- Enable RX functionality
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
        rx_status_out  : out std_logic_vector(7 downto 0);  -- To io_controller port_in
        rx_data_out    : out std_logic_vector(7 downto 0);  -- To io_controller port_in

        -- UART physical interface
        uart_tx : out std_logic;
        uart_rx : in  std_logic := '1'
    );
end entity s8008_uart;

architecture rtl of s8008_uart is

    -- Signals for UART TX engine
    signal tx_start       : std_logic := '0';
    signal tx_busy        : std_logic;
    signal tx_data_latched : std_logic_vector(7 downto 0) := (others => '0');

    -- Signals for UART RX engine
    signal rx_data_internal : std_logic_vector(7 downto 0) := (others => '0');
    signal rx_valid         : std_logic;
    signal rx_ready         : std_logic := '0';  -- Latched flag: data available (clk domain)
    signal rx_ready_phi1    : std_logic := '0';  -- Synchronized rx_ready for phi1 domain
    signal rx_data_latched  : std_logic_vector(7 downto 0) := (others => '0');

    -- Write detection signal (TX only)
    signal port_write_pending : std_logic := '0';

    -- Read detection signal (RX only)
    signal port_read_pending : std_logic := '0';
    signal rx_read_clear_phi1 : std_logic := '0';  -- Pulse on phi1 clock
    signal rx_read_clear_sync : std_logic_vector(2 downto 0) := (others => '0');  -- Synchronizer to clk domain
    signal rx_read_clear : std_logic;  -- Synchronized signal in clk domain

    -- Clock domain crossing for rx_ready (clk -> phi1)
    signal rx_ready_sync : std_logic_vector(2 downto 0) := (others => '0');  -- Synchronizer from clk to phi1
    signal cleared_locally : std_logic := '0';  -- Track if we cleared rx_ready_phi1 locally

    -- Reset stabilization counter - wait for system to stabilize after reset
    signal reset_stable_counter : unsigned(3 downto 0) := (others => '0');
    signal reset_stable : std_logic := '0';

begin

    --------------------------------------------------------------------------------
    -- UART TX Engine
    --------------------------------------------------------------------------------
    u_uart_tx_engine : entity work.uart_tx(rtl)
        generic map (
            CLK_FREQ_HZ => CLK_FREQ_HZ,
            BAUD_RATE   => BAUD_RATE
        )
        port map (
            clk       => clk,
            rst       => rst,
            tx_data   => tx_data_latched,
            tx_start  => tx_start,
            tx_busy   => tx_busy,
            uart_tx_o => uart_tx
        );

    --------------------------------------------------------------------------------
    -- UART RX Engine (conditional)
    --------------------------------------------------------------------------------
    gen_rx : if ENABLE_RX generate
        u_uart_rx_engine : entity work.uart_rx(rtl)
            generic map (
                CLK_FREQ_HZ => CLK_FREQ_HZ,
                BAUD_RATE   => BAUD_RATE
            )
            port map (
                clk       => clk,
                rst       => rst,
                rx_data   => rx_data_internal,
                rx_valid  => rx_valid,
                uart_rx_i => uart_rx
            );
    end generate gen_rx;

    -- Status outputs
    tx_status_out <= "0000000" & tx_busy;
    rx_status_out <= "0000000" & rx_ready_phi1;  -- Use phi1-synchronized version
    rx_data_out   <= rx_data_latched;

    --------------------------------------------------------------------------------
    -- Clock Domain Crossing: rx_read_clear from phi1 to clk
    --------------------------------------------------------------------------------
    -- Synchronize the read-clear pulse from phi1 domain to clk domain
    -- Use edge detection: when sync chain goes from '0' to '1', pulse rx_read_clear
    --------------------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                rx_read_clear_sync <= (others => '0');
            else
                -- Shift register synchronizer
                rx_read_clear_sync <= rx_read_clear_sync(1 downto 0) & rx_read_clear_phi1;
            end if;
        end if;
    end process;

    -- Edge detect: pulse when sync goes high
    rx_read_clear <= '1' when rx_read_clear_sync(2) = '0' and rx_read_clear_sync(1) = '1' else '0';

    --------------------------------------------------------------------------------
    -- Clock Domain Crossing: rx_ready from clk to phi1
    --------------------------------------------------------------------------------
    -- Synchronize rx_ready from clk domain to phi1 domain
    -- Clear immediately on read to prevent double-reading due to sync delay
    --------------------------------------------------------------------------------
    process(phi1, reset_n)
    begin
        if reset_n = '0' then
            rx_ready_sync <= (others => '0');
            rx_ready_phi1 <= '0';
            cleared_locally <= '0';
        elsif rising_edge(phi1) then
            -- 3-stage synchronizer from clk to phi1
            rx_ready_sync <= rx_ready_sync(1 downto 0) & rx_ready;

            -- If CPU reads (T3 with pending read), clear immediately
            if port_read_pending = '1' and (S2 = '0' and S1 = '0' and S0 = '1') then
                rx_ready_phi1 <= '0';
                cleared_locally <= '1';  -- Remember we cleared it
            -- If we cleared locally, wait until clk domain confirms clear
            elsif cleared_locally = '1' then
                -- Keep rx_ready_phi1 low while waiting
                rx_ready_phi1 <= '0';
                -- Only release when clk domain shows cleared
                if rx_ready_sync(2) = '0' then
                    cleared_locally <= '0';
                end if;
            -- Normal operation: follow synchronized signal
            else
                rx_ready_phi1 <= rx_ready_sync(2);
            end if;
        end if;
    end process;


    --------------------------------------------------------------------------------
    -- RX Data Latching (conditional)
    --------------------------------------------------------------------------------
    -- When uart_rx engine pulses rx_valid, latch the data and set rx_ready flag
    -- Always overwrite with latest byte (no FIFO - simple last-byte-wins behavior)
    --------------------------------------------------------------------------------
    gen_rx_latch : if ENABLE_RX generate
        process(clk)
        begin
            if rising_edge(clk) then
                if rst = '1' then
                    rx_ready <= '0';
                    rx_data_latched <= (others => '0');
                else
                    -- Handle clearing and latching independently to avoid losing data
                    -- If both happen in same cycle, latch wins (new data is more important)
                    if rx_valid = '1' then
                        -- When new byte received, ALWAYS latch it (overwrite if needed)
                        rx_data_latched <= rx_data_internal;
                        rx_ready <= '1';
                    elsif rx_read_clear = '1' then
                        -- Clear rx_ready when CPU reads the data (only if no new data)
                        rx_ready <= '0';
                    end if;
                end if;
            end if;
        end process;
    end generate gen_rx_latch;

    --------------------------------------------------------------------------------
    -- 8008 I/O Read/Write Detection
    --------------------------------------------------------------------------------
    -- Detects writes to TX_DATA_PORT and reads from RX_DATA_PORT
    --
    -- TX Strategy:
    --     1. At T2: Check if data_bus indicates cycle_type="11" (PCC/output) and
    --        port_addr = TX_DATA_PORT
    --     2. Set flag port_write_pending
    --     3. At T3: If flag is set, latch data and pulse tx_start
    --     4. Clear flag after use
    --
    -- RX Strategy:
    --     1. At T2: Check if data_bus indicates cycle_type="01" (PCI/input) and
    --        port_addr = RX_DATA_PORT
    --     2. Set flag port_read_pending
    --     3. At T3: If flag is set, pulse rx_read_clear to clear rx_ready
    --     4. Clear flag after use
    --------------------------------------------------------------------------------
    process(phi1, reset_n)
        variable is_t2 : std_logic;
        variable is_t3 : std_logic;
        variable port_addr : integer range 0 to 31;
    begin
        if reset_n = '0' then
            tx_start <= '0';
            port_write_pending <= '0';
            port_read_pending <= '0';
            rx_read_clear_phi1 <= '0';
            tx_data_latched <= (others => '0');
            reset_stable_counter <= (others => '0');
            reset_stable <= '0';

        elsif rising_edge(phi1) then
            -- Default: clear pulses unless we set them this cycle
            tx_start <= '0';
            rx_read_clear_phi1 <= '0';

            -- Wait for system to stabilize after reset (count 15 cycles)
            if reset_stable_counter < 15 then
                reset_stable_counter <= reset_stable_counter + 1;
            elsif reset_stable = '0' then
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

                -- At T2: Check cycle type and port address
                if is_t2 = '1' then
                    port_addr := to_integer(unsigned(data_bus(4 downto 0)));

                    if data_bus(7 downto 6) = "11" then
                        -- PCC cycle: I/O or stack operations
                        -- Intel 8008: INP uses ports 0-7, OUT uses ports 8-31
                        if port_addr < 8 then
                            -- INP (input from port 0-7)
                            if port_addr = RX_DATA_PORT then
                                port_read_pending <= '1';
                            else
                                port_read_pending <= '0';
                            end if;
                            port_write_pending <= '0';
                        else
                            -- OUT (output to port 8-31)
                            if port_addr = TX_DATA_PORT then
                                port_write_pending <= '1';
                            else
                                port_write_pending <= '0';
                            end if;
                            port_read_pending <= '0';
                        end if;

                    else
                        -- Other cycle type (PCI, PCR, PCW)
                        port_write_pending <= '0';
                        port_read_pending <= '0';
                    end if;
                end if;

                -- At T3: Process pending operations
                if is_t3 = '1' then
                    if port_write_pending = '1' then
                        -- TX: Latch data from bus and start transmission
                        tx_data_latched <= data_bus;
                        tx_start <= '1';
                        port_write_pending <= '0';
                    end if;

                    if port_read_pending = '1' then
                        -- RX: Clear rx_ready flag (data was read)
                        rx_read_clear_phi1 <= '1';
                        port_read_pending <= '0';
                    end if;
                end if;
            end if;
        end if;
    end process;

end architecture rtl;

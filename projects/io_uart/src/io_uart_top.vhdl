--------------------------------------------------------------------------------
-- IO UART Top Level - b8008 UART I/O Demo Project
--------------------------------------------------------------------------------
-- UART demo for the b8008 CPU with external UART peripheral.
--
-- Uses b8008_top (proven, working CPU+ROM+RAM) with UART as external peripheral.
--
-- I/O Port Mapping:
--   IN 1:   UART RX - bit 7 = ready flag, bits 6:0 = received data
--   OUT 8:  LED bank (directly active, accent active low)
--   OUT 9:  UART TX - sends byte immediately at 115200 baud
--
-- UART Settings:
--   Baud Rate: 115200
--   Format: 8N1 (8 data bits, no parity, 1 stop bit)
--
-- Hardware Connection:
--   Connect FTDI USB-to-serial adapter:
--     FPGA TX (B19) -> FTDI RX
--     FPGA RX (B12) -> FTDI TX
--     GND -> GND
--
-- Copyright (c) 2025 Robert Rico
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity io_uart_top is
    port (
        -- System clock (100 MHz LVDS)
        clk         : in  std_logic;

        -- DIP switches
        sw          : in  std_logic_vector(7 downto 0);

        -- Button input
        speed_btn   : in  std_logic;

        -- LED outputs
        led         : out std_logic_vector(7 downto 0);
        led_M20     : out std_logic;
        led_L18     : out std_logic;

        -- UART interface
        uart_tx     : out std_logic;
        uart_rx     : in  std_logic;

        -- CPU debug outputs (directly from b8008 for logic analyzer)
        cpu_d       : out std_logic_vector(7 downto 0);  -- Data bus (directly active directly wired)
        cpu_s0      : out std_logic;
        cpu_s1      : out std_logic;
        cpu_s2      : out std_logic;
        cpu_sync    : out std_logic;
        cpu_phi1    : out std_logic;
        cpu_phi2    : out std_logic;
        cpu_ready   : out std_logic;
        cpu_int     : out std_logic;

        -- Additional debug outputs for oscilloscope/logic analyzer
        dbg_reset_int      : out std_logic;  -- Internal reset signal
        dbg_bootstrap_int  : out std_logic;  -- Bootstrap interrupt active
        dbg_bootstrap_done : out std_logic;  -- Bootstrap completed
        dbg_state_half     : out std_logic;  -- Which half of 2-cycle state
        dbg_int_pending    : out std_logic   -- CPU interrupt pending
    );
end entity io_uart_top;

architecture rtl of io_uart_top is

    --------------------------------------------------------------------------------
    -- Component: b8008_top (CPU with ROM and RAM)
    --------------------------------------------------------------------------------
    component b8008_top is
        generic (
            ROM_FILE : string := "test_programs/alu_test_as.mem"
        );
        port (
            clk_in      : in std_logic;
            reset       : in std_logic;
            interrupt   : in std_logic;
            int_vector  : in std_logic_vector(2 downto 0);
            phi1_out    : out std_logic;
            phi2_out    : out std_logic;
            sync_out    : out std_logic;
            s0_out      : out std_logic;
            s1_out      : out std_logic;
            s2_out      : out std_logic;
            address_out : out std_logic_vector(13 downto 0);
            data_out    : out std_logic_vector(7 downto 0);
            ram_byte_0  : out std_logic_vector(7 downto 0);
            debug_reg_a         : out std_logic_vector(7 downto 0);
            debug_reg_b         : out std_logic_vector(7 downto 0);
            debug_reg_c         : out std_logic_vector(7 downto 0);
            debug_reg_d         : out std_logic_vector(7 downto 0);
            debug_reg_e         : out std_logic_vector(7 downto 0);
            debug_reg_h         : out std_logic_vector(7 downto 0);
            debug_reg_l         : out std_logic_vector(7 downto 0);
            debug_cycle         : out std_logic_vector(1 downto 0);
            debug_pc            : out std_logic_vector(13 downto 0);
            debug_ir            : out std_logic_vector(7 downto 0);
            debug_needs_address : out std_logic;
            debug_int_pending   : out std_logic;
            debug_flag_carry    : out std_logic;
            debug_flag_zero     : out std_logic;
            debug_flag_sign     : out std_logic;
            debug_flag_parity   : out std_logic;
            debug_io_port_8     : out std_logic_vector(7 downto 0);
            debug_io_port_9     : out std_logic_vector(7 downto 0);
            debug_io_port_10    : out std_logic_vector(7 downto 0);
            debug_state_half    : out std_logic;
            -- External I/O port interface
            io_port_in          : in  std_logic_vector(7 downto 0);
            io_port_in_select   : in  std_logic_vector(2 downto 0);
            io_port_in_enable   : in  std_logic;
            io_port_out         : out std_logic_vector(7 downto 0);
            io_port_num_out     : out std_logic_vector(4 downto 0);
            io_port_write       : out std_logic
        );
    end component;

    --------------------------------------------------------------------------------
    -- Component: USART (combined TX/RX)
    --------------------------------------------------------------------------------
    component usart is
        generic (
            CLK_FREQ_HZ : integer := 100_000_000;
            BAUD_RATE   : integer := 2400
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

    --------------------------------------------------------------------------------
    -- Internal Signals
    --------------------------------------------------------------------------------
    -- POR (Power-On Reset) and reset control
    signal por_active   : std_logic := '1';
    signal reset_sync   : std_logic_vector(2 downto 0) := (others => '1');
    signal reset_sw     : std_logic;
    signal reset_int    : std_logic;

    -- CPU signals
    signal phi1         : std_logic;
    signal phi2         : std_logic;
    signal sync_sig     : std_logic;
    signal s0_sig       : std_logic;
    signal s1_sig       : std_logic;
    signal s2_sig       : std_logic;

    -- Bootstrap interrupt control
    signal bootstrap_int     : std_logic := '0';
    signal bootstrap_done    : std_logic := '0';
    signal bootstrap_counter : unsigned(7 downto 0) := (others => '0');

    -- I/O port signals
    signal io_port_8    : std_logic_vector(7 downto 0);
    signal io_port_9    : std_logic_vector(7 downto 0);
    signal io_port_10   : std_logic_vector(7 downto 0);
    signal io_port_out  : std_logic_vector(7 downto 0);
    signal io_port_num  : std_logic_vector(4 downto 0);
    signal io_port_write : std_logic;

    -- UART signals
    signal uart_tx_data   : std_logic_vector(7 downto 0);
    signal uart_tx_start  : std_logic := '0';
    signal uart_tx_busy   : std_logic;
    signal uart_rx_data   : std_logic_vector(7 downto 0);
    signal uart_rx_valid  : std_logic;
    signal uart_rx_ready  : std_logic := '0';  -- Latched: '1' when byte available

    -- UART RX data latch (holds received byte until CPU reads it)
    signal uart_rx_latch  : std_logic_vector(7 downto 0) := (others => '0');

    -- External I/O port input (for INP 1 - UART RX)
    signal io_port_in_data : std_logic_vector(7 downto 0);

    -- Unused debug signals
    signal address_sig      : std_logic_vector(13 downto 0);
    signal data_sig         : std_logic_vector(7 downto 0);
    signal debug_reg_a, debug_reg_b, debug_reg_c : std_logic_vector(7 downto 0);
    signal debug_reg_d, debug_reg_e, debug_reg_h, debug_reg_l : std_logic_vector(7 downto 0);
    signal debug_cycle  : std_logic_vector(1 downto 0);
    signal debug_pc_sig : std_logic_vector(13 downto 0);
    signal debug_ir     : std_logic_vector(7 downto 0);
    signal debug_needs_address : std_logic;
    signal int_pending_sig : std_logic;
    signal debug_flag_carry, debug_flag_zero, debug_flag_sign, debug_flag_parity : std_logic;
    signal ram_byte_0   : std_logic_vector(7 downto 0);
    signal state_half_sig : std_logic;

    -- Clock counter for POR timing
    signal clk_counter : unsigned(25 downto 0) := (others => '0');

begin

    --------------------------------------------------------------------------------
    -- Power-On Reset (POR)
    --------------------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            clk_counter <= clk_counter + 1;
            if clk_counter(19) = '1' then
                por_active <= '0';
            end if;
        end if;
    end process;

    --------------------------------------------------------------------------------
    -- Reset Synchronization
    --------------------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            reset_sync <= reset_sync(1 downto 0) & sw(0);
        end if;
    end process;

    reset_sw <= reset_sync(2);
    reset_int <= por_active or reset_sw;

    --------------------------------------------------------------------------------
    -- Bootstrap Interrupt Control
    --------------------------------------------------------------------------------
    process(phi2, reset_int)
    begin
        if reset_int = '1' then
            bootstrap_int     <= '0';
            bootstrap_done    <= '0';
            bootstrap_counter <= (others => '0');
        elsif rising_edge(phi2) then
            if bootstrap_done = '0' then
                bootstrap_int <= '1';
                bootstrap_counter <= bootstrap_counter + 1;
                if bootstrap_counter >= 16 then
                    if s2_sig = '1' and s1_sig = '1' and s0_sig = '0' then
                        bootstrap_int  <= '0';
                        bootstrap_done <= '1';
                    end if;
                end if;
            end if;
        end if;
    end process;

    --------------------------------------------------------------------------------
    -- b8008 CPU System Instance
    --------------------------------------------------------------------------------
    u_system : b8008_top
        generic map (
            ROM_FILE => "./io_uart.mem"
        )
        port map (
            clk_in      => clk,
            reset       => reset_int,
            interrupt   => bootstrap_int,
            int_vector  => "000",  -- RST 0 for bootstrap
            phi1_out    => phi1,
            phi2_out    => phi2,
            sync_out    => sync_sig,
            s0_out      => s0_sig,
            s1_out      => s1_sig,
            s2_out      => s2_sig,
            address_out => address_sig,
            data_out    => data_sig,
            ram_byte_0  => ram_byte_0,
            debug_reg_a         => debug_reg_a,
            debug_reg_b         => debug_reg_b,
            debug_reg_c         => debug_reg_c,
            debug_reg_d         => debug_reg_d,
            debug_reg_e         => debug_reg_e,
            debug_reg_h         => debug_reg_h,
            debug_reg_l         => debug_reg_l,
            debug_cycle         => debug_cycle,
            debug_pc            => debug_pc_sig,
            debug_ir            => debug_ir,
            debug_needs_address => debug_needs_address,
            debug_int_pending   => int_pending_sig,
            debug_flag_carry    => debug_flag_carry,
            debug_flag_zero     => debug_flag_zero,
            debug_flag_sign     => debug_flag_sign,
            debug_flag_parity   => debug_flag_parity,
            debug_io_port_8     => io_port_8,
            debug_io_port_9     => io_port_9,
            debug_io_port_10    => io_port_10,
            debug_state_half    => state_half_sig,
            -- External I/O port interface (DISABLED for debugging)
            io_port_in          => io_port_in_data,
            io_port_in_select   => "001",  -- Port 1 uses external input
            io_port_in_enable   => '0',    -- DISABLED - use internal test values
            io_port_out         => io_port_out,
            io_port_num_out     => io_port_num,
            io_port_write       => io_port_write
        );

    --------------------------------------------------------------------------------
    -- USART Instance (115200 baud)
    --------------------------------------------------------------------------------
    u_uart : usart
        generic map (
            CLK_FREQ_HZ => 100_000_000,
            BAUD_RATE   => 115200
        )
        port map (
            clk         => clk,
            rst         => reset_int,
            tx_data     => uart_tx_data,
            tx_start    => uart_tx_start,
            tx_busy     => uart_tx_busy,
            rx_data     => uart_rx_data,
            rx_valid    => uart_rx_valid,
            uart_tx     => uart_tx,
            uart_rx     => uart_rx
        );

    --------------------------------------------------------------------------------
    -- UART TX Control: Trigger on OUT 9
    --------------------------------------------------------------------------------
    -- When OUT 9 executes (io_port_num = 9 and io_port_write = '1'),
    -- send the byte to UART TX
    process(clk, reset_int)
    begin
        if reset_int = '1' then
            uart_tx_data  <= (others => '0');
            uart_tx_start <= '0';
        elsif rising_edge(clk) then
            -- Default: clear start strobe
            uart_tx_start <= '0';

            -- Check for OUT 9 (port 9 = "01001")
            if io_port_write = '1' and io_port_num = "01001" then
                -- Capture data and trigger TX
                uart_tx_data  <= io_port_out;
                uart_tx_start <= '1';
            end if;
        end if;
    end process;

    --------------------------------------------------------------------------------
    -- UART RX Control: Latch received data for INP 1
    --------------------------------------------------------------------------------
    -- When UART receives a byte, latch it and set ready flag.
    -- INP 1 returns: bit 7 = ready flag, bits 6:0 = received data
    -- The ready flag clears when a new byte is latched (simple auto-clear)
    process(clk, reset_int)
    begin
        if reset_int = '1' then
            uart_rx_latch <= (others => '0');
            uart_rx_ready <= '0';
        elsif rising_edge(clk) then
            -- When UART receives a byte, latch it
            if uart_rx_valid = '1' then
                uart_rx_latch <= uart_rx_data;
                uart_rx_ready <= '1';
            end if;
            -- Note: For proper handshaking, the CPU should clear the ready flag
            -- after reading. For this simple demo, we just overwrite on new data.
        end if;
    end process;

    -- INP 1 data: bit 7 = ready, bits 6:0 = received data
    io_port_in_data <= uart_rx_ready & uart_rx_latch(6 downto 0);

    --------------------------------------------------------------------------------
    -- LED Outputs
    --------------------------------------------------------------------------------
    -- Drive LEDs from CPU I/O port 8 output (directly active, accent active low)
    led <= io_port_8;

    -- M20: UART TX busy indicator
    led_M20 <= not uart_tx_busy;

    -- L18: Reset indicator (off when running)
    led_L18 <= reset_int;

    --------------------------------------------------------------------------------
    -- CPU Debug Outputs (directly connected for logic analyzer)
    --------------------------------------------------------------------------------
    cpu_d       <= data_sig;  -- Actual data bus
    cpu_s0      <= s0_sig;
    cpu_s1      <= s1_sig;
    cpu_s2      <= s2_sig;
    cpu_sync    <= sync_sig;
    cpu_phi1    <= phi1;
    cpu_phi2    <= phi2;
    cpu_ready   <= '1';  -- Always ready
    cpu_int     <= bootstrap_int;

    --------------------------------------------------------------------------------
    -- Additional Debug Outputs
    --------------------------------------------------------------------------------
    dbg_reset_int      <= reset_int;
    dbg_bootstrap_int  <= bootstrap_int;
    dbg_bootstrap_done <= bootstrap_done;
    dbg_state_half     <= state_half_sig;
    dbg_int_pending    <= int_pending_sig;

end architecture rtl;

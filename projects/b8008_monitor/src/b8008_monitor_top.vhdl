--------------------------------------------------------------------------------
-- B8008 Monitor Top Level - Interactive Console
--------------------------------------------------------------------------------
-- Interactive monitor/console for the b8008 CPU with UART peripheral.
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

entity b8008_monitor_top is
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
        dbg_int_pending    : out std_logic;  -- CPU interrupt pending

        -- Debug buttons (directly to GPIO, active low with pull-up)
        dbg_btn_run_stop  : in std_logic;   -- Run/Stop toggle
        dbg_btn_step_cycle : in std_logic;  -- Single full cycle step (220 clocks)
        dbg_btn_step_sync : in std_logic    -- Step to SYNC (instruction boundary)
    );
end entity b8008_monitor_top;

architecture rtl of b8008_monitor_top is

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
            io_port_write       : out std_logic;
            io_port_read        : out std_logic
        );
    end component;

    --------------------------------------------------------------------------------
    -- Component: B8008_USART (UART with 8008 handshaking)
    --------------------------------------------------------------------------------
    -- Handles both RX and TX with automatic triggering from b8008_top signals.
    -- Just wire io_port_read/write, io_port_num, and io_port_out - done!
    --------------------------------------------------------------------------------
    component b8008_usart is
        generic (
            CLK_FREQ_HZ  : integer := 100_000_000;
            BAUD_RATE    : integer := 115200;
            RX_PORT_NUM  : std_logic_vector(2 downto 0) := "001";
            TX_PORT_NUM  : std_logic_vector(4 downto 0) := "01001"
        );
        port (
            clk             : in  std_logic;
            rst             : in  std_logic;
            io_port_read    : in  std_logic;
            io_port_write   : in  std_logic;
            io_port_num     : in  std_logic_vector(4 downto 0);
            io_port_out     : in  std_logic_vector(7 downto 0);
            rx_port_data    : out std_logic_vector(7 downto 0);
            tx_busy         : out std_logic;
            uart_tx         : out std_logic;
            uart_rx         : in  std_logic
        );
    end component;

    --------------------------------------------------------------------------------
    -- Component: debouncer (Button debouncing with edge detection)
    --------------------------------------------------------------------------------
    component debouncer is
        generic (
            CLK_FREQ_HZ   : integer := 100_000_000;
            DEBOUNCE_MS   : integer := 20;
            PULSE_STRETCH : integer := 100;
            DEBOUNCE_TIME : integer := 0
        );
        port (
            clk         : in  std_logic;
            rst         : in  std_logic;
            btn         : in  std_logic;
            btn_pressed : out std_logic
        );
    end component;

    --------------------------------------------------------------------------------
    -- Component: debug_clock_control (Three-button debug controller)
    --------------------------------------------------------------------------------
    component debug_clock_control is
        port (
            clk_in          : in  std_logic;
            reset           : in  std_logic;
            btn_run_stop    : in  std_logic;
            btn_step_cycle  : in  std_logic;
            btn_step_sync   : in  std_logic;
            phi1_in         : in  std_logic;
            phi2_in         : in  std_logic;
            sync_in         : in  std_logic;
            clk_out         : out std_logic;
            is_running      : out std_logic;
            next_is_phi1    : out std_logic;
            next_is_phi2    : out std_logic;
            triggered       : out std_logic;
            reset_request   : out std_logic
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
    signal io_port_read  : std_logic;

    -- UART signal (only tx_busy needed for optional status - TX/RX handled by b8008_usart)
    signal uart_tx_busy   : std_logic;


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

    -- Debug clock control signals
    signal gated_clk : std_logic;
    signal dbg_is_running : std_logic;
    signal dbg_next_is_phi1 : std_logic;
    signal dbg_next_is_phi2 : std_logic;
    signal dbg_triggered : std_logic;
    signal dbg_reset_request : std_logic;

    -- Debounced button signals (active high pulses)
    signal run_stop_pressed : std_logic;
    signal step_cycle_pressed : std_logic;
    signal step_sync_pressed : std_logic;

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
    -- Debug controller only sees POR and switch, not its own reset request
    -- This prevents reset feedback loop
    reset_int <= por_active or reset_sw or dbg_reset_request;

    --------------------------------------------------------------------------------
    -- Debug Button Debouncers
    --------------------------------------------------------------------------------
    -- Buttons are active low with internal pull-ups. Debouncer outputs
    -- active high single-cycle pulses on button press.
    --------------------------------------------------------------------------------
    u_debounce_run_stop : debouncer
        generic map (
            CLK_FREQ_HZ   => 100_000_000,
            DEBOUNCE_MS   => 20,
            PULSE_STRETCH => 1
        )
        port map (
            clk         => clk,
            rst         => not por_active,  -- Only reset on POR, not debug reset
            btn         => dbg_btn_run_stop,
            btn_pressed => run_stop_pressed
        );

    u_debounce_step_cycle : debouncer
        generic map (
            CLK_FREQ_HZ   => 100_000_000,
            DEBOUNCE_MS   => 20,
            PULSE_STRETCH => 1
        )
        port map (
            clk         => clk,
            rst         => not por_active,  -- Only reset on POR, not debug reset
            btn         => dbg_btn_step_cycle,
            btn_pressed => step_cycle_pressed
        );

    u_debounce_step_sync : debouncer
        generic map (
            CLK_FREQ_HZ   => 100_000_000,
            DEBOUNCE_MS   => 20,
            PULSE_STRETCH => 1
        )
        port map (
            clk         => clk,
            rst         => not por_active,  -- Only reset on POR, not debug reset
            btn         => dbg_btn_step_sync,
            btn_pressed => step_sync_pressed
        );

    --------------------------------------------------------------------------------
    -- Debug Clock Control
    --------------------------------------------------------------------------------
    -- Gates the master clock to the CPU. UART stays on ungated clock for accurate
    -- baud timing even when CPU is stopped.
    --------------------------------------------------------------------------------
    u_debug_clk : debug_clock_control
        port map (
            clk_in          => clk,
            reset           => por_active or reset_sw,  -- Don't include dbg_reset_request (feedback loop)
            btn_run_stop    => run_stop_pressed,
            btn_step_cycle  => step_cycle_pressed,
            btn_step_sync   => step_sync_pressed,
            phi1_in         => phi1,
            phi2_in         => phi2,
            sync_in         => sync_sig,
            clk_out         => gated_clk,
            is_running      => dbg_is_running,
            next_is_phi1    => dbg_next_is_phi1,
            next_is_phi2    => dbg_next_is_phi2,
            triggered       => dbg_triggered,
            reset_request   => dbg_reset_request
        );

    --------------------------------------------------------------------------------
    -- Bootstrap Interrupt Control
    --------------------------------------------------------------------------------
    -- Use async reset from clk domain directly. The reset signal is stable
    -- (held for many phi2 cycles) so metastability risk is minimal, and
    -- async reset ensures clean startup regardless of clock phase.
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
                -- Wait for counter to allow CPU to reach T1I, then check for T1I state
                -- Need enough cycles for CPU to exit STOPPED and enter T1I
                if bootstrap_counter >= 16 then
                    if s2_sig = '1' and s1_sig = '1' and s0_sig = '0' and sync_sig = '1' then
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
            ROM_FILE => "./b8008_monitor.mem"
        )
        port map (
            clk_in      => gated_clk,  -- Use gated clock for debug control
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
            -- External I/O port interface
            io_port_in          => io_port_in_data,
            io_port_in_select   => "001",  -- Port 1 uses external input
            io_port_in_enable   => '1',    -- ENABLED - use UART RX data
            io_port_out         => io_port_out,
            io_port_num_out     => io_port_num,
            io_port_write       => io_port_write,
            io_port_read        => io_port_read
        );

    --------------------------------------------------------------------------------
    -- B8008_USART Instance (115200 baud, with 8008 handshaking)
    --------------------------------------------------------------------------------
    -- This wrapper encapsulates ALL UART handshaking logic:
    -- - TX: Automatically triggers on OUT 9 (TX_PORT_NUM = "01001")
    -- - RX: Ready flag latching, clearing on falling edge of io_port_read
    -- New projects just instantiate this and wire b8008_top I/O signals - done!
    --------------------------------------------------------------------------------
    u_uart : b8008_usart
        generic map (
            CLK_FREQ_HZ => 100_000_000,
            BAUD_RATE   => 115200,
            RX_PORT_NUM => "001",    -- INP 1 for UART RX
            TX_PORT_NUM => "01001"   -- OUT 9 for UART TX
        )
        port map (
            clk          => clk,
            rst          => reset_int,
            io_port_read => io_port_read,
            io_port_write => io_port_write,
            io_port_num  => io_port_num,
            io_port_out  => io_port_out,
            rx_port_data => io_port_in_data,  -- Directly wired to CPU input
            tx_busy      => uart_tx_busy,
            uart_tx      => uart_tx,
            uart_rx      => uart_rx
        );

    -- TX and RX are now both handled by b8008_usart wrapper

    --------------------------------------------------------------------------------
    -- LED Outputs
    --------------------------------------------------------------------------------
    -- LEDs 0-3: Debug status (directly active low: '0' = ON)
    -- LEDs 4-7: CPU I/O port 8 output (directly active, accent active low)
    led(0) <= not dbg_is_running;     -- ON when running (active-low LED, '0'=ON)
    led(1) <= not dbg_next_is_phi2;   -- ON when phi2 is next phase
    led(2) <= not sync_sig;           -- ON during SYNC
    led(3) <= not dbg_triggered;      -- ON when breakpoint triggered (reserved)
    led(7 downto 4) <= io_port_8(7 downto 4);  -- Upper 4 bits from CPU I/O

    -- M20: TX busy indicator (ON = UART transmitting)
    led_M20 <= not uart_tx_busy;

    -- L18: Running indicator (ON when running, active-low LED)
    led_L18 <= not dbg_is_running;

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

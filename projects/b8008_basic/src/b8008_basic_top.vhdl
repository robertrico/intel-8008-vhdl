--------------------------------------------------------------------------------
-- B8008 Monitor Top Level - Interactive Console
--------------------------------------------------------------------------------
-- Interactive monitor/console for the b8008 CPU with UART peripheral.
--
-- Uses b8008_top (proven, working CPU+ROM+RAM) with UART as external peripheral.
--
-- I/O Port Mapping:
--   IN 1:   UART RX - bit 7 = ready flag, bits 6:0 = received data
--   OUT 8:  latched by the core, not displayed
--   RAM 0x00FF: memory-mapped LEDs, bit n -> LED n (bit 0 unused), 1 = on.
--           From BASIC: MON, then W 00FF,FE / W 00FF,00, G 1FB6 back.
--           LED0 (D25) = CPU running.
--   OUT 9:  UART TX - sends byte immediately at 115200 baud
--
-- Front-panel switches: ONLY sw(0) (DIP1) is used = reset (ON = '0' = run).
--   sw(1..7) are no-connects: no LED debug modes, no switch interrupts,
--   no READY hold, no post-bootstrap break. The port stays 8 bits wide so
--   the LPF pin locations remain valid.
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

entity b8008_basic_top is
    generic (
        RAM_INIT_FILE : string := "src/ram_boot.mem"   -- boot vector: JMP 1800h at RAM[0]
    );
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
        cpu_int     : out std_logic;

        -- Debug buttons (directly to GPIO, active low with pull-up)
        dbg_btn_run_stop  : in std_logic;   -- Run/Stop toggle
        dbg_btn_step_cycle : in std_logic;  -- Single full cycle step (220 clocks)
        dbg_btn_step_sync : in std_logic;   -- Step to SYNC (instruction boundary)

        -- External ROM interface
        rom_a    : out std_logic_vector(12 downto 0);  -- ROM address (8KB)
        rom_d    : in  std_logic_vector(7 downto 0);   -- ROM data input
        rom_ce_n : out std_logic;                      -- ROM chip enable (active low)
        rom_oe_n : out std_logic                       -- ROM output enable (active low)
    );
end entity b8008_basic_top;

architecture rtl of b8008_basic_top is

    --------------------------------------------------------------------------------
    -- ROM source select
    --------------------------------------------------------------------------------
    -- true  = on-chip LUT ROM (rom_4kx8, contents baked in at synthesis).
    --         External ROM pins still driven but rom_d is ignored. Use this to
    --         run with the EEPROM/level-shifter chain disconnected.
    -- false = external EEPROM via rom_a/rom_d (normal configuration).
    --------------------------------------------------------------------------------
    constant USE_INTERNAL_ROM : boolean := true;

    --------------------------------------------------------------------------------
    -- Component: int_button (front-panel interrupt from DIP switch)
    --------------------------------------------------------------------------------
    component int_button is
        generic (
            CLK_FREQ_HZ : integer := 25_000_000;
            DEBOUNCE_MS : integer := 20
        );
        port (
            clk        : in  std_logic;
            reset      : in  std_logic;
            sw_raw     : in  std_logic;
            vector_sel : in  std_logic;
            armed      : in  std_logic;
            t1i_ack    : in  std_logic;
            int_req    : out std_logic;
            int_vector : out std_logic_vector(2 downto 0)
        );
    end component;

    --------------------------------------------------------------------------------
    -- Component: b8008_top (CPU with external ROM and internal RAM)
    --------------------------------------------------------------------------------
    component b8008_top is
        generic (
            CLK_FREQ_HZ   : integer := 100_000_000;
            RAM_INIT_FILE : string  := "";
            ROM_BASE      : integer := 16#0000#;
            ROM_LAST      : integer := 16#0FFF#;
            RAM_BASE      : integer := 16#1000#;
            RAM_LAST      : integer := 16#3FFF#;
            RAM_ADDR_BITS : integer := 14;
            LED_SHADOW_ADDR : integer := 16#3FFF#
        );
        port (
            clk_in      : in std_logic;
            reset       : in std_logic;
            run_enable  : in std_logic;
            interrupt   : in std_logic;
            int_instruction : in std_logic_vector(7 downto 0) := "00000101";
            ready_in    : in std_logic := '1';
            phi1_out    : out std_logic;
            phi2_out    : out std_logic;
            sync_out    : out std_logic;
            s0_out      : out std_logic;
            s1_out      : out std_logic;
            s2_out      : out std_logic;
            address_out : out std_logic_vector(13 downto 0);
            data_out    : out std_logic_vector(7 downto 0);
            ram_byte_0  : out std_logic_vector(7 downto 0);
            ram_byte_led : out std_logic_vector(7 downto 0);
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
            io_port_read        : out std_logic;
            -- External ROM interface
            rom_a               : out std_logic_vector(13 downto 0);
            rom_d               : in  std_logic_vector(7 downto 0);
            rom_ce_n            : out std_logic;
            rom_oe_n            : out std_logic
        );
    end component;

    --------------------------------------------------------------------------------
    -- Component: rom_12kx8_bram (on-chip block-RAM ROM, synchronous read)
    --------------------------------------------------------------------------------
    -- Contents baked at synthesis; updated WITHOUT resynthesis via the ecpbram
    -- patch flow (make rom-update). One clock of read latency - invisible to
    -- the 8008, which needs data microseconds after the address settles.
    --------------------------------------------------------------------------------
    component rom_12kx8_bram is
        generic (
            ROM_FILE : string := ""
        );
        port (
            CLK      : in  std_logic;
            ADDR     : in  std_logic_vector(13 downto 0);
            DATA_OUT : out std_logic_vector(7 downto 0);
            CS_N     : in  std_logic
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
    -- Component: pll_25mhz (ECP5 PLL: 100 MHz -> 25 MHz)
    -- Implementation lives in src/components/pll_25mhz.v and is read by Yosys.
    -- GHDL only sees this component declaration and emits a black-box reference.
    --------------------------------------------------------------------------------
    component pll_25mhz is
        port (
            clk_in  : in  std_logic;
            clk_out : out std_logic;
            locked  : out std_logic
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
            bootstrap_done  : in  std_logic;
            run_enable      : out std_logic;
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
    -- System clock from PLL (25 MHz). Drives every flop in the design.
    -- The 100 MHz LVDS input pin (`clk`) only feeds the PLL.
    signal clk_sys      : std_logic;
    signal pll_locked   : std_logic;

    -- POR (Power-On Reset) and reset control
    signal por_active   : std_logic := '1';
    signal reset_sync   : std_logic_vector(2 downto 0) := (others => '1');
    signal reset_sw     : std_logic;
    signal reset_int    : std_logic;
    signal ready_sync   : std_logic_vector(1 downto 0) := "00";
    signal sw6_base     : std_logic := '0';   -- reset-time level = "run"
    signal sw6_base_cnt : integer range 0 to 25000 := 0;

    -- Front-panel interrupt (sw5 flip, sw7 vector)
    signal t1i_ack_sig  : std_logic;
    signal btn_int_req  : std_logic;
    signal btn_int_vec  : std_logic_vector(2 downto 0);
    -- Board jam circuit: this front panel only jams RST instructions;
    -- encode the switch vector as the full RST byte for the CPU system
    signal jam_instruction : std_logic_vector(7 downto 0);
    signal cpu_int_vec  : std_logic_vector(2 downto 0);

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
    signal bs_phi2_prev      : std_logic := '0';

    -- Auto-start: synthetic run/stop press ~2 ms after POR/reset release
    signal auto_start_cnt   : unsigned(16 downto 0) := (others => '0');
    signal auto_start_done  : std_logic := '0';
    signal auto_start_pulse : std_logic := '0';

    -- ROM source mux (internal LUT ROM vs external EEPROM)
    signal rom_a_int      : std_logic_vector(13 downto 0);
    -- ROM index guard: rom_a is (addr - ROM_BASE) mod 16K, so RAM accesses
    -- underflow past the 12K array. Silicon ignores it (CS-gated); the sim
    -- array read must be clamped.
    signal rom_a_safe     : std_logic_vector(13 downto 0);
    signal rom_d_cpu      : std_logic_vector(7 downto 0);
    signal rom_d_internal : std_logic_vector(7 downto 0);

    -- Rolling fetch capture: latch data + address at the end of every T3.
    -- When the CPU freezes these hold the last fetch it performed, readable
    -- on the LEDs via sw(2) (data), sw(3) (addr low), sw(4) (addr high).
    signal last_fetch      : std_logic_vector(7 downto 0)  := (others => '0');
    signal last_fetch_addr : std_logic_vector(13 downto 0) := (others => '0');
    signal fetch_seen      : std_logic := '0';

    -- I/O port signals
    signal io_port_8    : std_logic_vector(7 downto 0);
    signal ram_byte_led : std_logic_vector(7 downto 0);   -- shadow of RAM[0x00FF]
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
    signal dbg_run_enable : std_logic;
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
    -- PLL: 100 MHz LVDS input -> 25 MHz system clock
    --------------------------------------------------------------------------------
    -- Design's measured fmax is ~44 MHz; running off the raw 100 MHz osc caused
    -- the CPU register paths to fail timing and the monitor to emit garbage on
    -- UART. Drop to 25 MHz everywhere (well under fmax). Drives ALL flops below;
    -- the only thing on the 100 MHz domain is the PLL CLKI input itself.
    u_pll : pll_25mhz
        port map (
            clk_in  => clk,
            clk_out => clk_sys,
            locked  => pll_locked
        );

    --------------------------------------------------------------------------------
    -- Power-On Reset (POR)
    --------------------------------------------------------------------------------
    -- POR holds reset until the PLL has locked AND the counter has run out.
    -- Counter rolls 4x slower at 25 MHz than at 100 MHz, but that's fine for POR.
    process(clk_sys)
    begin
        if rising_edge(clk_sys) then
            if pll_locked = '0' then
                clk_counter <= (others => '0');
                por_active  <= '1';
            else
                clk_counter <= clk_counter + 1;
                if clk_counter(19) = '1' then
                    por_active <= '0';
                end if;
            end if;
        end if;
    end process;

    --------------------------------------------------------------------------------
    -- Reset Synchronization
    --------------------------------------------------------------------------------
    process(clk_sys)
    begin
        if rising_edge(clk_sys) then
            reset_sync <= reset_sync(1 downto 0) & sw(0);
        end if;
    end process;

    reset_sw <= reset_sync(2);

    -- sw(6) = READY hold, position-independent: the level ~1 ms after
    -- reset is captured as the baseline; ANY flip away from it parks the
    -- CPU in WAIT, flipping back resumes. No polarity assumption - the
    -- switch works from whatever position it rests in (a reset while
    -- flipped simply re-baselines).
    ready_hold : process(clk_sys)
    begin
        if rising_edge(clk_sys) then
            ready_sync <= ready_sync(0) & '0';   -- sw(6) NC: READY never held
            if reset_int = '1' then
                sw6_base_cnt <= 0;
            elsif sw6_base_cnt < 25000 then   -- ~1 ms at 25 MHz
                sw6_base_cnt <= sw6_base_cnt + 1;
                sw6_base     <= ready_sync(1);
            end if;
        end if;
    end process;
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
            CLK_FREQ_HZ   => 25_000_000,
            DEBOUNCE_MS   => 20,
            PULSE_STRETCH => 1
        )
        port map (
            clk         => clk_sys,
            rst         => not por_active,  -- Only reset on POR, not debug reset
            btn         => dbg_btn_run_stop,
            btn_pressed => run_stop_pressed
        );

    u_debounce_step_cycle : debouncer
        generic map (
            CLK_FREQ_HZ   => 25_000_000,
            DEBOUNCE_MS   => 20,
            PULSE_STRETCH => 1
        )
        port map (
            clk         => clk_sys,
            rst         => not por_active,  -- Only reset on POR, not debug reset
            btn         => dbg_btn_step_cycle,
            btn_pressed => step_cycle_pressed
        );

    u_debounce_step_sync : debouncer
        generic map (
            CLK_FREQ_HZ   => 25_000_000,
            DEBOUNCE_MS   => 20,
            PULSE_STRETCH => 1
        )
        port map (
            clk         => clk_sys,
            rst         => not por_active,  -- Only reset on POR, not debug reset
            btn         => dbg_btn_step_sync,
            btn_pressed => step_sync_pressed
        );

    --------------------------------------------------------------------------------
    -- Auto-start
    --------------------------------------------------------------------------------
    -- Fires one synthetic run/stop press 2 ms after POR (or the reset switch)
    -- releases, so the CPU boots without a physical button press. Re-arms on
    -- the reset switch, so flipping sw(0) restarts the system. The debug
    -- button still works normally afterwards (stop/resume/step).
    --------------------------------------------------------------------------------
    process(clk_sys)
    begin
        if rising_edge(clk_sys) then
            auto_start_pulse <= '0';
            if por_active = '1' or reset_sw = '1' then
                auto_start_cnt  <= (others => '0');
                auto_start_done <= '0';
            elsif auto_start_done = '0' then
                auto_start_cnt <= auto_start_cnt + 1;
                if auto_start_cnt = 50000 then    -- 2 ms at 25 MHz
                    auto_start_pulse <= '1';
                    auto_start_done  <= '1';
                end if;
            end if;
        end if;
    end process;

    --------------------------------------------------------------------------------
    -- Rolling Fetch Capture
    --------------------------------------------------------------------------------
    -- Latches the data bus and full address at the end of every T3 (phi2
    -- falling). While the CPU runs this updates continuously; the moment it
    -- freezes (HLT, STOPPED, wait) no further T3 occurs, so the registers
    -- hold the last fetch: the instruction that killed it and where it came
    -- from. Read on LEDs (bit set = LED ON):
    --   sw(2)='1' -> led = last data byte
    --   sw(3)='1' -> led = last address bits 7:0
    --   sw(4)='1' -> led = "00" & last address bits 13:8
    --   led_L18 lit = at least one fetch since reset
    -- On a dead boot expect address 0x0000, data 0x44 (JMP) if the first
    -- fetch ever happened at all.
    --------------------------------------------------------------------------------
    process(clk_sys)
    begin
        if rising_edge(clk_sys) then
            if reset_int = '1' then
                fetch_seen      <= '0';
                last_fetch      <= (others => '0');
                last_fetch_addr <= (others => '0');
            elsif phi2 = '0' and bs_phi2_prev = '1' and
                  s2_sig = '0' and s1_sig = '0' and s0_sig = '1' then  -- end of T3
                last_fetch      <= data_sig;
                last_fetch_addr <= address_sig;
                fetch_seen      <= '1';
            end if;
        end if;
    end process;

    --------------------------------------------------------------------------------
    -- Debug Clock Control
    --------------------------------------------------------------------------------
    -- Gates the master clock to the CPU. UART stays on ungated clock for accurate
    -- baud timing even when CPU is stopped.
    --------------------------------------------------------------------------------
    u_debug_clk : debug_clock_control
        port map (
            clk_in          => clk_sys,
            reset           => por_active or reset_sw,  -- Don't include dbg_reset_request (feedback loop)
            btn_run_stop    => run_stop_pressed or auto_start_pulse,
            btn_step_cycle  => step_cycle_pressed,
            btn_step_sync   => step_sync_pressed,
            phi1_in         => phi1,
            phi2_in         => phi2,
            sync_in         => sync_sig,
            bootstrap_done  => '0',              -- sw(1) NC: hardware break after bootstrap disabled
            run_enable      => dbg_run_enable,
            is_running      => dbg_is_running,
            next_is_phi1    => dbg_next_is_phi1,
            next_is_phi2    => dbg_next_is_phi2,
            triggered       => dbg_triggered,
            reset_request   => dbg_reset_request
        );

    --------------------------------------------------------------------------------
    -- Bootstrap Interrupt Control
    --------------------------------------------------------------------------------
    -- Runs entirely in the clk_sys domain, advancing on a phi2 rising-edge
    -- enable pulse. phi2, s0/s1/s2, sync, and reset_int are all clk_sys-domain
    -- signals, so there is no clock-domain crossing anywhere in this FSM.
    -- (The previous version clocked this on the derived phi2 signal with an
    -- async reset, which left every path into it unconstrained and caused
    -- spontaneous re-jam of RST 0: bootstrap_done would glitch back to 0,
    -- restarting the CPU mid-program or freezing it via the hardware break.)
    --------------------------------------------------------------------------------
    process(clk_sys)
    begin
        if rising_edge(clk_sys) then
            bs_phi2_prev <= phi2;

            if reset_int = '1' then
                bootstrap_int     <= '0';
                bootstrap_done    <= '0';
                bootstrap_counter <= (others => '0');
            elsif phi2 = '1' and bs_phi2_prev = '0' then
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
        end if;
    end process;

    --------------------------------------------------------------------------------
    -- Front-panel interrupt: sw(5) flip = one interrupt, sw(7) = vector
    --------------------------------------------------------------------------------
    -- Armed only after bootstrap so a flip can never race the RST 0 jam.
    -- The request latch clears on the CPU's T1I acknowledge (status 110,
    -- same decode the bootstrap FSM uses).
    t1i_ack_sig <= '1' when (s2_sig = '1' and s1_sig = '1' and s0_sig = '0') else '0';

    u_int_button : int_button
        generic map (
            CLK_FREQ_HZ => 25_000_000,
            DEBOUNCE_MS => 20
        )
        port map (
            clk        => clk_sys,
            reset      => reset_int,
            sw_raw     => '0',                   -- sw(5) NC: no switch interrupts
            vector_sel => '0',                   -- sw(7) NC
            armed      => bootstrap_done,
            t1i_ack    => t1i_ack_sig,
            int_req    => btn_int_req,
            int_vector => btn_int_vec
        );

    -- Latch the jam vector at REQUEST time. A combinational mux on
    -- bootstrap_done raced the bootstrap's own T1I: done rises mid-
    -- acknowledge, the jam byte flipped from RST 0 (0x05) to RST 5
    -- (0x2D), and the CPU vectored into an uninitialized RAM slot
    -- (0x00 = HLT) - dead board. The latch only moves while a button
    -- request is pending, so it is stable through every T1I.
    vec_latch : process(clk_sys)
    begin
        if rising_edge(clk_sys) then
            if reset_int = '1' or bootstrap_done = '0' then
                cpu_int_vec <= "000";          -- bootstrap jams RST 0
            elsif btn_int_req = '1' then
                cpu_int_vec <= btn_int_vec;    -- freeze the button vector
            end if;
        end if;
    end process;

    --------------------------------------------------------------------------------
    -- b8008 CPU System Instance
    --------------------------------------------------------------------------------
    jam_instruction <= "00" & cpu_int_vec & "101";

    u_system : b8008_top
        generic map (
            CLK_FREQ_HZ   => 25_000_000,       -- PLL output frequency
            RAM_INIT_FILE => RAM_INIT_FILE,    -- boot vector lives in RAM[0]
            ROM_BASE      => 16#1000#,
            ROM_LAST      => 16#3FFF#,
            RAM_BASE      => 16#0000#,
            RAM_LAST      => 16#0FFF#,
            RAM_ADDR_BITS => 12,
            LED_SHADOW_ADDR => 16#00FF#   -- memory-mapped LEDs: reserved page-0 byte, never written by SCELBAL
        )
        port map (
            clk_in      => clk_sys,            -- 25 MHz from on-chip PLL
            reset       => reset_int,
            run_enable  => dbg_run_enable,    -- Debug hold: '0' freezes phi state machine
            interrupt   => bootstrap_int or btn_int_req,
            int_instruction => jam_instruction,  -- RST 0 for bootstrap, sw(7) pick after
            ready_in    => '1',                -- sw(6) NC: always READY
            phi1_out    => phi1,
            phi2_out    => phi2,
            sync_out    => sync_sig,
            s0_out      => s0_sig,
            s1_out      => s1_sig,
            s2_out      => s2_sig,
            address_out => address_sig,
            data_out    => data_sig,
            ram_byte_0  => ram_byte_0,
            ram_byte_led => ram_byte_led,
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
            io_port_read        => io_port_read,
            -- ROM interface (muxed: internal LUT ROM or external EEPROM pins)
            rom_a               => rom_a_int,
            rom_d               => rom_d_cpu,
            rom_ce_n            => rom_ce_n,
            rom_oe_n            => rom_oe_n
        );

    -- External ROM address pins always driven (harmless when internal ROM active)
    rom_a <= rom_a_int(12 downto 0);
    rom_a_safe <= rom_a_int when unsigned(rom_a_int) < 12288 else (others => '0');

    gen_internal_rom : if USE_INTERNAL_ROM generate
        u_rom : rom_12kx8_bram
            port map (
                CLK      => clk_sys,
                ADDR     => rom_a_safe,
                DATA_OUT => rom_d_internal,
                CS_N     => '0'
            );
        rom_d_cpu <= rom_d_internal;
    end generate;

    gen_external_rom : if not USE_INTERNAL_ROM generate
        rom_d_cpu <= rom_d;
    end generate;

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
            CLK_FREQ_HZ => 25_000_000,
            BAUD_RATE   => 115200,
            RX_PORT_NUM => "001",    -- INP 1 for UART RX
            TX_PORT_NUM => "01001"   -- OUT 9 for UART TX
        )
        port map (
            clk          => clk_sys,
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
    -- Normal mode: status + I/O port. Debug capture modes via sw(2)/sw(3)/sw(4)
    -- show the rolling fetch capture (LED ON = bit set).
    -- LEDs 7:1 are memory-mapped: RAM[0x00FF] bit n -> LED n, 1 = on
    -- (MON, then W 00FF,FE lights all seven). LED0 (D25) = CPU running.
    -- Port 8 is not displayed. Same scheme as b8008_monitor (there at 0x3FFF).
    led <= (not ram_byte_led(7 downto 1)) &
           (not dbg_is_running);

    -- M20: TX busy indicator (ON = UART transmitting)
    led_M20 <= not uart_tx_busy;

    -- L18: Running indicator (ON when running, active-low LED)
    led_L18 <= not dbg_is_running;   -- sw(2..4) NC: fetch-capture LED modes removed

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
    cpu_int     <= bootstrap_int;

end architecture rtl;

--------------------------------------------------------------------------------
-- Interrupt Controller for Intel 8008 Blinky Project
--------------------------------------------------------------------------------
-- Generates interrupts from button edge detection
--
-- Interrupt Mechanism:
--   1. Detects rising and falling edges on button input
--   2. Asserts INT pin to CPU (active high)
--   3. Waits for CPU interrupt acknowledge (T1I state: S2=1, S1=1, S0=0)
--   4. Drives RST 0 opcode (0x05) on data bus during T1I
--   5. Clears INT after acknowledgment
--
-- Features:
--   - Button debouncing (50ms debounce period)
--   - Edge detection (both rising and falling)
--   - Simple interrupt pending flag
--   - RST 0 vector (jumps to address 0x0000)
--
-- Copyright (c) 2025 Robert Rico
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity interrupt_controller is
    generic (
        -- Clock frequency for debounce timing (default: 100 MHz)
        CLK_FREQ_HZ   : positive := 100_000_000;
        -- Debounce period in milliseconds
        DEBOUNCE_MS   : positive := 50
    );
    port (
        -- Clock and reset
        clk         : in  std_logic;
        reset_n     : in  std_logic;

        -- CPU interface (state signals)
        S2          : in  std_logic;
        S1          : in  std_logic;
        S0          : in  std_logic;
        SYNC        : in  std_logic;

        -- Data bus (bidirectional, for driving RST opcode)
        data_bus    : inout std_logic_vector(7 downto 0);

        -- Interrupt output to CPU
        INT         : out std_logic;

        -- Physical button input
        button_raw  : in  std_logic  -- Active high, raw button signal
    );
end entity interrupt_controller;

architecture rtl of interrupt_controller is
    -- Debounce counter
    constant DEBOUNCE_CYCLES : positive := (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;
    signal debounce_counter  : integer range 0 to DEBOUNCE_CYCLES;

    -- Button state
    signal button_sync    : std_logic_vector(1 downto 0);  -- Synchronizer
    signal button_debounced : std_logic;
    signal button_prev    : std_logic;

    -- Edge detection
    signal edge_detected  : std_logic;

    -- Startup interrupt generation
    -- Per Intel 8008 datasheet: CPU requires an interrupt pulse after power-on to exit STOPPED state
    signal startup_done   : std_logic;
    signal startup_delay  : integer range 0 to 255;  -- Delay counter for startup interrupt
    constant STARTUP_DELAY_CYCLES : integer := 100;  -- Wait 100 phi1 cycles after reset

    -- Interrupt state machine
    type int_state_t is (STARTUP_INT, IDLE, INT_PENDING, DRIVE_RST, CLEAR_INT);
    signal int_state : int_state_t;

    -- Synchronized CPU state detection (sample on SYNC to avoid glitches)
    signal sync_prev      : std_logic;
    signal sync_rising    : std_logic;
    signal state_sampled  : std_logic_vector(2 downto 0);  -- S2, S1, S0
    signal is_t1i_sampled : std_logic;
    signal is_t3_sampled  : std_logic;

    -- Latched state detection (stays high until cleared)
    signal t1i_detected   : std_logic;
    signal t3_detected    : std_logic;

    -- Data bus control
    signal data_bus_drive : std_logic;
    constant RST_0_OPCODE : std_logic_vector(7 downto 0) := "00000101";  -- RST 0 = 0x05

begin
    -- Sample state signals on SYNC rising edge to avoid glitches
    sync_rising <= '1' when (SYNC = '1' and sync_prev = '0') else '0';

    -- T1I state detection (interrupt acknowledge) - use sampled values
    is_t1i_sampled <= '1' when (state_sampled = "110") else '0';  -- S2=1, S1=1, S0=0

    -- T3 state detection (end of instruction fetch) - use sampled values
    is_t3_sampled <= '1' when (state_sampled = "001") else '0';  -- S2=0, S1=0, S0=1

    -- Data bus control: Drive RST opcode only during T1I
    data_bus <= RST_0_OPCODE when data_bus_drive = '1' else (others => 'Z');

    -- State signal sampling on SYNC rising edge
    state_sample_proc: process(clk, reset_n)
    begin
        if reset_n = '0' then
            sync_prev     <= '0';
            state_sampled <= "000";
            t1i_detected  <= '0';
            t3_detected   <= '0';
        elsif rising_edge(clk) then
            sync_prev <= SYNC;

            -- Sample state signals only on SYNC rising edge
            if sync_rising = '1' then
                state_sampled <= S2 & S1 & S0;

                -- Latch T1I and T3 detections
                if is_t1i_sampled = '1' then
                    t1i_detected <= '1';
                end if;

                if is_t3_sampled = '1' then
                    t3_detected <= '1';
                end if;
            end if;

            -- Clear latches when state machine consumes them
            if int_state = DRIVE_RST then
                t1i_detected <= '0';
            end if;

            if int_state = CLEAR_INT then
                t3_detected <= '0';
            end if;
        end if;
    end process state_sample_proc;

    -- Button debounce and synchronization process
    debounce_proc: process(clk, reset_n)
    begin
        if reset_n = '0' then
            button_sync      <= (others => '0');
            button_debounced <= '0';
            button_prev      <= '0';
            debounce_counter <= 0;
            edge_detected    <= '0';

        elsif rising_edge(clk) then
            -- Synchronizer (2-stage for metastability)
            button_sync <= button_sync(0) & button_raw;

            -- Debounce logic
            if button_sync(1) /= button_debounced then
                -- Button state changed, start/continue debounce
                if debounce_counter < DEBOUNCE_CYCLES then
                    debounce_counter <= debounce_counter + 1;
                else
                    -- Debounce complete, update button state
                    button_debounced <= button_sync(1);
                    debounce_counter <= 0;
                end if;
            else
                -- Button stable, reset counter
                debounce_counter <= 0;
            end if;

            -- Edge detection (one cycle pulse)
            button_prev   <= button_debounced;
            edge_detected <= '0';

            if button_debounced /= button_prev then
                -- Edge detected (rising or falling)
                edge_detected <= '1';
            end if;
        end if;
    end process debounce_proc;

    -- Interrupt controller state machine
    int_controller_proc: process(clk, reset_n)
    begin
        if reset_n = '0' then
            int_state      <= STARTUP_INT;  -- ENABLED: Generate startup interrupt per datasheet
            INT            <= '0';
            data_bus_drive <= '0';
            startup_done   <= '0';  -- Not done yet, will generate startup interrupt
            startup_delay  <= 0;

        elsif rising_edge(clk) then
            -- Default outputs
            data_bus_drive <= '0';

            case int_state is
                when STARTUP_INT =>
                    -- Generate startup interrupt to release CPU from STOPPED state
                    -- Per Intel 8008 datasheet section 2: "START-UP OF THE 8008"
                    -- Wait for CPU to stabilize after reset before asserting interrupt
                    if startup_done = '0' then
                        if startup_delay < STARTUP_DELAY_CYCLES then
                            startup_delay <= startup_delay + 1;
                        else
                            int_state    <= INT_PENDING;
                            startup_done <= '1';
                        end if;
                    else
                        int_state <= IDLE;
                    end if;

                when IDLE =>
                    -- Wait for button edge
                    if edge_detected = '1' then
                        int_state <= INT_PENDING;
                    end if;

                when INT_PENDING =>
                    -- Assert INT and drive RST opcode continuously
                    -- Per Intel 8008 datasheet: interrupt vector must be available
                    -- on data bus during T1I and T2 states
                    INT            <= '1';
                    data_bus_drive <= '1';  -- Drive RST opcode while INT is asserted

                    -- Check for interrupt acknowledge (T1I state) - use latched detection
                    if t1i_detected = '1' then
                        int_state <= DRIVE_RST;
                    end if;

                when DRIVE_RST =>
                    -- Continue driving during T2 after T1I
                    -- Stay in this state until T3 begins (when CPU captures the instruction)
                    INT            <= '1';
                    data_bus_drive <= '1';

                    -- Wait for T3 state before clearing (instruction has been fetched)
                    if t3_detected = '1' then
                        int_state <= CLEAR_INT;
                    end if;

                when CLEAR_INT =>
                    -- Clear interrupt and stop driving bus
                    INT            <= '0';
                    data_bus_drive <= '0';
                    int_state      <= IDLE;

                when others =>
                    int_state <= IDLE;

            end case;
        end if;
    end process int_controller_proc;

end architecture rtl;

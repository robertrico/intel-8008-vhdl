--------------------------------------------------------------------------------
-- debug_clock_control.vhdl
--------------------------------------------------------------------------------
-- Three-Button Debug Controller for Intel 8008
--
-- Simple clock gating with step capability.
--
-- Behavior:
--   - Run/Stop while running: Gate clocks OFF (CPU freezes)
--   - Run/Stop while stopped: Assert reset, ungate clocks (restart)
--   - Step Phi while stopped: Run until next phi falling edge
--   - Step Sync while stopped: Run until sync toggles
--
-- Copyright (c) 2025 Robert Rico
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity debug_clock_control is
    port (
        -- System clock (100 MHz)
        clk_in          : in  std_logic;
        reset           : in  std_logic;

        -- Debounced button inputs (active high pulses, single cycle)
        btn_run_stop    : in  std_logic;   -- Toggle run/stop state
        btn_step_cycle  : in  std_logic;   -- Single phi step
        btn_step_sync   : in  std_logic;   -- Run until SYNC toggles

        -- CPU feedback
        phi1_in         : in  std_logic;
        phi2_in         : in  std_logic;
        sync_in         : in  std_logic;
        bootstrap_done  : in  std_logic;   -- Stop after bootstrap completes

        -- Gated clock output to CPU
        clk_out         : out std_logic;

        -- Status outputs
        is_running      : out std_logic;
        next_is_phi1    : out std_logic;
        next_is_phi2    : out std_logic;
        triggered       : out std_logic;

        -- Reset request output
        reset_request   : out std_logic
    );
end entity debug_clock_control;

architecture rtl of debug_clock_control is

    -- Core state: are clocks enabled?
    -- Start stopped so user can step from known state
    signal clk_enable : std_logic := '0';

    -- Stepping mode (temporarily enable clocks)
    signal stepping_phi : std_logic := '0';   -- Stepping to next phi edge
    signal stepping_sync : std_logic := '0';  -- Stepping to sync toggle
    signal sync_prev : std_logic := '0';      -- For detecting sync toggle

    -- Edge detection
    signal phi1_prev : std_logic := '0';
    signal phi2_prev : std_logic := '0';
    signal phi1_falling : std_logic;
    signal phi2_falling : std_logic;

    -- Reset control
    signal reset_pending : std_logic := '0';
    signal reset_active : std_logic := '0';
    signal reset_counter : integer range 0 to 1023 := 0;

    -- Button edge detection - only act once per press
    signal btn_run_stop_prev : std_logic := '0';
    signal btn_run_stop_edge : std_logic;

    -- Bootstrap break - stop after bootstrap completes
    signal bootstrap_done_prev : std_logic := '0';

begin

    ---------------------------------------------------------------------------
    -- Clock Gating
    ---------------------------------------------------------------------------
    clk_out <= clk_in when (clk_enable = '1' or stepping_phi = '1' or stepping_sync = '1') else '0';

    ---------------------------------------------------------------------------
    -- Edge Detection
    ---------------------------------------------------------------------------
    process(clk_in, reset)
    begin
        if reset = '1' then
            phi1_prev <= '0';
            phi2_prev <= '0';
            sync_prev <= '0';
        elsif rising_edge(clk_in) then
            phi1_prev <= phi1_in;
            phi2_prev <= phi2_in;
            sync_prev <= sync_in;
        end if;
    end process;

    phi1_falling <= phi1_prev and not phi1_in;
    phi2_falling <= phi2_prev and not phi2_in;

    -- Detect rising edge of button (only act once per press)
    btn_run_stop_edge <= btn_run_stop and not btn_run_stop_prev;

    ---------------------------------------------------------------------------
    -- Main Control Logic
    ---------------------------------------------------------------------------
    process(clk_in, reset)
    begin
        if reset = '1' then
            clk_enable <= '0';  -- Start stopped
            stepping_phi <= '0';
            stepping_sync <= '0';
            reset_pending <= '0';
            reset_active <= '0';
            reset_counter <= 0;
            btn_run_stop_prev <= '0';
            bootstrap_done_prev <= '0';
        elsif rising_edge(clk_in) then

            -- Track button state for edge detection
            btn_run_stop_prev <= btn_run_stop;
            bootstrap_done_prev <= bootstrap_done;

            -- Hardware break: stop when bootstrap completes (rising edge)
            if bootstrap_done = '1' and bootstrap_done_prev = '0' then
                clk_enable <= '0';
            end if;

            -- Reset sequence: hold for 500 clocks then release
            if reset_active = '1' then
                reset_counter <= reset_counter + 1;
                if reset_counter = 500 then
                    reset_active <= '0';
                    reset_counter <= 0;
                end if;
            end if;

            -- Run/Stop button - only on rising edge
            if btn_run_stop_edge = '1' then
                if clk_enable = '1' then
                    -- Currently running -> stop (gate clocks)
                    clk_enable <= '0';
                else
                    -- Currently stopped -> reset and run
                    clk_enable <= '1';
                    reset_active <= '1';
                    reset_counter <= 0;
                end if;
            end if;

            -- Step Phi button (only when stopped)
            if btn_step_cycle = '1' and clk_enable = '0' then
                stepping_phi <= '1';
            end if;

            -- Stop stepping on phi falling edge
            if stepping_phi = '1' and (phi1_falling = '1' or phi2_falling = '1') then
                stepping_phi <= '0';
            end if;

            -- Step Sync button (only when stopped)
            if btn_step_sync = '1' and clk_enable = '0' then
                stepping_sync <= '1';
            end if;

            -- Stop stepping on sync toggle
            if stepping_sync = '1' and sync_in /= sync_prev then
                stepping_sync <= '0';
            end if;

        end if;
    end process;

    ---------------------------------------------------------------------------
    -- Status Outputs
    ---------------------------------------------------------------------------
    is_running <= clk_enable or stepping_phi or stepping_sync;

    -- Phase indicators (simple: based on current phi levels)
    next_is_phi1 <= '1' when phi1_in = '0' and phi2_in = '0' and phi2_prev = '1' else '0';
    next_is_phi2 <= '1' when phi1_in = '0' and phi2_in = '0' and phi1_prev = '1' else '0';

    triggered <= '0';  -- Reserved

    reset_request <= reset_active;

end architecture rtl;

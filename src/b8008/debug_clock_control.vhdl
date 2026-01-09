--------------------------------------------------------------------------------
-- debug_clock_control.vhdl
--------------------------------------------------------------------------------
-- Three-Button Debug Controller for Intel 8008
--
-- This module sits between the 100 MHz system clock and the b8008 CPU,
-- providing run/stop/step control. It acts like an external debug device
-- that could be wired to a few pins on a real system.
--
-- Features:
--   - Run/Stop toggle: Start/stop CPU execution
--   - Step Cycle: Advance one full clock cycle (phi1+phi2 = 220 clocks)
--   - Step to SYNC: Auto-run until SYNC asserts (instruction boundary)
--
-- Architecture:
--   The CPU generates phi1/phi2 internally from clk_in via phase_clocks.
--   We gate clk_in before it reaches the CPU. When stopped, no clock edges
--   reach the CPU, so phase_clocks freezes and the CPU preserves state.
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
        btn_step_cycle  : in  std_logic;   -- Single full cycle step (220 clocks)
        btn_step_sync   : in  std_logic;   -- Run until SYNC (instruction boundary)

        -- CPU feedback (directly from b8008_top outputs)
        phi1_in         : in  std_logic;   -- phi1 from CPU (for phase tracking)
        phi2_in         : in  std_logic;   -- phi2 from CPU (for phase tracking)
        sync_in         : in  std_logic;   -- SYNC from CPU (for step-to-SYNC)

        -- Gated clock output to CPU
        clk_out         : out std_logic;   -- Gated master clock

        -- Status outputs for LEDs
        is_running      : out std_logic;   -- '1' = running, '0' = stopped
        next_is_phi1    : out std_logic;   -- '1' = phi1 is next phase
        next_is_phi2    : out std_logic;   -- '1' = phi2 is next phase
        triggered       : out std_logic    -- Reserved for breakpoint (active high)
    );
end entity debug_clock_control;

architecture rtl of debug_clock_control is

    -- Phase timing constants (from phase_clocks.vhdl)
    -- These define how many 100 MHz clocks each phase lasts
    constant PHI1_CLOCKS : integer := 80;   -- 0.8 us phi1 pulse
    constant DEAD1_CLOCKS : integer := 40;  -- 0.4 us dead time after phi1
    constant PHI2_CLOCKS : integer := 60;   -- 0.6 us phi2 pulse
    constant DEAD2_CLOCKS : integer := 40;  -- 0.4 us dead time after phi2
    constant TOTAL_CYCLE : integer := 220;  -- Total clocks per phi1+phi2 cycle

    -- Debug state machine
    type debug_state_t is (
        DEBUG_RUNNING,      -- Free-running, clocks pass through
        DEBUG_STOPPING,     -- Waiting for clean stop point (end of DEAD_2)
        DEBUG_STOPPED,      -- Clocks frozen, waiting for command
        DEBUG_STEP_CYCLE,   -- Stepping through one full cycle (220 clocks)
        DEBUG_STEP_SYNC     -- Running until SYNC goes high
    );
    signal debug_state : debug_state_t := DEBUG_RUNNING;

    -- Clock enable signal (directly gates the clock)
    signal clk_enable : std_logic := '1';

    -- Phase tracking
    type phase_t is (PHASE_PHI1, PHASE_DEAD1, PHASE_PHI2, PHASE_DEAD2);
    signal current_phase : phase_t := PHASE_PHI1;
    signal phase_counter : integer range 0 to 127 := 0;

    -- Step counter for counting clocks during step operations
    signal step_counter : integer range 0 to 255 := 0;

    -- Edge detection for phi1/phi2 feedback
    signal phi1_prev : std_logic := '0';
    signal phi2_prev : std_logic := '0';
    signal phi1_rising : std_logic;
    signal phi2_rising : std_logic;
    signal phi1_falling : std_logic;
    signal phi2_falling : std_logic;

    -- Internal status signals
    signal running_int : std_logic := '1';
    signal next_phi1_int : std_logic := '0';
    signal next_phi2_int : std_logic := '0';

begin

    ---------------------------------------------------------------------------
    -- Clock Gating
    ---------------------------------------------------------------------------
    -- Simple AND gate: when clk_enable is low, output stays low
    -- This is the core of the debug controller
    clk_out <= clk_in and clk_enable;

    ---------------------------------------------------------------------------
    -- Edge Detection for Phase Feedback
    ---------------------------------------------------------------------------
    process(clk_in, reset)
    begin
        if reset = '1' then
            phi1_prev <= '0';
            phi2_prev <= '0';
        elsif rising_edge(clk_in) then
            phi1_prev <= phi1_in;
            phi2_prev <= phi2_in;
        end if;
    end process;

    phi1_rising  <= phi1_in and not phi1_prev;
    phi2_rising  <= phi2_in and not phi2_prev;
    phi1_falling <= not phi1_in and phi1_prev;
    phi2_falling <= not phi2_in and phi2_prev;

    ---------------------------------------------------------------------------
    -- Phase Tracking State Machine
    ---------------------------------------------------------------------------
    -- Track current phase by watching phi1/phi2 feedback and counting clocks
    -- This runs on the ungated system clock so we can track even when stopped
    process(clk_in, reset)
    begin
        if reset = '1' then
            current_phase <= PHASE_PHI1;
            phase_counter <= 0;
        elsif rising_edge(clk_in) then
            if clk_enable = '1' then
                -- Only advance when clock is enabled (CPU is running)
                case current_phase is
                    when PHASE_PHI1 =>
                        if phase_counter = PHI1_CLOCKS - 1 then
                            current_phase <= PHASE_DEAD1;
                            phase_counter <= 0;
                        else
                            phase_counter <= phase_counter + 1;
                        end if;

                    when PHASE_DEAD1 =>
                        if phase_counter = DEAD1_CLOCKS - 1 then
                            current_phase <= PHASE_PHI2;
                            phase_counter <= 0;
                        else
                            phase_counter <= phase_counter + 1;
                        end if;

                    when PHASE_PHI2 =>
                        if phase_counter = PHI2_CLOCKS - 1 then
                            current_phase <= PHASE_DEAD2;
                            phase_counter <= 0;
                        else
                            phase_counter <= phase_counter + 1;
                        end if;

                    when PHASE_DEAD2 =>
                        if phase_counter = DEAD2_CLOCKS - 1 then
                            current_phase <= PHASE_PHI1;
                            phase_counter <= 0;
                        else
                            phase_counter <= phase_counter + 1;
                        end if;
                end case;
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- Debug State Machine
    ---------------------------------------------------------------------------
    process(clk_in, reset)
    begin
        if reset = '1' then
            debug_state <= DEBUG_RUNNING;
            clk_enable <= '1';
            step_counter <= 0;
        elsif rising_edge(clk_in) then
            case debug_state is

                ---------------------------------------------------------------
                -- RUNNING: Free-running mode, clocks pass through
                ---------------------------------------------------------------
                when DEBUG_RUNNING =>
                    clk_enable <= '1';
                    if btn_run_stop = '1' then
                        -- User wants to stop - wait for clean stop point
                        debug_state <= DEBUG_STOPPING;
                    end if;

                ---------------------------------------------------------------
                -- STOPPING: Wait for end of DEAD_2 (clean stop point)
                ---------------------------------------------------------------
                when DEBUG_STOPPING =>
                    clk_enable <= '1';  -- Keep running until we reach stop point
                    -- Stop at the end of DEAD_2 (phi1 is about to start)
                    if current_phase = PHASE_DEAD2 and phase_counter = DEAD2_CLOCKS - 1 then
                        debug_state <= DEBUG_STOPPED;
                        clk_enable <= '0';
                    end if;

                ---------------------------------------------------------------
                -- STOPPED: Clocks frozen, waiting for command
                ---------------------------------------------------------------
                when DEBUG_STOPPED =>
                    clk_enable <= '0';

                    if btn_run_stop = '1' then
                        -- Resume running
                        debug_state <= DEBUG_RUNNING;
                        clk_enable <= '1';

                    elsif btn_step_cycle = '1' then
                        -- Step one full cycle (220 clocks)
                        -- Always works regardless of current phase
                        debug_state <= DEBUG_STEP_CYCLE;
                        step_counter <= 0;
                        clk_enable <= '1';

                    elsif btn_step_sync = '1' then
                        -- Run until SYNC goes high (instruction boundary)
                        debug_state <= DEBUG_STEP_SYNC;
                        clk_enable <= '1';
                    end if;

                ---------------------------------------------------------------
                -- STEP_CYCLE: Step through one full cycle (phi1+phi2 = 220 clocks)
                ---------------------------------------------------------------
                when DEBUG_STEP_CYCLE =>
                    clk_enable <= '1';
                    step_counter <= step_counter + 1;
                    -- Stop after full cycle
                    if step_counter = TOTAL_CYCLE - 1 then
                        debug_state <= DEBUG_STOPPED;
                        clk_enable <= '0';
                        step_counter <= 0;
                    end if;

                ---------------------------------------------------------------
                -- STEP_SYNC: Run until SYNC asserts (instruction boundary)
                ---------------------------------------------------------------
                when DEBUG_STEP_SYNC =>
                    clk_enable <= '1';
                    -- SYNC goes high at start of T1 (first half of each T-state)
                    -- Stop when we see SYNC high at the end of DEAD_2
                    -- (This is the start of a new instruction)
                    if sync_in = '1' and current_phase = PHASE_DEAD2 and
                       phase_counter = DEAD2_CLOCKS - 1 then
                        debug_state <= DEBUG_STOPPED;
                        clk_enable <= '0';
                    end if;

            end case;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- Status Outputs
    ---------------------------------------------------------------------------
    -- Running status
    running_int <= '1' when debug_state = DEBUG_RUNNING or
                            debug_state = DEBUG_STOPPING or
                            debug_state = DEBUG_STEP_CYCLE or
                            debug_state = DEBUG_STEP_SYNC else '0';
    is_running <= running_int;

    -- Next phase indicators (only meaningful when stopped)
    -- After DEAD_2, phi1 is next
    next_phi1_int <= '1' when (current_phase = PHASE_DEAD2) or
                              (current_phase = PHASE_PHI1 and phase_counter = 0) else '0';
    -- After DEAD_1, phi2 is next
    next_phi2_int <= '1' when (current_phase = PHASE_DEAD1) or
                              (current_phase = PHASE_PHI2 and phase_counter = 0) else '0';

    next_is_phi1 <= next_phi1_int;
    next_is_phi2 <= next_phi2_int;

    -- Breakpoint trigger (reserved for Phase 2)
    triggered <= '0';

end architecture rtl;

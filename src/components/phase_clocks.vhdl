-------------------------------------------------------------------------------
-- Two-Phase Non-Overlapping Clock Generator for Intel 8008
-------------------------------------------------------------------------------
-- Copyright (c) 2025 Robert Rico
--
-- Generates PHI1 and PHI2 clock phases with proper timing for Intel 8008:
--   - PHI1: 0.8 µs pulse width
--   - Dead time: 0.4 µs
--   - PHI2: 0.6 µs pulse width
--   - Dead time: 0.4 µs
--   - Total cycle: 2.2 µs (within 3 µs max cycle time)
--
-- License: MIT (see LICENSE.txt)
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity phase_clocks is
    Port (
        clk_in : in STD_LOGIC;
        reset  : in STD_LOGIC;
        -- When low, the phase state machine freezes in place: phi1/phi2 hold
        -- their current levels and no rising/falling pulses are emitted.
        -- Defaults to '1' (always run) so existing unconnected instantiations
        -- behave as before.
        run_enable : in STD_LOGIC := '1';
        phi1   : out STD_LOGIC;
        phi2   : out STD_LOGIC;
        sync   : out STD_LOGIC;  -- Divide-by-two: distinguishes between two clock periods of each state
        -- One-cycle pulses on clk_in domain, for downstream flops that want to
        -- act on a phi1/phi2 edge without being clocked by phi1/phi2 directly.
        -- Use as: process(clk_in) ... if rising_edge(clk_in) and phi1_rising='1' then ...
        phi1_rising  : out STD_LOGIC;
        phi1_falling : out STD_LOGIC;
        phi2_rising  : out STD_LOGIC;
        phi2_falling : out STD_LOGIC
    );
end phase_clocks;

architecture rtl of phase_clocks is
    type clk_phase is (PHI_1, PHI_2, DEAD_PHI, DEAD_PHI_2);

    -- Intel 8008 Timing Constraints (assuming 100 MHz input clock = 10ns period):
    -- Max cycle time: 3 µs (rising PHI1 to next rising PHI1)
    -- Min PHI1 pulse width: 0.7 µs (70 clocks @ 100 MHz)
    -- Min PHI2 pulse width: 0.55 µs (55 clocks @ 100 MHz)

    -- Timing configuration:
    -- PHI1: 0.8 µs (80 clocks) - exceeds 0.7 µs minimum
    -- Dead time 1: 0.4 µs (40 clocks)
    -- PHI2: 0.6 µs (60 clocks) - exceeds 0.55 µs minimum
    -- Dead time 2: 0.4 µs (40 clocks)
    -- Total cycle: 2.2 µs - meets 3 µs maximum

    constant PHI1_DIVIDER : integer := 80;    -- 0.8 µs PHI1 pulse width
    constant PHI2_DIVIDER : integer := 60;    -- 0.6 µs PHI2 pulse width
    constant DEAD_DIVIDER : integer := 40;    -- 0.4 µs dead time

    signal counter : integer range 0 to 127 := 0;
    signal current_phase : clk_phase := PHI_1;

    -- Internal signals to avoid glitches
    signal phi1_next : std_logic := '1';
    signal phi2_next : std_logic := '0';

    -- SYNC signal: toggles every complete phi1+phi2 cycle
    -- High during one clock cycle, low during next clock cycle
    -- Two clock cycles = one state
    signal sync_toggle : std_logic := '1';

    -- Internal copies of phi1/phi2 so we can detect edges without reading output ports
    signal phi1_reg  : std_logic := '1';
    signal phi2_reg  : std_logic := '0';
    signal phi1_prev : std_logic := '1';
    signal phi2_prev : std_logic := '0';
begin
    -- Registered outputs to eliminate glitches. When run_enable='0', phi1_reg
    -- and phi2_reg hold their current value (phi1_next/phi2_next are also
    -- frozen below) and phi*_prev also freezes -- so no edge pulses fire.
    process(clk_in, reset)
    begin
        if reset = '1' then
            phi1_reg  <= '1';
            phi2_reg  <= '0';
            phi1_prev <= '1';
            phi2_prev <= '0';
            sync <= '1';  -- Start with SYNC high
        elsif rising_edge(clk_in) then
            if run_enable = '1' then
                phi1_reg  <= phi1_next;
                phi2_reg  <= phi2_next;
                phi1_prev <= phi1_reg;
                phi2_prev <= phi2_reg;
                sync <= sync_toggle;
            end if;
        end if;
    end process;

    phi1 <= phi1_reg;
    phi2 <= phi2_reg;

    -- One-cycle edge pulses, asserted the clk after the phi transition.
    -- Downstream flops clocked on clk_in see the pulse and act exactly one
    -- clk_in cycle after the phi edge occurred -- same ordering as
    -- rising_edge(phi*) but on the clk_in domain.
    phi1_rising  <= phi1_reg and not phi1_prev;
    phi1_falling <= phi1_prev and not phi1_reg;
    phi2_rising  <= phi2_reg and not phi2_prev;
    phi2_falling <= phi2_prev and not phi2_reg;

    -- State machine and counter logic. Gated on run_enable so that when the
    -- debug controller asserts stop the entire phase state freezes with the
    -- CPU naturally halted (no phi edges means no downstream updates).
    process(clk_in, reset)
    begin
        if reset = '1' then
            counter <= 0;
            phi1_next <= '1';
            phi2_next <= '0';
            current_phase <= PHI_1;
            sync_toggle <= '1';  -- Start with SYNC high
        elsif rising_edge(clk_in) and run_enable = '1' then
            case current_phase is
                -- PHI1 active phase
                when PHI_1 =>
                    if counter = PHI1_DIVIDER - 1 then
                        phi1_next <= '0';
                        phi2_next <= '0';
                        current_phase <= DEAD_PHI_2;
                        counter <= 0;
                    else
                        counter <= counter + 1;
                    end if;

                -- Dead time before PHI2
                when DEAD_PHI_2 =>
                    if counter = DEAD_DIVIDER - 1 then
                        phi1_next <= '0';
                        phi2_next <= '1';
                        current_phase <= PHI_2;
                        counter <= 0;
                    else
                        counter <= counter + 1;
                    end if;

                -- PHI2 active phase
                when PHI_2 =>
                    if counter = PHI2_DIVIDER - 1 then
                        phi1_next <= '0';
                        phi2_next <= '0';
                        current_phase <= DEAD_PHI;
                        counter <= 0;
                    else
                        counter <= counter + 1;
                    end if;

                -- Dead time before PHI1
                when DEAD_PHI =>
                    if counter = DEAD_DIVIDER - 1 then
                        phi1_next <= '1';
                        phi2_next <= '0';
                        current_phase <= PHI_1;
                        counter <= 0;
                        -- Toggle SYNC at end of every complete phi1+phi2 clock cycle
                        sync_toggle <= not sync_toggle;
                    else
                        counter <= counter + 1;
                    end if;

            end case;
        end if;
    end process;
end rtl;
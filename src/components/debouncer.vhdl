--------------------------------------------------------------------------------
-- Button Debouncer with Edge Detection
--------------------------------------------------------------------------------
-- Reusable button debouncer with 2-FF synchronizer and edge detection
--
-- Features:
--   - 2-flip-flop synchronizer chain (prevents metastability)
--   - Configurable debounce time via clock frequency and milliseconds
--   - Falling edge detection (outputs single-cycle pulse on button press)
--   - Active-low reset compatible
--
-- Generics:
--   CLK_FREQ_HZ   - Input clock frequency in Hz (e.g., 100_000_000 for 100 MHz)
--   DEBOUNCE_MS   - Debounce time in milliseconds (typically 10-20ms)
--
-- Operation:
--   - btn input assumed active-low (pulled high, goes low when pressed)
--   - btn_pressed outputs single-cycle high pulse on falling edge (press event)
--   - Works at any clock frequency via time-based configuration
--
-- Copyright (c) 2025 Robert Rico
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity debouncer is
    generic(
        CLK_FREQ_HZ   : integer := 100_000_000;  -- Clock frequency in Hz
        DEBOUNCE_MS   : integer := 20;           -- Debounce time in milliseconds
        PULSE_STRETCH : integer := 100;          -- Stretch output pulse by N cycles (for slow CPUs)
        -- Legacy support: if DEBOUNCE_TIME is set, it overrides calculation
        DEBOUNCE_TIME : integer := 0             -- Direct cycle count (0 = use calculated)
    );
    port(
        clk : in std_logic;
        rst : in std_logic;  -- Active low reset
        btn : in std_logic;
        btn_pressed : out std_logic
    );
end debouncer;

architecture rtl of debouncer is
    -- Function to calculate debounce cycles
    function calc_debounce_cycles return integer is
    begin
        if DEBOUNCE_TIME = 0 then
            return (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;
        else
            return DEBOUNCE_TIME;
        end if;
    end function;

    -- Calculate debounce cycles based on frequency and time
    -- If DEBOUNCE_TIME is explicitly set (non-zero), use it for legacy compatibility
    constant DEBOUNCE_CYCLES : integer := calc_debounce_cycles;

    signal btn_sync : std_logic_vector(1 downto 0) := "11";
    signal btn_stable : std_logic := '1';
    signal btn_prev : std_logic := '1';
    signal debounce_counter : integer range 0 to DEBOUNCE_CYCLES := 0;
    signal btn_edge_detect : std_logic := '0';

    -- Pulse stretcher signals
    signal stretch_counter : integer range 0 to PULSE_STRETCH := 0;
    signal btn_ready : std_logic := '0';

begin

    process(clk, rst)
    begin
        if rst = '0' then  -- Active low reset
            btn_sync <= "11";
            btn_stable <= '1';
            btn_prev <= '1';
            debounce_counter <= 0;
            btn_edge_detect <= '0';
            stretch_counter <= 0;
            btn_ready <= '0';
        elsif rising_edge(clk) then
            -- Synchronizer chain
            btn_sync <= btn_sync(0) & btn;

            -- Debounce logic
            if btn_sync(1) = btn_stable then
                debounce_counter <= 0;
            else
                if debounce_counter < DEBOUNCE_CYCLES then
                    debounce_counter <= debounce_counter + 1;
                else
                    btn_stable <= btn_sync(1);
                    debounce_counter <= 0;
                end if;
            end if;

            -- Edge detection: falling edge (button press '1' -> '0')
            if btn_prev = '1' and btn_stable = '0' then
                btn_edge_detect <= '1';
            else
                btn_edge_detect <= '0';
            end if;

            btn_prev <= btn_stable;

            -- Pulse stretcher: hold btn_ready high for PULSE_STRETCH cycles
            if btn_edge_detect = '1' then
                -- Edge detected, start stretch counter
                stretch_counter <= PULSE_STRETCH;
                btn_ready <= '1';
            elsif stretch_counter > 0 then
                -- Counting down
                stretch_counter <= stretch_counter - 1;
                btn_ready <= '1';
            else
                -- Counter expired
                btn_ready <= '0';
            end if;
        end if;
    end process;

    btn_pressed <= btn_ready;

end rtl;
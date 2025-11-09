--------------------------------------------------------------------------------
-- Simple Interrupt Controller for Intel 8008 Blinky Project
--------------------------------------------------------------------------------
-- Generates a single startup interrupt to release CPU from STOPPED state
-- Minimal design using phi1 clock for state tracking
--
-- Operation:
--   1. INT is asserted high after reset
--   2. When T1I state is detected (S2=1, S1=1, S0=0), drive 0x05 during T1I+T2
--   3. After T3 state completes, clear INT permanently
--   4. CPU can now execute program and halt without being re-interrupted
--
-- Copyright (c) 2025 Robert Rico
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity interrupt_controller_simple is
    port (
        -- CPU clock (phi1) for state tracking
        phi1            : in  std_logic;
        reset_n         : in  std_logic;

        -- CPU interface (state signals)
        S2              : in  std_logic;
        S1              : in  std_logic;
        S0              : in  std_logic;
        SYNC            : in  std_logic;

        -- Bus arbiter interface
        int_data_out    : out std_logic_vector(7 downto 0);  -- Always 0x05
        int_data_enable : out std_logic;                      -- High during T1I

        -- Interrupt output to CPU
        INT             : out std_logic                       -- High after reset, clears after acknowledge
    );
end entity interrupt_controller_simple;

architecture rtl of interrupt_controller_simple is
    constant RST_0_OPCODE : std_logic_vector(7 downto 0) := "00000101";  -- RST 0 = 0x05

    -- State detection signals (combinatorial from CPU state)
    signal is_t1i_comb : std_logic;
    signal is_t2_comb  : std_logic;
    signal is_t3_comb  : std_logic;

    -- Registered state detection (filtered for glitches)
    signal is_t1i : std_logic;
    signal is_t2  : std_logic;
    signal is_t3  : std_logic;

    -- Latch to track interrupt acknowledge sequence
    signal in_int_ack : std_logic := '0';

    -- INT assertion control - set on reset, cleared after interrupt acknowledge
    signal int_asserted : std_logic := '1';
begin
    -- Detect states combinatorially
    is_t1i_comb <= '1' when (S2 = '1' and S1 = '1' and S0 = '0') else '0';
    is_t2_comb  <= '1' when (S2 = '1' and S1 = '0' and S0 = '0') else '0';
    is_t3_comb  <= '1' when (S2 = '0' and S1 = '0' and S0 = '1') else '0';

    -- INT driven by int_asserted signal (high on reset, cleared after acknowledge)
    INT <= int_asserted;

    -- Always output RST opcode
    int_data_out <= RST_0_OPCODE;

    -- Track interrupt acknowledge sequence and INT state
    -- Uses phi1 clock (same as CPU) - registers state detection to filter glitches
    process(phi1, reset_n)
    begin
        if reset_n = '0' then
            is_t1i <= '0';
            is_t2 <= '0';
            is_t3 <= '0';
            in_int_ack <= '0';
            int_asserted <= '1';  -- Assert INT on reset for startup interrupt
        elsif rising_edge(phi1) then
            -- Register state detection signals to filter glitches
            is_t1i <= is_t1i_comb;
            is_t2 <= is_t2_comb;
            is_t3 <= is_t3_comb;

            if is_t1i = '1' then
                -- Entering interrupt acknowledge
                in_int_ack <= '1';
            elsif is_t3 = '1' and in_int_ack = '1' then
                -- Completed interrupt acknowledge sequence
                in_int_ack <= '0';
                int_asserted <= '0';  -- Clear INT after startup interrupt completes
            end if;
        end if;
    end process;

    -- Drive bus during T1I or during T2 that follows T1I
    int_data_enable <= is_t1i or (is_t2 and in_int_ack);

end architecture rtl;

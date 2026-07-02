--------------------------------------------------------------------------------
-- int_button.vhdl
--------------------------------------------------------------------------------
-- Front-panel interrupt request from a DIP switch
--
-- Any debounced flip of the switch (either direction) while armed raises
-- one interrupt request. The request is a LATCH, held until the CPU's T1I
-- acknowledge clears it, so slow phi-domain sampling cannot miss it. The
-- RST vector to jam is captured from vector_sel at request time and held
-- stable while the request is pending.
--
-- DUMB module: no knowledge of the CPU, bootstrap, or instructions -
-- the caller supplies "armed" and the T1I acknowledge strobe.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity int_button is
    generic (
        CLK_FREQ_HZ : integer := 25_000_000;
        DEBOUNCE_MS : integer := 20
    );
    port (
        clk        : in  std_logic;
        reset      : in  std_logic;                    -- active high
        sw_raw     : in  std_logic;                    -- raw DIP level (async)
        vector_sel : in  std_logic;                    -- 0 = RST 5, 1 = RST 7
        armed      : in  std_logic;                    -- ignore flips while '0'
        t1i_ack    : in  std_logic;                    -- '1' during T1I: clears request
        int_req    : out std_logic;                    -- level, held until acked
        int_vector : out std_logic_vector(2 downto 0)  -- "101" or "111"
    );
end entity int_button;

architecture rtl of int_button is

    constant DEBOUNCE_CYCLES : integer := (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;

    signal sw_sync   : std_logic_vector(1 downto 0) := "00";
    signal sw_stable : std_logic := '0';
    signal counter   : integer range 0 to DEBOUNCE_CYCLES := 0;
    signal req_ff    : std_logic := '0';
    signal vec_ff    : std_logic_vector(2 downto 0) := "101";

begin

    process(clk, reset)
    begin
        if reset = '1' then
            sw_sync   <= "00";
            sw_stable <= '0';
            counter   <= 0;
            req_ff    <= '0';
        elsif rising_edge(clk) then
            sw_sync <= sw_sync(0) & sw_raw;

            if sw_sync(1) = sw_stable then
                counter <= 0;
            elsif counter < DEBOUNCE_CYCLES then
                counter <= counter + 1;
            else
                sw_stable <= sw_sync(1);   -- accepted flip (either direction)
                counter   <= 0;
                if armed = '1' and req_ff = '0' then
                    req_ff <= '1';
                    if vector_sel = '1' then
                        vec_ff <= "111";   -- RST 7
                    else
                        vec_ff <= "101";   -- RST 5
                    end if;
                end if;
            end if;

            if t1i_ack = '1' then
                req_ff <= '0';
            end if;
        end if;
    end process;

    int_req    <= req_ff;
    int_vector <= vec_ff;

end architecture rtl;

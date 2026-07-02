--------------------------------------------------------------------------------
-- ram_1kx8_sync.vhdl - 1K x 8 RAM, synchronous read and write
--------------------------------------------------------------------------------
-- Replaces the legacy async-read ram_1kx8 (distributed LUTRAM with tristate
-- outputs). Synchronous read makes Yosys infer block RAM (DP16KD) and removes
-- the deep asynchronous read mux and the 'Z' bus. The one-clock read latency
-- is invisible to the 8008: the address is latched at T1/T2 and data is not
-- consumed until well into T3, microseconds later.
--
-- No chip-select gating on the read port: DATA_OUT always carries the
-- registered read of ADDR. The data-bus multiplexer in b8008_top only
-- selects it when the RAM is addressed, so gating here is redundant.
--
-- Copyright (c) 2026 Robert Rico
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ram_1kx8_sync is
    port (
        CLK      : in  std_logic;
        ADDR     : in  std_logic_vector(9 downto 0);
        DATA_IN  : in  std_logic_vector(7 downto 0);
        DATA_OUT : out std_logic_vector(7 downto 0);
        RW_N     : in  std_logic;   -- 0 = write, 1 = read
        CS_N     : in  std_logic    -- 0 = selected
    );
end entity ram_1kx8_sync;

architecture rtl of ram_1kx8_sync is
    type ram_array is array (0 to 1023) of std_logic_vector(7 downto 0);
    signal ram : ram_array := (others => x"00");
begin

    process(CLK)
    begin
        if rising_edge(CLK) then
            if CS_N = '0' and RW_N = '0' then
                ram(to_integer(unsigned(ADDR))) <= DATA_IN;
            end if;
            DATA_OUT <= ram(to_integer(unsigned(ADDR)));
        end if;
    end process;

end architecture rtl;

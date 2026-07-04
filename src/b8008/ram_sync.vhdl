--------------------------------------------------------------------------------
-- ram_sync.vhdl - Parameterized synchronous RAM (2^ADDR_BITS x 8)
--------------------------------------------------------------------------------
-- Generalizes the old ram_1kx8_sync (fixed 1K) to any power-of-two size via
-- the ADDR_BITS generic. Synchronous read and write so Yosys infers block
-- RAM (DP16KD). The one-clock read latency is invisible to the 8008: the
-- address is latched at T1/T2 and data is not consumed until well into T3,
-- microseconds later.
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
use std.textio.all;

entity ram_sync is
    generic (
        ADDR_BITS : integer := 10;
        -- Simulation-only preload (one hex byte per line, same format as
        -- the .mem files). Empty string = all zeros, exactly as the
        -- synthesized BRAM initializes on the FPGA.
        INIT_FILE : string := ""
    );
    port (
        CLK      : in  std_logic;
        ADDR     : in  std_logic_vector(ADDR_BITS-1 downto 0);
        DATA_IN  : in  std_logic_vector(7 downto 0);
        DATA_OUT : out std_logic_vector(7 downto 0);
        RW_N     : in  std_logic;   -- 0 = write, 1 = read
        CS_N     : in  std_logic    -- 0 = selected
    );
end entity ram_sync;

architecture rtl of ram_sync is
    type ram_array is array (0 to 2**ADDR_BITS - 1) of std_logic_vector(7 downto 0);

    impure function init_ram return ram_array is
        file f       : text;
        variable l   : line;
        variable b   : std_logic_vector(7 downto 0);
        variable mem : ram_array := (others => x"00");
        variable i   : integer := 0;
    begin
        if INIT_FILE'length > 0 then
            file_open(f, INIT_FILE, read_mode);
            while not endfile(f) and i < 2**ADDR_BITS loop
                readline(f, l);
                hread(l, b);
                mem(i) := b;
                i := i + 1;
            end loop;
            file_close(f);
        end if;
        return mem;
    end function;

    signal ram : ram_array := init_ram;
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

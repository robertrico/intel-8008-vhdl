--------------------------------------------------------------------------------
-- address_decoder.vhdl - Configurable memory address decoder
--------------------------------------------------------------------------------
-- Decodes the 14-bit latched address into ROM and RAM selects. Ranges are
-- inclusive [BASE, LAST] and set by generics; defaults match the b8008_top
-- memory map. Addresses outside both ranges select nothing (open bus - the
-- data mux in b8008_top falls through to zeros).
--
-- The decoder is dumb: it knows nothing about cycle types, T-states, or
-- read/write. It maps an address to a chip select, full stop.
--
-- Copyright (c) 2026 Robert Rico
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity address_decoder is
    generic (
        ROM_BASE : integer := 16#0000#;
        ROM_LAST : integer := 16#1FFF#;
        RAM_BASE : integer := 16#2000#;
        RAM_LAST : integer := 16#23FF#
    );
    port (
        address  : in  std_logic_vector(13 downto 0);
        rom_sel  : out std_logic;
        ram_sel  : out std_logic;
        rom_cs_n : out std_logic;   -- active low mirror of rom_sel
        ram_cs_n : out std_logic    -- active low mirror of ram_sel
    );
end entity address_decoder;

architecture rtl of address_decoder is
    signal addr_int : integer range 0 to 16383;
    signal rom_hit  : std_logic;
    signal ram_hit  : std_logic;
begin

    addr_int <= to_integer(unsigned(address));

    rom_hit <= '1' when addr_int >= ROM_BASE and addr_int <= ROM_LAST else '0';
    ram_hit <= '1' when addr_int >= RAM_BASE and addr_int <= RAM_LAST else '0';

    rom_sel  <= rom_hit;
    ram_sel  <= ram_hit;
    rom_cs_n <= not rom_hit;
    ram_cs_n <= not ram_hit;

end architecture rtl;

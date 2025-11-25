--------------------------------------------------------------------------------
-- scratchpad_addr_mux.vhdl
--------------------------------------------------------------------------------
-- Scratchpad Address Multiplexer for Intel 8008
--
-- Selects which register to access based on 3-bit select signal
-- - Input: 3-bit register select (000=A, 001=B, 010=C, 011=D, 100=E, 101=H, 110=L, 111=M)
-- - Output: 3-bit address to scratchpad decoder
-- - DUMB module: just passes through the select signal
--
-- Note: This is kept as a separate module for clarity and future expansion
-- (e.g., adding priority arbitration if needed)
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.b8008_types.all;

entity scratchpad_addr_mux is
    port (
        -- Register select from Memory/I/O Control
        reg_select : in std_logic_vector(2 downto 0);

        -- Output to scratchpad decoder
        addr_out : out std_logic_vector(2 downto 0)
    );
end entity scratchpad_addr_mux;

architecture rtl of scratchpad_addr_mux is

begin

    -- Simple pass-through for now
    -- In the future, this could handle:
    -- - Priority arbitration between multiple requesters
    -- - Register remapping
    -- - Special handling for M (memory indirect via H:L)
    addr_out <= reg_select;

end architecture rtl;

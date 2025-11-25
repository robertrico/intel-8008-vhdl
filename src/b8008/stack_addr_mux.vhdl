--------------------------------------------------------------------------------
-- stack_addr_mux.vhdl
--------------------------------------------------------------------------------
-- Stack Address Multiplexer for Intel 8008
--
-- Selects between PC and stack pointer for address output
-- - During normal instruction fetch: use PC address
-- - During CALL/RST/RET: use stack address
-- - DUMB module: just a 2:1 multiplexer
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.b8008_types.all;

entity stack_addr_mux is
    port (
        -- Address inputs
        pc_addr    : in std_logic_vector(13 downto 0);  -- From program counter
        stack_addr : in std_logic_vector(13 downto 0);  -- From stack (via decoder)

        -- Select control from Memory/I/O Control
        select_stack : in std_logic;  -- 0=PC, 1=stack

        -- Address output (to memory address bus)
        addr_out : out std_logic_vector(13 downto 0)
    );
end entity stack_addr_mux;

architecture rtl of stack_addr_mux is

begin

    -- Simple 2:1 multiplexer
    addr_out <= stack_addr when select_stack = '1' else pc_addr;

end architecture rtl;

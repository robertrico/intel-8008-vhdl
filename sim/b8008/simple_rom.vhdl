--------------------------------------------------------------------------------
-- simple_rom.vhdl
--------------------------------------------------------------------------------
-- Simple ROM for b8008 testbench
--
-- Very basic ROM that responds to address and outputs data
-- Used for testing instruction fetch
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity simple_rom is
    port (
        address  : in  std_logic_vector(13 downto 0);
        data     : out std_logic_vector(7 downto 0);
        enable   : in  std_logic  -- Output enable
    );
end entity simple_rom;

architecture behavioral of simple_rom is

    type rom_array_t is array (0 to 15) of std_logic_vector(7 downto 0);

    -- Simple test program:
    -- 0x00: HLT (00 000 000) - Halt instruction
    -- Rest filled with HLT for safety
    constant ROM_CONTENT : rom_array_t := (
        0  => x"00",  -- HLT
        1  => x"00",  -- HLT
        2  => x"00",  -- HLT
        3  => x"00",  -- HLT
        4  => x"00",  -- HLT
        5  => x"00",  -- HLT
        6  => x"00",  -- HLT
        7  => x"00",  -- HLT
        8  => x"00",  -- HLT
        9  => x"00",  -- HLT
        10 => x"00",  -- HLT
        11 => x"00",  -- HLT
        12 => x"00",  -- HLT
        13 => x"00",  -- HLT
        14 => x"00",  -- HLT
        15 => x"00"   -- HLT
    );

begin

    -- Asynchronous read - always output data, no tri-state
    -- (Tri-state will be handled by testbench logic)
    process(address)
        variable addr_int : integer;
    begin
        addr_int := to_integer(unsigned(address));
        if addr_int < 16 then
            data <= ROM_CONTENT(addr_int);
        else
            data <= x"00";  -- Default to HLT for out of range
        end if;
    end process;

end architecture behavioral;

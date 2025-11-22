--------------------------------------------------------------------------------
-- b8008_types.vhdl
--------------------------------------------------------------------------------
-- Common types and constants for the b8008 modular Intel 8008 implementation
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package b8008_types is

    -- Intel 8008 has 14-bit addressing (16KB address space)
    subtype address_t is unsigned(13 downto 0);

    -- 8-bit data
    subtype data_t is std_logic_vector(7 downto 0);

    -- Control signals for program counter
    type pc_control_t is record
        increment : std_logic;  -- Increment PC
        load      : std_logic;  -- Load new value into PC
        hold      : std_logic;  -- Hold current value (no change)
    end record;

    -- Default PC control: hold
    constant PC_HOLD : pc_control_t := (
        increment => '0',
        load      => '0',
        hold      => '1'
    );

    constant PC_INCREMENT : pc_control_t := (
        increment => '1',
        load      => '0',
        hold      => '0'
    );

    constant PC_LOAD : pc_control_t := (
        increment => '0',
        load      => '1',
        hold      => '0'
    );

end package b8008_types;

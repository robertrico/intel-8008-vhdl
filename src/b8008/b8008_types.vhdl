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
        increment_lower : std_logic;  -- Increment lower byte (PCL) during T1
        increment_upper : std_logic;  -- Increment upper byte (PCH) during T2 if carry
        load            : std_logic;  -- Load new value into PC
    end record;
    -- (No 'hold' member: absence of any op IS hold - every slot keeps
    -- its value when no increment/load fires.)

    -- Default PC control: no operation (slot holds)
    constant PC_HOLD : pc_control_t := (
        increment_lower => '0',
        increment_upper => '0',
        load            => '0'
    );

    constant PC_INCREMENT_LOWER : pc_control_t := (
        increment_lower => '1',
        increment_upper => '0',
        load            => '0'
    );

    constant PC_INCREMENT_UPPER : pc_control_t := (
        increment_lower => '0',
        increment_upper => '1',
        load            => '0'
    );

    constant PC_LOAD : pc_control_t := (
        increment_lower => '0',
        increment_upper => '0',
        load            => '1'
    );

end package b8008_types;

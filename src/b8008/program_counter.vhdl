--------------------------------------------------------------------------------
-- program_counter.vhdl
--------------------------------------------------------------------------------
-- Simple, explicit program counter for Intel 8008
--
-- This module does ONE thing: manages the 14-bit program counter
-- - Increments when told to increment
-- - Loads when told to load
-- - Holds when told to hold
-- - NO conditional logic, NO knowledge of instructions or interrupts
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.b8008_types.all;

entity program_counter is
    port (
        clk       : in  std_logic;
        reset     : in  std_logic;

        -- Control signals (explicit, one-hot)
        control   : in  pc_control_t;

        -- Data input for load operation
        data_in   : in  address_t;

        -- Current PC value (always available)
        pc_out    : out address_t
    );
end entity program_counter;

architecture rtl of program_counter is
    signal pc : address_t := (others => '0');
begin

    -- Output current PC
    pc_out <= pc;

    -- PC control process
    process(clk, reset)
    begin
        if reset = '1' then
            pc <= (others => '0');

        elsif rising_edge(clk) then
            -- Explicit control - no complex conditions
            if control.increment = '1' then
                pc <= pc + 1;

            elsif control.load = '1' then
                pc <= data_in;

            elsif control.hold = '1' then
                -- Do nothing, keep current value
                null;

            else
                -- Default: hold
                -- (All control signals should be one-hot, but default to safe behavior)
                null;
            end if;
        end if;
    end process;

end architecture rtl;

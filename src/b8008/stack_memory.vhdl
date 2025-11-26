--------------------------------------------------------------------------------
-- stack_memory.vhdl
--------------------------------------------------------------------------------
-- Stack Memory for Intel 8008
--
-- 8-level stack, each level stores a 14-bit return address
-- - Used for CALL/RET/RST instructions
-- - Each level has individual enable from stack decoder
-- - DUMB module: 8 x 14-bit registers
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.b8008_types.all;

entity stack_memory is
    port (
        -- Clock (phi1 from clock generator)
        phi1 : in std_logic;

        -- Reset
        reset : in std_logic;

        -- 14-bit address input (from PC during CALL/RST)
        addr_in : in address_t;

        -- Individual level enables from stack decoder
        enable_level_0 : in std_logic;
        enable_level_1 : in std_logic;
        enable_level_2 : in std_logic;
        enable_level_3 : in std_logic;
        enable_level_4 : in std_logic;
        enable_level_5 : in std_logic;
        enable_level_6 : in std_logic;
        enable_level_7 : in std_logic;

        -- Read/Write control from stack decoder
        stack_read  : in std_logic;
        stack_write : in std_logic;

        -- 14-bit address output (to PC during RET)
        addr_out : out address_t
    );
end entity stack_memory;

architecture rtl of stack_memory is

    -- 8 stack levels, each 14 bits wide
    type stack_array_t is array (0 to 7) of address_t;
    signal stack : stack_array_t := (others => (others => '0'));

begin

    -- Write to stack on phi1 rising edge
    process(phi1, reset)
    begin
        if reset = '1' then
            stack <= (others => (others => '0'));
        elsif rising_edge(phi1) then
            if stack_write = '1' then
                if enable_level_0 = '1' then
                    stack(0) <= addr_in;
                    report "STACK: Writing level 0 = 0x" & to_hstring(unsigned(addr_in));
                end if;
                if enable_level_1 = '1' then
                    stack(1) <= addr_in;
                    report "STACK: Writing level 1 = 0x" & to_hstring(unsigned(addr_in));
                end if;
                if enable_level_2 = '1' then stack(2) <= addr_in; end if;
                if enable_level_3 = '1' then stack(3) <= addr_in; end if;
                if enable_level_4 = '1' then stack(4) <= addr_in; end if;
                if enable_level_5 = '1' then stack(5) <= addr_in; end if;
                if enable_level_6 = '1' then stack(6) <= addr_in; end if;
                if enable_level_7 = '1' then stack(7) <= addr_in; end if;
            end if;
        end if;
    end process;

    -- Read from stack (combinational)
    addr_out <= stack(0) when (stack_read = '1' and enable_level_0 = '1') else
                stack(1) when (stack_read = '1' and enable_level_1 = '1') else
                stack(2) when (stack_read = '1' and enable_level_2 = '1') else
                stack(3) when (stack_read = '1' and enable_level_3 = '1') else
                stack(4) when (stack_read = '1' and enable_level_4 = '1') else
                stack(5) when (stack_read = '1' and enable_level_5 = '1') else
                stack(6) when (stack_read = '1' and enable_level_6 = '1') else
                stack(7) when (stack_read = '1' and enable_level_7 = '1') else
                (others => '0');

    -- Monitor reads
    process(stack_read, enable_level_0, enable_level_1, stack)
    begin
        if stack_read = '1' then
            if enable_level_0 = '1' then
                report "STACK: Reading level 0 = 0x" & to_hstring(unsigned(stack(0)));
            elsif enable_level_1 = '1' then
                report "STACK: Reading level 1 = 0x" & to_hstring(unsigned(stack(1)));
            end if;
        end if;
    end process;

end architecture rtl;

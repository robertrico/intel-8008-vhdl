--------------------------------------------------------------------------------
-- stack_pointer.vhdl
--------------------------------------------------------------------------------
-- Stack Pointer for Intel 8008
--
-- 3-bit stack pointer (8 levels deep)
-- - Points to current top of stack (000 to 111)
-- - Increments on PUSH (stack grows)
-- - Decrements on POP (stack shrinks)
-- - Wraps around (no overflow detection in original 8008)
-- - DUMB module: just a 3-bit counter
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.b8008_types.all;

entity stack_pointer is
    port (
        -- Clock (phi1 from clock generator)
        phi1 : in std_logic;

        -- Reset
        reset : in std_logic;

        -- Control from Memory/I/O Control
        stack_push : in std_logic;  -- Increment stack pointer (push)
        stack_pop  : in std_logic;  -- Decrement stack pointer (pop)

        -- Stack pointer output (to stack address decoder)
        sp_out : out std_logic_vector(2 downto 0)
    );
end entity stack_pointer;

architecture rtl of stack_pointer is

    -- Internal 3-bit stack pointer
    signal sp : unsigned(2 downto 0) := (others => '0');

begin

    -- Stack pointer logic
    process(phi1, reset)
    begin
        if reset = '1' then
            sp <= (others => '0');
        elsif rising_edge(phi1) then
            if stack_push = '1' then
                -- Push: increment (wraps from 111 to 000)
                sp <= sp + 1;
            elsif stack_pop = '1' then
                -- Pop: decrement (wraps from 000 to 111)
                sp <= sp - 1;
            end if;
        end if;
    end process;

    -- Output current stack pointer
    sp_out <= std_logic_vector(sp);

end architecture rtl;

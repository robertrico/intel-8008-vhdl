--------------------------------------------------------------------------------
-- stack_memory.vhdl
--------------------------------------------------------------------------------
-- Address Stack for Intel 8008 - the PC lives HERE, per the Intel block
-- diagram: 8 x 14-bit registers, and the register selected by the stack
-- pointer IS the program counter.
--
-- The module applies the classic PC operations to slot[sp_in]:
-- - increment_lower / increment_upper (two-stage per the 1972 datasheet)
-- - load (jump/call targets, RST vectors)
-- - hold
--
-- CALL/RST no longer copy anything: the caller's slot already holds the
-- return address the moment SP moves on. RET is just SP moving back.
-- 7 nested returns fit; the 8th CALL wraps SP onto the oldest context -
-- exactly the real 8008's documented behavior.
--
-- DUMB module: no knowledge of instructions. Control says increment/load/
-- hold; the stack pointer says which slot is live.
--
-- SYNTHESIS NOTE: Clocked by the master clk; updates only on phi1_rising
-- pulse so every flop in the CPU shares one clock tree.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.b8008_types.all;

entity stack_memory is
    port (
        -- Master clock + phi1 rising-edge pulse (one clk cycle wide)
        clk         : in std_logic;
        phi1_rising : in std_logic;

        -- Reset
        reset : in std_logic;

        -- Which slot is the live PC (from stack_pointer)
        sp_in : in std_logic_vector(2 downto 0);

        -- PC operation on slot[sp_in] (from Memory/IO Control via b8008)
        control : in pc_control_t;

        -- Data input for load operation (jump targets, RST vectors)
        data_in : in address_t;

        -- The live PC value: slot[sp_in], with in-flight operations
        -- forwarded combinationally (same semantics the old program_counter
        -- had, so address consumers see the post-op value immediately)
        addr_out : out address_t;

        -- Carry flag: lower-byte increment wrapped 0xFF -> 0x00
        carry_out : out std_logic
    );
end entity stack_memory;

architecture rtl of stack_memory is

    -- 8 stack levels, each 14 bits wide. Slot[sp_in] is the PC.
    type stack_array_t is array (0 to 7) of address_t;
    signal stack : stack_array_t := (others => (others => '0'));

    -- Single shared carry flag (one incrementer on the real die)
    signal carry_flag : std_logic := '0';

    signal slot : address_t;
    signal slot_incremented_lower : address_t;
    signal slot_incremented_upper : address_t;
    signal next_carry : std_logic;

begin

    -- The live slot
    slot <= stack(to_integer(unsigned(sp_in)));

    -- Combinational: incremented values of the live slot
    process(slot)
        variable pc_lower : unsigned(7 downto 0);
        variable pc_upper : unsigned(5 downto 0);
    begin
        pc_lower := slot(7 downto 0);
        pc_upper := slot(13 downto 8);

        slot_incremented_lower <= pc_upper & (pc_lower + 1);
        slot_incremented_upper <= (pc_upper + 1) & pc_lower;

        if pc_lower = x"FF" then
            next_carry <= '1';
        else
            next_carry <= '0';
        end if;
    end process;

    -- Output mux: forward in-flight operation results, else the slot
    addr_out <= data_in                when control.load = '1' else
                slot_incremented_upper when control.increment_upper = '1' else
                slot_incremented_lower when control.increment_lower = '1' else
                slot;

    carry_out <= next_carry when control.increment_lower = '1' else carry_flag;

    -- Synchronous: apply the operation to the live slot on phi1
    process(clk, reset)
        variable idx : integer range 0 to 7;
    begin
        if reset = '1' then
            stack <= (others => (others => '0'));
            carry_flag <= '0';
        elsif rising_edge(clk) then
            if phi1_rising = '1' then
                idx := to_integer(unsigned(sp_in));
                if control.load = '1' then
                    stack(idx) <= data_in;
                    carry_flag <= '0';
                    report "STACK/PC: slot " & integer'image(idx) & " load 0x" & to_hstring(data_in);
                elsif control.increment_upper = '1' then
                    stack(idx) <= slot_incremented_upper;
                    carry_flag <= '0';
                    report "STACK/PC: slot " & integer'image(idx) & " upper increment, PC = 0x" & to_hstring(slot_incremented_upper);
                elsif control.increment_lower = '1' then
                    stack(idx) <= slot_incremented_lower;
                    if unsigned(slot(7 downto 0)) = x"FF" then
                        carry_flag <= '1';
                        report "STACK/PC: slot " & integer'image(idx) & " lower increment wrapped (CARRY)";
                    else
                        carry_flag <= '0';
                    end if;
                end if;
                -- No operation: every slot holds. A CALL's "push" is just
                -- the stack pointer moving - this slot keeps the return
                -- address it already contains.
            end if;
        end if;
    end process;

end architecture rtl;

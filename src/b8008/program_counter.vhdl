--------------------------------------------------------------------------------
-- program_counter.vhdl
--------------------------------------------------------------------------------
-- Simple, explicit program counter for Intel 8008
--
-- This module does ONE thing: manages the 14-bit program counter
-- - Increments lower byte when increment_lower control is high
-- - Increments upper byte when increment_upper control is high
-- - Loads when load control is high
-- - Holds when hold control is high or all controls low
-- - NO conditional logic, NO knowledge of instructions or interrupts
--
-- SYNTHESIS NOTE: Uses synchronous design with phi1 clock.
-- The output is the NEXT PC value when an operation is requested,
-- allowing the address to be correct on the same clock edge.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.b8008_types.all;

entity program_counter is
    port (
        -- Clock (phi1 from clock generator)
        phi1      : in  std_logic;

        -- Reset
        reset     : in  std_logic;

        -- Control signals (active high levels)
        control   : in  pc_control_t;

        -- Data input for load operation
        data_in   : in  address_t;

        -- Current PC value (always available)
        pc_out    : out address_t;

        -- Carry flag: set when lower byte increment wraps from 0xFF to 0x00
        carry_out : out std_logic
    );
end entity program_counter;

architecture rtl of program_counter is
    signal pc_reg : address_t := (others => '0');
    signal carry_flag : std_logic := '0';

    -- Computed next PC value (combinational)
    signal next_pc : address_t;
    signal next_carry : std_logic;

begin

    -- Combinational: compute what the PC will be
    -- This allows the output to reflect the new value immediately
    process(pc_reg, control, data_in)
        variable pc_lower : unsigned(7 downto 0);
        variable pc_upper : unsigned(5 downto 0);
    begin
        pc_lower := unsigned(pc_reg(7 downto 0));
        pc_upper := unsigned(pc_reg(13 downto 8));
        next_carry <= '0';

        if control.load = '1' then
            -- Load takes priority
            next_pc <= data_in;
        elsif control.increment_upper = '1' then
            -- Increment upper byte (carry handling)
            pc_upper := pc_upper + 1;
            next_pc <= pc_upper & pc_lower;
        elsif control.increment_lower = '1' then
            -- Increment lower byte
            if pc_lower = x"FF" then
                next_carry <= '1';
            end if;
            pc_lower := pc_lower + 1;
            next_pc <= pc_upper & pc_lower;
        else
            -- Hold
            next_pc <= pc_reg;
        end if;
    end process;

    -- Output the computed next value when operation is active,
    -- otherwise output the registered value
    pc_out <= next_pc when (control.increment_lower = '1' or
                            control.increment_upper = '1' or
                            control.load = '1') else pc_reg;

    carry_out <= next_carry when control.increment_lower = '1' else carry_flag;

    -- Synchronous: update the register on phi1
    process(phi1, reset)
    begin
        if reset = '1' then
            pc_reg <= (others => '0');
            carry_flag <= '0';
        elsif rising_edge(phi1) then
            -- Update register with next value
            pc_reg <= next_pc;

            -- Update carry flag
            if control.increment_lower = '1' then
                if unsigned(pc_reg(7 downto 0)) = x"FF" then
                    carry_flag <= '1';
                    report "PC: Lower byte increment 0x" & to_hstring(unsigned(pc_reg(7 downto 0))) & " -> 0x00 (CARRY)";
                else
                    carry_flag <= '0';
                end if;
                report "PC: Lower byte = 0x" & to_hstring(unsigned(next_pc(7 downto 0))) &
                       ", full PC = 0x" & to_hstring(next_pc);
            elsif control.increment_upper = '1' then
                carry_flag <= '0';
                report "PC: Upper byte increment (carry), full PC = 0x" & to_hstring(next_pc);
            elsif control.load = '1' then
                carry_flag <= '0';
                report "PC: Loading 0x" & to_hstring(data_in);
            end if;
        end if;
    end process;

end architecture rtl;

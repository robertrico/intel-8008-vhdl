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
-- SYNTHESIS NOTE: Clocked by the master clk; updates only on phi1_rising
-- pulse so every flop in the CPU shares one clock tree. Semantically
-- equivalent to a rising_edge(phi1) trigger, one clk cycle later.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.b8008_types.all;

entity program_counter is
    port (
        -- Master clock + phi1 rising-edge pulse (one clk cycle wide)
        clk         : in  std_logic;
        phi1_rising : in  std_logic;

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

    -- Computed operation results (combinational, only valid when operation active)
    signal pc_incremented_lower : address_t;
    signal pc_incremented_upper : address_t;
    signal next_carry : std_logic;

    -- Control signal for whether any operation is active
    signal operation_active : std_logic;

begin

    -- Determine if any operation is active
    operation_active <= control.increment_lower or control.increment_upper or control.load;

    -- Combinational: compute incremented values (always computed, selected by mux)
    -- This avoids combinational loops by not feeding pc_reg back through next_pc
    process(pc_reg)
        variable pc_lower : unsigned(7 downto 0);
        variable pc_upper : unsigned(5 downto 0);
    begin
        pc_lower := pc_reg(7 downto 0);
        pc_upper := pc_reg(13 downto 8);

        -- Lower byte increment: keep upper, increment lower
        pc_incremented_lower <= pc_upper & (pc_lower + 1);

        -- Upper byte increment: increment upper, keep lower
        pc_incremented_upper <= (pc_upper + 1) & pc_lower;

        -- Carry detection
        if pc_lower = x"FF" then
            next_carry <= '1';
        else
            next_carry <= '0';
        end if;
    end process;

    -- Output mux: select between registered value and computed values
    -- No combinational loop because pc_reg doesn't feed back through itself
    pc_out <= data_in when control.load = '1' else
              pc_incremented_upper when control.increment_upper = '1' else
              pc_incremented_lower when control.increment_lower = '1' else
              pc_reg;

    carry_out <= next_carry when control.increment_lower = '1' else carry_flag;

    -- Synchronous: update on the master clock, but only act on a phi1 rising
    -- edge (gated by phi1_rising pulse). Equivalent to the former
    -- rising_edge(phi1) trigger, now single-clock-domain friendly.
    process(clk, reset)
    begin
        if reset = '1' then
            pc_reg <= (others => '0');
            carry_flag <= '0';
        elsif rising_edge(clk) then
            if phi1_rising = '1' then
                -- Update register based on active operation
                if control.load = '1' then
                    pc_reg <= data_in;
                    carry_flag <= '0';
                    report "PC: Loading 0x" & to_hstring(data_in);
                elsif control.increment_upper = '1' then
                    pc_reg <= pc_incremented_upper;
                    carry_flag <= '0';
                    report "PC: Upper byte increment (carry), full PC = 0x" & to_hstring(pc_incremented_upper);
                elsif control.increment_lower = '1' then
                    pc_reg <= pc_incremented_lower;
                    if unsigned(pc_reg(7 downto 0)) = x"FF" then
                        carry_flag <= '1';
                        report "PC: Lower byte increment 0x" & to_hstring(unsigned(pc_reg(7 downto 0))) & " -> 0x00 (CARRY)";
                    else
                        carry_flag <= '0';
                    end if;
                    report "PC: Lower byte = 0x" & to_hstring(unsigned(pc_incremented_lower(7 downto 0))) &
                           ", full PC = 0x" & to_hstring(pc_incremented_lower);
                end if;
                -- When no operation active, pc_reg holds its value
            end if;
        end if;
    end process;

end architecture rtl;

--------------------------------------------------------------------------------
-- ahl_pointer.vhdl
--------------------------------------------------------------------------------
-- Address Pointer A H L Module for Intel 8008
--
-- Provides scratchpad address selection for A, H, and L registers during
-- memory indirect operations.
--
-- During memory operations (LrM, LMr, ALU M), cycle 2 needs to output the
-- memory address on the data bus during T1/T2:
--   T1: L register (scratchpad address "110" = 6)
--   T2: H register (scratchpad address "101" = 5)
--
-- This module provides the scratchpad addresses to read H and L, overriding
-- the normal SSS/DDD register selection during these states.
--
-- NOT a register! Just combinational logic for address selection.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.b8008_types.all;

entity ahl_pointer is
    port (
        -- State inputs
        state_t1      : in std_logic;  -- T1 state (output L register)
        state_t2      : in std_logic;  -- T2 state (output H register)

        -- Cycle tracking
        current_cycle : in integer range 1 to 3;  -- Current machine cycle

        -- Instruction type
        instr_is_mem_indirect : in std_logic;  -- '1' when SSS or DDD = "111" (M)

        -- Outputs to scratchpad address multiplexer
        ahl_select    : out std_logic_vector(2 downto 0);  -- Scratchpad address
        ahl_active    : out std_logic  -- '1' to override normal SSS/DDD selection
    );
end entity ahl_pointer;

architecture rtl of ahl_pointer is

    -- Scratchpad register addresses (from b8008 architecture)
    constant ADDR_A : std_logic_vector(2 downto 0) := "000";  -- A register
    constant ADDR_B : std_logic_vector(2 downto 0) := "001";  -- B register
    constant ADDR_C : std_logic_vector(2 downto 0) := "010";  -- C register
    constant ADDR_D : std_logic_vector(2 downto 0) := "011";  -- D register
    constant ADDR_E : std_logic_vector(2 downto 0) := "100";  -- E register
    constant ADDR_H : std_logic_vector(2 downto 0) := "101";  -- H register
    constant ADDR_L : std_logic_vector(2 downto 0) := "110";  -- L register

begin

    -- Combinational logic for scratchpad address selection
    process(state_t1, state_t2, current_cycle, instr_is_mem_indirect)
    begin
        -- Defaults: inactive, don't override SSS/DDD
        ahl_select <= (others => '0');
        ahl_active <= '0';

        -- During cycle 2 of memory indirect operations:
        -- Override scratchpad selection to read H and L for address output
        if current_cycle = 2 and instr_is_mem_indirect = '1' then
            if state_t1 = '1' then
                -- T1: Select L register to output lower address byte
                ahl_select <= ADDR_L;
                ahl_active <= '1';
            elsif state_t2 = '1' then
                -- T2: Select H register to output upper address bits
                ahl_select <= ADDR_H;
                ahl_active <= '1';
            end if;
        end if;
    end process;

end architecture rtl;

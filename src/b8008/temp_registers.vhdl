--------------------------------------------------------------------------------
-- temp_registers.vhdl
--------------------------------------------------------------------------------
-- Temporary Registers (Reg.a and Reg.b) for Intel 8008
--
-- Two 8-bit temporary registers that interface with the internal data bus
-- - Reg.a: Typically holds accumulator value for ALU operations
-- - Reg.b: Typically holds operand for ALU operations
-- - Both can read from internal bus when enabled
-- - Both have separate outputs to ALU and other modules
-- - DUMB module: just registers with enable signals
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.b8008_types.all;

entity temp_registers is
    port (
        -- Clock input (phi2 for latching)
        phi2 : in std_logic;

        -- Control inputs from Register and ALU Control
        load_reg_a : in std_logic;  -- Enable latch for Reg.a from bus
        load_reg_b : in std_logic;  -- Enable latch for Reg.b from bus

        output_reg_a : in std_logic;  -- Enable Reg.a to drive internal bus
        output_reg_b : in std_logic;  -- Enable Reg.b to drive internal bus

        -- Internal data bus (bidirectional)
        internal_bus : inout std_logic_vector(7 downto 0);

        -- Outputs to ALU and other modules
        reg_a_out : out std_logic_vector(7 downto 0);
        reg_b_out : out std_logic_vector(7 downto 0)
    );
end entity temp_registers;

architecture rtl of temp_registers is

    -- Internal storage
    signal reg_a : std_logic_vector(7 downto 0) := (others => '0');
    signal reg_b : std_logic_vector(7 downto 0) := (others => '0');

begin

    -- Output registers directly to ALU
    reg_a_out <= reg_a;
    reg_b_out <= reg_b;

    -- Bidirectional internal bus control
    -- Drive bus when output enabled, otherwise high-impedance
    internal_bus <= reg_a when output_reg_a = '1' else (others => 'Z');
    internal_bus <= reg_b when output_reg_b = '1' else (others => 'Z');

    -- Latch Reg.a on phi2 rising edge when enabled
    -- For unary ALU operations (INR/DCR), load constant 0x01 instead of from bus
    process(phi2)
    begin
        if rising_edge(phi2) then
            if load_reg_a = '1' then
                -- For INR/DCR: load constant 0x01 for increment/decrement
                -- Detect by checking if load_reg_b is also active (unary ops load both at same time at T4)
                if load_reg_b = '1' then
                    -- Unary operation: load constant 1
                    reg_a <= x"01";
                    report "TEMP_REG: Loading Reg.a with constant 0x01 for INR/DCR";
                else
                    -- Normal operation: load from bus
                    reg_a <= internal_bus;
                    report "TEMP_REG: Loading Reg.a from internal_bus = 0x" & to_hstring(unsigned(internal_bus));
                end if;
            end if;
        end if;
    end process;

    -- Latch Reg.b on phi2 rising edge when enabled
    process(phi2)
    begin
        if rising_edge(phi2) then
            if load_reg_b = '1' then
                reg_b <= internal_bus;
                report "TEMP_REG: Loading Reg.b from internal_bus = 0x" & to_hstring(unsigned(internal_bus));
            end if;
        end if;
    end process;

end architecture rtl;

--------------------------------------------------------------------------------
-- temp_registers.vhdl
--------------------------------------------------------------------------------
-- Temporary Registers (Reg.a and Reg.b) for Intel 8008
--
-- Two 8-bit temporary registers that interface with the internal data bus
-- - Reg.a: Typically holds accumulator value for ALU operations
-- - Reg.b: Typically holds operand for ALU operations
-- - Both load from internal bus when enabled
-- - Both have separate outputs to ALU and other modules
-- - DUMB module: just registers with enable signals, no instruction awareness
--
-- The control unit is responsible for ensuring the correct data is on the
-- internal bus when load signals are asserted.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.b8008_types.all;

entity temp_registers is
    port (
        -- Master clock + phi2 rising-edge pulse (one clk cycle wide)
        clk         : in std_logic;
        phi2_rising : in std_logic;

        -- Reset (active high)
        reset : in std_logic;

        -- Control inputs from Register and ALU Control
        load_reg_a : in std_logic;  -- Enable latch for Reg.a from internal bus
        load_reg_b : in std_logic;  -- Enable latch for Reg.b from internal bus

        output_reg_a : in std_logic;  -- Enable Reg.a to drive internal bus
        output_reg_b : in std_logic;  -- Enable Reg.b to drive internal bus

        -- Internal data bus (separate in/out for synthesis compatibility)
        internal_bus_in  : in  std_logic_vector(7 downto 0);
        internal_bus_out : out std_logic_vector(7 downto 0);
        internal_bus_oe  : out std_logic;

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

    -- Internal bus output control
    -- NOTE: Only one should be enabled at a time (mutual exclusion by control logic)
    internal_bus_out <= reg_a when output_reg_a = '1' else reg_b;
    internal_bus_oe  <= output_reg_a or output_reg_b;

    -- Latch Reg.a on phi2 rising edge when enabled
    process(clk, reset)
    begin
        if reset = '1' then
            reg_a <= (others => '0');
        elsif rising_edge(clk) then
            if phi2_rising = '1' and load_reg_a = '1' then
                reg_a <= internal_bus_in;
                report "TEMP_REG: Loading Reg.a = 0x" & to_hstring(unsigned(internal_bus_in));
            end if;
        end if;
    end process;

    -- Latch Reg.b on phi2 rising edge when enabled
    process(clk, reset)
    begin
        if reset = '1' then
            reg_b <= (others => '0');
        elsif rising_edge(clk) then
            if phi2_rising = '1' and load_reg_b = '1' then
                reg_b <= internal_bus_in;
                report "TEMP_REG: Loading Reg.b = 0x" & to_hstring(unsigned(internal_bus_in));
            end if;
        end if;
    end process;

end architecture rtl;

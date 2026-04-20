--------------------------------------------------------------------------------
-- instruction_register.vhdl
--------------------------------------------------------------------------------
-- Instruction Register for Intel 8008
--
-- Holds the current instruction byte
-- - Bidirectional connection to internal bus (can read/write)
-- - Output enable from Memory/I/O Control (controls when IR drives bus)
-- - Load enable from control logic (controls when IR loads from bus)
-- - Always outputs current value to Instruction Decoder
-- - DUMB module: just an 8-bit register with tri-state bus connection
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.b8008_types.all;

entity instruction_register is
    port (
        -- Master clock + phi1 falling-edge pulse (one clk cycle wide)
        clk          : in std_logic;
        phi1_falling : in std_logic;

        -- Reset
        reset : in std_logic;

        -- Internal data bus (separate in/out for synthesis compatibility)
        internal_bus_in  : in  std_logic_vector(7 downto 0);
        internal_bus_out : out std_logic_vector(7 downto 0);
        internal_bus_oe  : out std_logic;

        -- Load IR from bus (from control logic)
        load_ir : in std_logic;

        -- Output IR to bus (enable from Memory/I/O Control)
        output_ir : in std_logic;

        -- Output to Instruction Decoder (8 individual bits)
        ir_bit_7 : out std_logic;
        ir_bit_6 : out std_logic;
        ir_bit_5 : out std_logic;
        ir_bit_4 : out std_logic;
        ir_bit_3 : out std_logic;
        ir_bit_2 : out std_logic;
        ir_bit_1 : out std_logic;
        ir_bit_0 : out std_logic
    );
end entity instruction_register;

architecture rtl of instruction_register is

    signal ir : std_logic_vector(7 downto 0) := (others => '0');

begin

    -- Load instruction register from internal bus, gated on phi1 falling edge
    -- (samples in middle of phi1 cycle when data is stable)
    process(clk, reset)
    begin
        if reset = '1' then
            ir <= (others => '0');
        elsif rising_edge(clk) then
            if phi1_falling = '1' and load_ir = '1' then
                ir <= internal_bus_in;
                report "IR: Loading from bus = 0x" & to_hstring(unsigned(internal_bus_in));
            end if;
        end if;
    end process;

    -- Internal bus output control
    internal_bus_out <= ir;
    internal_bus_oe  <= output_ir;

    -- Output individual bits to decoder
    ir_bit_7 <= ir(7);
    ir_bit_6 <= ir(6);
    ir_bit_5 <= ir(5);
    ir_bit_4 <= ir(4);
    ir_bit_3 <= ir(3);
    ir_bit_2 <= ir(2);
    ir_bit_1 <= ir(1);
    ir_bit_0 <= ir(0);

end architecture rtl;

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
        -- Clock (phi1 from clock generator)
        phi1 : in std_logic;

        -- Reset
        reset : in std_logic;

        -- Bidirectional internal bus
        internal_bus : inout std_logic_vector(7 downto 0);

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

    -- Load instruction register from internal bus
    -- Use falling_edge to sample in middle of clock cycle when data is stable
    process(phi1, reset)
    begin
        if reset = '1' then
            ir <= (others => '0');
        elsif falling_edge(phi1) then
            if load_ir = '1' then
                ir <= internal_bus;
                report "IR: Loading from bus = 0x" & to_hstring(unsigned(internal_bus));
            end if;
        end if;
    end process;

    -- Bidirectional internal bus control
    internal_bus <= ir when output_ir = '1' else (others => 'Z');

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

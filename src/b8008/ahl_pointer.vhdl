--------------------------------------------------------------------------------
-- ahl_pointer.vhdl
--------------------------------------------------------------------------------
-- AHL Address Pointer for Intel 8008
--
-- Holds H and L registers as a 14-bit memory address pointer
-- - Loads 14-bit address from H (high 8 bits) and L (low 6 bits)
-- - Outputs 14-bit address to memory address bus
-- - DUMB module: just a register with load/output control
--
-- Note: In the 8008, addresses are 14 bits (16KB address space)
-- H register provides bits [13:6], L register provides bits [5:0]
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.b8008_types.all;

entity ahl_pointer is
    port (
        -- Clock (phi1 from clock generator)
        phi1 : in std_logic;

        -- Reset
        reset : in std_logic;

        -- H and L register inputs (from register file)
        h_reg : in std_logic_vector(7 downto 0);  -- High byte
        l_reg : in std_logic_vector(7 downto 0);  -- Low byte (only [5:0] used)

        -- Control from Memory/I/O Control
        load_ahl   : in std_logic;  -- Load H:L into address pointer
        output_ahl : in std_logic;  -- Output address to memory bus

        -- 14-bit address output (to memory address bus)
        address_out : out address_t
    );
end entity ahl_pointer;

architecture rtl of ahl_pointer is

    -- Internal 14-bit address register
    signal ahl_address : address_t := (others => '0');

begin

    -- Load address from H:L registers
    process(phi1, reset)
    begin
        if reset = '1' then
            ahl_address <= (others => '0');
        elsif rising_edge(phi1) then
            if load_ahl = '1' then
                -- H provides bits [13:6], L provides bits [5:0]
                ahl_address(13 downto 6) <= unsigned(h_reg);
                ahl_address(5 downto 0)  <= unsigned(l_reg(5 downto 0));
            end if;
        end if;
    end process;

    -- Output address (controlled by output_ahl)
    -- In real hardware this would tri-state, but for now just always output
    address_out <= ahl_address;

end architecture rtl;

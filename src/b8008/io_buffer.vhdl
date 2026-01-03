--------------------------------------------------------------------------------
-- io_buffer.vhdl
--------------------------------------------------------------------------------
-- Data Bus Buffer for Intel 8008
--
-- Buffer between external data bus D[7:0] and internal data bus
-- - Controlled by Memory and I/O Control block
-- - Can transfer data in either direction
-- - Uses separate input/output signals for synthesis compatibility
-- - DUMB module: just a buffer with direction control
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.b8008_types.all;

entity io_buffer is
    port (
        -- External data bus (to outside world) - separate in/out for synthesis
        external_data_in  : in  std_logic_vector(7 downto 0);  -- Data from external
        external_data_out : out std_logic_vector(7 downto 0);  -- Data to external
        external_data_oe  : out std_logic;                     -- Output enable for external bus

        -- Internal data bus (separate in/out for synthesis compatibility)
        internal_bus_in  : in  std_logic_vector(7 downto 0);   -- Data from internal bus
        internal_bus_out : out std_logic_vector(7 downto 0);   -- Data to internal bus
        internal_bus_oe  : out std_logic;                      -- Output enable for internal bus

        -- Control from Memory and I/O Control block
        enable : in std_logic;          -- Enable buffer (0 = tri-state both sides)
        direction : in std_logic        -- 0 = external->internal (read), 1 = internal->external (write)
    );
end entity io_buffer;

architecture rtl of io_buffer is

begin

    -- Data transfer with direction control
    -- When enable=1 and direction=0: external data -> internal bus (READ)
    -- When enable=1 and direction=1: internal bus -> external data (WRITE)
    -- When enable=0: both sides disabled

    -- Transfer external to internal (READ) - drive internal bus
    internal_bus_out <= external_data_in;
    internal_bus_oe  <= enable and (not direction);  -- Enable when reading from external

    -- Transfer internal to external (WRITE) - output data and enable
    external_data_out <= internal_bus_in;  -- Output internal bus value
    external_data_oe  <= enable and direction;  -- Enable when writing to external

end architecture rtl;

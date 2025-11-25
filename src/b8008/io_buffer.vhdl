--------------------------------------------------------------------------------
-- io_buffer.vhdl
--------------------------------------------------------------------------------
-- Data Bus Buffer for Intel 8008
--
-- Bidirectional buffer between external data bus D[7:0] and internal data bus
-- - Controlled by Memory and I/O Control block
-- - Can transfer data in either direction
-- - Tri-state outputs when not enabled
-- - DUMB module: just a bidirectional buffer with direction control
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.b8008_types.all;

entity io_buffer is
    port (
        -- External data bus (to outside world)
        external_data : inout std_logic_vector(7 downto 0);

        -- Internal data bus (to CPU internals)
        internal_bus : inout std_logic_vector(7 downto 0);

        -- Control from Memory and I/O Control block
        enable : in std_logic;          -- Enable buffer (0 = tri-state both sides)
        direction : in std_logic        -- 0 = external->internal (read), 1 = internal->external (write)
    );
end entity io_buffer;

architecture rtl of io_buffer is

begin

    -- Bidirectional data transfer with direction control
    -- When enable=1 and direction=0: external data -> internal bus (READ)
    -- When enable=1 and direction=1: internal bus -> external data (WRITE)
    -- When enable=0: both sides tri-stated

    -- Transfer external to internal (READ)
    internal_bus <= external_data when (enable = '1' and direction = '0') else (others => 'Z');

    -- Transfer internal to external (WRITE)
    external_data <= internal_bus when (enable = '1' and direction = '1') else (others => 'Z');

end architecture rtl;

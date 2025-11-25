--------------------------------------------------------------------------------
-- sss_ddd_selector.vhdl
--------------------------------------------------------------------------------
-- SSS/DDD Register Address Selector for Intel 8008
--
-- Selects between SSS (source) or DDD (destination) register field from
-- instruction decoder and forwards to scratchpad address multiplexer.
--
-- - SSS field (bits [2:0]) = source register
-- - DDD field (bits [5:3]) = destination register
-- - Encoding: A=000, B=001, C=010, D=011, E=100, H=101, L=110, M=111
--
-- DUMB module: Simple 2:1 multiplexer
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.b8008_types.all;

entity sss_ddd_selector is
    port (
        -- SSS and DDD fields from instruction decoder
        sss_field : in std_logic_vector(2 downto 0);
        ddd_field : in std_logic_vector(2 downto 0);

        -- Control: select which field to output
        select_sss : in std_logic;  -- '1' = output SSS, '0' = output DDD
        select_ddd : in std_logic;  -- '1' = output DDD, '0' = output SSS

        -- Output to scratchpad address multiplexer
        reg_addr : out std_logic_vector(2 downto 0)
    );
end entity sss_ddd_selector;

architecture rtl of sss_ddd_selector is
begin

    -- Simple multiplexer
    -- If both are '1', DDD takes priority (shouldn't happen in normal operation)
    reg_addr <= ddd_field when select_ddd = '1' else
                sss_field when select_sss = '1' else
                "000";  -- Default to A register

end architecture rtl;

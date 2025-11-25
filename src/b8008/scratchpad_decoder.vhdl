--------------------------------------------------------------------------------
-- scratchpad_decoder.vhdl
--------------------------------------------------------------------------------
-- Scratchpad Decoder for Intel 8008
--
-- Decodes 3-bit register address to individual register enable signals
-- - 000 = A (Accumulator)
-- - 001 = B
-- - 010 = C
-- - 011 = D
-- - 100 = E
-- - 101 = H
-- - 110 = L
-- - 111 = M (Memory indirect - not a physical register)
-- - DUMB module: just a 3-to-8 decoder
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.b8008_types.all;

entity scratchpad_decoder is
    port (
        -- 3-bit register address input
        addr_in : in std_logic_vector(2 downto 0);

        -- Read/Write enables from Memory/I/O Control
        read_enable  : in std_logic;
        write_enable : in std_logic;

        -- Individual register enables (one-hot)
        enable_a : out std_logic;  -- 000
        enable_b : out std_logic;  -- 001
        enable_c : out std_logic;  -- 010
        enable_d : out std_logic;  -- 011
        enable_e : out std_logic;  -- 100
        enable_h : out std_logic;  -- 101
        enable_l : out std_logic;  -- 110
        enable_m : out std_logic;  -- 111 (memory indirect)

        -- Read/Write control outputs (same for all registers)
        read_out  : out std_logic;
        write_out : out std_logic
    );
end entity scratchpad_decoder;

architecture rtl of scratchpad_decoder is

begin

    -- Decode 3-bit address to one-hot enables
    process(addr_in, read_enable, write_enable)
    begin
        -- Default: all disabled
        enable_a <= '0';
        enable_b <= '0';
        enable_c <= '0';
        enable_d <= '0';
        enable_e <= '0';
        enable_h <= '0';
        enable_l <= '0';
        enable_m <= '0';

        -- Only enable if read or write is active
        if read_enable = '1' or write_enable = '1' then
            case addr_in is
                when "000" => enable_a <= '1';
                when "001" => enable_b <= '1';
                when "010" => enable_c <= '1';
                when "011" => enable_d <= '1';
                when "100" => enable_e <= '1';
                when "101" => enable_h <= '1';
                when "110" => enable_l <= '1';
                when "111" => enable_m <= '1';
                when others => null;
            end case;
        end if;
    end process;

    -- Pass through read/write signals
    read_out  <= read_enable;
    write_out <= write_enable;

end architecture rtl;

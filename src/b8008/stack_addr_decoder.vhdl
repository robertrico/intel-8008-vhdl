--------------------------------------------------------------------------------
-- stack_addr_decoder.vhdl
--------------------------------------------------------------------------------
-- Stack Address Decoder for Intel 8008
--
-- Decodes 3-bit stack pointer to one-hot enables for 8-level stack
-- - Each stack level stores a 14-bit return address
-- - One-hot encoding: only one level enabled at a time
-- - DUMB module: 3-to-8 decoder
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.b8008_types.all;

entity stack_addr_decoder is
    port (
        -- Stack pointer input (3 bits for 8 levels)
        sp_in : in std_logic_vector(2 downto 0);

        -- Read/Write enables from Memory/I/O Control
        stack_read  : in std_logic;  -- Read from stack (e.g., RET)
        stack_write : in std_logic;  -- Write to stack (e.g., CALL, RST)

        -- One-hot enables for 8 stack levels
        enable_level_0 : out std_logic;  -- 000
        enable_level_1 : out std_logic;  -- 001
        enable_level_2 : out std_logic;  -- 010
        enable_level_3 : out std_logic;  -- 011
        enable_level_4 : out std_logic;  -- 100
        enable_level_5 : out std_logic;  -- 101
        enable_level_6 : out std_logic;  -- 110
        enable_level_7 : out std_logic;  -- 111

        -- Read/Write control outputs (same for all levels)
        read_out  : out std_logic;
        write_out : out std_logic
    );
end entity stack_addr_decoder;

architecture rtl of stack_addr_decoder is

begin

    -- Decode 3-bit stack pointer to one-hot enables
    process(sp_in, stack_read, stack_write)
    begin
        -- Default: all disabled
        enable_level_0 <= '0';
        enable_level_1 <= '0';
        enable_level_2 <= '0';
        enable_level_3 <= '0';
        enable_level_4 <= '0';
        enable_level_5 <= '0';
        enable_level_6 <= '0';
        enable_level_7 <= '0';

        -- Only enable if read or write is active
        if stack_read = '1' or stack_write = '1' then
            case sp_in is
                when "000" => enable_level_0 <= '1';
                when "001" => enable_level_1 <= '1';
                when "010" => enable_level_2 <= '1';
                when "011" => enable_level_3 <= '1';
                when "100" => enable_level_4 <= '1';
                when "101" => enable_level_5 <= '1';
                when "110" => enable_level_6 <= '1';
                when "111" => enable_level_7 <= '1';
                when others => null;
            end case;
        end if;
    end process;

    -- Pass through read/write signals
    read_out  <= stack_read;
    write_out <= stack_write;

end architecture rtl;

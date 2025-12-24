-------------------------------------------------------------------------------
-- 4K x 8 RAM Memory Component with File Initialization
-------------------------------------------------------------------------------
-- RAM that can be pre-loaded from a .mem file, used for sample programs
-- that expect RAM at address 0x0000 with code/data in the same space.
--
-- Copyright (c) 2025 Robert Rico
-- License: MIT (see LICENSE.txt)
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;

entity ram_4kx8 is
    generic (
        INIT_FILE : string := ""  -- Optional file to initialize RAM contents
    );
    port(
        -- Clock for synchronous writes
        CLK : in std_logic;

        -- 12-bit address (2^12 = 4096)
        ADDR : in std_logic_vector(11 downto 0);

        -- 8-bit data
        DATA_IN : in std_logic_vector(7 downto 0);
        DATA_OUT : out std_logic_vector(7 downto 0);

        -- Read/Write control (active low)
        RW_N : in std_logic;  -- 0 = Write, 1 = Read

        -- Chip select (active low)
        CS_N : in std_logic
    );
end ram_4kx8;

architecture rtl of ram_4kx8 is
    -- RAM storage: 4096 locations x 8 bits
    type ram_array is array(0 to 4095) of std_logic_vector(7 downto 0);

    -- Function to initialize RAM from file
    impure function init_ram_from_file(filename : string) return ram_array is
        file mem_file : text;
        variable line_buf : line;
        variable ram_init : ram_array := (others => x"00");
        variable addr : integer := 0;
        variable good : boolean;
        variable status : file_open_status;
    begin
        if filename'length > 0 then
            -- Try to open file with status check
            file_open(status, mem_file, filename, read_mode);

            if status = open_ok then
                while not endfile(mem_file) and addr < 4096 loop
                    readline(mem_file, line_buf);
                    -- Skip empty lines
                    if line_buf'length > 0 then
                        -- Read hex value (2 hex digits)
                        hread(line_buf, ram_init(addr), good);
                        if good then
                            addr := addr + 1;
                        end if;
                    end if;
                end loop;

                file_close(mem_file);
                report "RAM: Loaded " & integer'image(addr) & " bytes from " & filename;
            else
                report "RAM: File " & filename & " not found, starting with zeroed RAM" severity warning;
            end if;
        end if;
        return ram_init;
    end function;

    signal ram : ram_array := init_ram_from_file(INIT_FILE);

begin
    -- Synchronous write process
    write_proc: process(CLK)
    begin
        if rising_edge(CLK) then
            if CS_N = '0' and RW_N = '0' then
                ram(to_integer(unsigned(ADDR))) <= DATA_IN;
            end if;
        end if;
    end process;

    -- Combinational read process
    read_proc: process(ADDR, CS_N, RW_N, ram)
    begin
        if CS_N = '0' and RW_N = '1' then
            DATA_OUT <= ram(to_integer(unsigned(ADDR)));
        else
            DATA_OUT <= (others => 'Z');
        end if;
    end process;

end rtl;

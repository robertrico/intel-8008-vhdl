-------------------------------------------------------------------------------
-- 8K x 8 ROM Memory Component
-------------------------------------------------------------------------------
-- Testbench ROM for b8008_top external ROM interface testing.
-- Simulates external EEPROM/Flash behavior with active-low CE and OE.
--
-- Copyright (c) 2025 Robert Rico
-- License: MIT (see LICENSE.txt)
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;
use IEEE.STD_LOGIC_TEXTIO.ALL;

entity rom_8kx8 is
    generic(
        -- ROM initialization file
        ROM_FILE : string := "test_programs/alu_test_as.mem"
    );
    port(
        -- 13-bit address (2^13 = 8192)
        ADDR : in std_logic_vector(12 downto 0);

        -- 8-bit data output
        DATA_OUT : out std_logic_vector(7 downto 0);

        -- Chip select (active low)
        CS_N : in std_logic;

        -- Output enable (active low)
        OE_N : in std_logic
    );
end rom_8kx8;

architecture rtl of rom_8kx8 is
    -- ROM storage: 8192 locations x 8 bits
    type rom_array is array(0 to 8191) of std_logic_vector(7 downto 0);

    -- Function to load ROM from file
    impure function load_rom(filename : string) return rom_array is
        file file_handle : text;
        variable file_line : line;
        variable rom_data : rom_array := (others => x"00");
        variable hex_value : std_logic_vector(7 downto 0);
        variable load_addr : integer := 0;
        variable status : file_open_status;
    begin
        -- Try to open the file
        file_open(status, file_handle, filename, read_mode);

        if status = open_ok then
            -- File opened successfully, read data
            while not endfile(file_handle) and load_addr < 8192 loop
                readline(file_handle, file_line);
                if file_line'length > 0 then
                    hread(file_line, hex_value);
                    rom_data(load_addr) := hex_value;
                    load_addr := load_addr + 1;
                end if;
            end loop;
            file_close(file_handle);

            report "Loaded ROM from " & filename & " (" & integer'image(load_addr) & " bytes)" severity note;
        else
            -- File not found, use default program
            report "ROM file " & filename & " not found, using default program" severity warning;
            -- Simple ADD test: A = 5 + 3 = 8
            rom_data(0) := x"06";  -- MVI A, 5
            rom_data(1) := x"05";
            rom_data(2) := x"0E";  -- MVI B, 3
            rom_data(3) := x"03";
            rom_data(4) := x"81";  -- ADD B
            rom_data(5) := x"2E";  -- MVI H, 0x20
            rom_data(6) := x"20";
            rom_data(7) := x"36";  -- MVI L, 0x00
            rom_data(8) := x"00";
            rom_data(9) := x"F8";  -- MOV M, A
            rom_data(10) := x"00"; -- HLT
        end if;

        return rom_data;
    end function;

    -- Initialize ROM by loading from file
    signal rom : rom_array := load_rom(ROM_FILE);

begin
    -- Combinational ROM read with active-low chip select and output enable
    -- Mimics real EEPROM/Flash behavior
    process(ADDR, CS_N, OE_N, rom)
    begin
        if CS_N = '0' and OE_N = '0' then
            DATA_OUT <= rom(to_integer(unsigned(ADDR)));
        else
            DATA_OUT <= (others => 'Z');  -- High-Z when not selected
        end if;
    end process;

end rtl;

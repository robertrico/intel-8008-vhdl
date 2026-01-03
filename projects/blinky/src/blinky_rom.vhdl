-------------------------------------------------------------------------------
-- Blinky ROM - Embedded program for LED blink test
-------------------------------------------------------------------------------
-- This ROM contains the blinky.asm program pre-compiled for synthesis
-- (GHDL synth doesn't support file_open, so we embed the data)
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity blinky_rom is
    port(
        ADDR     : in  std_logic_vector(11 downto 0);
        DATA_OUT : out std_logic_vector(7 downto 0);
        CS_N     : in  std_logic
    );
end blinky_rom;

architecture rtl of blinky_rom is
    type rom_array is array(0 to 4095) of std_logic_vector(7 downto 0);

    -- Blinky program (from blinky.mem):
    -- 0x0000: JMP 0x0003        ; 44 03 00
    -- 0x0003: MVI A, 0xFE       ; 06 FE
    -- 0x0005: OUT 8             ; 51
    -- 0x0006: CALL delay        ; 46 12 00
    -- 0x0009: MVI A, 0xFF       ; 06 FF
    -- 0x000B: OUT 8             ; 51
    -- 0x000C: CALL delay        ; 46 12 00
    -- 0x000F: JMP 0x0003        ; 44 03 00
    -- 0x0012: delay: MVI B, 200 ; 0E C8
    -- 0x0014: delay_outer: MVI C, 80 ; 16 50
    -- 0x0016: delay_inner: DCR C ; 11
    -- 0x0017: JNZ delay_inner   ; 48 16 00
    -- 0x001A: DCR B             ; 09
    -- 0x001B: JNZ delay_outer   ; 48 14 00
    -- 0x001E: RET               ; 07

    constant rom : rom_array := (
        -- RST 0 vector: JMP main (0x0003)
        0  => x"44",  -- JMP opcode
        1  => x"03",  -- low address
        2  => x"00",  -- high address

        -- main/blink_loop:
        3  => x"06",  -- MVI A, 0xFE (LED0 on)
        4  => x"FE",
        5  => x"51",  -- OUT 8 (port 8, RR=01)

        6  => x"46",  -- CALL delay (0x0012)
        7  => x"12",
        8  => x"00",

        9  => x"06",  -- MVI A, 0xFF (LED0 off)
        10 => x"FF",
        11 => x"51",  -- OUT 8

        12 => x"46",  -- CALL delay
        13 => x"12",
        14 => x"00",

        15 => x"44",  -- JMP blink_loop (0x0003)
        16 => x"03",
        17 => x"00",

        -- delay subroutine at 0x0012:
        18 => x"0E",  -- MVI B, 200
        19 => x"C8",

        -- delay_outer at 0x0014:
        20 => x"16",  -- MVI C, 80
        21 => x"50",

        -- delay_inner at 0x0016:
        22 => x"11",  -- DCR C

        23 => x"48",  -- JNZ delay_inner (0x0016)
        24 => x"16",
        25 => x"00",

        26 => x"09",  -- DCR B

        27 => x"48",  -- JNZ delay_outer (0x0014)
        28 => x"14",
        29 => x"00",

        30 => x"07",  -- RET

        others => x"FF"
    );

begin
    process(ADDR, CS_N)
    begin
        if CS_N = '0' and ADDR /= "XXXXXXXXXXXX" and ADDR /= "ZZZZZZZZZZZZ" and
           ADDR /= "UUUUUUUUUUUU" and ADDR /= "------------" then
            DATA_OUT <= rom(to_integer(unsigned(ADDR)));
        else
            DATA_OUT <= (others => 'Z');
        end if;
    end process;

end rtl;

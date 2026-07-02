--------------------------------------------------------------------------------
-- address_decoder_tb.vhdl - Testbench for the configurable address decoder
--------------------------------------------------------------------------------
-- Two instances under test:
--   u_default : default generics = current memory map
--               ROM 0x0000-0x1FFF, RAM 0x2000-0x23FF
--   u_big     : RAM grown to 8KB (RAM_LAST => 0x3FFF)
--
-- Checks boundary addresses on both instances: base, last, one past last,
-- and that ROM/RAM selects are mutually exclusive with active-low CS mirrors.
--
-- Run: make test-address-decoder
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity address_decoder_tb is
end entity address_decoder_tb;

architecture behavior of address_decoder_tb is

    component address_decoder is
        generic (
            ROM_BASE : integer := 16#0000#;
            ROM_LAST : integer := 16#1FFF#;
            RAM_BASE : integer := 16#2000#;
            RAM_LAST : integer := 16#23FF#
        );
        port (
            address  : in  std_logic_vector(13 downto 0);
            rom_sel  : out std_logic;
            ram_sel  : out std_logic;
            rom_cs_n : out std_logic;
            ram_cs_n : out std_logic
        );
    end component;

    signal address : std_logic_vector(13 downto 0) := (others => '0');

    signal d_rom_sel, d_ram_sel, d_rom_cs_n, d_ram_cs_n : std_logic;
    signal b_rom_sel, b_ram_sel, b_rom_cs_n, b_ram_cs_n : std_logic;

    signal test_count : integer := 0;
    signal fail_count : integer := 0;

begin

    u_default : address_decoder
        port map (
            address  => address,
            rom_sel  => d_rom_sel,
            ram_sel  => d_ram_sel,
            rom_cs_n => d_rom_cs_n,
            ram_cs_n => d_ram_cs_n
        );

    u_big : address_decoder
        generic map (
            RAM_LAST => 16#3FFF#
        )
        port map (
            address  => address,
            rom_sel  => b_rom_sel,
            ram_sel  => b_ram_sel,
            rom_cs_n => b_rom_cs_n,
            ram_cs_n => b_ram_cs_n
        );

    stimulus : process

        procedure check(addr     : integer;
                        exp_rom  : std_logic;
                        exp_ram  : std_logic;
                        exp_brom : std_logic;
                        exp_bram : std_logic;
                        name     : string) is
        begin
            address <= std_logic_vector(to_unsigned(addr, 14));
            wait for 10 ns;
            test_count <= test_count + 1;

            -- default-map instance
            assert d_rom_sel = exp_rom
                report "FAIL [" & name & "] default rom_sel: expected " &
                       std_logic'image(exp_rom) & " got " & std_logic'image(d_rom_sel)
                severity error;
            assert d_ram_sel = exp_ram
                report "FAIL [" & name & "] default ram_sel: expected " &
                       std_logic'image(exp_ram) & " got " & std_logic'image(d_ram_sel)
                severity error;
            assert d_rom_cs_n = not exp_rom
                report "FAIL [" & name & "] default rom_cs_n not inverse of rom_sel"
                severity error;
            assert d_ram_cs_n = not exp_ram
                report "FAIL [" & name & "] default ram_cs_n not inverse of ram_sel"
                severity error;

            -- 8KB-RAM instance
            assert b_rom_sel = exp_brom
                report "FAIL [" & name & "] big rom_sel: expected " &
                       std_logic'image(exp_brom) & " got " & std_logic'image(b_rom_sel)
                severity error;
            assert b_ram_sel = exp_bram
                report "FAIL [" & name & "] big ram_sel: expected " &
                       std_logic'image(exp_bram) & " got " & std_logic'image(b_ram_sel)
                severity error;
            assert b_rom_cs_n = not exp_brom
                report "FAIL [" & name & "] big rom_cs_n not inverse of rom_sel"
                severity error;
            assert b_ram_cs_n = not exp_bram
                report "FAIL [" & name & "] big ram_cs_n not inverse of ram_sel"
                severity error;

            if d_rom_sel /= exp_rom or d_ram_sel /= exp_ram or
               d_rom_cs_n /= not exp_rom or d_ram_cs_n /= not exp_ram or
               b_rom_sel /= exp_brom or b_ram_sel /= exp_bram or
               b_rom_cs_n /= not exp_brom or b_ram_cs_n /= not exp_bram then
                fail_count <= fail_count + 1;
            end if;
        end procedure;

    begin
        --      addr       def_rom def_ram big_rom big_ram
        check(16#0000#,    '1',    '0',    '1',    '0',   "ROM base");
        check(16#0001#,    '1',    '0',    '1',    '0',   "ROM base+1");
        check(16#1FFF#,    '1',    '0',    '1',    '0',   "ROM last");
        check(16#2000#,    '0',    '1',    '0',    '1',   "RAM base");
        check(16#23FF#,    '0',    '1',    '0',    '1',   "RAM 1KB last");
        check(16#2400#,    '0',    '0',    '0',    '1',   "past 1KB RAM");
        check(16#3000#,    '0',    '0',    '0',    '1',   "mid upper 8KB");
        check(16#3FFF#,    '0',    '0',    '0',    '1',   "RAM 8KB last");
        check(16#1000#,    '1',    '0',    '1',    '0',   "ROM middle");

        wait for 10 ns;
        if fail_count = 0 then
            report "=== ADDRESS DECODER TEST PASSED (" &
                   integer'image(test_count) & " checks) ===" severity note;
        else
            report "=== ADDRESS DECODER TEST FAILED: " &
                   integer'image(fail_count) & " of " &
                   integer'image(test_count) & " checks failed ===" severity failure;
        end if;
        wait;
    end process;

end architecture behavior;

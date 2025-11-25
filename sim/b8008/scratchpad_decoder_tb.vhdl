--------------------------------------------------------------------------------
-- scratchpad_decoder_tb.vhdl
--------------------------------------------------------------------------------
-- Testbench for Scratchpad Decoder
-- Tests: 3-to-8 decode with read/write enables
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.b8008_types.all;

entity scratchpad_decoder_tb is
end entity scratchpad_decoder_tb;

architecture test of scratchpad_decoder_tb is

    component scratchpad_decoder is
        port (
            addr_in      : in std_logic_vector(2 downto 0);
            read_enable  : in std_logic;
            write_enable : in std_logic;
            enable_a     : out std_logic;
            enable_b     : out std_logic;
            enable_c     : out std_logic;
            enable_d     : out std_logic;
            enable_e     : out std_logic;
            enable_h     : out std_logic;
            enable_l     : out std_logic;
            enable_m     : out std_logic;
            read_out     : out std_logic;
            write_out    : out std_logic
        );
    end component;

    -- Inputs
    signal addr_in      : std_logic_vector(2 downto 0) := (others => '0');
    signal read_enable  : std_logic := '0';
    signal write_enable : std_logic := '0';

    -- Outputs
    signal enable_a  : std_logic;
    signal enable_b  : std_logic;
    signal enable_c  : std_logic;
    signal enable_d  : std_logic;
    signal enable_e  : std_logic;
    signal enable_h  : std_logic;
    signal enable_l  : std_logic;
    signal enable_m  : std_logic;
    signal read_out  : std_logic;
    signal write_out : std_logic;

begin

    uut : scratchpad_decoder
        port map (
            addr_in      => addr_in,
            read_enable  => read_enable,
            write_enable => write_enable,
            enable_a     => enable_a,
            enable_b     => enable_b,
            enable_c     => enable_c,
            enable_d     => enable_d,
            enable_e     => enable_e,
            enable_h     => enable_h,
            enable_l     => enable_l,
            enable_m     => enable_m,
            read_out     => read_out,
            write_out    => write_out
        );

    test_process : process
        variable errors : integer := 0;
    begin
        report "========================================";
        report "Scratchpad Decoder Test";
        report "========================================";

        -- Test all 8 register selects with read enable
        report "";
        report "Testing all registers with read_enable=1";

        read_enable <= '1';

        for i in 0 to 7 loop
            addr_in <= std_logic_vector(to_unsigned(i, 3));
            wait for 10 ns;

            -- Check that only one enable is high
            case i is
                when 0 =>
                    if enable_a /= '1' or enable_b /= '0' or enable_c /= '0' or
                       enable_d /= '0' or enable_e /= '0' or enable_h /= '0' or
                       enable_l /= '0' or enable_m /= '0' then
                        report "  ERROR: Register A (000) decode failed" severity error;
                        errors := errors + 1;
                    else
                        report "  PASS: Register A decoded";
                    end if;

                when 1 =>
                    if enable_b /= '1' or enable_a /= '0' or enable_c /= '0' or
                       enable_d /= '0' or enable_e /= '0' or enable_h /= '0' or
                       enable_l /= '0' or enable_m /= '0' then
                        report "  ERROR: Register B (001) decode failed" severity error;
                        errors := errors + 1;
                    else
                        report "  PASS: Register B decoded";
                    end if;

                when 2 =>
                    if enable_c /= '1' or enable_a /= '0' or enable_b /= '0' or
                       enable_d /= '0' or enable_e /= '0' or enable_h /= '0' or
                       enable_l /= '0' or enable_m /= '0' then
                        report "  ERROR: Register C (010) decode failed" severity error;
                        errors := errors + 1;
                    else
                        report "  PASS: Register C decoded";
                    end if;

                when 3 =>
                    if enable_d /= '1' or enable_a /= '0' or enable_b /= '0' or
                       enable_c /= '0' or enable_e /= '0' or enable_h /= '0' or
                       enable_l /= '0' or enable_m /= '0' then
                        report "  ERROR: Register D (011) decode failed" severity error;
                        errors := errors + 1;
                    else
                        report "  PASS: Register D decoded";
                    end if;

                when 4 =>
                    if enable_e /= '1' or enable_a /= '0' or enable_b /= '0' or
                       enable_c /= '0' or enable_d /= '0' or enable_h /= '0' or
                       enable_l /= '0' or enable_m /= '0' then
                        report "  ERROR: Register E (100) decode failed" severity error;
                        errors := errors + 1;
                    else
                        report "  PASS: Register E decoded";
                    end if;

                when 5 =>
                    if enable_h /= '1' or enable_a /= '0' or enable_b /= '0' or
                       enable_c /= '0' or enable_d /= '0' or enable_e /= '0' or
                       enable_l /= '0' or enable_m /= '0' then
                        report "  ERROR: Register H (101) decode failed" severity error;
                        errors := errors + 1;
                    else
                        report "  PASS: Register H decoded";
                    end if;

                when 6 =>
                    if enable_l /= '1' or enable_a /= '0' or enable_b /= '0' or
                       enable_c /= '0' or enable_d /= '0' or enable_e /= '0' or
                       enable_h /= '0' or enable_m /= '0' then
                        report "  ERROR: Register L (110) decode failed" severity error;
                        errors := errors + 1;
                    else
                        report "  PASS: Register L decoded";
                    end if;

                when 7 =>
                    if enable_m /= '1' or enable_a /= '0' or enable_b /= '0' or
                       enable_c /= '0' or enable_d /= '0' or enable_e /= '0' or
                       enable_h /= '0' or enable_l /= '0' then
                        report "  ERROR: Register M (111) decode failed" severity error;
                        errors := errors + 1;
                    else
                        report "  PASS: Register M decoded";
                    end if;

                when others => null;
            end case;
        end loop;

        read_enable <= '0';

        -- Test with write enable
        report "";
        report "Test: Write enable to register C";

        addr_in      <= "010";  -- C
        write_enable <= '1';
        wait for 10 ns;

        if enable_c /= '1' then
            report "  ERROR: Register C should be enabled" severity error;
            errors := errors + 1;
        else
            report "  PASS: Write enable works";
        end if;

        write_enable <= '0';

        -- Test: No enable when both read and write are 0
        report "";
        report "Test: All disabled when read_enable=0 and write_enable=0";

        addr_in <= "000";  -- A
        wait for 10 ns;

        if enable_a /= '0' or enable_b /= '0' or enable_c /= '0' or
           enable_d /= '0' or enable_e /= '0' or enable_h /= '0' or
           enable_l /= '0' or enable_m /= '0' then
            report "  ERROR: All enables should be 0" severity error;
            errors := errors + 1;
        else
            report "  PASS: All disabled when no read/write";
        end if;

        -- Summary
        report "";
        report "========================================";
        if errors = 0 then
            report "*** ALL TESTS PASSED ***";
        else
            report "*** TESTS FAILED: " & integer'image(errors) & " errors ***" severity error;
        end if;
        report "========================================";

        wait;
    end process;

end architecture test;

--------------------------------------------------------------------------------
-- stack_addr_decoder_tb.vhdl
--------------------------------------------------------------------------------
-- Testbench for Stack Address Decoder
-- Tests: 3-to-8 decode with read/write enables
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.b8008_types.all;

entity stack_addr_decoder_tb is
end entity stack_addr_decoder_tb;

architecture test of stack_addr_decoder_tb is

    component stack_addr_decoder is
        port (
            sp_in          : in std_logic_vector(2 downto 0);
            stack_read     : in std_logic;
            stack_write    : in std_logic;
            enable_level_0 : out std_logic;
            enable_level_1 : out std_logic;
            enable_level_2 : out std_logic;
            enable_level_3 : out std_logic;
            enable_level_4 : out std_logic;
            enable_level_5 : out std_logic;
            enable_level_6 : out std_logic;
            enable_level_7 : out std_logic;
            read_out       : out std_logic;
            write_out      : out std_logic
        );
    end component;

    -- Inputs
    signal sp_in       : std_logic_vector(2 downto 0) := (others => '0');
    signal stack_read  : std_logic := '0';
    signal stack_write : std_logic := '0';

    -- Outputs
    signal enable_level_0 : std_logic;
    signal enable_level_1 : std_logic;
    signal enable_level_2 : std_logic;
    signal enable_level_3 : std_logic;
    signal enable_level_4 : std_logic;
    signal enable_level_5 : std_logic;
    signal enable_level_6 : std_logic;
    signal enable_level_7 : std_logic;
    signal read_out       : std_logic;
    signal write_out      : std_logic;

begin

    uut : stack_addr_decoder
        port map (
            sp_in          => sp_in,
            stack_read     => stack_read,
            stack_write    => stack_write,
            enable_level_0 => enable_level_0,
            enable_level_1 => enable_level_1,
            enable_level_2 => enable_level_2,
            enable_level_3 => enable_level_3,
            enable_level_4 => enable_level_4,
            enable_level_5 => enable_level_5,
            enable_level_6 => enable_level_6,
            enable_level_7 => enable_level_7,
            read_out       => read_out,
            write_out      => write_out
        );

    test_process : process
        variable errors : integer := 0;
    begin
        report "========================================";
        report "Stack Address Decoder Test";
        report "========================================";

        -- Test all 8 levels with stack_write
        report "";
        report "Testing all 8 stack levels with stack_write=1";

        stack_write <= '1';

        for i in 0 to 7 loop
            sp_in <= std_logic_vector(to_unsigned(i, 3));
            wait for 10 ns;

            -- Check that only one enable is high
            case i is
                when 0 =>
                    if enable_level_0 /= '1' or enable_level_1 /= '0' or
                       enable_level_2 /= '0' or enable_level_3 /= '0' or
                       enable_level_4 /= '0' or enable_level_5 /= '0' or
                       enable_level_6 /= '0' or enable_level_7 /= '0' then
                        report "  ERROR: Level 0 decode failed" severity error;
                        errors := errors + 1;
                    else
                        report "  PASS: Level 0 decoded";
                    end if;

                when 1 =>
                    if enable_level_1 /= '1' or enable_level_0 /= '0' or
                       enable_level_2 /= '0' or enable_level_3 /= '0' or
                       enable_level_4 /= '0' or enable_level_5 /= '0' or
                       enable_level_6 /= '0' or enable_level_7 /= '0' then
                        report "  ERROR: Level 1 decode failed" severity error;
                        errors := errors + 1;
                    else
                        report "  PASS: Level 1 decoded";
                    end if;

                when 2 =>
                    if enable_level_2 /= '1' or enable_level_0 /= '0' or
                       enable_level_1 /= '0' or enable_level_3 /= '0' or
                       enable_level_4 /= '0' or enable_level_5 /= '0' or
                       enable_level_6 /= '0' or enable_level_7 /= '0' then
                        report "  ERROR: Level 2 decode failed" severity error;
                        errors := errors + 1;
                    else
                        report "  PASS: Level 2 decoded";
                    end if;

                when 3 =>
                    if enable_level_3 /= '1' or enable_level_0 /= '0' or
                       enable_level_1 /= '0' or enable_level_2 /= '0' or
                       enable_level_4 /= '0' or enable_level_5 /= '0' or
                       enable_level_6 /= '0' or enable_level_7 /= '0' then
                        report "  ERROR: Level 3 decode failed" severity error;
                        errors := errors + 1;
                    else
                        report "  PASS: Level 3 decoded";
                    end if;

                when 4 =>
                    if enable_level_4 /= '1' or enable_level_0 /= '0' or
                       enable_level_1 /= '0' or enable_level_2 /= '0' or
                       enable_level_3 /= '0' or enable_level_5 /= '0' or
                       enable_level_6 /= '0' or enable_level_7 /= '0' then
                        report "  ERROR: Level 4 decode failed" severity error;
                        errors := errors + 1;
                    else
                        report "  PASS: Level 4 decoded";
                    end if;

                when 5 =>
                    if enable_level_5 /= '1' or enable_level_0 /= '0' or
                       enable_level_1 /= '0' or enable_level_2 /= '0' or
                       enable_level_3 /= '0' or enable_level_4 /= '0' or
                       enable_level_6 /= '0' or enable_level_7 /= '0' then
                        report "  ERROR: Level 5 decode failed" severity error;
                        errors := errors + 1;
                    else
                        report "  PASS: Level 5 decoded";
                    end if;

                when 6 =>
                    if enable_level_6 /= '1' or enable_level_0 /= '0' or
                       enable_level_1 /= '0' or enable_level_2 /= '0' or
                       enable_level_3 /= '0' or enable_level_4 /= '0' or
                       enable_level_5 /= '0' or enable_level_7 /= '0' then
                        report "  ERROR: Level 6 decode failed" severity error;
                        errors := errors + 1;
                    else
                        report "  PASS: Level 6 decoded";
                    end if;

                when 7 =>
                    if enable_level_7 /= '1' or enable_level_0 /= '0' or
                       enable_level_1 /= '0' or enable_level_2 /= '0' or
                       enable_level_3 /= '0' or enable_level_4 /= '0' or
                       enable_level_5 /= '0' or enable_level_6 /= '0' then
                        report "  ERROR: Level 7 decode failed" severity error;
                        errors := errors + 1;
                    else
                        report "  PASS: Level 7 decoded";
                    end if;

                when others => null;
            end case;
        end loop;

        stack_write <= '0';

        -- Test with stack_read
        report "";
        report "Test: Read enable to level 5";

        sp_in <= "101";
        stack_read <= '1';
        wait for 10 ns;

        if enable_level_5 /= '1' then
            report "  ERROR: Level 5 should be enabled" severity error;
            errors := errors + 1;
        else
            report "  PASS: Read enable works";
        end if;

        stack_read <= '0';

        -- Test: All disabled when no read/write
        report "";
        report "Test: All disabled when stack_read=0 and stack_write=0";

        sp_in <= "000";
        wait for 10 ns;

        if enable_level_0 /= '0' or enable_level_1 /= '0' or
           enable_level_2 /= '0' or enable_level_3 /= '0' or
           enable_level_4 /= '0' or enable_level_5 /= '0' or
           enable_level_6 /= '0' or enable_level_7 /= '0' then
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

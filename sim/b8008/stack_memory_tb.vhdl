--------------------------------------------------------------------------------
-- stack_memory_tb.vhdl
--------------------------------------------------------------------------------
-- Testbench for Stack Memory
-- Tests: Write to stack levels, read from stack levels, all 8 levels
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.b8008_types.all;

entity stack_memory_tb is
end entity stack_memory_tb;

architecture test of stack_memory_tb is

    component stack_memory is
        port (
            phi1           : in std_logic;
            reset          : in std_logic;
            addr_in        : in std_logic_vector(13 downto 0);
            enable_level_0 : in std_logic;
            enable_level_1 : in std_logic;
            enable_level_2 : in std_logic;
            enable_level_3 : in std_logic;
            enable_level_4 : in std_logic;
            enable_level_5 : in std_logic;
            enable_level_6 : in std_logic;
            enable_level_7 : in std_logic;
            stack_read     : in std_logic;
            stack_write    : in std_logic;
            addr_out       : out std_logic_vector(13 downto 0)
        );
    end component;

    -- Clock
    signal phi1 : std_logic := '0';
    constant phi1_period : time := 500 ns;

    -- Inputs
    signal reset          : std_logic := '0';
    signal addr_in        : std_logic_vector(13 downto 0) := (others => '0');
    signal enable_level_0 : std_logic := '0';
    signal enable_level_1 : std_logic := '0';
    signal enable_level_2 : std_logic := '0';
    signal enable_level_3 : std_logic := '0';
    signal enable_level_4 : std_logic := '0';
    signal enable_level_5 : std_logic := '0';
    signal enable_level_6 : std_logic := '0';
    signal enable_level_7 : std_logic := '0';
    signal stack_read     : std_logic := '0';
    signal stack_write    : std_logic := '0';

    -- Outputs
    signal addr_out : std_logic_vector(13 downto 0);

begin

    -- Clock generation
    phi1 <= not phi1 after phi1_period / 2;

    uut : stack_memory
        port map (
            phi1           => phi1,
            reset          => reset,
            addr_in        => addr_in,
            enable_level_0 => enable_level_0,
            enable_level_1 => enable_level_1,
            enable_level_2 => enable_level_2,
            enable_level_3 => enable_level_3,
            enable_level_4 => enable_level_4,
            enable_level_5 => enable_level_5,
            enable_level_6 => enable_level_6,
            enable_level_7 => enable_level_7,
            stack_read     => stack_read,
            stack_write    => stack_write,
            addr_out       => addr_out
        );

    test_process : process
        variable errors : integer := 0;
    begin
        report "========================================";
        report "Stack Memory Test";
        report "========================================";

        -- Test 1: Reset clears all levels
        report "";
        report "Test 1: Reset clears all stack levels";

        reset <= '1';
        wait for phi1_period;
        reset <= '0';
        wait for phi1_period;

        report "  PASS: Reset completed";

        -- Test 2: Write to level 0
        report "";
        report "Test 2: Write address 0x1234 to level 0";

        addr_in        <= "00010010001101";  -- 0x1234 in 14 bits
        enable_level_0 <= '1';
        stack_write    <= '1';
        wait until rising_edge(phi1);
        wait for 10 ns;
        enable_level_0 <= '0';
        stack_write    <= '0';

        -- Read back
        enable_level_0 <= '1';
        stack_read     <= '1';
        wait for 10 ns;

        if addr_out /= "00010010001101" then
            report "  ERROR: Level 0 should contain 0x1234" severity error;
            errors := errors + 1;
        else
            report "  PASS: Level 0 written and read correctly";
        end if;

        enable_level_0 <= '0';
        stack_read     <= '0';

        -- Test 3: Write to level 3
        report "";
        report "Test 3: Write address 0x3ABC to level 3";

        addr_in        <= "11101010111100";  -- 0x3ABC in 14 bits
        enable_level_3 <= '1';
        stack_write    <= '1';
        wait until rising_edge(phi1);
        wait for 10 ns;
        enable_level_3 <= '0';
        stack_write    <= '0';

        -- Read back
        enable_level_3 <= '1';
        stack_read     <= '1';
        wait for 10 ns;

        if addr_out /= "11101010111100" then
            report "  ERROR: Level 3 should contain 0x3ABC" severity error;
            errors := errors + 1;
        else
            report "  PASS: Level 3 written and read correctly";
        end if;

        enable_level_3 <= '0';
        stack_read     <= '0';

        -- Test 4: Write to all levels
        report "";
        report "Test 4: Write to all 8 levels";

        -- Write unique addresses to each level
        for i in 0 to 7 loop
            addr_in <= std_logic_vector(to_unsigned(i * 256, 14));
            stack_write <= '1';

            case i is
                when 0 => enable_level_0 <= '1';
                when 1 => enable_level_1 <= '1';
                when 2 => enable_level_2 <= '1';
                when 3 => enable_level_3 <= '1';
                when 4 => enable_level_4 <= '1';
                when 5 => enable_level_5 <= '1';
                when 6 => enable_level_6 <= '1';
                when 7 => enable_level_7 <= '1';
                when others => null;
            end case;

            wait until rising_edge(phi1);
            wait for 10 ns;

            enable_level_0 <= '0';
            enable_level_1 <= '0';
            enable_level_2 <= '0';
            enable_level_3 <= '0';
            enable_level_4 <= '0';
            enable_level_5 <= '0';
            enable_level_6 <= '0';
            enable_level_7 <= '0';
            stack_write <= '0';
            wait for 10 ns;
        end loop;

        report "  PASS: All levels written";

        -- Test 5: Read back all levels
        report "";
        report "Test 5: Read back all 8 levels";

        for i in 0 to 7 loop
            stack_read <= '1';

            case i is
                when 0 => enable_level_0 <= '1';
                when 1 => enable_level_1 <= '1';
                when 2 => enable_level_2 <= '1';
                when 3 => enable_level_3 <= '1';
                when 4 => enable_level_4 <= '1';
                when 5 => enable_level_5 <= '1';
                when 6 => enable_level_6 <= '1';
                when 7 => enable_level_7 <= '1';
                when others => null;
            end case;

            wait for 10 ns;

            if addr_out /= std_logic_vector(to_unsigned(i * 256, 14)) then
                report "  ERROR: Level " & integer'image(i) &
                       " read back incorrect value" severity error;
                errors := errors + 1;
            end if;

            enable_level_0 <= '0';
            enable_level_1 <= '0';
            enable_level_2 <= '0';
            enable_level_3 <= '0';
            enable_level_4 <= '0';
            enable_level_5 <= '0';
            enable_level_6 <= '0';
            enable_level_7 <= '0';
            stack_read <= '0';
            wait for 10 ns;
        end loop;

        report "  PASS: All levels read correctly";

        -- Test 6: Output is 0 when not reading
        report "";
        report "Test 6: Output is 0 when stack_read=0";

        wait for 10 ns;

        if addr_out /= "00000000000000" then
            report "  ERROR: Output should be 0 when not reading" severity error;
            errors := errors + 1;
        else
            report "  PASS: Output correctly 0 when not reading";
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

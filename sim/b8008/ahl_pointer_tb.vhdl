--------------------------------------------------------------------------------
-- ahl_pointer_tb.vhdl
--------------------------------------------------------------------------------
-- Testbench for AHL Address Pointer
-- Tests: Load H:L into address pointer, output 14-bit address
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.b8008_types.all;

entity ahl_pointer_tb is
end entity ahl_pointer_tb;

architecture test of ahl_pointer_tb is

    component ahl_pointer is
        port (
            phi1        : in std_logic;
            reset       : in std_logic;
            h_reg       : in std_logic_vector(7 downto 0);
            l_reg       : in std_logic_vector(7 downto 0);
            load_ahl    : in std_logic;
            output_ahl  : in std_logic;
            address_out : out std_logic_vector(13 downto 0)
        );
    end component;

    -- Clock
    signal phi1 : std_logic := '0';
    constant phi1_period : time := 500 ns;

    -- Inputs
    signal reset      : std_logic := '0';
    signal h_reg      : std_logic_vector(7 downto 0) := (others => '0');
    signal l_reg      : std_logic_vector(7 downto 0) := (others => '0');
    signal load_ahl   : std_logic := '0';
    signal output_ahl : std_logic := '0';

    -- Outputs
    signal address_out : std_logic_vector(13 downto 0);

begin

    -- Clock generation
    phi1 <= not phi1 after phi1_period / 2;

    uut : ahl_pointer
        port map (
            phi1        => phi1,
            reset       => reset,
            h_reg       => h_reg,
            l_reg       => l_reg,
            load_ahl    => load_ahl,
            output_ahl  => output_ahl,
            address_out => address_out
        );

    test_process : process
        variable errors : integer := 0;
    begin
        report "========================================";
        report "AHL Address Pointer Test";
        report "========================================";

        -- Test 1: Reset clears address
        report "";
        report "Test 1: Reset clears address";

        reset <= '1';
        wait for phi1_period;
        reset <= '0';
        wait for phi1_period;

        if address_out /= "00000000000000" then
            report "  ERROR: Address should be 0 after reset" severity error;
            errors := errors + 1;
        else
            report "  PASS: Address cleared after reset";
        end if;

        -- Test 2: Load H:L into address pointer
        report "";
        report "Test 2: Load H=0x3F, L=0x2A (14-bit: 0x3F2A -> 0011111100101010)";

        h_reg    <= x"3F";  -- 00111111
        l_reg    <= x"2A";  -- 00101010 (only [5:0] used = 101010)
        load_ahl <= '1';
        wait until rising_edge(phi1);
        wait for 10 ns;
        load_ahl <= '0';

        if address_out /= "00111111101010" then
            report "  ERROR: Address should be 0011111110101010, got " &
                   to_string(address_out) severity error;
            errors := errors + 1;
        else
            report "  PASS: H:L loaded correctly";
        end if;

        -- Test 3: Load different address
        report "";
        report "Test 3: Load H=0xFF, L=0xFF (14-bit: 0x3FFF)";

        h_reg    <= x"FF";
        l_reg    <= x"FF";
        load_ahl <= '1';
        wait until rising_edge(phi1);
        wait for 10 ns;
        load_ahl <= '0';

        if address_out /= "11111111111111" then
            report "  ERROR: Address should be all ones" severity error;
            errors := errors + 1;
        else
            report "  PASS: Maximum address loaded";
        end if;

        -- Test 4: Hold address when load=0
        report "";
        report "Test 4: Address holds when load_ahl=0";

        h_reg <= x"00";
        l_reg <= x"00";
        wait for phi1_period * 2;

        if address_out /= "11111111111111" then
            report "  ERROR: Address should hold previous value" severity error;
            errors := errors + 1;
        else
            report "  PASS: Address held correctly";
        end if;

        -- Test 5: Load zero address
        report "";
        report "Test 5: Load H=0x00, L=0x00";

        h_reg    <= x"00";
        l_reg    <= x"00";
        load_ahl <= '1';
        wait until rising_edge(phi1);
        wait for 10 ns;
        load_ahl <= '0';

        if address_out /= "00000000000000" then
            report "  ERROR: Address should be zero" severity error;
            errors := errors + 1;
        else
            report "  PASS: Zero address loaded";
        end if;

        -- Test 6: Only lower 6 bits of L are used
        report "";
        report "Test 6: Upper 2 bits of L ignored (L=0xC0 -> only 0x00 used)";

        h_reg    <= x"12";  -- 00010010
        l_reg    <= x"C0";  -- 11000000 (only [5:0]=000000 used)
        load_ahl <= '1';
        wait until rising_edge(phi1);
        wait for 10 ns;
        load_ahl <= '0';

        if address_out /= "00010010000000" then
            report "  ERROR: Upper bits of L should be ignored, got " &
                   to_string(address_out) severity error;
            errors := errors + 1;
        else
            report "  PASS: Upper L bits correctly ignored";
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

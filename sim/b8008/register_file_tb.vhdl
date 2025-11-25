--------------------------------------------------------------------------------
-- register_file_tb.vhdl
--------------------------------------------------------------------------------
-- Testbench for Register File
-- Tests: Write to registers, read from registers, H/L outputs
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.b8008_types.all;

entity register_file_tb is
end entity register_file_tb;

architecture test of register_file_tb is

    component register_file is
        port (
            phi2         : in std_logic;
            reset        : in std_logic;
            internal_bus : inout std_logic_vector(7 downto 0);
            enable_a     : in std_logic;
            enable_b     : in std_logic;
            enable_c     : in std_logic;
            enable_d     : in std_logic;
            enable_e     : in std_logic;
            enable_h     : in std_logic;
            enable_l     : in std_logic;
            read_enable  : in std_logic;
            write_enable : in std_logic;
            h_reg_out    : out std_logic_vector(7 downto 0);
            l_reg_out    : out std_logic_vector(7 downto 0)
        );
    end component;

    -- Clock
    signal phi2 : std_logic := '0';
    constant phi2_period : time := 500 ns;

    -- Inputs
    signal reset        : std_logic := '0';
    signal enable_a     : std_logic := '0';
    signal enable_b     : std_logic := '0';
    signal enable_c     : std_logic := '0';
    signal enable_d     : std_logic := '0';
    signal enable_e     : std_logic := '0';
    signal enable_h     : std_logic := '0';
    signal enable_l     : std_logic := '0';
    signal read_enable  : std_logic := '0';
    signal write_enable : std_logic := '0';

    -- Bidirectional bus
    signal internal_bus : std_logic_vector(7 downto 0);
    signal bus_driver   : std_logic_vector(7 downto 0) := (others => 'Z');

    -- Outputs
    signal h_reg_out : std_logic_vector(7 downto 0);
    signal l_reg_out : std_logic_vector(7 downto 0);

begin

    -- Clock generation
    phi2 <= not phi2 after phi2_period / 2;

    -- Drive bus from testbench
    internal_bus <= bus_driver;

    uut : register_file
        port map (
            phi2         => phi2,
            reset        => reset,
            internal_bus => internal_bus,
            enable_a     => enable_a,
            enable_b     => enable_b,
            enable_c     => enable_c,
            enable_d     => enable_d,
            enable_e     => enable_e,
            enable_h     => enable_h,
            enable_l     => enable_l,
            read_enable  => read_enable,
            write_enable => write_enable,
            h_reg_out    => h_reg_out,
            l_reg_out    => l_reg_out
        );

    test_process : process
        variable errors : integer := 0;
    begin
        report "========================================";
        report "Register File Test";
        report "========================================";

        -- Test 1: Reset clears all registers
        report "";
        report "Test 1: Reset clears all registers";

        reset <= '1';
        wait for phi2_period;
        reset <= '0';
        wait for phi2_period;

        if h_reg_out /= x"00" or l_reg_out /= x"00" then
            report "  ERROR: H and L should be zero after reset" severity error;
            errors := errors + 1;
        else
            report "  PASS: Registers cleared after reset";
        end if;

        -- Test 2: Write to register A
        report "";
        report "Test 2: Write 0x42 to register A";

        bus_driver   <= x"42";
        enable_a     <= '1';
        write_enable <= '1';
        wait until rising_edge(phi2);
        wait for 10 ns;
        enable_a     <= '0';
        write_enable <= '0';
        bus_driver   <= (others => 'Z');

        -- Read back from A
        enable_a    <= '1';
        read_enable <= '1';
        wait for 10 ns;

        if internal_bus /= x"42" then
            report "  ERROR: Register A should contain 0x42" severity error;
            errors := errors + 1;
        else
            report "  PASS: Register A written and read correctly";
        end if;

        enable_a    <= '0';
        read_enable <= '0';
        wait for 10 ns;

        -- Test 3: Write to register H and check direct output
        report "";
        report "Test 3: Write 0x3F to register H";

        bus_driver   <= x"3F";
        enable_h     <= '1';
        write_enable <= '1';
        wait until rising_edge(phi2);
        wait for 10 ns;
        enable_h     <= '0';
        write_enable <= '0';
        bus_driver   <= (others => 'Z');
        wait for 10 ns;

        if h_reg_out /= x"3F" then
            report "  ERROR: H output should be 0x3F" severity error;
            errors := errors + 1;
        else
            report "  PASS: H register direct output correct";
        end if;

        -- Test 4: Write to register L and check direct output
        report "";
        report "Test 4: Write 0x2A to register L";

        bus_driver   <= x"2A";
        enable_l     <= '1';
        write_enable <= '1';
        wait until rising_edge(phi2);
        wait for 10 ns;
        enable_l     <= '0';
        write_enable <= '0';
        bus_driver   <= (others => 'Z');
        wait for 10 ns;

        if l_reg_out /= x"2A" then
            report "  ERROR: L output should be 0x2A" severity error;
            errors := errors + 1;
        else
            report "  PASS: L register direct output correct";
        end if;

        -- Test 5: Write to all registers
        report "";
        report "Test 5: Write to all registers (B=0x11, C=0x22, D=0x33, E=0x44)";

        -- Write B
        bus_driver   <= x"11";
        enable_b     <= '1';
        write_enable <= '1';
        wait until rising_edge(phi2);
        wait for 10 ns;
        enable_b     <= '0';
        write_enable <= '0';
        bus_driver   <= (others => 'Z');
        wait for 10 ns;

        -- Write C
        bus_driver   <= x"22";
        enable_c     <= '1';
        write_enable <= '1';
        wait until rising_edge(phi2);
        wait for 10 ns;
        enable_c     <= '0';
        write_enable <= '0';
        bus_driver   <= (others => 'Z');
        wait for 10 ns;

        -- Write D
        bus_driver   <= x"33";
        enable_d     <= '1';
        write_enable <= '1';
        wait until rising_edge(phi2);
        wait for 10 ns;
        enable_d     <= '0';
        write_enable <= '0';
        bus_driver   <= (others => 'Z');
        wait for 10 ns;

        -- Write E
        bus_driver   <= x"44";
        enable_e     <= '1';
        write_enable <= '1';
        wait until rising_edge(phi2);
        wait for 10 ns;
        enable_e     <= '0';
        write_enable <= '0';
        bus_driver   <= (others => 'Z');
        wait for 10 ns;

        report "  PASS: All registers written";

        -- Test 6: Read back all registers
        report "";
        report "Test 6: Read back all registers";

        -- Read B
        enable_b    <= '1';
        read_enable <= '1';
        wait for 10 ns;
        if internal_bus /= x"11" then
            report "  ERROR: Register B should be 0x11" severity error;
            errors := errors + 1;
        end if;
        enable_b    <= '0';
        read_enable <= '0';
        wait for 10 ns;

        -- Read C
        enable_c    <= '1';
        read_enable <= '1';
        wait for 10 ns;
        if internal_bus /= x"22" then
            report "  ERROR: Register C should be 0x22" severity error;
            errors := errors + 1;
        end if;
        enable_c    <= '0';
        read_enable <= '0';
        wait for 10 ns;

        -- Read D
        enable_d    <= '1';
        read_enable <= '1';
        wait for 10 ns;
        if internal_bus /= x"33" then
            report "  ERROR: Register D should be 0x33" severity error;
            errors := errors + 1;
        end if;
        enable_d    <= '0';
        read_enable <= '0';
        wait for 10 ns;

        -- Read E
        enable_e    <= '1';
        read_enable <= '1';
        wait for 10 ns;
        if internal_bus /= x"44" then
            report "  ERROR: Register E should be 0x44" severity error;
            errors := errors + 1;
        else
            report "  PASS: All registers read correctly";
        end if;
        enable_e    <= '0';
        read_enable <= '0';
        wait for 10 ns;

        -- Test 7: Bus tri-states when not reading
        report "";
        report "Test 7: Bus tri-states when read_enable=0";

        wait for 10 ns;

        if internal_bus /= "ZZZZZZZZ" then
            report "  ERROR: Bus should be tri-stated" severity error;
            errors := errors + 1;
        else
            report "  PASS: Bus correctly tri-stated";
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

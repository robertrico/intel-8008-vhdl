--------------------------------------------------------------------------------
-- io_buffer_tb.vhdl
--------------------------------------------------------------------------------
-- Testbench for I/O Buffer
-- Tests: Read (external->internal), Write (internal->external), tri-state
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.b8008_types.all;

entity io_buffer_tb is
end entity io_buffer_tb;

architecture test of io_buffer_tb is

    component io_buffer is
        port (
            external_data : inout std_logic_vector(7 downto 0);
            internal_bus  : inout std_logic_vector(7 downto 0);
            enable        : in std_logic;
            direction     : in std_logic
        );
    end component;

    -- Control signals
    signal enable    : std_logic := '0';
    signal direction : std_logic := '0';

    -- Bidirectional buses
    signal external_data : std_logic_vector(7 downto 0);
    signal internal_bus  : std_logic_vector(7 downto 0);

    -- Test drivers
    signal external_driver : std_logic_vector(7 downto 0) := (others => 'Z');
    signal internal_driver : std_logic_vector(7 downto 0) := (others => 'Z');

begin

    -- Drive buses from testbench
    external_data <= external_driver;
    internal_bus  <= internal_driver;

    uut : io_buffer
        port map (
            external_data => external_data,
            internal_bus  => internal_bus,
            enable        => enable,
            direction     => direction
        );

    test_process : process
        variable errors : integer := 0;
    begin
        report "========================================";
        report "I/O Buffer Test";
        report "========================================";

        wait for 100 ns;

        -- Test 1: Disabled (both sides tri-state)
        report "";
        report "Test 1: Buffer disabled (enable=0)";

        external_driver <= x"AA";
        internal_driver <= x"55";
        enable          <= '0';
        direction       <= '0';
        wait for 50 ns;

        if external_data /= x"AA" or internal_bus /= x"55" then
            report "  ERROR: Both buses should remain independent when disabled" severity error;
            errors := errors + 1;
        else
            report "  PASS: Buses independent when disabled";
        end if;

        -- Test 2: Read mode (external -> internal)
        report "";
        report "Test 2: Read mode (external 0x42 -> internal)";

        external_driver <= x"42";
        internal_driver <= (others => 'Z');
        enable          <= '1';
        direction       <= '0';  -- Read from external
        wait for 50 ns;

        if internal_bus /= x"42" then
            report "  ERROR: Internal bus should be 0x42, got 0x" & to_hstring(internal_bus) severity error;
            errors := errors + 1;
        else
            report "  PASS: External data transferred to internal bus";
        end if;

        if external_data /= x"42" then
            report "  ERROR: External should still be 0x42" severity error;
            errors := errors + 1;
        end if;

        -- Test 3: Write mode (internal -> external)
        report "";
        report "Test 3: Write mode (internal 0x99 -> external)";

        external_driver <= (others => 'Z');
        internal_driver <= x"99";
        enable          <= '1';
        direction       <= '1';  -- Write to external
        wait for 50 ns;

        if external_data /= x"99" then
            report "  ERROR: External data should be 0x99, got 0x" & to_hstring(external_data) severity error;
            errors := errors + 1;
        else
            report "  PASS: Internal bus transferred to external data";
        end if;

        if internal_bus /= x"99" then
            report "  ERROR: Internal should still be 0x99" severity error;
            errors := errors + 1;
        end if;

        -- Test 4: Change data during read
        report "";
        report "Test 4: Change external data during read mode";

        external_driver <= x"11";
        internal_driver <= (others => 'Z');
        enable          <= '1';
        direction       <= '0';
        wait for 20 ns;

        if internal_bus /= x"11" then
            report "  ERROR: Internal should follow external (0x11)" severity error;
            errors := errors + 1;
        end if;

        external_driver <= x"22";
        wait for 20 ns;

        if internal_bus /= x"22" then
            report "  ERROR: Internal should follow external (0x22)" severity error;
            errors := errors + 1;
        else
            report "  PASS: Internal follows external in read mode";
        end if;

        -- Test 5: Disable during operation
        report "";
        report "Test 5: Disable during read operation";

        external_driver <= x"FF";
        internal_driver <= (others => 'Z');
        enable          <= '1';
        direction       <= '0';
        wait for 20 ns;

        if internal_bus /= x"FF" then
            report "  ERROR: Internal should be 0xFF before disable" severity error;
            errors := errors + 1;
        end if;

        enable <= '0';
        wait for 20 ns;

        if internal_bus /= "ZZZZZZZZ" then
            report "  ERROR: Internal should be tri-stated after disable" severity error;
            errors := errors + 1;
        else
            report "  PASS: Buffers tri-state when disabled";
        end if;

        -- Test 6: All zeros transfer
        report "";
        report "Test 6: Transfer 0x00 (read mode)";

        external_driver <= x"00";
        internal_driver <= (others => 'Z');
        enable          <= '1';
        direction       <= '0';
        wait for 50 ns;

        if internal_bus /= x"00" then
            report "  ERROR: Internal should be 0x00" severity error;
            errors := errors + 1;
        else
            report "  PASS: Zero value transferred correctly";
        end if;

        -- Test 7: All ones transfer
        report "";
        report "Test 7: Transfer 0xFF (write mode)";

        external_driver <= (others => 'Z');
        internal_driver <= x"FF";
        enable          <= '1';
        direction       <= '1';
        wait for 50 ns;

        if external_data /= x"FF" then
            report "  ERROR: External should be 0xFF" severity error;
            errors := errors + 1;
        else
            report "  PASS: All-ones value transferred correctly";
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

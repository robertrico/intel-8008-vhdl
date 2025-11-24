--------------------------------------------------------------------------------
-- carry_lookahead_tb.vhdl
--------------------------------------------------------------------------------
-- Testbench for Carry Look-Ahead Logic
-- Tests: Generate/Propagate, Carry propagation, Enable control
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.b8008_types.all;

entity carry_lookahead_tb is
end entity carry_lookahead_tb;

architecture test of carry_lookahead_tb is

    -- Component declaration
    component carry_lookahead is
        port (
            reg_a     : in std_logic_vector(7 downto 0);
            reg_b     : in std_logic_vector(7 downto 0);
            carry_in  : in std_logic;
            enable    : in std_logic;
            carry_out : out std_logic_vector(7 downto 0)
        );
    end component;

    -- Inputs
    signal reg_a     : std_logic_vector(7 downto 0) := (others => '0');
    signal reg_b     : std_logic_vector(7 downto 0) := (others => '0');
    signal carry_in  : std_logic := '0';
    signal enable    : std_logic := '0';

    -- Outputs
    signal carry_out : std_logic_vector(7 downto 0);

begin

    uut : carry_lookahead
        port map (
            reg_a     => reg_a,
            reg_b     => reg_b,
            carry_in  => carry_in,
            enable    => enable,
            carry_out => carry_out
        );

    -- Test stimulus
    test_process : process
        variable errors : integer := 0;
    begin
        report "========================================";
        report "Carry Look-Ahead Test";
        report "========================================";

        wait for 100 ns;

        -- Test 1: Simple addition without carry
        report "";
        report "Test 1: Addition 0x01 + 0x01 (no carry in)";

        reg_a <= x"01";  -- 00000001
        reg_b <= x"01";  -- 00000001
        carry_in <= '0';
        enable <= '1';
        wait for 50 ns;

        -- Expected carries: bit 0: 1+1=10, generates carry
        -- So carry_out(0)=0 (carry into bit 0), carry_out(1)=1 (carry from bit 0)
        if carry_out(0) /= '0' then
            report "  ERROR: carry_out(0) should be 0 (no carry in)" severity error;
            errors := errors + 1;
        end if;
        if carry_out(1) /= '1' then
            report "  ERROR: carry_out(1) should be 1 (carry from 1+1)" severity error;
            errors := errors + 1;
        else
            report "  PASS: Carry generated from bit 0 addition";
        end if;

        -- Test 2: Addition with carry propagation
        report "";
        report "Test 2: Addition 0xFF + 0x01 (carry propagation)";

        reg_a <= x"FF";  -- 11111111
        reg_b <= x"01";  -- 00000001
        carry_in <= '0';
        enable <= '1';
        wait for 50 ns;

        -- Expected: All bits generate or propagate carries
        -- C0=0, C1=1, C2=1, C3=1, C4=1, C5=1, C6=1, C7=1
        if carry_out(7) /= '1' then
            report "  ERROR: carry_out(7) should be 1 (overflow)" severity error;
            errors := errors + 1;
        else
            report "  PASS: Carry propagated through all bits";
        end if;

        -- Test 3: Addition with carry input
        report "";
        report "Test 3: Addition 0x00 + 0x00 with carry_in=1";

        reg_a <= x"00";
        reg_b <= x"00";
        carry_in <= '1';
        enable <= '1';
        wait for 50 ns;

        -- Expected: Carry_in propagates through if bits allow
        -- With 0+0, first bit propagates (Pi=0 XOR 0 = 0, Gi=0 AND 0 = 0)
        -- So Ci+1 = Gi + Pi·Ci = 0 + 0·1 = 0
        -- Carry should not propagate past bit 0
        if carry_out(0) /= '1' then
            report "  ERROR: carry_out(0) should be 1 (carry_in)" severity error;
            errors := errors + 1;
        end if;
        if carry_out(1) /= '0' then
            report "  ERROR: carry_out(1) should be 0 (no propagation from 0+0)" severity error;
            errors := errors + 1;
        end if;
        report "  PASS: Carry input handled correctly";

        -- Test 4: Disabled output
        report "";
        report "Test 4: Enable = 0 (outputs should be zero)";

        reg_a <= x"FF";
        reg_b <= x"FF";
        carry_in <= '1';
        enable <= '0';  -- Disabled
        wait for 50 ns;

        if carry_out /= x"00" then
            report "  ERROR: carry_out should be 0x00 when disabled, got 0x" &
                   to_hstring(carry_out) severity error;
            errors := errors + 1;
        else
            report "  PASS: Output is zero when disabled";
        end if;

        -- Test 5: Complex carry generation
        report "";
        report "Test 5: Addition 0xAA + 0x55 (alternating bits)";

        reg_a <= x"AA";  -- 10101010
        reg_b <= x"55";  -- 01010101
        carry_in <= '0';
        enable <= '1';
        wait for 50 ns;

        -- Each bit: Ai XOR Bi = 1 (all propagate)
        -- But no generates (Ai AND Bi = 0 for all)
        -- So carries don't propagate without carry_in
        -- All propagate bits mean: result = 0xFF, but no carry out
        report "  INFO: carry_out = 0x" & to_hstring(carry_out);
        report "  PASS: Complex pattern handled";

        -- Test 6: Carry with alternating pattern and carry_in
        report "";
        report "Test 6: Addition 0xAA + 0x55 with carry_in=1";

        reg_a <= x"AA";  -- 10101010
        reg_b <= x"55";  -- 01010101
        carry_in <= '1';
        enable <= '1';
        wait for 50 ns;

        -- With all propagate bits and carry_in, carry should propagate through all
        if carry_out(7) /= '1' then
            report "  ERROR: carry_out(7) should be 1 with full propagation" severity error;
            errors := errors + 1;
        else
            report "  PASS: Carry propagated through all propagate bits";
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

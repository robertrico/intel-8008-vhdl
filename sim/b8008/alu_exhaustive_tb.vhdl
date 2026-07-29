--------------------------------------------------------------------------------
-- alu_exhaustive_tb.vhdl
--------------------------------------------------------------------------------
-- Exhaustive equivalence sweep for the carry-lookahead ALU datapath.
--
-- Drives every arithmetic case against a numeric_std reference model
-- (the pre-lookahead implementation, correct by construction):
--
--   ADD/ADC/SUB/SBB/CMP : all 256 x 256 operand pairs x carry_in {0,1}
--   INR/DCR             : all 256 register values x carry_in {0,1}
--
-- 656,384 cases total. Checks result(8:0) and all four flags, including
-- the borrow-high polarity for the subtract family and the INR/DCR
-- carry passthrough exception.
--
-- Run: make test-alu-exhaustive
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.b8008_types.all;

entity alu_exhaustive_tb is
end entity alu_exhaustive_tb;

architecture test of alu_exhaustive_tb is

    signal clk         : std_logic := '0';
    signal phi2_rising : std_logic := '1';
    constant CLK_PERIOD : time := 20 ns;

    signal accumulator_in : std_logic_vector(7 downto 0) := (others => '0');
    signal reg_b_in       : std_logic_vector(7 downto 0) := (others => '0');
    signal opcode         : std_logic_vector(2 downto 0) := (others => '0');
    signal is_inr_dcr     : std_logic := '0';
    signal is_rotate      : std_logic := '0';
    signal carry_in       : std_logic := '0';
    signal enable         : std_logic := '0';
    signal output_result  : std_logic := '0';

    signal internal_bus_out : std_logic_vector(7 downto 0);
    signal internal_bus_oe  : std_logic;
    signal result       : std_logic_vector(8 downto 0);
    signal flag_carry   : std_logic;
    signal flag_zero    : std_logic;
    signal flag_sign    : std_logic;
    signal flag_parity  : std_logic;

    signal done : boolean := false;

    constant OP_ADD : std_logic_vector(2 downto 0) := "000";
    constant OP_ADC : std_logic_vector(2 downto 0) := "001";
    constant OP_SUB : std_logic_vector(2 downto 0) := "010";
    constant OP_SBB : std_logic_vector(2 downto 0) := "011";
    constant OP_CMP : std_logic_vector(2 downto 0) := "111";

    type op_list_t is array (natural range <>) of std_logic_vector(2 downto 0);
    constant ARITH_OPS : op_list_t := (OP_ADD, OP_ADC, OP_SUB, OP_SBB, OP_CMP);

    -- Reference model: 9-bit unsigned arithmetic exactly as the
    -- pre-lookahead ALU computed it (bit 8 = carry for adds,
    -- borrow for subtracts)
    function ref_result(op : std_logic_vector(2 downto 0);
                        a, b : std_logic_vector(7 downto 0);
                        cin : std_logic) return std_logic_vector is
        variable av, bv, r : unsigned(8 downto 0);
        variable cv : unsigned(8 downto 0) := (others => '0');
    begin
        av := unsigned('0' & a);
        bv := unsigned('0' & b);
        if cin = '1' then
            cv(0) := '1';
        end if;
        case op is
            when OP_ADD => r := av + bv;
            when OP_ADC => r := av + bv + cv;
            when OP_SUB => r := av - bv;
            when OP_SBB => r := av - bv - cv;
            when OP_CMP => r := av - bv;
            when others => r := (others => '0');
        end case;
        return std_logic_vector(r);
    end function;

    function even_parity(v : std_logic_vector(7 downto 0)) return std_logic is
    begin
        return not (v(0) xor v(1) xor v(2) xor v(3) xor
                    v(4) xor v(5) xor v(6) xor v(7));
    end function;

begin

    uut : entity work.alu
        port map (
            clk              => clk,
            phi2_rising      => phi2_rising,
            accumulator_in   => accumulator_in,
            reg_b_in         => reg_b_in,
            opcode           => opcode,
            is_inr_dcr       => is_inr_dcr,
            is_rotate        => is_rotate,
            carry_in         => carry_in,
            enable           => enable,
            output_result    => output_result,
            internal_bus_out => internal_bus_out,
            internal_bus_oe  => internal_bus_oe,
            result           => result,
            flag_carry       => flag_carry,
            flag_zero        => flag_zero,
            flag_sign        => flag_sign,
            flag_parity      => flag_parity
        );

    clk_proc : process
    begin
        while not done loop
            clk <= '0';
            wait for CLK_PERIOD / 2;
            clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    test_process : process
        variable errors   : integer := 0;
        variable cases    : integer := 0;
        variable exp      : std_logic_vector(8 downto 0);
        variable exp_cy   : std_logic;

        -- Latch one operation: enable low one edge, high next edge
        procedure pulse is
        begin
            enable <= '0';
            wait until rising_edge(clk);
            enable <= '1';
            wait until rising_edge(clk);
            wait for 1 ns;
        end procedure;

        procedure check(op : std_logic_vector(2 downto 0);
                        a, b : std_logic_vector(7 downto 0);
                        cin : std_logic; inr : std_logic) is
        begin
            exp := ref_result(op, a, b, cin);
            if inr = '1' then
                exp_cy := cin;               -- INR/DCR: carry passes through
            else
                exp_cy := exp(8);            -- adds: carry; subs: borrow (ref is borrow-high)
            end if;

            cases := cases + 1;

            if result /= exp then
                report "MISMATCH result: op=" & to_hstring(op) &
                       " a=0x" & to_hstring(a) & " b=0x" & to_hstring(b) &
                       " cin=" & std_logic'image(cin) &
                       " inr=" & std_logic'image(inr) &
                       " got=0x" & to_hstring(result) &
                       " exp=0x" & to_hstring(exp) severity error;
                errors := errors + 1;
            end if;
            if flag_carry /= exp_cy then
                report "MISMATCH carry: op=" & to_hstring(op) &
                       " a=0x" & to_hstring(a) & " b=0x" & to_hstring(b) &
                       " cin=" & std_logic'image(cin) &
                       " inr=" & std_logic'image(inr) &
                       " got=" & std_logic'image(flag_carry) &
                       " exp=" & std_logic'image(exp_cy) severity error;
                errors := errors + 1;
            end if;
            if flag_zero /= '1' and exp(7 downto 0) = x"00" then
                report "MISMATCH zero flag (should be 1)" severity error;
                errors := errors + 1;
            elsif flag_zero /= '0' and exp(7 downto 0) /= x"00" then
                report "MISMATCH zero flag (should be 0)" severity error;
                errors := errors + 1;
            end if;
            if flag_sign /= exp(7) then
                report "MISMATCH sign flag" severity error;
                errors := errors + 1;
            end if;
            if flag_parity /= even_parity(exp(7 downto 0)) then
                report "MISMATCH parity flag" severity error;
                errors := errors + 1;
            end if;

            assert errors <= 20
                report "Aborting: more than 20 mismatches" severity failure;
        end procedure;
    begin
        report "========================================";
        report "ALU Exhaustive Sweep vs Reference Model";
        report "========================================";

        wait for 100 ns;

        -- Binary arithmetic: 5 ops x 256 x 256 x 2 carry = 655,360 cases
        for oi in ARITH_OPS'range loop
            opcode <= ARITH_OPS(oi);
            for c in 0 to 1 loop
                if c = 1 then
                    carry_in <= '1';
                else
                    carry_in <= '0';
                end if;
                for a in 0 to 255 loop
                    accumulator_in <= std_logic_vector(to_unsigned(a, 8));
                    for b in 0 to 255 loop
                        reg_b_in <= std_logic_vector(to_unsigned(b, 8));
                        pulse;
                        check(ARITH_OPS(oi),
                              std_logic_vector(to_unsigned(a, 8)),
                              std_logic_vector(to_unsigned(b, 8)),
                              carry_in, '0');
                    end loop;
                end loop;
            end loop;
            report "Op " & to_hstring(ARITH_OPS(oi)) & " done: " &
                   integer'image(cases) & " cases, " &
                   integer'image(errors) & " errors";
        end loop;

        -- INR/DCR: ADD/SUB with constant 1, all 256 values x 2 carry.
        -- Result comes from reg_b op 1; carry flag must pass through.
        is_inr_dcr <= '1';
        for oi in 0 to 1 loop
            if oi = 0 then
                opcode <= OP_ADD;   -- INR
            else
                opcode <= OP_SUB;   -- DCR
            end if;
            for c in 0 to 1 loop
                if c = 1 then
                    carry_in <= '1';
                else
                    carry_in <= '0';
                end if;
                for b in 0 to 255 loop
                    reg_b_in <= std_logic_vector(to_unsigned(b, 8));
                    pulse;
                    if oi = 0 then
                        check(OP_ADD, std_logic_vector(to_unsigned(b, 8)), x"01", carry_in, '1');
                    else
                        check(OP_SUB, std_logic_vector(to_unsigned(b, 8)), x"01", carry_in, '1');
                    end if;
                end loop;
            end loop;
        end loop;
        report "INR/DCR done: " & integer'image(cases) & " cases total";

        report "========================================";
        if errors = 0 then
            report "*** EXHAUSTIVE SWEEP PASSED: " &
                   integer'image(cases) & " cases, 0 mismatches ***";
        else
            report "*** EXHAUSTIVE SWEEP FAILED: " &
                   integer'image(errors) & " mismatches in " &
                   integer'image(cases) & " cases ***" severity error;
        end if;
        report "========================================";

        done <= true;
        wait;
    end process;

end architecture test;

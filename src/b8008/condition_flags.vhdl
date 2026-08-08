--------------------------------------------------------------------------------
-- condition_flags.vhdl
--------------------------------------------------------------------------------
-- Conditional Flip-Flops and Condition Logic for Intel 8008
--
-- Stores the four condition flags and evaluates conditions
-- - Receives flag updates from ALU via Register and ALU Control
-- - Stores flags in flip-flops (Carry, Zero, Sign, Parity)
-- - Evaluates condition codes for conditional instructions
-- - Outputs condition_met signal to Memory and I/O Control
-- - DUMB module: just stores flags and evaluates conditions
--
-- Condition Codes (2-bit CC field from instruction, bits 4:3):
--   00 - Carry
--   01 - Zero
--   10 - Sign
--   11 - Parity
--
-- Instructions specify if testing for true (JTc, CTc, RTc) or false (JFc, CFc, RFc)
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.b8008_types.all;

entity condition_flags is
    port (
        -- Master clock + phi2 rising-edge pulse (one clk cycle wide)
        clk         : in std_logic;
        phi2_rising : in std_logic;

        -- Reset
        reset : in std_logic;

        -- Flag inputs from ALU
        flag_carry_in  : in std_logic;
        flag_zero_in   : in std_logic;
        flag_sign_in   : in std_logic;
        flag_parity_in : in std_logic;

        -- Update enable from Register and ALU Control
        update_flags : in std_logic;

        -- When '1' with update_flags: write carry only, hold Z/S/P
        -- (8008 rotates affect carry alone - control tells us, we stay dumb)
        carry_only : in std_logic;

        -- Condition code from instruction (CC field, bits 4:3, 2 bits)
        condition_code : in std_logic_vector(1 downto 0);

        -- Test for true (1) or false (0) - from instruction decoder
        test_true : in std_logic;

        -- Condition evaluation enable (from instruction decoder)
        eval_condition : in std_logic;

        -- Output enable to internal bus
        output_flags : in std_logic;

        -- Internal data bus (separate in/out for synthesis compatibility)
        -- Note: Condition flags only writes to bus, never reads
        internal_bus_out : out std_logic_vector(7 downto 0);
        internal_bus_oe  : out std_logic;

        -- Output: Condition met (to Memory and I/O Control)
        condition_met : out std_logic;

        -- Flag outputs (for debugging or external use)
        flag_carry  : out std_logic;
        flag_zero   : out std_logic;
        flag_sign   : out std_logic;
        flag_parity : out std_logic
    );
end entity condition_flags;

architecture rtl of condition_flags is

    -- Internal flag storage
    signal carry_ff  : std_logic := '0';
    signal zero_ff   : std_logic := '0';
    signal sign_ff   : std_logic := '0';
    signal parity_ff : std_logic := '0';

    -- Condition codes (2-bit)
    constant COND_CARRY  : std_logic_vector(1 downto 0) := "00";
    constant COND_ZERO   : std_logic_vector(1 downto 0) := "01";
    constant COND_SIGN   : std_logic_vector(1 downto 0) := "10";
    constant COND_PARITY : std_logic_vector(1 downto 0) := "11";

begin

    -- Update flag flip-flops on phi2 rising edge (gated)
    process(clk, reset)
    begin
        if reset = '1' then
            carry_ff  <= '0';
            zero_ff   <= '0';
            sign_ff   <= '0';
            parity_ff <= '0';
        elsif rising_edge(clk) then
            if phi2_rising = '1' and update_flags = '1' then
                carry_ff <= flag_carry_in;
                if carry_only = '0' then
                    zero_ff   <= flag_zero_in;
                    sign_ff   <= flag_sign_in;
                    parity_ff <= flag_parity_in;
                end if;
                report "COND_FLAGS: Updating flags - C=" & std_logic'image(flag_carry_in) &
                       " Z=" & std_logic'image(flag_zero_in) &
                       " S=" & std_logic'image(flag_sign_in) &
                       " P=" & std_logic'image(flag_parity_in) &
                       " carry_only=" & std_logic'image(carry_only);
            end if;
        end if;
    end process;

    -- Output flags
    flag_carry  <= carry_ff;
    flag_zero   <= zero_ff;
    flag_sign   <= sign_ff;
    flag_parity <= parity_ff;

    -- Drive internal bus with flags when output_flags is enabled
    -- (register_alu_control asserts it at INP's PCC T4 - "COND FF OUT").
    -- Datasheet bit order (DS72 p.37): S->D0, Z->D1, P->D2, C->D3
    internal_bus_out <= "0000" & carry_ff & parity_ff & zero_ff & sign_ff;
    internal_bus_oe  <= output_flags;

    -- Condition evaluation (pure combinational)
    process(condition_code, carry_ff, zero_ff, sign_ff, parity_ff, eval_condition, test_true)
        variable flag_value : std_logic;
        variable condition_result : std_logic;
    begin
        -- Default: condition met (for unconditional instructions)
        -- Only evaluate flags if eval_condition = '1' (conditional instructions)
        condition_result := '1';

        if eval_condition = '1' then
            -- Conditional instruction - evaluate the condition
            -- Select which flag to test
            case condition_code is
                when COND_CARRY =>
                    flag_value := carry_ff;

                when COND_ZERO =>
                    flag_value := zero_ff;

                when COND_SIGN =>
                    flag_value := sign_ff;

                when COND_PARITY =>
                    flag_value := parity_ff;

                when others =>
                    flag_value := '0';
            end case;

            -- Test for true or false based on instruction
            if test_true = '1' then
                condition_result := flag_value;      -- JTc, CTc, RTc (test if flag = 1)
            else
                condition_result := not flag_value;  -- JFc, CFc, RFc (test if flag = 0)
            end if;

            -- Debug condition evaluation
            if eval_condition = '1' then
                report "COND_FLAGS: eval_condition=1 test_true=" & std_logic'image(test_true) &
                       " flag_value=" & std_logic'image(flag_value) &
                       " condition_result=" & std_logic'image(condition_result);
            end if;
        end if;

        condition_met <= condition_result;
    end process;

end architecture rtl;

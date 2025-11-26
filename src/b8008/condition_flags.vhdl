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
        -- Clock (phi2 from clock generator)
        phi2 : in std_logic;

        -- Reset
        reset : in std_logic;

        -- Flag inputs from ALU
        flag_carry_in  : in std_logic;
        flag_zero_in   : in std_logic;
        flag_sign_in   : in std_logic;
        flag_parity_in : in std_logic;

        -- Update enable from Register and ALU Control
        update_flags : in std_logic;

        -- Condition code from instruction (CC field, bits 4:3, 2 bits)
        condition_code : in std_logic_vector(1 downto 0);

        -- Test for true (1) or false (0) - from instruction decoder
        test_true : in std_logic;

        -- Condition evaluation enable (from instruction decoder)
        eval_condition : in std_logic;

        -- Output enable to internal bus
        output_flags : in std_logic;

        -- Internal data bus (flags output as 8-bit value)
        internal_bus : inout std_logic_vector(7 downto 0);

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

    -- Update flag flip-flops on phi2 rising edge
    process(phi2, reset)
    begin
        if reset = '1' then
            carry_ff  <= '0';
            zero_ff   <= '0';
            sign_ff   <= '0';
            parity_ff <= '0';
        elsif rising_edge(phi2) then
            if update_flags = '1' then
                carry_ff  <= flag_carry_in;
                zero_ff   <= flag_zero_in;
                sign_ff   <= flag_sign_in;
                parity_ff <= flag_parity_in;
            end if;
        end if;
    end process;

    -- Output flags
    flag_carry  <= carry_ff;
    flag_zero   <= zero_ff;
    flag_sign   <= sign_ff;
    flag_parity <= parity_ff;

    -- Drive internal bus with flags when output_flags is enabled
    -- Format: bit 0=carry, bit 1=zero, bit 2=sign, bit 3=parity, bits 7:4=0
    internal_bus <= ("0000" & parity_ff & sign_ff & zero_ff & carry_ff) when output_flags = '1' else (others => 'Z');

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

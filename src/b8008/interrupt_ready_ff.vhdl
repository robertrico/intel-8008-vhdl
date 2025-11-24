--------------------------------------------------------------------------------
-- interrupt_ready_ff.vhdl
--------------------------------------------------------------------------------
-- Interrupt and Ready Flip-Flops for Intel 8008
--
-- Two simple flip-flops for system control:
-- - Interrupt FF: Set by external INT signal, cleared when serviced
-- - Ready FF: Set by external READY signal, controls wait states
--
-- DUMB module: just stores two control bits
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.b8008_types.all;

entity interrupt_ready_ff is
    port (
        -- Clock (phi2 from clock generator)
        phi2 : in std_logic;

        -- Reset
        reset : in std_logic;

        -- External interrupt request
        int_request : in std_logic;

        -- Clear interrupt (from state timing when entering T1I)
        int_clear : in std_logic;

        -- External ready signal
        ready_in : in std_logic;

        -- Outputs
        interrupt_pending : out std_logic;
        ready_status      : out std_logic
    );
end entity interrupt_ready_ff;

architecture rtl of interrupt_ready_ff is

    signal int_ff   : std_logic := '0';
    signal ready_ff : std_logic := '1';  -- Default ready

begin

    -- Interrupt flip-flop
    process(phi2, reset)
    begin
        if reset = '1' then
            int_ff <= '0';
        elsif rising_edge(phi2) then
            if int_clear = '1' then
                int_ff <= '0';
            elsif int_request = '1' then
                int_ff <= '1';
            end if;
        end if;
    end process;

    -- Ready flip-flop (samples external ready signal)
    process(phi2, reset)
    begin
        if reset = '1' then
            ready_ff <= '1';
        elsif rising_edge(phi2) then
            ready_ff <= ready_in;
        end if;
    end process;

    -- Outputs
    interrupt_pending <= int_ff;
    ready_status      <= ready_ff;

end architecture rtl;

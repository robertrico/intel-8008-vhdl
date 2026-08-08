library ieee;
use ieee.std_logic_1164.all;

entity stack_pointer_miter is
    port (
        clk         : in std_logic;
        phi1_rising : in std_logic;
        reset       : in std_logic;
        stack_push  : in std_logic;
        stack_pop   : in std_logic
    );
end entity stack_pointer_miter;

architecture formal of stack_pointer_miter is
    signal sp_gold, sp_gate : std_logic_vector(2 downto 0);
begin
    gold: entity work.stack_pointer
        port map(
                clk => clk,
                phi1_rising => phi1_rising,
                reset => reset,
                stack_push => stack_push,
                stack_pop => stack_pop,
                sp_out => sp_gold
            );
    gate: entity work.stack_pointer_gate
        port map(
                clk => clk,
                phi1_rising => phi1_rising,
                reset => reset,
                stack_push => stack_push,
                stack_pop => stack_pop,
                sp_out => sp_gate
            );
    default clock is rising_edge(clk);
    assert always (sp_gold = sp_gate);
end architecture formal;
                
                


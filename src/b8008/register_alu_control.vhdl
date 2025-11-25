--------------------------------------------------------------------------------
-- register_alu_control.vhdl
--------------------------------------------------------------------------------
-- Register and ALU Control for Intel 8008
--
-- Controls temporary registers (Reg.a, Reg.b), ALU, and Condition Flags
-- - Generates load signals for temp registers based on timing states
-- - Enables ALU execution during T5 of ALU operations
-- - Updates condition flags after ALU operations
-- - DUMB module: pure timing-based control, no conditional logic
--
-- Based on timing analysis of isa.json
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.b8008_types.all;

entity register_alu_control is
    port (
        -- Clock input from Clock Generator
        phi2 : in std_logic;

        -- Status signals from State Timing Generator (encode T1-T5)
        status_s0 : in std_logic;
        status_s1 : in std_logic;
        status_s2 : in std_logic;

        -- Instruction decoder input
        instr_is_alu_op : in std_logic;

        -- Machine cycle control input
        cycle_is_2 : in std_logic;  -- 0=cycle 1, 1=cycle 2

        -- Interrupt input
        interrupt : in std_logic;

        -- Control outputs (load signals)
        load_reg_a   : out std_logic;  -- Latch data into temp Reg.a
        load_reg_b   : out std_logic;  -- Latch data into temp Reg.b
        alu_enable   : out std_logic;  -- Enable ALU execution
        update_flags : out std_logic;  -- Latch condition flags

        -- Output enable signals (CRITICAL ISSUE #2)
        output_reg_a  : out std_logic;  -- Reg.a drives internal bus
        output_reg_b  : out std_logic;  -- Reg.b drives internal bus
        output_result : out std_logic;  -- ALU result drives internal bus
        output_flags  : out std_logic   -- Flags drive internal bus
    );
end entity register_alu_control;

architecture rtl of register_alu_control is

    -- Decode status signals into T-states
    -- T1:  S2=0, S1=1, S0=0 (binary 010)
    -- T2:  S2=1, S1=0, S0=0 (binary 100)
    -- T3:  S2=0, S1=0, S0=1 (binary 001)
    -- T4:  S2=0, S1=1, S0=1 (binary 011)
    -- T5:  S2=1, S1=0, S0=1 (binary 101)
    -- T1I: S2=1, S1=1, S0=0 (binary 110)
    signal state_is_t1  : std_logic;
    signal state_is_t2  : std_logic;
    signal state_is_t3  : std_logic;
    signal state_is_t4  : std_logic;
    signal state_is_t5  : std_logic;
    signal state_is_t1i : std_logic;

begin

    -- Decode status signals to one-hot state indicators
    state_is_t1  <= '1' when (status_s2 = '0' and status_s1 = '1' and status_s0 = '0') else '0';
    state_is_t2  <= '1' when (status_s2 = '1' and status_s1 = '0' and status_s0 = '0') else '0';
    state_is_t3  <= '1' when (status_s2 = '0' and status_s1 = '0' and status_s0 = '1') else '0';
    state_is_t4  <= '1' when (status_s2 = '0' and status_s1 = '1' and status_s0 = '1') else '0';
    state_is_t5  <= '1' when (status_s2 = '1' and status_s1 = '0' and status_s0 = '1') else '0';
    state_is_t1i <= '1' when (status_s2 = '1' and status_s1 = '1' and status_s0 = '0') else '0';

    -- Timing-based control signal generation
    -- Based on isa.json patterns:
    --
    -- Reg.b loads:
    --   - Every instruction: C1 T3 (fetch instruction to IR and Reg.b)
    --   - ALU OP r: C1 T4 (load SSS register to Reg.b)
    --   - ALU OP I/M: C2 T3 (load immediate/memory data to Reg.b)
    --
    -- Reg.a loads:
    --   - ALU OP r: C1 T4 (load accumulator to Reg.a)
    --   - ALU OP I/M: C2 T3 (load accumulator to Reg.a)
    --
    -- ALU execution:
    --   - ALU OP r: C1 T5
    --   - ALU OP I/M: C2 T5

    -- Load Reg.b: T3 (any cycle) OR T4 (cycle 1 only, for register operands)
    load_reg_b <= (state_is_t3 and phi2) or
                  (state_is_t4 and not cycle_is_2 and phi2);

    -- Load Reg.a: T4 (cycle 1) OR T3 (cycle 2) for ALU operations
    -- Note: Accumulator is loaded when we need it for ALU operations
    load_reg_a <= (state_is_t4 and not cycle_is_2 and instr_is_alu_op and phi2) or
                  (state_is_t3 and cycle_is_2 and instr_is_alu_op and phi2);

    -- ALU enable: T5 during ALU operations
    -- ALU executes on phi2 falling edge (start of phi1.2 period)
    alu_enable <= state_is_t5 and instr_is_alu_op and phi2;

    -- Update flags: Same timing as ALU enable (flags updated after ALU operation)
    update_flags <= state_is_t5 and instr_is_alu_op and phi2;

    -- Output Enable Signals (CRITICAL ISSUE #2)
    --
    -- NOTE: These are currently set to '0' (never drive bus) because in the Intel 8008
    -- architecture, temp registers are internal to the ALU/register side and their
    -- outputs (reg_a_out, reg_b_out) go directly to the ALU inputs, not the internal bus.
    --
    -- The temp registers are loaded FROM the internal bus, but they don't drive it back.
    -- Their purpose is to hold operands for the ALU during phi2 cycle.
    --
    -- If we discover during integration that these need to drive the bus (e.g., for
    -- JMP/CALL address formation), we can update this logic based on instruction decode.
    --
    output_reg_a  <= '0';  -- Temp registers don't drive internal bus in normal operation
    output_reg_b  <= '0';  -- Temp registers don't drive internal bus in normal operation

    -- ALU result drives bus after ALU execution completes
    -- This happens when the ALU result needs to be written to accumulator
    output_result <= state_is_t5 and instr_is_alu_op and phi2;

    -- Flags never drive the internal bus in Intel 8008
    -- Flags are tested internally by condition_flags module
    -- They don't need to be read onto the bus
    output_flags  <= '0';

end architecture rtl;

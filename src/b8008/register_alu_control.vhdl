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

        -- Instruction decoder inputs
        instr_is_alu_op      : in std_logic;  -- ALU operation (for ALU enable)
        instr_uses_temp_regs : in std_logic;  -- Uses Reg.a/Reg.b (ALU ops, JMP, CALL)
        instr_writes_reg     : in std_logic;  -- Instruction writes to register (for MVI output)

        -- Machine cycle control input
        current_cycle : in integer range 1 to 3;

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
    -- T4:  S2=1, S1=1, S0=1 (binary 111)
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
    state_is_t4  <= '1' when (status_s2 = '1' and status_s1 = '1' and status_s0 = '1') else '0';
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

    -- Load Reg.b: T3 (cycles 1-2 only) OR T4 (cycle 1 only, for register operands)
    -- Cycle 1 T3: opcode byte (all instructions)
    -- Cycle 2 T3: immediate/address low byte (for instructions that use temp regs)
    -- Cycle 3 T3: address high byte goes to Reg.a, NOT Reg.b!
    -- Cycle 1 T4: source register operand (for ALU register operations)
    -- NOTE: Don't gate on phi2 here - let the temp registers sample on phi2 rising edge
    load_reg_b <= '1' when (state_is_t3 = '1' and instr_uses_temp_regs = '1' and current_cycle < 3) else
                  '1' when (state_is_t4 = '1' and current_cycle = 1) else
                  '0';

    -- Load Reg.a: T4 (cycle 1) OR T3 (cycle 2 or 3) for instructions using temp regs
    -- Cycle 1 T4: accumulator (for ALU operations)
    -- Cycle 2 T3: accumulator (for ALU immediate/memory operations - NOT for JMP/CALL!)
    -- Cycle 3 T3: address high byte (for JMP/CALL)
    -- For JMP/CALL: only load Reg.a in cycle 3 (high byte), not cycle 2
    -- NOTE: Don't gate on phi2 here - let the temp registers sample on phi2 rising edge
    load_reg_a <= '1' when (state_is_t4 = '1' and current_cycle = 1 and instr_is_alu_op = '1') else
                  '1' when (state_is_t3 = '1' and current_cycle = 2 and instr_is_alu_op = '1') else
                  '1' when (state_is_t3 = '1' and current_cycle = 3 and instr_uses_temp_regs = '1') else
                  '0';

    -- ALU enable: T5 during ALU operations
    -- ALU executes on phi2 falling edge (start of phi1.2 period)
    alu_enable <= state_is_t5 and instr_is_alu_op and phi2;

    -- Update flags: Same timing as ALU enable (flags updated after ALU operation)
    update_flags <= state_is_t5 and instr_is_alu_op and phi2;

    -- Output Enable Signals
    --
    -- Temp registers normally don't drive the internal bus - they hold operands for ALU.
    -- EXCEPTION: For MVI (load register immediate), Reg.b must drive the bus during T4
    -- so the register file can read the immediate value from Reg.b.
    --
    output_reg_a  <= '0';  -- Reg.a never needs to drive bus
    output_reg_b  <= '1' when (state_is_t4 = '1' and current_cycle = 2 and instr_writes_reg = '1' and instr_is_alu_op = '0') else
                     '0';

    -- ALU result drives bus after ALU execution completes
    -- This happens when the ALU result needs to be written to accumulator
    output_result <= state_is_t5 and instr_is_alu_op and phi2;

    -- Flags never drive the internal bus in Intel 8008
    -- Flags are tested internally by condition_flags module
    -- They don't need to be read onto the bus
    output_flags  <= '0';

end architecture rtl;

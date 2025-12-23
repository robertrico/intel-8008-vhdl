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
        instr_is_alu_op       : in std_logic;  -- ALU operation (for ALU enable)
        instr_uses_temp_regs  : in std_logic;  -- Uses Reg.a/Reg.b (register ALU ops, JMP, CALL)
        instr_needs_immediate : in std_logic;  -- Needs immediate byte (for immediate ALU ops, MVI)
        instr_writes_reg      : in std_logic;  -- Instruction writes to register (for MVI output)
        instr_is_write        : in std_logic;  -- Memory write operation (LMr, LMI)
        instr_is_io           : in std_logic;  -- I/O operation (INP, OUT)

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

    -- Load Reg.b: T3 (cycles 1-2) OR T4 (cycle 1 only, for register ALU ops and MOV)
    -- Cycle 1 T3: opcode byte - per isa.json "FETCH INSTR. TO IR & REG.b"
    --             Used for I/O to capture port number for output during cycle 2 T2
    -- Cycle 2 T3: immediate/address low byte (for immediate ALU ops, JMP, CALL, MVI)
    -- Cycle 3 T3: address high byte goes to Reg.a, NOT Reg.b!
    -- Cycle 1 T4: source register operand (for register ALU operations AND MOV register-to-register)
    -- NOTE: Don't gate on phi2 here - let the temp registers sample on phi2 rising edge
    load_reg_b <= '1' when (state_is_t3 = '1' and current_cycle = 1) else  -- All C1 T3: opcode to Reg.b (per isa.json)
                  '1' when (state_is_t3 = '1' and current_cycle = 2 and (instr_uses_temp_regs = '1' or instr_needs_immediate = '1')) else
                  '1' when (state_is_t4 = '1' and current_cycle = 1 and instr_uses_temp_regs = '1' and instr_needs_immediate = '0') else
                  '0';

    -- Debug: Report Reg.b loading (combinational, triggers whenever signals change)
    process(state_is_t3, current_cycle, instr_uses_temp_regs, instr_needs_immediate, load_reg_b)
    begin
        if state_is_t3 = '1' and current_cycle = 2 then
            report "REG_ALU_CTRL: Cycle 2 T3 - instr_uses_temp_regs=" & std_logic'image(instr_uses_temp_regs) &
                   " instr_needs_immediate=" & std_logic'image(instr_needs_immediate) &
                   " load_reg_b=" & std_logic'image(load_reg_b);
        end if;
    end process;

    -- Load Reg.a: ONLY for address high bytes (JMP/CALL cycle 3)
    --
    -- IMPORTANT: Reg.a is NOT used for ALU operands! The accumulator is hardwired
    -- directly to the ALU input. Reg.a is only used for the high byte of jump/call
    -- addresses during 3-cycle instructions.
    --
    -- Cycle 3 T3: address high byte (for JMP/CALL)
    -- NOTE: Don't gate on phi2 here - let the temp registers sample on phi2 rising edge
    load_reg_a <= '1' when (state_is_t3 = '1' and current_cycle = 3 and instr_uses_temp_regs = '1') else
                  '0';

    -- ALU enable: T5 during ALU operations
    -- ALU is combinational, so enable it for the entire T5 state
    -- Result will be stable and ready when register samples at phi2 rising edge
    -- IMPORTANT: For 2-cycle ALU ops (immediate/memory), ALU runs in cycle 2 T5, NOT cycle 1 T5
    -- For 1-cycle ALU ops (register), ALU runs in cycle 1 T5
    alu_enable <= '1' when (state_is_t5 = '1' and instr_is_alu_op = '1' and
                            ((current_cycle = 1 and instr_needs_immediate = '0') or   -- 1-cycle: reg ALU
                             (current_cycle = 2 and instr_needs_immediate = '1')))    -- 2-cycle: imm/mem ALU
                  else '0';

    -- Update flags: Same timing as ALU enable (flags updated after ALU operation)
    -- NOTE: Don't gate with phi2 here - the condition_flags module latches on phi2 rising edge
    update_flags <= '1' when (state_is_t5 = '1' and instr_is_alu_op = '1' and
                              ((current_cycle = 1 and instr_needs_immediate = '0') or   -- 1-cycle: reg ALU
                               (current_cycle = 2 and instr_needs_immediate = '1')))    -- 2-cycle: imm/mem ALU
                    else '0';

    -- Debug: Report when we're trying to update flags
    process(phi2)
    begin
        if rising_edge(phi2) then
            if state_is_t5 = '1' and instr_is_alu_op = '1' then
                report "REG_ALU_CTRL: At T5 with ALU op, update_flags should pulse";
            end if;
        end if;
    end process;

    -- Output Enable Signals
    --
    -- Temp registers normally don't drive the internal bus - they hold operands for ALU.
    -- EXCEPTION:
    -- MOV (register-to-register): Reg.b drives bus at T5 cycle 1 (per isa.json)
    --
    -- Per isa.json, Reg.b is used as intermediate latch for data transfers:
    -- Data loads into Reg.b at T3, then transfers to destination at T5
    --
    output_reg_a  <= '0';  -- Reg.a never needs to drive bus
    -- Reg.b drives bus for:
    -- 1. MOV register-to-register at T5 cycle 1: Reg.b (loaded at T4 from SSS) writes to DDD
    -- 2. LMI (MVI M) at T3 cycle 3: Reg.b (loaded at cycle 2 T3 with immediate) writes to memory
    -- 3. LrI (MVI), LrM, INP at T5 cycle 2: Reg.b (loaded at T3) writes to destination
    --    Per isa.json: T3=DATA TO REG.b, T5=REG.b TO DDD (or REG.A for INP)
    -- 4. I/O cycle 2 T2: Reg.b (contains port number from instruction) outputs to data bus
    --    Per isa.json: INP/OUT cycle 2, T2: "REG.b TO OUT"
    output_reg_b  <= '1' when (state_is_t5 = '1' and current_cycle = 1 and instr_writes_reg = '1' and instr_uses_temp_regs = '1' and
                               instr_is_alu_op = '0' and instr_needs_immediate = '0') else
                     '1' when (state_is_t3 = '1' and current_cycle = 3 and instr_is_write = '1' and instr_needs_immediate = '1') else
                     '1' when (state_is_t5 = '1' and current_cycle = 2 and instr_writes_reg = '1' and
                               instr_is_alu_op = '0' and instr_needs_immediate = '1') else
                     '1' when (state_is_t2 = '1' and current_cycle = 2 and instr_is_io = '1') else  -- I/O T2: port number out
                     '0';

    -- ALU result drives bus during T5 for ALU operations
    -- Keep it on the bus for the entire T5 state so it's stable when register samples
    output_result <= state_is_t5 and instr_is_alu_op;

    -- Flags never drive the internal bus in Intel 8008
    -- Flags are tested internally by condition_flags module
    -- They don't need to be read onto the bus
    output_flags  <= '0';

end architecture rtl;

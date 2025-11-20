-------------------------------------------------------------------------------
-- v8008 Testbench Utilities Package
-------------------------------------------------------------------------------
-- Reusable functions and patterns for v8008 testbenches with sub-phase support
-- Solves data bus multiplexing systematically across all testbenches
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

package v8008_tb_utils is

    -- Instruction type detection functions
    -- Use these to determine when to provide RAM vs ROM data

    function is_alu_m_instr(instr : std_logic_vector(7 downto 0)) return boolean;
    function is_mvi_m_instr(instr : std_logic_vector(7 downto 0)) return boolean;
    function is_memory_read_instr(instr : std_logic_vector(7 downto 0)) return boolean;
    function is_memory_write_instr(instr : std_logic_vector(7 downto 0)) return boolean;
    function is_inp_instr(instr : std_logic_vector(7 downto 0)) return boolean;

    -- Universal data bus selection logic
    -- Returns true if RAM should be provided during T3, false for ROM
    function should_use_ram(
        state : std_logic_vector(2 downto 0);
        cycle : integer;
        instr : std_logic_vector(7 downto 0)
    ) return boolean;

end package v8008_tb_utils;

package body v8008_tb_utils is

    -- ALU M instructions: 10 PPP 111 (PPP = operation, 111 = memory reference)
    -- Opcodes: 0x87 (ADD M), 0x8F (ADC M), 0x97 (SUB M), 0x9F (SBB M),
    --          0xA7 (ANA M), 0xAF (XRA M), 0xB7 (ORA M), 0xBF (CMP M)
    function is_alu_m_instr(instr : std_logic_vector(7 downto 0)) return boolean is
    begin
        return (instr(7 downto 6) = "10" and instr(2 downto 0) = "111");
    end function;

    -- MVI M instruction: 0x3E (00 111 110)
    function is_mvi_m_instr(instr : std_logic_vector(7 downto 0)) return boolean is
    begin
        return (instr = x"3E");
    end function;

    -- INP instruction: 01 00M MM1 (bit 0 = 1, bits 7-6 = 01, bits 4-3 = 00)
    -- Opcodes: 0x41, 0x43, 0x45, 0x47, 0x49, 0x4B, 0x4D, 0x4F
    function is_inp_instr(instr : std_logic_vector(7 downto 0)) return boolean is
    begin
        return (instr(7 downto 6) = "01" and instr(4 downto 3) = "00" and instr(0) = '1');
    end function;

    -- Memory read instructions: need RAM data during cycle 1 T3
    function is_memory_read_instr(instr : std_logic_vector(7 downto 0)) return boolean is
    begin
        return is_alu_m_instr(instr);  -- ALU M reads from memory
        -- Note: MVI M fetches immediate in cycle 1, writes in cycle 2
    end function;

    -- Memory write instructions: write to RAM during cycle 2 T3
    function is_memory_write_instr(instr : std_logic_vector(7 downto 0)) return boolean is
    begin
        return is_mvi_m_instr(instr);  -- MVI M writes to memory in cycle 2
    end function;

    -- Universal decision function for ROM vs RAM selection
    -- Call this during T3 to determine data source
    function should_use_ram(
        state : std_logic_vector(2 downto 0);
        cycle : integer;
        instr : std_logic_vector(7 downto 0)
    ) return boolean is
    begin
        -- Only during T3 (data transfer state) do we multiplex
        if state = "001" then  -- T3: S2S1S0 = 001
            -- Memory read instructions: provide RAM during cycle 1 T3
            if cycle = 1 and is_memory_read_instr(instr) then
                return true;
            end if;
            -- Note: Memory write detection can be added here if needed
            -- if cycle = 2 and is_memory_write_instr(instr) then
            --     return true;  -- Though typically we don't provide data on writes
            -- end if;
        end if;

        -- Default: provide ROM (instruction fetch)
        return false;
    end function;

end package body v8008_tb_utils;

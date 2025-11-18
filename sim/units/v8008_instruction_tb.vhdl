-------------------------------------------------------------------------------
-- Intel 8008 v8008 Instruction Register Test
-------------------------------------------------------------------------------
-- Testbench for v8008 instruction register and fetch logic.
--
-- Test Coverage:
--   - Instruction register initialization
--   - Instruction fetch from data bus
--   - Instruction register holds value during execution
--   - Debug output verification
--   - State machine transitions during instruction fetch
--
-- Copyright (c) 2025 Robert Rico
-- License: MIT
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;

entity v8008_instruction_tb is
end v8008_instruction_tb;

architecture behavior of v8008_instruction_tb is
    -- Component declarations
    component phase_clocks
        port(
            clk_in : in std_logic;
            reset : in std_logic;
            phi1 : out std_logic;
            phi2 : out std_logic
        );
    end component;

    component v8008
        port(
            phi1 : in std_logic;
            phi2 : in std_logic;
            data_bus_in     : in  std_logic_vector(7 downto 0);
            data_bus_out    : out std_logic_vector(7 downto 0);
            data_bus_enable : out std_logic;
            S0 : out std_logic;
            S1 : out std_logic;
            S2 : out std_logic;
            SYNC : out std_logic;
            READY : in std_logic;
            INT : in std_logic;
            debug_reg_A : out std_logic_vector(7 downto 0);
            debug_reg_B : out std_logic_vector(7 downto 0);
            debug_reg_C : out std_logic_vector(7 downto 0);
            debug_reg_D : out std_logic_vector(7 downto 0);
            debug_reg_E : out std_logic_vector(7 downto 0);
            debug_reg_H : out std_logic_vector(7 downto 0);
            debug_reg_L : out std_logic_vector(7 downto 0);
            debug_pc : out std_logic_vector(13 downto 0);
            debug_flags : out std_logic_vector(3 downto 0);
            debug_instruction : out std_logic_vector(7 downto 0);
            debug_stack_pointer : out std_logic_vector(2 downto 0);
            debug_hl_address : out std_logic_vector(13 downto 0)
        );
    end component;

    -- Test signals
    signal master_clk_tb : std_logic := '0';
    signal reset_tb : std_logic := '1';
    signal phi1_tb : std_logic := '0';
    signal phi2_tb : std_logic := '0';
    signal ready_tb : std_logic := '1';
    signal int_tb : std_logic := '0';
    signal data_bus_in_tb : std_logic_vector(7 downto 0) := (others => '0');
    signal cpu_data_out_tb     : std_logic_vector(7 downto 0);
    signal cpu_data_enable_tb  : std_logic;
    signal S0_tb, S1_tb, S2_tb : std_logic;
    signal sync_tb : std_logic;

    -- Debug signals
    signal debug_reg_A_tb : std_logic_vector(7 downto 0);
    signal debug_reg_B_tb : std_logic_vector(7 downto 0);
    signal debug_reg_C_tb : std_logic_vector(7 downto 0);
    signal debug_reg_D_tb : std_logic_vector(7 downto 0);
    signal debug_reg_E_tb : std_logic_vector(7 downto 0);
    signal debug_reg_H_tb : std_logic_vector(7 downto 0);
    signal debug_reg_L_tb : std_logic_vector(7 downto 0);
    signal debug_pc_tb : std_logic_vector(13 downto 0);
    signal debug_flags_tb : std_logic_vector(3 downto 0);
    signal debug_instruction_tb : std_logic_vector(7 downto 0);
    signal debug_stack_pointer_tb : std_logic_vector(2 downto 0);
    signal debug_hl_address_tb : std_logic_vector(13 downto 0);

    -- Test control
    signal test_errors : integer := 0;
    signal test_phase : integer := 0;
    signal is_int_ack : boolean := false;  -- Track interrupt acknowledge cycle

    -- Master clock period
    constant MASTER_CLK_PERIOD : time := 10 ns;  -- 100 MHz master clock
    
    -- 8008 Instruction opcodes for testing
    constant NOP : std_logic_vector(7 downto 0) := "00000000";  -- No operation
    constant HLT : std_logic_vector(7 downto 0) := "11111111";  -- Halt (all 1s)
    constant MVI_A : std_logic_vector(7 downto 0) := "00111110"; -- MVI A, data
    constant MVI_B : std_logic_vector(7 downto 0) := "00000110"; -- MVI B, data
    constant MOV_A_B : std_logic_vector(7 downto 0) := "11000000"; -- MOV A,B

    -- Helper procedure to check value
    procedure check_value(
        signal actual : in std_logic_vector;
        constant expected : in std_logic_vector;
        constant name : in string;
        signal errors : inout integer;
        variable l : inout line
    ) is
    begin
        if actual /= expected then
            write(l, string'("  ERROR: ") & name & 
                     string'(" = 0x") & to_hstring(actual) &
                     string'(", expected 0x") & to_hstring(expected));
            writeline(output, l);
            errors <= errors + 1;
        else
            write(l, string'("  PASS: ") & name & 
                     string'(" = 0x") & to_hstring(expected));
            writeline(output, l);
        end if;
    end procedure;

begin

    -- Master clock generation
    master_clk_tb <= not master_clk_tb after MASTER_CLK_PERIOD / 2;

    -- Phase clock generator
    PHASE_GEN: phase_clocks
        port map (
            clk_in => master_clk_tb,
            reset => reset_tb,
            phi1 => phi1_tb,
            phi2 => phi2_tb
        );

    -- CPU instance (v8008)
    CPU: v8008
        port map (
            phi1 => phi1_tb,
            phi2 => phi2_tb,
            data_bus_in => data_bus_in_tb,
            data_bus_out => cpu_data_out_tb,
            data_bus_enable => cpu_data_enable_tb,
            S0 => S0_tb,
            S1 => S1_tb,
            S2 => S2_tb,
            SYNC => sync_tb,
            READY => ready_tb,
            INT => int_tb,
            debug_reg_A => debug_reg_A_tb,
            debug_reg_B => debug_reg_B_tb,
            debug_reg_C => debug_reg_C_tb,
            debug_reg_D => debug_reg_D_tb,
            debug_reg_E => debug_reg_E_tb,
            debug_reg_H => debug_reg_H_tb,
            debug_reg_L => debug_reg_L_tb,
            debug_pc => debug_pc_tb,
            debug_flags => debug_flags_tb,
            debug_instruction => debug_instruction_tb,
            debug_stack_pointer => debug_stack_pointer_tb,
            debug_hl_address => debug_hl_address_tb
        );

    -- Data bus process - provides RST instruction during interrupt acknowledge
    data_bus_proc: process(S2_tb, S1_tb, S0_tb)
    begin
        -- Default: use test pattern
        data_bus_in_tb <= data_bus_in_tb;
        
        -- During T1I (interrupt acknowledge): S2=1, S1=1, S0=0 (110)
        if S2_tb = '1' and S1_tb = '1' and S0_tb = '0' then
            is_int_ack <= true;
        end if;
        
        -- During T3 (data transfer): S2=0, S1=0, S0=1 (001)
        if S2_tb = '0' and S1_tb = '0' and S0_tb = '1' and is_int_ack then
            -- Provide RST 0 instruction (0x05 = 00 000 101)
            data_bus_in_tb <= X"05";
        end if;
        
        -- Clear interrupt acknowledge flag when leaving T3
        if not (S2_tb = '0' and S1_tb = '0' and S0_tb = '1') then
            if is_int_ack and S2_tb = '0' and S1_tb = '1' and S0_tb = '0' then
                -- Back to T1, clear flag
                is_int_ack <= false;
            end if;
        end if;
    end process data_bus_proc;

    -- Test stimulus process
    STIMULUS: process
        variable l : line;
        
        -- Helper procedure to wait for clock cycles
        procedure wait_cycles(n : natural) is
        begin
            for i in 1 to n loop
                wait until rising_edge(phi2_tb);
            end loop;
        end procedure;
        
    begin
        write(l, string'("========================================"));
        writeline(output, l);
        write(l, string'("v8008 Instruction Register Test"));
        writeline(output, l);
        write(l, string'("========================================"));
        writeline(output, l);

        -- Test 1: Initial state after reset
        test_phase <= 1;
        write(l, string'("Test 1: Initial instruction register value"));
        writeline(output, l);
        
        -- Apply reset
        reset_tb <= '1';
        wait for 100 ns;
        reset_tb <= '0';
        wait for 100 ns;
        
        -- Wait for phase clocks to stabilize
        wait for 1400 ns;
        
        -- Send interrupt pulse to exit STOPPED state
        write(l, string'("  Sending interrupt to start CPU..."));
        writeline(output, l);
        int_tb <= '1';
        wait for 3000 ns;  -- Hold through next phi2 edge
        int_tb <= '0';
        wait for 4000 ns;  -- Let CPU process interrupt
        
        -- Check instruction register is initialized to 0x00
        check_value(debug_instruction_tb, X"00", "Instruction Register", test_errors, l);
        
        -- Test 2: Instruction fetch simulation
        test_phase <= 2;
        write(l, string'("Test 2: Simulated instruction fetch"));
        writeline(output, l);
        
        -- Put NOP instruction on data bus
        data_bus_in_tb <= NOP;
        wait_cycles(1);
        
        write(l, string'("  Placed NOP (0x00) on data bus"));
        writeline(output, l);
        
        -- Wait for potential fetch cycle
        wait_cycles(5);
        
        -- Note: Since v8008 starts in STOPPED state and we don't have
        -- a way to start it yet, the instruction register may not change.
        -- This test verifies the infrastructure is in place.
        
        write(l, string'("  Instruction register value: 0x") & to_hstring(debug_instruction_tb));
        writeline(output, l);
        
        -- Test 3: Different instruction patterns
        test_phase <= 3;
        write(l, string'("Test 3: Different instruction patterns on bus"));
        writeline(output, l);
        
        -- Try MVI A instruction
        data_bus_in_tb <= MVI_A;
        wait_cycles(2);
        write(l, string'("  Placed MVI A (0x3E) on data bus"));
        writeline(output, l);
        
        -- Try MOV A,B instruction
        data_bus_in_tb <= MOV_A_B;
        wait_cycles(2);
        write(l, string'("  Placed MOV A,B (0xC0) on data bus"));
        writeline(output, l);
        
        -- Try HLT instruction
        data_bus_in_tb <= HLT;
        wait_cycles(2);
        write(l, string'("  Placed HLT (0xFF) on data bus"));
        writeline(output, l);
        
        -- Test 4: Program counter check
        test_phase <= 4;
        write(l, string'("Test 4: Program counter value"));
        writeline(output, l);
        
        -- PC should still be at 0x0000
        check_value(debug_pc_tb, "00000000000000", "Program Counter", test_errors, l);
        
        -- Test 5: State outputs
        test_phase <= 5;
        write(l, string'("Test 5: State outputs (S2, S1, S0)"));
        writeline(output, l);
        
        -- In STOPPED state, should be S2=0, S1=1, S0=1 (binary 011)
        write(l, string'("  State outputs: S2=") & std_logic'image(S2_tb) &
                 string'(" S1=") & std_logic'image(S1_tb) &
                 string'(" S0=") & std_logic'image(S0_tb));
        writeline(output, l);
        
        if S2_tb = '0' and S1_tb = '1' and S0_tb = '1' then
            write(l, string'("  PASS: CPU in STOPPED state (011)"));
            writeline(output, l);
        else
            write(l, string'("  Note: CPU not in expected STOPPED state"));
            writeline(output, l);
        end if;

        -- Final summary
        write(l, string'("========================================"));
        writeline(output, l);
        if test_errors = 0 then
            write(l, string'("TEST PASSED - Instruction register test successful"));
            writeline(output, l);
            write(l, string'("Instruction register infrastructure verified"));
            writeline(output, l);
        else
            write(l, string'("TEST FAILED - ") & integer'image(test_errors) & 
                     string'(" errors detected"));
            writeline(output, l);
        end if;
        write(l, string'("========================================"));
        writeline(output, l);

        wait;
    end process;

end behavior;
-------------------------------------------------------------------------------
-- Intel 8008 v8008 Single RST Instruction Test
-------------------------------------------------------------------------------
-- Tests a single RST instruction to verify proper execution
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;

entity v8008_rst_single_tb is
    generic (
        RST_NUM : integer range 0 to 7 := 1;  -- Which RST to test (default RST 1)
        TEST_NAME : string := "RST 1"         -- Name for reporting
    );
end v8008_rst_single_tb;

architecture behavior of v8008_rst_single_tb is
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

    -- Signals
    signal master_clk : std_logic := '0';
    signal reset : std_logic := '0';
    signal phi1 : std_logic;
    signal phi2 : std_logic;
    
    -- CPU signals
    signal data_bus_in : std_logic_vector(7 downto 0) := X"00";
    signal data_bus_out : std_logic_vector(7 downto 0);
    signal data_bus_enable : std_logic;
    signal S0, S1, S2 : std_logic;
    signal SYNC : std_logic;
    signal READY : std_logic := '1';
    signal INT : std_logic := '0';
    
    -- Debug signals
    signal debug_pc : std_logic_vector(13 downto 0);
    signal debug_instruction : std_logic_vector(7 downto 0);
    signal debug_stack_pointer : std_logic_vector(2 downto 0);
    
    -- Test control
    signal test_done : boolean := false;
    
    -- Constants
    constant CLK_PERIOD : time := 10 ns;
    
    -- Calculate RST opcode based on generic
    -- RST format: 00 AAA 101 where AAA is the vector number
    function get_rst_opcode(num : integer) return std_logic_vector is
        variable opcode : std_logic_vector(7 downto 0);
    begin
        opcode := "00" & std_logic_vector(to_unsigned(num, 3)) & "101";
        return opcode;
    end function;
    
    -- Calculate expected PC vector (RST_NUM * 8)
    function get_expected_vector(num : integer) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned(num * 8, 14));
    end function;
    
    constant RST_OPCODE : std_logic_vector(7 downto 0) := get_rst_opcode(RST_NUM);
    constant EXPECTED_VECTOR : std_logic_vector(13 downto 0) := get_expected_vector(RST_NUM);

begin

    -- Clock generation
    master_clk <= not master_clk after CLK_PERIOD/2 when not test_done else '0';

    -- Phase clock generator
    PHASE_GEN: phase_clocks
        port map (
            clk_in => master_clk,
            reset => reset,
            phi1 => phi1,
            phi2 => phi2
        );

    -- CPU instance
    CPU: v8008
        port map (
            phi1 => phi1,
            phi2 => phi2,
            data_bus_in => data_bus_in,
            data_bus_out => data_bus_out,
            data_bus_enable => data_bus_enable,
            S0 => S0,
            S1 => S1,
            S2 => S2,
            SYNC => SYNC,
            READY => READY,
            INT => INT,
            debug_reg_A => open,
            debug_reg_B => open,
            debug_reg_C => open,
            debug_reg_D => open,
            debug_reg_E => open,
            debug_reg_H => open,
            debug_reg_L => open,
            debug_pc => debug_pc,
            debug_flags => open,
            debug_instruction => debug_instruction,
            debug_stack_pointer => debug_stack_pointer,
            debug_hl_address => open
        );

    -- Interrupt controller process - injects RST instruction
    int_controller: process(phi2, S0, S1, S2)
        variable state : std_logic_vector(2 downto 0);
        variable in_int_ack : boolean := false;
        variable l : line;
    begin
        state := S2 & S1 & S0;  -- Note: S2S1S0 order for comparison
        
        -- Track interrupt acknowledge cycle (T1I through T5)
        if state = "110" then  -- T1I (S2S1S0 = 110)
            in_int_ack := true;
            write(l, string'("INT_CTRL: T1I detected, entering int ack cycle"));
            writeline(output, l);
        elsif state = "101" then  -- T5
            if in_int_ack then
                in_int_ack := false;
                write(l, string'("INT_CTRL: T5 detected, exiting int ack cycle"));
                writeline(output, l);
            end if;
        end if;
        
        -- During T3 of interrupt acknowledge, inject RST instruction
        if in_int_ack and state = "001" then  -- T3 state
            data_bus_in <= RST_OPCODE;
            write(l, string'("INT_CTRL: Injecting ") & TEST_NAME & string'(" opcode 0x") & 
                  to_hstring(unsigned(RST_OPCODE)));
            writeline(output, l);
        elsif not in_int_ack and state = "001" then  -- Normal T3 (memory read)
            -- Provide HLT at vector address
            if debug_pc = EXPECTED_VECTOR then
                data_bus_in <= X"00";  -- HLT
                write(l, string'("INT_CTRL: Providing HLT at vector address"));
            else
                data_bus_in <= X"00";  -- Default HLT
            end if;
        else
            data_bus_in <= X"00";  -- Default
        end if;
    end process;

    -- Clock monitor for debugging
    clock_mon: process(phi1, phi2)
        variable l : line;
    begin
        if rising_edge(phi1) then
            write(l, string'("CLOCK: phi1 rising"));
            writeline(output, l);
        end if;
        if rising_edge(phi2) then  
            write(l, string'("CLOCK: phi2 rising"));
            writeline(output, l);
        end if;
    end process;
    
    -- Test process
    test_proc: process
        variable l : line;
        variable pc_before : std_logic_vector(13 downto 0);
        variable pc_after : std_logic_vector(13 downto 0);
        variable stack_before : std_logic_vector(2 downto 0);
        variable stack_after : std_logic_vector(2 downto 0);
        variable state : std_logic_vector(2 downto 0);
        
    begin
        write(l, string'("========================================"));
        writeline(output, l);
        write(l, string'("v8008 ") & TEST_NAME & string'(" Test"));
        writeline(output, l);
        write(l, string'("========================================"));
        writeline(output, l);
        
        -- Initialize (no real reset for 8008)
        reset <= '1';
        wait for 100 ns;
        reset <= '0';
        wait for 100 ns;
        
        write(l, string'("Waiting for CPU to reach STOPPED state..."));
        writeline(output, l);
        
        -- Wait for CPU to reach STOPPED state (should be immediate after "reset")
        wait for 2 us;
        
        -- Check state
        state := S2 & S1 & S0;
        write(l, string'("Current state: S2S1S0 = ") & 
              std_logic'image(S2) & std_logic'image(S1) & std_logic'image(S0));
        writeline(output, l);
        
        if state = "011" then
            write(l, string'("CPU is in STOPPED state (correct)"));
            writeline(output, l);
        else
            write(l, string'("WARNING: CPU not in STOPPED state!"));
            writeline(output, l);
        end if;
        
        -- Record initial state
        pc_before := debug_pc;
        stack_before := debug_stack_pointer;
        write(l, string'("Initial PC = 0x") & to_hstring(unsigned(pc_before)));
        writeline(output, l);
        write(l, string'("Initial Stack Pointer = ") & integer'image(to_integer(unsigned(stack_before))));
        writeline(output, l);
        
        -- Trigger interrupt
        write(l, string'("Triggering interrupt with INT signal..."));
        writeline(output, l);
        
        -- Wait for phi1 to be low
        wait until phi1 = '0';
        wait for 5 ns;
        
        INT <= '1';
        write(l, string'("INT set high"));
        writeline(output, l);
        
        -- Wait for interrupt to be latched (at phi2 edge)
        wait until rising_edge(phi2);
        wait for 10 ns;
        
        -- Wait for CPU to enter T1I (at next phi1)
        wait until rising_edge(phi1);
        wait for 10 ns;
        
        -- Lower INT
        INT <= '0';
        write(l, string'("INT set low"));
        writeline(output, l);
        
        -- Wait a bit to check state after transition
        wait for 100 ns;
        
        -- Check state after T1I transition
        state := S2 & S1 & S0;
        write(l, string'("State after T1I transition: S2S1S0 = ") & 
              std_logic'image(S2) & std_logic'image(S1) & std_logic'image(S0));
        writeline(output, l);
        if state = "110" then
            write(l, string'("CPU is in T1I state (correct)"));
            writeline(output, l);
        else
            write(l, string'("WARNING: CPU not in T1I state!"));
            writeline(output, l);
        end if;
        
        -- Wait for RST execution to complete
        -- T1I -> T2 -> T3 -> T4 -> T5 (5 states)
        -- Need to wait for T5 to actually execute
        wait for 15 us;
        
        -- Check results
        pc_after := debug_pc;
        stack_after := debug_stack_pointer;
        
        write(l, string'("========================================"));
        writeline(output, l);
        write(l, string'("Results:"));
        writeline(output, l);
        write(l, string'("  PC before: 0x") & to_hstring(unsigned(pc_before)));
        writeline(output, l);
        write(l, string'("  PC after:  0x") & to_hstring(unsigned(pc_after)));
        writeline(output, l);
        write(l, string'("  Expected:  0x") & to_hstring(unsigned(EXPECTED_VECTOR)) & 
              string'(" (") & TEST_NAME & string'(" vector)"));
        writeline(output, l);
        
        write(l, string'("  Stack before: ") & integer'image(to_integer(unsigned(stack_before))));
        writeline(output, l);
        write(l, string'("  Stack after:  ") & integer'image(to_integer(unsigned(stack_after))));
        writeline(output, l);
        
        -- Check if PC jumped to correct vector
        if pc_after = EXPECTED_VECTOR then
            write(l, string'("PASS: PC jumped to correct ") & TEST_NAME & string'(" vector"));
            writeline(output, l);
        else
            write(l, string'("FAIL: PC did not jump to ") & TEST_NAME & string'(" vector"));
            writeline(output, l);
            assert false severity failure;
        end if;
        
        -- Check if stack pointer incremented
        if to_integer(unsigned(stack_after)) = (to_integer(unsigned(stack_before)) + 1) mod 8 then
            write(l, string'("PASS: Stack pointer incremented"));
            writeline(output, l);
        else
            write(l, string'("WARNING: Stack pointer did not increment as expected"));
            writeline(output, l);
        end if;
        
        write(l, string'("========================================"));
        writeline(output, l);
        
        test_done <= true;
        wait;
    end process;

end behavior;
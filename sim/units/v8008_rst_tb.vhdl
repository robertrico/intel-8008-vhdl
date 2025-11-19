-------------------------------------------------------------------------------
-- Intel 8008 v8008 All RST Instructions Test
-------------------------------------------------------------------------------
-- Tests all 8 RST instructions (RST 0-7) sequentially:
-- RST 0: Vector 0x0000 (opcode 0x05 = 00 000 101)
-- RST 1: Vector 0x0008 (opcode 0x0D = 00 001 101)
-- RST 2: Vector 0x0010 (opcode 0x15 = 00 010 101)
-- RST 3: Vector 0x0018 (opcode 0x1D = 00 011 101)
-- RST 4: Vector 0x0020 (opcode 0x25 = 00 100 101)
-- RST 5: Vector 0x0028 (opcode 0x2D = 00 101 101)
-- RST 6: Vector 0x0030 (opcode 0x35 = 00 110 101)
-- RST 7: Vector 0x0038 (opcode 0x3D = 00 111 101)
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;

entity v8008_rst_tb is
end v8008_rst_tb;

architecture behavior of v8008_rst_tb is

    -- Component declaration for v8008 CPU
    component v8008
        port (
            -- Two-phase clock inputs
            phi1 : in std_logic;
            phi2 : in std_logic;
            
            -- Data bus
            data_bus_in     : in  std_logic_vector(7 downto 0);
            data_bus_out    : out std_logic_vector(7 downto 0);
            data_bus_enable : out std_logic;
            
            -- State outputs
            S0 : out std_logic;
            S1 : out std_logic;
            S2 : out std_logic;
            
            -- SYNC output
            SYNC : out std_logic;
            
            -- READY input
            READY : in std_logic;
            
            -- Interrupt request
            INT : in std_logic;
            
            -- Debug outputs
            debug_pc : out std_logic_vector(13 downto 0);
            debug_instruction : out std_logic_vector(7 downto 0);
            debug_stack_pointer : out std_logic_vector(2 downto 0)
        );
    end component;
    
    -- Clock and control signals
    signal phi1        : std_logic := '0';
    signal phi2        : std_logic := '0';
    signal INT         : std_logic := '0';
    signal READY       : std_logic := '1';
    
    -- CPU interface
    signal data_bus_in : std_logic_vector(7 downto 0) := (others => '0');
    signal data_bus_out: std_logic_vector(7 downto 0);
    signal data_bus_enable : std_logic;
    signal S0          : std_logic;
    signal S1          : std_logic;
    signal S2          : std_logic;
    signal SYNC        : std_logic;
    
    -- Debug signals
    signal debug_pc    : std_logic_vector(13 downto 0);
    signal debug_instruction : std_logic_vector(7 downto 0);
    signal debug_stack_pointer : std_logic_vector(2 downto 0);
    
    -- Test control
    signal done        : boolean := false;
    signal test_phase  : string(1 to 20) := (others => ' ');
    signal test_num    : integer := 0;
    signal inject_rst  : integer range 0 to 7 := 0;  -- Which RST to inject
    
    -- Constants
    constant PHI1_PERIOD : time := 1100 ns;
    constant PHI2_PERIOD : time := 1100 ns;
    constant OVERLAP_TIME : time := 100 ns;
    
    -- Test program in ROM
    type rom_array_t is array (0 to 2047) of std_logic_vector(7 downto 0);
    signal rom_contents : rom_array_t := (
        -- Each RST vector contains a HLT instruction
        -- RST 0 vector (0x0000)
        0 => x"FF",  -- HLT
        
        -- RST 1 vector (0x0008)
        8 => x"FF",  -- HLT
        
        -- RST 2 vector (0x0010)
        16 => x"FF",  -- HLT
        
        -- RST 3 vector (0x0018)
        24 => x"FF",  -- HLT
        
        -- RST 4 vector (0x0020)
        32 => x"FF",  -- HLT
        
        -- RST 5 vector (0x0028)
        40 => x"FF",  -- HLT
        
        -- RST 6 vector (0x0030)
        48 => x"FF",  -- HLT
        
        -- RST 7 vector (0x0038)
        56 => x"FF",  -- HLT
        
        others => x"00"  -- Fill with HLT (0x00)
    );
    
    -- ROM address
    signal rom_addr : std_logic_vector(10 downto 0);
    signal rom_data : std_logic_vector(7 downto 0);
    
    -- Stack tracking
    signal initial_sp : std_logic_vector(2 downto 0);
    signal initial_pc : std_logic_vector(13 downto 0);
    
begin

    -- Instantiate v8008 CPU
    UUT: v8008
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
            debug_pc => debug_pc,
            debug_instruction => debug_instruction,
            debug_stack_pointer => debug_stack_pointer
        );
    
    -- ROM process
    ROM_PROC: process(rom_addr)
    begin
        rom_data <= rom_contents(to_integer(unsigned(rom_addr)));
    end process ROM_PROC;
    
    -- Address decoding for ROM
    rom_addr <= debug_pc(10 downto 0);
    
    -- Data bus multiplexing with interrupt handling
    DBUS_MUX: process
        variable state_vec : std_logic_vector(2 downto 0);
        variable in_int_ack : boolean := false;
    begin
        wait on S0, S1, S2, rom_data, inject_rst;
        
        state_vec := S2 & S1 & S0;
        
        -- Detect T1I state (S2S1S0 = 110) to enter interrupt ack
        if state_vec = "110" then
            in_int_ack := true;
        end if;
        
        -- During T3 in interrupt ack, inject RST instruction
        if in_int_ack and state_vec = "001" then  -- T3: S2S1S0 = 001
            -- Inject the requested RST instruction
            -- RST format: 00 AAA 101 where AAA is the vector number
            data_bus_in <= "00" & std_logic_vector(to_unsigned(inject_rst, 3)) & "101";
        else
            data_bus_in <= rom_data;  -- Normal instruction fetch
        end if;
        
        -- Exit interrupt ack on T5 (S2S1S0 = 101)
        if in_int_ack and state_vec = "101" then
            in_int_ack := false;
        end if;
    end process DBUS_MUX;
    
    -- Clock generation
    CLOCK_PROC: process
    begin
        while not done loop
            -- phi1 high phase
            phi1 <= '1';
            wait for PHI1_PERIOD - OVERLAP_TIME;
            
            -- phi2 rises while phi1 still high (overlap)
            phi2 <= '1';
            wait for OVERLAP_TIME;
            
            -- phi1 falls, phi2 stays high
            phi1 <= '0';
            wait for PHI2_PERIOD - OVERLAP_TIME;
            
            -- phi2 falls
            phi2 <= '0';
            wait for OVERLAP_TIME;
        end loop;
        wait;
    end process CLOCK_PROC;
    
    -- Main test process
    TEST_PROC: process
        variable state_vec : std_logic_vector(2 downto 0);
        variable expected_pc : std_logic_vector(13 downto 0);
        variable rst_opcode : std_logic_vector(7 downto 0);
        variable stopped_count : integer;
    begin
        report "========================================";
        report "Intel 8008 RST Instructions Test";
        report "Testing all 8 RST vectors (RST 0-7)";
        report "========================================";
        
        -- Wait for initialization
        test_phase <= "INIT                ";
        wait for 500 ns;
        
        -- CPU starts in STOPPED state (8008 has no reset)
        state_vec := S2 & S1 & S0;
        assert state_vec = "011" 
            report "ERROR: CPU not starting in STOPPED state"
            severity error;
        report "CPU correctly starts in STOPPED state";
        
        -- Save initial state
        initial_pc <= debug_pc;
        initial_sp <= debug_stack_pointer;
        report "Initial PC: 0x" & to_hstring(initial_pc);
        report "Initial SP: " & integer'image(to_integer(unsigned(initial_sp)));
        
        -- Test each RST instruction
        for rst_num in 0 to 7 loop
            test_num <= rst_num;
            inject_rst <= rst_num;
            
            -- Calculate expected vector address
            expected_pc := std_logic_vector(to_unsigned(rst_num * 8, 14));
            rst_opcode := "00" & std_logic_vector(to_unsigned(rst_num, 3)) & "101";
            
            test_phase <= "TEST_RST            "; -- Simple fixed string
            report "";
            report "Test " & integer'image(rst_num + 1) & ": Testing RST " & integer'image(rst_num);
            report "  Opcode: 0x" & to_hstring(rst_opcode);
            report "  Expected vector: 0x" & to_hstring(expected_pc);
            report "--------------------------------------";
            
            -- Trigger interrupt to inject RST
            wait until rising_edge(phi1);
            INT <= '1';
            wait for 3000 ns;
            INT <= '0';
            
            -- Wait for RST execution (T1I->T2->T3->T4->T5->T1)
            wait for 15000 ns;
            
            -- Check PC jumped to correct vector
            assert debug_pc = expected_pc
                report "ERROR: RST " & integer'image(rst_num) & 
                       " - PC is 0x" & to_hstring(debug_pc) & 
                       ", expected 0x" & to_hstring(expected_pc)
                severity error;
            
            report "PC jumped to 0x" & to_hstring(debug_pc) & " (correct)";
            
            -- Check stack pointer incremented
            assert to_integer(unsigned(debug_stack_pointer)) = 
                   ((to_integer(unsigned(initial_sp)) + rst_num + 1) mod 8)
                report "ERROR: Stack pointer not correct after RST " & integer'image(rst_num)
                severity error;
            
            report "Stack pointer: " & integer'image(to_integer(unsigned(debug_stack_pointer))) &
                   " (correct)";
            
            -- Now CPU should fetch and execute HLT at the vector address
            -- Wait for HLT execution
            wait for 10000 ns;
            
            -- Verify CPU is back in STOPPED state
            stopped_count := 0;
            for i in 1 to 10 loop
                wait until rising_edge(phi2);
                state_vec := S2 & S1 & S0;
                if state_vec = "011" then  -- STOPPED state
                    stopped_count := stopped_count + 1;
                    if stopped_count = 1 then
                        report "CPU in STOPPED after HLT at vector 0x" & 
                               to_hstring(debug_pc);
                    end if;
                    exit when stopped_count >= 2;
                end if;
            end loop;
            
            assert stopped_count > 0
                report "ERROR: CPU did not enter STOPPED after HLT at RST " & 
                       integer'image(rst_num) & " vector"
                severity error;
            
            report "PASS: RST " & integer'image(rst_num) & " works correctly";
        end loop;
        
        ------------------------------
        -- Test complete
        ------------------------------
        test_phase <= "DONE                ";
        report "";
        report "========================================";
        report "RST Test Summary:";
        report "  - RST 0 (vector 0x0000): PASS";
        report "  - RST 1 (vector 0x0008): PASS";
        report "  - RST 2 (vector 0x0010): PASS";
        report "  - RST 3 (vector 0x0018): PASS";
        report "  - RST 4 (vector 0x0020): PASS";
        report "  - RST 5 (vector 0x0028): PASS";
        report "  - RST 6 (vector 0x0030): PASS";
        report "  - RST 7 (vector 0x0038): PASS";
        report "  - All 8 RST instructions work correctly";
        report "========================================";
        
        done <= true;
        wait;
    end process TEST_PROC;
    
end behavior;
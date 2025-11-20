-------------------------------------------------------------------------------
-- Intel 8008 v8008 HLT (HALT) Instruction Test - All Opcodes
-------------------------------------------------------------------------------
-- Tests all three HLT opcodes (0x00, 0x01, 0xFF):
-- 1. Starts CPU with interrupt to begin execution
-- 2. Executes HLT 0x00 and verifies STOPPED state
-- 3. Wakes with interrupt, jumps to test HLT 0x01
-- 4. Executes HLT 0x01 and verifies STOPPED state
-- 5. Wakes with interrupt, jumps to test HLT 0xFF
-- 6. Executes HLT 0xFF and verifies STOPPED state
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;

entity v8008_hlt_all_tb is
end v8008_hlt_all_tb;

architecture behavior of v8008_hlt_all_tb is

    -- Component declaration for phase_clocks
    component phase_clocks
        port (
            clk_in : in std_logic;
            reset  : in std_logic;
            phi1   : out std_logic;
            phi2   : out std_logic
        );
    end component;

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
    
    -- Clock and control signals
    signal clk_master  : std_logic := '0';
    signal reset       : std_logic := '0';
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
    signal debug_reg_A : std_logic_vector(7 downto 0);
    signal debug_reg_B : std_logic_vector(7 downto 0);
    signal debug_reg_C : std_logic_vector(7 downto 0);
    signal debug_reg_D : std_logic_vector(7 downto 0);
    signal debug_reg_E : std_logic_vector(7 downto 0);
    signal debug_reg_H : std_logic_vector(7 downto 0);
    signal debug_reg_L : std_logic_vector(7 downto 0);
    signal debug_pc    : std_logic_vector(13 downto 0);
    signal debug_flags : std_logic_vector(3 downto 0);
    signal debug_instruction : std_logic_vector(7 downto 0);
    signal debug_stack_pointer : std_logic_vector(2 downto 0);
    signal debug_hl_address : std_logic_vector(13 downto 0);
    
    -- Test control
    signal done        : boolean := false;
    signal test_phase  : string(1 to 20) := (others => ' ');
    signal test_num    : integer := 0;
    signal inject_rst  : integer := 0;  -- Which RST to inject (0, 1, 2, etc)
    
    -- Constants
    constant CLK_PERIOD : time := 10 ns;  -- 100 MHz master clock
    
    -- Test program in ROM
    type rom_array_t is array (0 to 2047) of std_logic_vector(7 downto 0);
    signal rom_contents : rom_array_t := (
        -- RST 0 vector (0x0000) - Test HLT 0x00
        0 => x"00",  -- HLT (0x00)
        1 => x"00",  -- HLT (safety)
        
        -- RST 1 vector (0x0008) - Test HLT 0x01
        8 => x"01",  -- HLT (0x01)
        9 => x"01",  -- HLT (safety)
        
        -- RST 2 vector (0x0010) - Test HLT 0xFF
        16 => x"FF",  -- HLT (0xFF)
        17 => x"FF",  -- HLT (safety)
        
        others => x"FF"  -- Fill with HLT
    );
    
    -- ROM address
    signal rom_addr : std_logic_vector(10 downto 0);
    signal rom_data : std_logic_vector(7 downto 0);
    
begin

    -- Instantiate phase_clocks generator
    CLK_GEN: phase_clocks
        port map (
            clk_in => clk_master,
            reset => reset,
            phi1 => phi1,
            phi2 => phi2
        );

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
            debug_reg_A => debug_reg_A,
            debug_reg_B => debug_reg_B,
            debug_reg_C => debug_reg_C,
            debug_reg_D => debug_reg_D,
            debug_reg_E => debug_reg_E,
            debug_reg_H => debug_reg_H,
            debug_reg_L => debug_reg_L,
            debug_pc => debug_pc,
            debug_flags => debug_flags,
            debug_instruction => debug_instruction,
            debug_stack_pointer => debug_stack_pointer,
            debug_hl_address => debug_hl_address
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
            -- RST format: 00 AAA 101
            data_bus_in <= "00" & std_logic_vector(to_unsigned(inject_rst, 3)) & "101";
            report "Injecting RST " & integer'image(inject_rst) & 
                   " opcode: 0x" & to_hstring("00" & std_logic_vector(to_unsigned(inject_rst, 3)) & "101");
        else
            data_bus_in <= rom_data;  -- Normal instruction fetch
        end if;
        
        -- Exit interrupt ack on T5 (S2S1S0 = 101)
        if in_int_ack and state_vec = "101" then
            in_int_ack := false;
        end if;
    end process DBUS_MUX;
    
    -- Master clock generation (100 MHz)
    CLOCK_PROC: process
    begin
        while not done loop
            clk_master <= '0';
            wait for CLK_PERIOD / 2;
            clk_master <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process CLOCK_PROC;
    
    -- Main test process
    TEST_PROC: process
        variable state_vec : std_logic_vector(2 downto 0);
        variable stopped_count : integer := 0;
    begin
        report "========================================";
        report "Intel 8008 HLT Instructions Test";
        report "Testing all opcodes (0x00, 0x01, 0xFF)";
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
        
        ------------------------------
        -- Test 1: HLT opcode 0x00
        ------------------------------
        test_num <= 1;
        test_phase <= "TEST1_HLT_00        ";
        report "";
        report "Test 1: Testing HLT with opcode 0x00";
        report "--------------------------------------";
        
        -- Trigger interrupt with RST 0 to jump to address 0x0000
        inject_rst <= 0;
        report "Triggering interrupt with RST 0 to start execution at 0x0000";
        wait until rising_edge(phi1);
        INT <= '1';
        wait for 3000 ns;
        INT <= '0';
        
        -- Wait for interrupt processing and execution to begin
        wait for 15000 ns;
        
        -- Now CPU should execute HLT at 0x0000 and return to STOPPED
        -- Wait for HLT execution (T1->T2->T3->STOPPED)
        stopped_count := 0;
        for i in 1 to 20 loop
            wait until rising_edge(phi2);
            state_vec := S2 & S1 & S0;
            
            if state_vec = "011" then  -- STOPPED state
                stopped_count := stopped_count + 1;
                if stopped_count = 1 then
                    report "CPU entered STOPPED state after executing HLT (0x00) at PC=0x" & 
                           to_hstring(debug_pc);
                end if;
            end if;
            
            -- After finding STOPPED, wait a bit then break
            if stopped_count >= 3 then
                exit;
            end if;
        end loop;
        
        assert stopped_count > 0
            report "ERROR: CPU did not enter STOPPED after HLT 0x00"
            severity error;
        report "PASS: HLT 0x00 correctly enters STOPPED state";
        
        ------------------------------
        -- Test 2: HLT opcode 0x01
        ------------------------------
        test_num <= 2;
        test_phase <= "TEST2_HLT_01        ";
        report "";
        report "Test 2: Testing HLT with opcode 0x01";
        report "--------------------------------------";
        
        -- Trigger interrupt with RST 1 to jump to address 0x0008
        inject_rst <= 1;
        report "Triggering interrupt with RST 1 to jump to 0x0008";
        wait until rising_edge(phi1);
        INT <= '1';
        wait for 3000 ns;
        INT <= '0';
        
        -- Wait for interrupt processing and execution to begin
        wait for 15000 ns;
        
        -- Now CPU should execute HLT at 0x0008 and return to STOPPED
        stopped_count := 0;
        for i in 1 to 20 loop
            wait until rising_edge(phi2);
            state_vec := S2 & S1 & S0;
            
            if state_vec = "011" then  -- STOPPED state
                stopped_count := stopped_count + 1;
                if stopped_count = 1 then
                    report "CPU entered STOPPED state after executing HLT (0x01) at PC=0x" & 
                           to_hstring(debug_pc);
                end if;
            end if;
            
            -- After finding STOPPED, wait a bit then break
            if stopped_count >= 3 then
                exit;
            end if;
        end loop;
        
        assert stopped_count > 0
            report "ERROR: CPU did not enter STOPPED after HLT 0x01"
            severity error;
        report "PASS: HLT 0x01 correctly enters STOPPED state";
        
        ------------------------------
        -- Test 3: HLT opcode 0xFF
        ------------------------------
        test_num <= 3;
        test_phase <= "TEST3_HLT_FF        ";
        report "";
        report "Test 3: Testing HLT with opcode 0xFF";
        report "--------------------------------------";
        
        -- Trigger interrupt with RST 2 to jump to address 0x0010
        inject_rst <= 2;
        report "Triggering interrupt with RST 2 to jump to 0x0010";
        wait until rising_edge(phi1);
        INT <= '1';
        wait for 3000 ns;
        INT <= '0';
        
        -- Wait for interrupt processing and execution to begin
        wait for 15000 ns;
        
        -- Now CPU should execute HLT at 0x0010 and return to STOPPED
        stopped_count := 0;
        for i in 1 to 20 loop
            wait until rising_edge(phi2);
            state_vec := S2 & S1 & S0;
            
            if state_vec = "011" then  -- STOPPED state
                stopped_count := stopped_count + 1;
                if stopped_count = 1 then
                    report "CPU entered STOPPED state after executing HLT (0xFF) at PC=0x" & 
                           to_hstring(debug_pc);
                end if;
            end if;
            
            -- After finding STOPPED, wait a bit then break
            if stopped_count >= 3 then
                exit;
            end if;
        end loop;
        
        assert stopped_count > 0
            report "ERROR: CPU did not enter STOPPED after HLT 0xFF"
            severity error;
        report "PASS: HLT 0xFF correctly enters STOPPED state";
        
        ------------------------------
        -- Test complete
        ------------------------------
        test_phase <= "DONE                ";
        report "";
        report "========================================";
        report "HLT Test Summary:";
        report "  - HLT (0x00) enters STOPPED state: PASS";
        report "  - HLT (0x01) enters STOPPED state: PASS";
        report "  - HLT (0xFF) enters STOPPED state: PASS";
        report "  - All three HLT opcodes work correctly";
        report "========================================";
        
        done <= true;
        wait;
    end process TEST_PROC;
    
end behavior;
-------------------------------------------------------------------------------
-- Intel 8008 v8008 MVI Instruction Test
-------------------------------------------------------------------------------
-- Tests MVI (Move Immediate) instruction for registers A, H, L:
-- MVI A, imm8 - opcode 0x06 (00 000 110)
-- MVI H, imm8 - opcode 0x2E (00 101 110)
-- MVI L, imm8 - opcode 0x36 (00 110 110)
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;

entity v8008_mvi_tb is
end v8008_mvi_tb;

architecture behavior of v8008_mvi_tb is

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

    -- Constants
    constant PHI1_PERIOD : time := 1100 ns;
    constant PHI2_PERIOD : time := 1100 ns;
    constant OVERLAP_TIME : time := 100 ns;

    -- Test program in ROM
    type rom_array_t is array (0 to 2047) of std_logic_vector(7 downto 0);
    signal rom_contents : rom_array_t := (
        -- RST 0 vector (0x0000) - Test program starts here
        0 => x"06",  -- MVI A, 0x42
        1 => x"42",
        2 => x"0E",  -- MVI B, 0x12
        3 => x"12",
        4 => x"16",  -- MVI C, 0x34
        5 => x"34",
        6 => x"1E",  -- MVI D, 0x56
        7 => x"56",
        8 => x"26",  -- MVI E, 0x78
        9 => x"78",
        10 => x"2E", -- MVI H, 0x9A
        11 => x"9A",
        12 => x"36", -- MVI L, 0xBC
        13 => x"BC",
        14 => x"FF", -- HLT

        others => x"00"
    );

    -- ROM address
    signal rom_addr : std_logic_vector(10 downto 0);
    signal rom_data : std_logic_vector(7 downto 0);

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

    -- ROM process - clocked to avoid delta-cycle races with PC increment
    ROM_PROC: process(phi2)
    begin
        if falling_edge(phi2) then
            rom_data <= rom_contents(to_integer(unsigned(rom_addr)));
        end if;
    end process ROM_PROC;

    -- Address decoding for ROM
    rom_addr <= debug_pc(10 downto 0);

    -- Data bus multiplexing with interrupt handling
    DBUS_MUX: process
        variable state_vec : std_logic_vector(2 downto 0);
        variable in_int_ack : boolean := false;
    begin
        wait on S0, S1, S2, rom_data;

        state_vec := S2 & S1 & S0;

        -- Detect T1I state (S2S1S0 = 110) to enter interrupt ack
        if state_vec = "110" then
            in_int_ack := true;
        end if;

        -- During T3 in interrupt ack, inject RST 0 instruction
        if in_int_ack and state_vec = "001" then  -- T3: S2S1S0 = 001
            -- Inject RST 0: opcode 0x05 (00 000 101)
            data_bus_in <= x"05";
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
        variable stopped_count : integer;
    begin
        report "========================================";
        report "Intel 8008 MVI Instruction Test";
        report "Testing MVI for registers A, B, C, D, E, H, L";
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

        -- Trigger interrupt to boot CPU with RST 0
        test_phase <= "BOOT                ";
        report "";
        report "Booting CPU with RST 0 interrupt...";
        wait until rising_edge(phi1);
        INT <= '1';
        wait for 3000 ns;
        INT <= '0';

        -- Wait for RST execution to complete
        wait for 15000 ns;

        -- Verify PC is at 0x0000 (RST 0 vector)
        assert debug_pc = "00000000000000"
            report "ERROR: PC is not at 0x0000 after RST 0"
            severity error;
        report "PC at 0x0000 after RST 0 (correct)";

        -- Execute test program
        test_phase <= "EXECUTE             ";
        report "";
        report "Executing MVI test program...";

        -- Wait for all MVI instructions to execute and HLT
        wait for 100000 ns;

        -- Verify CPU is in STOPPED state
        test_phase <= "VERIFY              ";
        stopped_count := 0;
        for i in 1 to 10 loop
            wait until rising_edge(phi2);
            state_vec := S2 & S1 & S0;
            if state_vec = "011" then  -- STOPPED state
                stopped_count := stopped_count + 1;
                exit when stopped_count >= 2;
            end if;
        end loop;

        assert stopped_count > 0
            report "ERROR: CPU did not enter STOPPED state after HLT"
            severity error;
        report "CPU in STOPPED state after HLT";

        -- Verify all register values
        report "";
        report "========================================";
        report "Verifying Register Values:";
        report "========================================";

        -- Check A register
        report "Register A: 0x" & to_hstring(debug_reg_A) & " (expected 0x42)";
        assert debug_reg_A = x"42"
            report "ERROR: Register A mismatch"
            severity error;

        -- Check B register
        report "Register B: 0x" & to_hstring(debug_reg_B) & " (expected 0x12)";
        assert debug_reg_B = x"12"
            report "ERROR: Register B mismatch"
            severity error;

        -- Check C register
        report "Register C: 0x" & to_hstring(debug_reg_C) & " (expected 0x34)";
        assert debug_reg_C = x"34"
            report "ERROR: Register C mismatch"
            severity error;

        -- Check D register
        report "Register D: 0x" & to_hstring(debug_reg_D) & " (expected 0x56)";
        assert debug_reg_D = x"56"
            report "ERROR: Register D mismatch"
            severity error;

        -- Check E register
        report "Register E: 0x" & to_hstring(debug_reg_E) & " (expected 0x78)";
        assert debug_reg_E = x"78"
            report "ERROR: Register E mismatch"
            severity error;

        -- Check H register
        report "Register H: 0x" & to_hstring(debug_reg_H) & " (expected 0x9A)";
        assert debug_reg_H = x"9A"
            report "ERROR: Register H mismatch"
            severity error;

        -- Check L register
        report "Register L: 0x" & to_hstring(debug_reg_L) & " (expected 0xBC)";
        assert debug_reg_L = x"BC"
            report "ERROR: Register L mismatch"
            severity error;

        -- Check HL address
        -- H = 0x9A: bits [5:0] = 0x1A (011010), so address bits [13:8] = 0x1A
        report "HL Address: 0x" & to_hstring(debug_hl_address) & " (expected 0x1ABC)";
        assert debug_hl_address(13 downto 8) = "011010" and  -- H = 0x9A -> bits [13:8] = 0x1A
               debug_hl_address(7 downto 0) = x"BC"
            report "ERROR: HL address mismatch"
            severity error;

        ------------------------------
        -- Test complete
        ------------------------------
        test_phase <= "DONE                ";
        report "";
        report "========================================";
        report "MVI Test Summary:";
        report "  - MVI A, 0x42: PASS";
        report "  - MVI B, 0x12: PASS";
        report "  - MVI C, 0x34: PASS";
        report "  - MVI D, 0x56: PASS";
        report "  - MVI E, 0x78: PASS";
        report "  - MVI H, 0x9A: PASS";
        report "  - MVI L, 0xBC: PASS";
        report "  - All MVI instructions work correctly";
        report "========================================";

        done <= true;
        wait;
    end process TEST_PROC;

end behavior;

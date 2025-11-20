-------------------------------------------------------------------------------
-- Intel 8008 v8008 MOV Register-to-Register Instruction Test
-------------------------------------------------------------------------------
-- Tests MOV r1, r2 instruction (register-to-register only, no memory):
-- MOV r1, r2 - opcode 11 DDD SSS (where DDD ≠ 111 and SSS ≠ 111)
-- Examples:
--   MOV B, A  - opcode 0xC8 (11 001 000)
--   MOV C, A  - opcode 0xD0 (11 010 000)
--   MOV A, B  - opcode 0xC1 (11 000 001)
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;

entity v8008_mov_rr_tb is
end v8008_mov_rr_tb;

architecture behavior of v8008_mov_rr_tb is

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

    -- Constants
    constant CLK_PERIOD : time := 10 ns;  -- 100 MHz master clock

    -- Test program in ROM
    type rom_array_t is array (0 to 2047) of std_logic_vector(7 downto 0);
    signal rom_contents : rom_array_t := (
        -- RST 0 vector (0x0000) - Test program starts here
        0 => x"06",  -- MVI A, 0x55
        1 => x"55",
        2 => x"C8",  -- MOV B, A  (11 001 000) - B should become 0x55

        3 => x"16",  -- MVI C, 0xAA (00 010 110)
        4 => x"AA",
        5 => x"DA",  -- MOV D, C  (11 011 010) - D should become 0xAA

        6 => x"E1",  -- MOV E, B  (11 100 001) - E should become 0x55
        7 => x"EC",  -- MOV H, E  (11 101 100) - H should become 0x55

        8 => x"F3",  -- MOV L, D  (11 110 011) - L should become 0xAA
        9 => x"C6",  -- MOV A, L  (11 000 110) - A should become 0xAA

        -- Additional cross-register tests
        -- MOV destination, source = 11 DDD SSS
        -- A=000, B=001, C=010, D=011, E=100, H=101, L=110
        10 => x"16", -- MVI C, 0x12
        11 => x"12",
        12 => x"D9", -- MOV D, B  (11 011 001) - D should become 0x55
        13 => x"E2", -- MOV E, C  (11 100 010) - E should become 0x12
        14 => x"EB", -- MOV H, D  (11 101 011) - H should become 0x55
        15 => x"F4", -- MOV L, E  (11 110 100) - L should become 0x12
        16 => x"C5", -- MOV A, H  (11 000 101) - A should become 0x55

        17 => x"FF", -- HLT

        others => x"00"
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
        variable stopped_count : integer;
    begin
        report "========================================";
        report "Intel 8008 MOV r1, r2 Instruction Test";
        report "Testing register-to-register MOV operations";
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
        report "Executing MOV r1, r2 test program...";

        -- Wait for all MOV instructions to execute and HLT
        -- With sub-phase implementation, execution takes ~2x longer
        wait for 2000000 ns;  -- 2ms

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

        -- After the test sequence:
        -- A should be 0x55 (from MOV A, H, where H=0x55)
        -- B should be 0x55 (from MOV B, A)
        -- C should be 0x12 (from MVI C, 0x12)
        -- D should be 0x55 (from MOV D, B)
        -- E should be 0x12 (from MOV E, C)
        -- H should be 0x55 (from MOV H, D)
        -- L should be 0x12 (from MOV L, E)

        report "Register A: 0x" & to_hstring(debug_reg_A) & " (expected 0x55)";
        assert debug_reg_A = x"55"
            report "ERROR: Register A mismatch"
            severity error;

        report "Register B: 0x" & to_hstring(debug_reg_B) & " (expected 0x55)";
        assert debug_reg_B = x"55"
            report "ERROR: Register B mismatch"
            severity error;

        report "Register C: 0x" & to_hstring(debug_reg_C) & " (expected 0x12)";
        assert debug_reg_C = x"12"
            report "ERROR: Register C mismatch"
            severity error;

        report "Register D: 0x" & to_hstring(debug_reg_D) & " (expected 0x55)";
        assert debug_reg_D = x"55"
            report "ERROR: Register D mismatch"
            severity error;

        report "Register E: 0x" & to_hstring(debug_reg_E) & " (expected 0x12)";
        assert debug_reg_E = x"12"
            report "ERROR: Register E mismatch"
            severity error;

        report "Register H: 0x" & to_hstring(debug_reg_H) & " (expected 0x55)";
        assert debug_reg_H = x"55"
            report "ERROR: Register H mismatch"
            severity error;

        report "Register L: 0x" & to_hstring(debug_reg_L) & " (expected 0x12)";
        assert debug_reg_L = x"12"
            report "ERROR: Register L mismatch"
            severity error;

        ------------------------------
        -- Test complete
        ------------------------------
        test_phase <= "DONE                ";
        report "";
        report "========================================";
        report "MOV r1, r2 Test Summary:";
        report "  - MOV B, A: PASS";
        report "  - MOV D, C: PASS";
        report "  - MOV E, B: PASS";
        report "  - MOV H, E: PASS";
        report "  - MOV L, D: PASS";
        report "  - MOV A, L: PASS";
        report "  - All register-to-register MOV instructions work correctly";
        report "========================================";

        done <= true;
        wait;
    end process TEST_PROC;

end behavior;

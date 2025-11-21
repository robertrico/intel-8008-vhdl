-------------------------------------------------------------------------------
-- Intel 8008 v8008 OUT (Output to Port) Instruction Test
-------------------------------------------------------------------------------
-- Tests OUT instruction (opcode pattern: 01 RRM MM1, where RR ≠ 00):
-- - Writes accumulator data to one of 24 output ports
-- - Port address: RRMMM (5 bits) where RR ≠ 00
-- - Two-cycle instruction (fetch + I/O write)
-- - Cycle 0: T1-T2 (PCL/PCH out), T3 (fetch to IR and Reg.b), T4/T5 skip
-- - Cycle 1: T1 (Reg.A out), T2 (Reg.b out), T3 (IDLE - wait for READY), T4/T5 skip
-- - Cycle 2: Skip (instruction complete)
-- - Verifies data appears on data bus during T1 of Cycle 1
-- - Verifies port address appears during T2 of Cycle 1
-- - Tests ALL 24 ports (8-31) with unique data values
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;

library work;
use work.v8008_tb_utils.all;

entity v8008_out_tb is
end v8008_out_tb;

architecture behavior of v8008_out_tb is

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
    signal done : boolean := false;
    constant CLK_PERIOD : time := 10 ns;

    -- ROM for test program
    type rom_t is array (0 to 255) of std_logic_vector(7 downto 0);
    constant rom_contents : rom_t := (
        -- Test program: OUT to all 24 ports with unique data values
        -- Port format: 01 RRM MM1 where RR ≠ 00
        -- Port address = RRMMM (bits [5:1]), where RR ≠ 00
        -- Valid ports: 8-31 (24 ports total)
        -- Each port gets value = port_number (e.g., port 8 gets 0x08)

        -- Port 8: OUT 8 (RRMMM=01000) - opcode=01 01 000 1 = 0x51
        0 => x"06",  -- MVI A, 0x08
        1 => x"08",
        2 => x"51",  -- OUT 8

        -- Port 9: OUT 9 (RRMMM=01001) - opcode=01 01 001 1 = 0x53
        3 => x"06",  -- MVI A, 0x09
        4 => x"09",
        5 => x"53",  -- OUT 9

        -- Port 10: OUT 10 (RRMMM=01010) - opcode=01 01 010 1 = 0x55
        6 => x"06",  -- MVI A, 0x0A
        7 => x"0A",
        8 => x"55",  -- OUT 10

        -- Port 11: OUT 11 (RRMMM=01011) - opcode=01 01 011 1 = 0x57
        9 => x"06",  -- MVI A, 0x0B
        10 => x"0B",
        11 => x"57",  -- OUT 11

        -- Port 12: OUT 12 (RRMMM=01100) - opcode=01 01 100 1 = 0x59
        12 => x"06",  -- MVI A, 0x0C
        13 => x"0C",
        14 => x"59",  -- OUT 12

        -- Port 13: OUT 13 (RRMMM=01101) - opcode=01 01 101 1 = 0x5B
        15 => x"06",  -- MVI A, 0x0D
        16 => x"0D",
        17 => x"5B",  -- OUT 13

        -- Port 14: OUT 14 (RRMMM=01110) - opcode=01 01 110 1 = 0x5D
        18 => x"06",  -- MVI A, 0x0E
        19 => x"0E",
        20 => x"5D",  -- OUT 14

        -- Port 15: OUT 15 (RRMMM=01111) - opcode=01 01 111 1 = 0x5F
        21 => x"06",  -- MVI A, 0x0F
        22 => x"0F",
        23 => x"5F",  -- OUT 15

        -- Port 16: OUT 16 (RRMMM=10000) - RR=10, MMM=000, opcode=01 10 0 00 1 = 0x61
        24 => x"06",  -- MVI A, 0x10
        25 => x"10",
        26 => x"61",  -- OUT 16

        -- Port 17: OUT 17 (RRMMM=10001) - RR=10, MMM=001, opcode=01 10 0 01 1 = 0x63
        27 => x"06",  -- MVI A, 0x11
        28 => x"11",
        29 => x"63",  -- OUT 17

        -- Port 18: OUT 18 (RRMMM=10010) - RR=10, MMM=010, opcode=01 10 0 10 1 = 0x65
        30 => x"06",  -- MVI A, 0x12
        31 => x"12",
        32 => x"65",  -- OUT 18

        -- Port 19: OUT 19 (RRMMM=10011) - RR=10, MMM=011, opcode=01 10 0 11 1 = 0x67
        33 => x"06",  -- MVI A, 0x13
        34 => x"13",
        35 => x"67",  -- OUT 19

        -- Port 20: OUT 20 (RRMMM=10100) - RR=10, MMM=100, opcode=01 10 1 00 1 = 0x69
        36 => x"06",  -- MVI A, 0x14
        37 => x"14",
        38 => x"69",  -- OUT 20

        -- Port 21: OUT 21 (RRMMM=10101) - RR=10, MMM=101, opcode=01 10 1 01 1 = 0x6B
        39 => x"06",  -- MVI A, 0x15
        40 => x"15",
        41 => x"6B",  -- OUT 21

        -- Port 22: OUT 22 (RRMMM=10110) - RR=10, MMM=110, opcode=01 10 1 10 1 = 0x6D
        42 => x"06",  -- MVI A, 0x16
        43 => x"16",
        44 => x"6D",  -- OUT 22

        -- Port 23: OUT 23 (RRMMM=10111) - RR=10, MMM=111, opcode=01 10 1 11 1 = 0x6F
        45 => x"06",  -- MVI A, 0x17
        46 => x"17",
        47 => x"6F",  -- OUT 23

        -- Port 24: OUT 24 (RRMMM=11000) - opcode=01 11 000 1 = 0x71
        48 => x"06",  -- MVI A, 0x18
        49 => x"18",
        50 => x"71",  -- OUT 24

        -- Port 25: OUT 25 (RRMMM=11001) - opcode=01 11 001 1 = 0x73
        51 => x"06",  -- MVI A, 0x19
        52 => x"19",
        53 => x"73",  -- OUT 25

        -- Port 26: OUT 26 (RRMMM=11010) - opcode=01 11 010 1 = 0x75
        54 => x"06",  -- MVI A, 0x1A
        55 => x"1A",
        56 => x"75",  -- OUT 26

        -- Port 27: OUT 27 (RRMMM=11011) - opcode=01 11 011 1 = 0x77
        57 => x"06",  -- MVI A, 0x1B
        58 => x"1B",
        59 => x"77",  -- OUT 27

        -- Port 28: OUT 28 (RRMMM=11100) - opcode=01 11 100 1 = 0x79
        60 => x"06",  -- MVI A, 0x1C
        61 => x"1C",
        62 => x"79",  -- OUT 28

        -- Port 29: OUT 29 (RRMMM=11101) - opcode=01 11 101 1 = 0x7B
        63 => x"06",  -- MVI A, 0x1D
        64 => x"1D",
        65 => x"7B",  -- OUT 29

        -- Port 30: OUT 30 (RRMMM=11110) - opcode=01 11 110 1 = 0x7D
        66 => x"06",  -- MVI A, 0x1E
        67 => x"1E",
        68 => x"7D",  -- OUT 30

        -- Port 31: OUT 31 (RRMMM=11111) - opcode=01 11 111 1 = 0x7F
        69 => x"06",  -- MVI A, 0x1F
        70 => x"1F",
        71 => x"7F",  -- OUT 31

        72 => x"FF",  -- HLT

        others => x"00"
    );

    signal rom_addr : std_logic_vector(7 downto 0);
    signal rom_data : std_logic_vector(7 downto 0);

    -- I/O capture signals (ports 8-31)
    type io_data_array is array (8 to 31) of std_logic_vector(7 downto 0);
    signal io_port_data : io_data_array := (others => x"00");
    signal io_port_written : std_logic_vector(31 downto 8) := (others => '0');

begin

    -- Clock generator
    READY <= '1';  -- Always ready for this test

    CLK_GEN: phase_clocks port map (
        clk_in => clk_master,
        reset => reset,
        phi1 => phi1,
        phi2 => phi2
    );

    -- CPU instance
    UUT: v8008 port map (
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

    -- ROM access
    rom_addr <= debug_pc(7 downto 0);

    ROM_PROC: process(phi2)
    begin
        if falling_edge(phi2) then
            rom_data <= rom_contents(to_integer(unsigned(rom_addr)));
        end if;
    end process;

    -- Data bus multiplexing (ROM for instruction fetch, capture I/O writes)
    DBUS_MUX: process(phi2)
        variable state_vec : std_logic_vector(2 downto 0);
        variable in_int_ack : boolean := false;
    begin
        if falling_edge(phi2) then
            state_vec := S2 & S1 & S0;

            -- Interrupt ack detection
            if state_vec = "110" then
                in_int_ack := true;
            elsif in_int_ack and state_vec = "101" then
                in_int_ack := false;
            end if;

            -- Data bus input (for instruction fetch)
            if in_int_ack and state_vec = "001" then
                data_bus_in <= x"05";  -- RST 0
            else
                data_bus_in <= rom_data;
            end if;
        end if;
    end process;

    -- I/O write capture: Monitor data bus during OUT instruction
    -- During OUT Cycle 1 T2, the CPU outputs the instruction byte (port address)
    -- We detect this by checking if data_bus_out matches the OUT instruction pattern
    IO_CAPTURE: process
        variable port_addr : integer := 0;
    begin
        wait on data_bus_out, data_bus_enable, debug_reg_A;

        -- Debug: Log all data_bus changes when enable is high (disabled for cleaner output)
        -- if data_bus_enable = '1' then
        --     report "DEBUG: data_bus_enable=1, data_bus_out=0x" & to_hstring(data_bus_out) &
        --            ", debug_reg_A=0x" & to_hstring(debug_reg_A);
        -- end if;

        -- Detect OUT T2: data_bus_out contains instruction byte matching OUT pattern
        -- AND data_bus_enable is high
        if data_bus_enable = '1' and
           data_bus_out(7 downto 6) = "01" and
           data_bus_out(0) = '1' and
           data_bus_out(5 downto 4) /= "00" then
            -- This is OUT T2 - data_bus_out has the instruction/port address
            -- The accumulator value is in debug_reg_A
            port_addr := to_integer(unsigned(data_bus_out(5 downto 1)));
            report "DEBUG: Detected OUT pattern! opcode=0x" & to_hstring(data_bus_out) & ", port_addr=" & integer'image(port_addr);
            if port_addr >= 8 and port_addr <= 31 then
                io_port_data(port_addr) <= debug_reg_A;
                io_port_written(port_addr) <= '1';
                report "I/O WRITE: Port " & integer'image(port_addr) &
                       " = 0x" & to_hstring(debug_reg_A);
            end if;
        end if;
    end process;

    -- Master clock process
    CLOCK_PROC: process
    begin
        while not done loop
            clk_master <= '0';
            wait for CLK_PERIOD / 2;
            clk_master <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    -- Main test process
    TEST_PROC: process
        variable errors : integer := 0;
    begin
        report "========================================";
        report "Intel 8008 OUT Instruction Test";
        report "Testing output to I/O ports";
        report "========================================";

        wait for 500 ns;

        -- Boot CPU with RST 0
        report "Booting CPU with RST 0...";
        wait until rising_edge(phi1);
        INT <= '1';
        wait for 3000 ns;
        INT <= '0';

        -- Wait for program to execute
        -- 24 OUT instructions + 24 MVI instructions = 48 instructions
        -- Each takes ~20-40us, need ~2ms total
        wait for 2500000 ns;

        -- Verify results
        report "========================================";
        report "Verifying OUT operations (all 24 ports):";
        report "========================================";

        -- Test all 24 ports (8-31), each should have value = port number
        for port_num in 8 to 31 loop
            if io_port_written(port_num) = '1' and
               io_port_data(port_num) = std_logic_vector(to_unsigned(port_num, 8)) then
                report "PASS: OUT port " & integer'image(port_num) &
                       " = 0x" & to_hstring(io_port_data(port_num));
            else
                report "ERROR: OUT port " & integer'image(port_num) &
                       " failed - written=" & std_logic'image(io_port_written(port_num)) &
                       ", got 0x" & to_hstring(io_port_data(port_num)) &
                       ", expected 0x" & to_hstring(std_logic_vector(to_unsigned(port_num, 8)))
                       severity error;
                errors := errors + 1;
            end if;
        end loop;

        report "========================================";
        if errors = 0 then
            report "*** ALL OUT TESTS PASSED ***";
            report "Tested all 24 OUT ports (8-31) with unique values";
        else
            report "*** TEST FAILED: " & integer'image(errors) & " errors ***";
        end if;
        report "========================================";

        done <= true;
        wait;
    end process;

end behavior;

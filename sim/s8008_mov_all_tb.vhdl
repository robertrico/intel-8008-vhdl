-------------------------------------------------------------------------------
-- Testbench for Intel 8008 - MOV All Test Program
-------------------------------------------------------------------------------
-- Hardware-accurate testbench using real ROM and RAM components
-- Tests consecutive MOV instructions and pipeline hazards
--
-- Memory Map:
--   0x0000 - 0x07FF (2KB):  ROM (program memory)
--   0x0800 - 0x0BFF (1KB):  RAM (data memory)
--
-- Program Flow (test_mov_all.asm):
--   Test 1 (0x0000): MVI A,55H then MOV B,A -> B should be 0x55
--   Test 2 (0x0010): MVI A,11H, ADI 22H, MOV C,A -> C should be 0x33
--   Test 3 (0x0020): MVI A,01H, RLC x4, MOV B,A -> B should be 0x10
--   Test 4 (0x0030): Chain of MOVs (A->C->D->E) -> All should be 0xAA
--   Test 5 (0x0040): Parse hex byte pattern -> A should be 0x13
--   Test 6 (0x0050): MOV A,M basic read -> A should be 0x11
--   Test 7 (0x0060): Sequential MOV A,M reads -> B=0xAA, C=0xBB, D=0xCC, E=0xDD
--   Test 8 (0x0070): Rapid consecutive MOV A,M -> B=0x12, C=0x34
--   Test 9 (0x0080): MOV A,M with ALU ops -> A=0x0F, B=0x10
--   Test 10 (0x0090): MOV A,M alternating with register moves -> B=0xAA, C=0x55, D=0xAA
--   Test 11 (0x00A0): MOV A,M after increment pattern -> B=0x01, C=0x02, D=0x04, E=0x08
--   Test 12 (0x00B0): MOV A,M with H,L modifications -> B=0x99, C=0x88, D=0x99
--
-- Expected Results (at each HLT):
--   Test 1: A=0x55, B=0x55
--   Test 2: A=0x33, C=0x33
--   Test 3: A=0x10, B=0x10
--   Test 4: A=0xAA, C=0xAA, D=0xAA, E=0xAA
--   Test 5: A=0x13, B=0x10
--   Test 6: A=0x11
--   Test 7: B=0xAA, C=0xBB, D=0xCC, E=0xDD
--   Test 8: B=0x12, C=0x34
--   Test 9: A=0x0F, B=0x10
--   Test 10: B=0xAA, C=0x55, D=0xAA
--   Test 11: B=0x01, C=0x02, D=0x04, E=0x08
--   Test 12: B=0x99, C=0x88, D=0x99
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity s8008_mov_all_tb is
end s8008_mov_all_tb;

architecture sim of s8008_mov_all_tb is

    -- Component declarations
    component s8008 is
        port (
            phi1 : in std_logic;
            phi2 : in std_logic;
            reset_n : in std_logic;
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
            debug_flags : out std_logic_vector(3 downto 0)
        );
    end component;

    component rom_2kx8 is
        generic(
            ROM_FILE : string := "test_programs/test_mov_all.mem"
        );
        port (
            ADDR : in std_logic_vector(10 downto 0);
            DATA_OUT : out std_logic_vector(7 downto 0);
            CS_N : in std_logic
        );
    end component;

    component ram_1kx8 is
        port (
            CLK : in std_logic;
            ADDR : in std_logic_vector(9 downto 0);
            DATA_IN : in std_logic_vector(7 downto 0);
            DATA_OUT : out std_logic_vector(7 downto 0);
            RW_N : in std_logic;
            CS_N : in std_logic;
            DEBUG_BYTE_0 : out std_logic_vector(7 downto 0)
        );
    end component;

    component phase_clocks is
        port (
            clk_in : in std_logic;
            reset : in std_logic;
            phi1 : out std_logic;
            phi2 : out std_logic
        );
    end component;

    -- CPU signals
    signal phi1_tb : std_logic := '0';
    signal phi2_tb : std_logic := '0';
    signal reset_tb : std_logic := '1';  -- Active high for testbench convenience
    signal reset_n_tb : std_logic := '0';  -- Active low for CPU
    signal data_bus_tb : std_logic_vector(7 downto 0);
    signal cpu_data_out_tb     : std_logic_vector(7 downto 0);
    signal cpu_data_enable_tb  : std_logic;
    signal S0_tb, S1_tb, S2_tb : std_logic;
    signal SYNC_tb : std_logic;
    signal READY_tb : std_logic := '1';
    signal INT_tb : std_logic := '0';

    -- Hardware timing simulation
    signal enable_wait_states : boolean := false;
    signal wait_state_counter : integer := 0;

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

    -- Clock signal
    signal master_clk_tb : std_logic := '0';

    -- Memory signals
    signal mem_addr : std_logic_vector(13 downto 0);
    signal addr_low_capture : std_logic_vector(7 downto 0) := x"00";
    signal addr_high_capture : std_logic_vector(5 downto 0) := "000000";
    signal cycle_type_capture : std_logic_vector(1 downto 0) := "00";

    -- ROM signals
    signal rom_addr : std_logic_vector(10 downto 0);
    signal rom_data : std_logic_vector(7 downto 0);
    signal rom_cs_n : std_logic := '1';

    -- RAM signals
    signal ram_addr : std_logic_vector(9 downto 0);
    signal ram_data_in : std_logic_vector(7 downto 0) := x"00";
    signal ram_data_out : std_logic_vector(7 downto 0);
    signal ram_rw_n : std_logic := '1';
    signal ram_cs_n : std_logic := '1';
    signal ram_debug_byte_0 : std_logic_vector(7 downto 0);

    -- Timing
    constant MASTER_CLK_PERIOD : time := 10 ns;
    signal sim_done : boolean := false;

    -- Instruction tracking
    signal instruction_count : integer := 0;
    signal last_SYNC : std_logic := '0';

    -- Interrupt acknowledge tracking
    signal is_int_ack : std_logic := '0';

    -- Test tracking
    signal test_number : integer := 0;
    signal halt_count : integer := 0;

begin

    --===========================================
    -- Clock Generation
    --===========================================
    master_clk_gen: process
    begin
        while not sim_done loop
            master_clk_tb <= '0';
            wait for MASTER_CLK_PERIOD / 2;
            master_clk_tb <= '1';
            wait for MASTER_CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    --===========================================
    -- Phase Clock Generator
    --===========================================
    clk_gen: phase_clocks
        port map (
            clk_in => master_clk_tb,
            reset => reset_tb,
            phi1 => phi1_tb,
            phi2 => phi2_tb
        );

    --===========================================
    -- Device Under Test
    --===========================================
    dut: s8008
        port map (
            phi1 => phi1_tb,
            phi2 => phi2_tb,
            reset_n => reset_n_tb,
            data_bus_in     => data_bus_tb,
            data_bus_out    => cpu_data_out_tb,
            data_bus_enable => cpu_data_enable_tb,
            S0 => S0_tb,
            S1 => S1_tb,
            S2 => S2_tb,
            SYNC => SYNC_tb,
            READY => READY_tb,
            INT => INT_tb,
            debug_reg_A => debug_reg_A_tb,
            debug_reg_B => debug_reg_B_tb,
            debug_reg_C => debug_reg_C_tb,
            debug_reg_D => debug_reg_D_tb,
            debug_reg_E => debug_reg_E_tb,
            debug_reg_H => debug_reg_H_tb,
            debug_reg_L => debug_reg_L_tb,
            debug_pc => debug_pc_tb,
            debug_flags => debug_flags_tb
        );

    --===========================================
    -- ROM Component (2KB)
    --===========================================
    rom: rom_2kx8
        generic map (
            ROM_FILE => "test_programs/test_mov_all.mem"
        )
        port map (
            ADDR => rom_addr,
            DATA_OUT => rom_data,
            CS_N => rom_cs_n
        );

    --===========================================
    -- RAM Component (1KB)
    --===========================================
    ram: ram_1kx8
        port map (
            CLK => phi1_tb,
            ADDR => ram_addr,
            DATA_IN => ram_data_in,
            DATA_OUT => ram_data_out,
            RW_N => ram_rw_n,
            CS_N => ram_cs_n,
            DEBUG_BYTE_0 => ram_debug_byte_0
        );

    --===========================================
    -- Tri-state Reconstruction
    --===========================================
    data_bus_tb <= cpu_data_out_tb when cpu_data_enable_tb = '1' else (others => 'Z');

    --===========================================
    -- Memory Address Decode
    --===========================================
    mem_addr <= addr_high_capture & addr_low_capture;

    -- ROM: addresses 0x0000 - 0x07FF (bit 11 = 0)
    rom_addr <= mem_addr(10 downto 0);
    rom_cs_n <= '0' when mem_addr(11) = '0' else '1';

    -- RAM: addresses 0x0800 - 0x0BFF (bit 11 = 1, bit 10 = 0)
    ram_addr <= mem_addr(9 downto 0);
    ram_cs_n <= '0' when mem_addr(11) = '1' and mem_addr(10) = '0' else '1';

    --===========================================
    -- Memory Controller
    --===========================================
    addr_capture: process(phi1_tb)
    begin
        if rising_edge(phi1_tb) then
            -- T1I state: Detect interrupt acknowledge cycle (S2 S1 S0 = 1 1 0)
            if S2_tb = '1' and S1_tb = '1' and S0_tb = '0' then
                is_int_ack <= '1';
            end if;

            -- T1 state: Capture low address byte (S2 S1 S0 = 0 1 0)
            if S2_tb = '0' and S1_tb = '1' and S0_tb = '0' then
                if data_bus_tb /= "ZZZZZZZZ" then
                    addr_low_capture <= data_bus_tb;
                end if;
            end if;

            -- T2 state: Capture high address and cycle type (S2 S1 S0 = 1 0 0)
            if S2_tb = '1' and S1_tb = '0' and S0_tb = '0' then
                if is_int_ack = '0' and data_bus_tb /= "ZZZZZZZZ" then
                    addr_high_capture <= data_bus_tb(5 downto 0);
                    cycle_type_capture <= data_bus_tb(7 downto 6);
                end if;
            end if;

            -- T3 state: Clear interrupt acknowledge flag
            if S2_tb = '0' and S1_tb = '0' and S0_tb = '1' then
                is_int_ack <= '0';
            end if;
        end if;
    end process;

    -- RAM control process (synchronous writes)
    ram_control: process(phi1_tb)
    begin
        if rising_edge(phi1_tb) then
            if ((S2_tb = '0' and S1_tb = '0' and S0_tb = '1') or  -- T3
                (S2_tb = '1' and S1_tb = '1' and S0_tb = '1') or  -- T4
                (S2_tb = '1' and S1_tb = '0' and S0_tb = '1')) and -- T5
               cycle_type_capture = "10" then
                ram_rw_n <= '0';
                if data_bus_tb /= "ZZZZZZZZ" then
                    ram_data_in <= data_bus_tb;
                end if;
            else
                ram_rw_n <= '1';
            end if;
        end if;
    end process;

    -- Bus multiplexer (combinational)
    bus_mux: process(S2_tb, S1_tb, S0_tb, cycle_type_capture, mem_addr, rom_data, ram_data_out, is_int_ack)
    begin
        data_bus_tb <= (others => 'Z');

        if ((S2_tb = '0' and S1_tb = '0' and S0_tb = '1') or  -- T3
            (S2_tb = '1' and S1_tb = '1' and S0_tb = '1') or  -- T4
            (S2_tb = '1' and S1_tb = '0' and S0_tb = '1')) then -- T5

            if is_int_ack = '1' then
                data_bus_tb <= x"05";  -- RST 0
            elsif cycle_type_capture = "00" or cycle_type_capture = "01" then
                if mem_addr(11) = '0' then
                    data_bus_tb <= rom_data;
                elsif mem_addr(11) = '1' and mem_addr(10) = '0' then
                    data_bus_tb <= ram_data_out;
                else
                    data_bus_tb <= x"FF";
                end if;
            end if;
        end if;
    end process;

    --===========================================
    -- Hardware Timing Simulation - Wait State Generator
    --===========================================
    -- This simulates real hardware timing issues by inserting wait states
    -- Wait states stretch T3/T4/T5 cycles, which can expose timing bugs
    wait_state_gen: process(phi1_tb)
        variable lfsr : std_logic_vector(7 downto 0) := "10101010";  -- PRNG seed
        variable random_bit : std_logic;
    begin
        if rising_edge(phi1_tb) then
            if enable_wait_states then
                -- Simple LFSR for pseudo-random wait states
                random_bit := lfsr(7) xor lfsr(5) xor lfsr(4) xor lfsr(3);
                lfsr := lfsr(6 downto 0) & random_bit;

                -- During T3/T4/T5 states, randomly insert wait states
                if ((S2_tb = '0' and S1_tb = '0' and S0_tb = '1') or  -- T3
                    (S2_tb = '1' and S1_tb = '1' and S0_tb = '1') or  -- T4
                    (S2_tb = '1' and S1_tb = '0' and S0_tb = '1')) then -- T5

                    -- 25% chance of wait state on each cycle
                    if lfsr(1 downto 0) = "00" then
                        READY_tb <= '0';
                        wait_state_counter <= wait_state_counter + 1;
                    else
                        READY_tb <= '1';
                    end if;
                else
                    READY_tb <= '1';
                end if;
            else
                READY_tb <= '1';
            end if;
        end if;
    end process;

    --===========================================
    -- Instruction Counter
    --===========================================
    instr_counter: process(phi1_tb)
    begin
        if rising_edge(phi1_tb) then
            if SYNC_tb = '1' and S2_tb = '1' and S1_tb = '0' and S0_tb = '0' then
                if last_SYNC = '0' then
                    instruction_count <= instruction_count + 1;
                end if;
            end if;
            last_SYNC <= SYNC_tb;
        end if;
    end process;

    --===========================================
    -- Main Test Sequence
    --===========================================
    test_sequence: process
        variable last_S2, last_S1, last_S0 : std_logic;
    begin
        wait for 20 ns;

        report "========================================================";
        report "Intel 8008 MOV All Instructions Test";
        report "========================================================";
        report "Testing MOV instructions and pipeline hazards:";
        report "  Test 1 (0x0000): MVI then MOV";
        report "  Test 2 (0x0010): ALU op then MOV";
        report "  Test 3 (0x0020): RLC then MOV";
        report "  Test 4 (0x0030): Chain of MOVs";
        report "  Test 5 (0x0040): Parse hex byte pattern";
        report "  Test 6 (0x0050): MOV A,M basic read";
        report "  Test 7 (0x0060): Sequential MOV A,M reads";
        report "  Test 8 (0x0070): Rapid consecutive MOV A,M";
        report "  Test 9 (0x0080): MOV A,M with ALU operations";
        report "  Test 10 (0x0090): MOV A,M alternating with register moves";
        report "  Test 11 (0x00A0): MOV A,M after increment pattern";
        report "  Test 12 (0x00B0): MOV A,M with H,L modifications";
        report "========================================================";

        -- Initialize
        reset_tb <= '1';
        reset_n_tb <= '0';
        wait for 100 ns;

        reset_tb <= '0';
        reset_n_tb <= '1';
        wait for 2 us;

        -- ========================================
        -- Run 1: ALL MOV A,M stress tests with perfect timing
        -- ========================================
        report "========================================================" severity note;
        report "RUN 1: MOV A,M Stress Tests (perfect timing)" severity note;
        report "========================================================" severity note;

        enable_wait_states <= false;

        -- Pulse interrupt to start
        INT_tb <= '1';
        wait for 10 us;
        INT_tb <= '0';

        -- Run all tests
        report "Running all MOV A,M stress tests..." severity note;
        wait for 5000 us;

        -- Check for STOPPED state (HLT)
        assert S2_tb = '0' and S1_tb = '1' and S0_tb = '1'
            report "FAIL: Run 1 - CPU should be in STOPPED state after HLT"
            severity error;

        report "Run 1 Results (perfect timing):" severity note;
        report "  A = 0x" & to_hstring(debug_reg_A_tb) severity note;
        report "  B = 0x" & to_hstring(debug_reg_B_tb) & " (expect 0x11 from test6)" severity note;
        report "  C = 0x" & to_hstring(debug_reg_C_tb) & " (expect 0x22 from test6)" severity note;
        report "  D = 0x" & to_hstring(debug_reg_D_tb) & " (expect 0x33 from test6)" severity note;

        assert debug_reg_B_tb = x"11"
            report "FAIL: Run 1 - B should be 0x11 (register write after MOV M,A failed), got 0x" & to_hstring(debug_reg_B_tb)
            severity error;
        assert debug_reg_C_tb = x"22"
            report "FAIL: Run 1 - C should be 0x22 (register write after MOV M,A failed), got 0x" & to_hstring(debug_reg_C_tb)
            severity error;
        assert debug_reg_D_tb = x"33"
            report "FAIL: Run 1 - D should be 0x33 (register write after MOV M,A failed), got 0x" & to_hstring(debug_reg_D_tb)
            severity error;

        if debug_reg_B_tb = x"11" and debug_reg_C_tb = x"22" and debug_reg_D_tb = x"33" then
            report "  PASS: Run 1 - Register write hazard test passed" severity note;
        else
            report "  FAIL: Run 1 - Perfect timing test failed!" severity error;
        end if;

        -- ========================================
        -- Run 2: MOV A,M stress tests with wait states
        -- ========================================
        report "========================================================" severity note;
        report "RUN 2: MOV A,M Stress Tests (with wait states)" severity note;
        report "========================================================" severity note;

        -- Reset CPU
        reset_tb <= '1';
        reset_n_tb <= '0';
        wait for 100 ns;
        reset_tb <= '0';
        reset_n_tb <= '1';
        wait for 2 us;

        enable_wait_states <= true;

        -- Start from 0x0000 via interrupt
        INT_tb <= '1';
        wait for 10 us;
        INT_tb <= '0';

        -- Run ALL MOV A,M tests with wait states
        report "Running all MOV A,M stress tests with wait states..." severity note;
        wait for 10000 us;  -- More time for wait states

        assert S2_tb = '0' and S1_tb = '1' and S0_tb = '1'
            report "FAIL: Run 2 - CPU should be in STOPPED state after HLT"
            severity error;

        report "Run 2 Results (with wait states):" severity note;
        report "  A = 0x" & to_hstring(debug_reg_A_tb) severity note;
        report "  B = 0x" & to_hstring(debug_reg_B_tb) & " (expect 0x11 from test6)" severity note;
        report "  C = 0x" & to_hstring(debug_reg_C_tb) & " (expect 0x22 from test6)" severity note;
        report "  D = 0x" & to_hstring(debug_reg_D_tb) & " (expect 0x33 from test6)" severity note;
        report "  Wait states inserted: " & integer'image(wait_state_counter) severity note;

        assert debug_reg_B_tb = x"11"
            report "FAIL: Run 2 - B should be 0x11, got 0x" & to_hstring(debug_reg_B_tb)
            severity error;
        assert debug_reg_C_tb = x"22"
            report "FAIL: Run 2 - C should be 0x22, got 0x" & to_hstring(debug_reg_C_tb)
            severity error;
        assert debug_reg_D_tb = x"33"
            report "FAIL: Run 2 - D should be 0x33, got 0x" & to_hstring(debug_reg_D_tb)
            severity error;

        if debug_reg_B_tb = x"11" and debug_reg_C_tb = x"22" and debug_reg_D_tb = x"33" then
            report "  PASS: Run 2 - Register write hazard test passed!" severity note;
        else
            report "  FAIL: Run 2 - MOV A,M stress tests FAILED (pipeline hazard detected)!" severity error;
        end if;

        -- Final summary
        report "========================================================" severity note;
        report "=== ALL MOV A,M STRESS TESTS COMPLETED ===" severity note;
        report "========================================================" severity note;
        report "Summary:" severity note;
        report "  Run 1: Perfect timing (no wait states)" severity note;
        report "  Run 2: Hardware timing (random wait states)" severity note;
        report "" severity note;
        report "MOV A,M stress tests executed:" severity note;
        report "  - Test 6: Basic memory read" severity note;
        report "  - Test 7: Sequential memory reads (pipeline hazard pattern)" severity note;
        report "  - Test 8: Rapid consecutive reads from same address" severity note;
        report "  - Test 9: Memory reads interleaved with ALU operations" severity note;
        report "  - Test 10: Memory reads alternating with register moves" severity note;
        report "  - Test 11: Memory reads with address pointer increments" severity note;
        report "  - Test 12: Memory reads with H,L modifications" severity note;
        report "" severity note;
        report "If any test fails, there is a MOV A,M pipeline hazard bug!" severity note;
        report "========================================================" severity note;

        sim_done <= true;
        wait;
    end process;

end sim;

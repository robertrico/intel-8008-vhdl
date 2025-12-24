--------------------------------------------------------------------------------
-- b8008_serial_tb.vhdl
--------------------------------------------------------------------------------
-- Testbench for running sample programs with serial I/O
--
-- This testbench runs unmodified 1970s-era 8008 programs that use:
-- - Port 0: Serial input (IN 0 reads bit 0)
-- - Port 8: Serial output (OUT 8 writes bit 0)
--
-- The testbench:
-- 1. Captures bit-banged serial output and decodes into characters
-- 2. Can provide simulated serial input for interactive programs
-- 3. Reports decoded serial output via VHDL report statements
--
-- Usage: make test-serial PROG=stars_as
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.b8008_types.all;

entity b8008_serial_tb is
    generic (
        ROM_FILE    : string  := "test_programs/samples/hello_8008.mem";
        RUN_TIME_MS : integer := 100;  -- Simulation time in milliseconds
        START_ADDR  : integer := 0     -- Start address (injected as JMP during bootstrap)
    );
end entity b8008_serial_tb;

architecture testbench of b8008_serial_tb is

    -- Component: b8008 CPU
    component b8008 is
        port (
            clk_in         : in std_logic;
            reset          : in std_logic;
            phi1_out       : out std_logic;
            phi2_out       : out std_logic;
            data_bus       : inout std_logic_vector(7 downto 0);
            sync_out       : out std_logic;
            s0_out         : out std_logic;
            s1_out         : out std_logic;
            s2_out         : out std_logic;
            ready_in       : in std_logic;
            interrupt      : in std_logic;
            debug_reg_a         : out std_logic_vector(7 downto 0);
            debug_reg_b         : out std_logic_vector(7 downto 0);
            debug_reg_c         : out std_logic_vector(7 downto 0);
            debug_reg_d         : out std_logic_vector(7 downto 0);
            debug_reg_e         : out std_logic_vector(7 downto 0);
            debug_reg_h         : out std_logic_vector(7 downto 0);
            debug_reg_l         : out std_logic_vector(7 downto 0);
            debug_cycle         : out integer range 1 to 3;
            debug_pc            : out std_logic_vector(13 downto 0);
            debug_ir            : out std_logic_vector(7 downto 0);
            debug_needs_address : out std_logic;
            debug_int_pending   : out std_logic;
            cycle_type          : out std_logic_vector(1 downto 0);
            debug_flag_carry    : out std_logic;
            debug_flag_zero     : out std_logic;
            debug_flag_sign     : out std_logic;
            debug_flag_parity   : out std_logic
        );
    end component;

    -- Component: 4KB ROM
    component rom_4kx8 is
        generic (
            ROM_FILE : string := "test_programs/alu_test_as.mem"
        );
        port (
            ADDR     : in  std_logic_vector(11 downto 0);
            DATA_OUT : out std_logic_vector(7 downto 0);
            CS_N     : in  std_logic
        );
    end component;

    -- Component: 4KB RAM (with file initialization for sample programs)
    component ram_4kx8 is
        generic (
            INIT_FILE : string := ""
        );
        port (
            CLK          : in  std_logic;
            ADDR         : in  std_logic_vector(11 downto 0);
            DATA_IN      : in  std_logic_vector(7 downto 0);
            DATA_OUT     : out std_logic_vector(7 downto 0);
            RW_N         : in  std_logic;
            CS_N         : in  std_logic
        );
    end component;

    -- Component: Serial capture
    component serial_capture is
        generic (
            OUTPUT_FILE : string := "serial_output.txt"
        );
        port (
            clk          : in std_logic;
            reset        : in std_logic;
            port_8_data  : in std_logic_vector(7 downto 0);
            port_8_write : in std_logic;
            char_valid   : out std_logic;
            char_data    : out std_logic_vector(7 downto 0);
            char_count   : out integer
        );
    end component;

    -- Clock and reset
    constant CLK_PERIOD : time := 10 ns;  -- 100 MHz
    signal clk_in       : std_logic := '0';
    signal reset        : std_logic := '1';
    signal test_running : boolean := true;

    -- CPU signals
    signal phi1, phi2   : std_logic;
    signal data_bus     : std_logic_vector(7 downto 0);
    signal sync_out     : std_logic;
    signal s0_out, s1_out, s2_out : std_logic;
    signal interrupt    : std_logic := '0';
    signal cycle_type   : std_logic_vector(1 downto 0);

    -- Debug signals
    signal debug_reg_a, debug_reg_b, debug_reg_c : std_logic_vector(7 downto 0);
    signal debug_reg_d, debug_reg_e : std_logic_vector(7 downto 0);
    signal debug_reg_h, debug_reg_l : std_logic_vector(7 downto 0);
    signal debug_pc : std_logic_vector(13 downto 0);
    signal debug_ir : std_logic_vector(7 downto 0);
    signal debug_cycle : integer range 1 to 3;
    signal debug_needs_address, debug_int_pending : std_logic;
    signal debug_flag_carry, debug_flag_zero : std_logic;
    signal debug_flag_sign, debug_flag_parity : std_logic;

    -- Memory signals
    signal latched_address : std_logic_vector(13 downto 0) := (others => '0');
    signal rom_cs_n : std_logic;
    signal rom_data : std_logic_vector(7 downto 0);
    signal ram_cs_n : std_logic;
    signal ram_data_in : std_logic_vector(7 downto 0);
    signal ram_data_out : std_logic_vector(7 downto 0);
    signal ram_rw_n : std_logic;

    -- Address decode
    signal rom_selected, ram_selected : std_logic;
    signal is_write, is_io : std_logic;

    -- T-state decode
    signal is_t1, is_t2, is_t3, is_t4, is_t5 : std_logic;

    -- I/O signals
    signal io_port_num : std_logic_vector(2 downto 0);
    signal io_input_data : std_logic_vector(7 downto 0);

    -- Serial capture signals
    signal port_8_data : std_logic_vector(7 downto 0) := (others => '0');
    signal port_8_write : std_logic := '0';
    signal io_captured_this_t3 : std_logic := '0';  -- Flag: already captured in this T3 period
    signal serial_char_valid : std_logic;
    signal serial_char_data : std_logic_vector(7 downto 0);
    signal serial_char_count : integer;

    -- Serial input simulation (for interactive programs)
    -- Pre-loaded with "N\r" to answer "Want the rules? N" then halt
    type input_buffer_t is array(0 to 15) of std_logic_vector(7 downto 0);
    signal input_buffer : input_buffer_t := (
        x"4E",  -- 'N'
        x"0D",  -- CR
        others => x"00"
    );
    signal input_index : integer := 0;
    signal input_bit_pos : integer := 0;  -- 0=idle, 1-10 = start + 8 data + stop
    signal serial_input_bit : std_logic := '1';  -- Idle high

    -- Bootstrap JMP injection
    -- When START_ADDR != 0, inject a JMP instruction during the first 3 memory cycles
    -- Cycle 1: JMP opcode (0x44), Cycle 2: low address byte, Cycle 3: high address byte
    signal bootstrap_cycle : integer range 0 to 4 := 0;  -- 0=not started, 1-3=injecting, 4=done
    signal bootstrap_byte : std_logic_vector(7 downto 0);
    signal is_t1i : std_logic;

begin

    -- T1I state detection
    is_t1i <= '1' when (s2_out = '1' and s1_out = '1' and s0_out = '0') else '0';

    -- ========================================================================
    -- CLOCK GENERATION
    -- ========================================================================
    clk_process : process
    begin
        while test_running loop
            clk_in <= '0';
            wait for CLK_PERIOD / 2;
            clk_in <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    -- ========================================================================
    -- CPU INSTANCE
    -- ========================================================================
    u_cpu : b8008
        port map (
            clk_in      => clk_in,
            reset       => reset,
            phi1_out    => phi1,
            phi2_out    => phi2,
            data_bus    => data_bus,
            sync_out    => sync_out,
            s0_out      => s0_out,
            s1_out      => s1_out,
            s2_out      => s2_out,
            ready_in    => '1',
            interrupt   => interrupt,
            debug_reg_a => debug_reg_a,
            debug_reg_b => debug_reg_b,
            debug_reg_c => debug_reg_c,
            debug_reg_d => debug_reg_d,
            debug_reg_e => debug_reg_e,
            debug_reg_h => debug_reg_h,
            debug_reg_l => debug_reg_l,
            debug_cycle => debug_cycle,
            debug_pc    => debug_pc,
            debug_ir    => debug_ir,
            debug_needs_address => debug_needs_address,
            debug_int_pending => debug_int_pending,
            cycle_type  => cycle_type,
            debug_flag_carry  => debug_flag_carry,
            debug_flag_zero   => debug_flag_zero,
            debug_flag_sign   => debug_flag_sign,
            debug_flag_parity => debug_flag_parity
        );

    -- ========================================================================
    -- MEMORY INSTANCES
    -- ========================================================================
    u_rom : rom_4kx8
        generic map (
            ROM_FILE => ROM_FILE
        )
        port map (
            ADDR     => latched_address(11 downto 0),
            DATA_OUT => rom_data,
            CS_N     => rom_cs_n
        );

    -- RAM is initialized with same contents as ROM for sample programs
    -- that expect RAM at 0x0000 (code and data in same address space)
    u_ram : ram_4kx8
        generic map (
            INIT_FILE => ROM_FILE
        )
        port map (
            CLK          => phi1,
            ADDR         => latched_address(11 downto 0),
            DATA_IN      => ram_data_in,
            DATA_OUT     => ram_data_out,
            RW_N         => ram_rw_n,
            CS_N         => ram_cs_n
        );

    -- ========================================================================
    -- SERIAL CAPTURE INSTANCE
    -- ========================================================================
    u_serial_capture : serial_capture
        generic map (
            OUTPUT_FILE => "serial_output.txt"
        )
        port map (
            clk          => clk_in,
            reset        => reset,
            port_8_data  => port_8_data,
            port_8_write => port_8_write,
            char_valid   => serial_char_valid,
            char_data    => serial_char_data,
            char_count   => serial_char_count
        );

    -- ========================================================================
    -- T-STATE DECODE
    -- ========================================================================
    is_t1 <= '1' when (s2_out = '0' and s1_out = '1' and s0_out = '0') else '0';
    is_t2 <= '1' when (s2_out = '1' and s1_out = '0' and s0_out = '0') else '0';
    is_t3 <= '1' when (s2_out = '0' and s1_out = '0' and s0_out = '1') else '0';
    is_t4 <= '1' when (s2_out = '1' and s1_out = '1' and s0_out = '1') else '0';
    is_t5 <= '1' when (s2_out = '1' and s1_out = '0' and s0_out = '1') else '0';

    -- ========================================================================
    -- ADDRESS LATCHING
    -- ========================================================================
    process(phi1, reset)
    begin
        if reset = '1' then
            latched_address <= (others => '0');
        elsif rising_edge(phi1) then
            if is_t1 = '1' and sync_out = '1' then
                latched_address(7 downto 0) <= data_bus;
            elsif is_t2 = '1' and sync_out = '1' then
                latched_address(13 downto 8) <= data_bus(5 downto 0);
            end if;
        end if;
    end process;

    -- ========================================================================
    -- BOOTSTRAP JMP INJECTION
    -- ========================================================================
    -- Track bootstrap cycles and compute JMP instruction bytes
    -- JMP opcode = 0x44 (01 000 100), followed by low addr byte, high addr byte
    bootstrap_byte <= x"44" when bootstrap_cycle = 1 else                              -- JMP opcode
                      std_logic_vector(to_unsigned(START_ADDR mod 256, 8)) when bootstrap_cycle = 2 else  -- Low byte
                      std_logic_vector(to_unsigned(START_ADDR / 256, 8)) when bootstrap_cycle = 3 else    -- High byte
                      x"00";

    -- Track bootstrap state machine
    process(phi1, reset)
    begin
        if reset = '1' then
            bootstrap_cycle <= 0;
        elsif rising_edge(phi1) then
            if bootstrap_cycle = 0 and is_t1i = '1' then
                -- Start bootstrap on T1I (interrupt acknowledge)
                bootstrap_cycle <= 1;
            elsif bootstrap_cycle >= 1 and bootstrap_cycle < 4 then
                -- Advance on each T1 (start of new cycle)
                if is_t1 = '1' and sync_out = '1' then
                    bootstrap_cycle <= bootstrap_cycle + 1;
                end if;
            end if;
        end if;
    end process;

    -- ========================================================================
    -- ADDRESS DECODE
    -- ========================================================================
    -- For sample programs like mandelbrot, the entire 4K space is treated as
    -- RAM that's pre-loaded with the program. ROM provides initial values,
    -- but writes go to RAM. This emulates a system with RAM at 0x0000.
    -- ROM is always selected for reads in 0x0000-0x0FFF range
    -- RAM is selected for writes in 0x0000-0x0FFF range (overlaid on ROM)
    rom_selected <= '1' when latched_address(13 downto 12) = "00" else '0';
    ram_selected <= '1' when latched_address(13 downto 12) = "00" else '0';  -- RAM overlays ROM
    rom_cs_n <= not rom_selected;
    ram_cs_n <= not ram_selected;

    is_write <= '1' when cycle_type = "11" else '0';
    is_io    <= '1' when cycle_type = "10" else '0';

    ram_rw_n <= '0' when (is_write = '1' and ram_selected = '1' and
                         (is_t3 = '1' or is_t4 = '1' or is_t5 = '1')) else '1';
    ram_data_in <= data_bus;

    -- ========================================================================
    -- I/O PORT HANDLING
    -- ========================================================================
    io_port_num <= latched_address(11 downto 9);

    -- Input ports: Port 0 returns serial input bit in LSB
    -- For non-interactive programs, keep line idle (high)
    io_input_data <= "1111111" & serial_input_bit when io_port_num = "000" else
                     x"01" when io_port_num = "001" else  -- TX status: always ready
                     x"00" when io_port_num = "010" else  -- RX data: not implemented
                     x"00" when io_port_num = "011" else  -- RX status: nothing available
                     x"00";

    -- Output port 8 capture for serial
    -- Uses T3 state tracking to ensure only ONE pulse per I/O cycle
    -- The flag io_captured_this_t3 is set when we capture, cleared when we leave T3
    -- NOTE: We use phi2 rising edge to capture, giving CPU time to drive the bus
    -- after phi1 rising edge where the control signals are set
    process(phi2, reset)
        variable in_port8_io_t3 : boolean;
    begin
        if reset = '1' then
            port_8_data  <= (others => '0');
            port_8_write <= '0';
            io_captured_this_t3 <= '0';
        elsif rising_edge(phi2) then
            port_8_write <= '0';  -- Default: no write

            -- Check if we're in port 8 I/O T3 state
            -- For OUT ports 8-15: RR field = 01, MMM field = port - 8
            -- latched_address(13:12) has the high bits which for port 8 should be from the address info
            -- io_port_num has the MMM field (bits 11:9 of latched address)
            in_port8_io_t3 := (is_io = '1' and is_t3 = '1' and
                               latched_address(13 downto 12) = "01" and io_port_num = "000");

            if in_port8_io_t3 then
                -- We're in the right state, capture if we haven't already
                if io_captured_this_t3 = '0' then
                    port_8_data  <= data_bus;
                    port_8_write <= '1';
                    io_captured_this_t3 <= '1';
                    report "SERIAL_TB: Port 8 write @ PC=0x" & to_hstring(unsigned(debug_pc)) &
                           ", data=0x" & to_hstring(unsigned(data_bus)) &
                           " (bit=" & std_logic'image(data_bus(0)) &
                           ") A=0x" & to_hstring(unsigned(debug_reg_a)) &
                           " addr=0x" & to_hstring(unsigned(latched_address)) &
                           " rom_sel=" & std_logic'image(rom_selected) &
                           " ram_sel=" & std_logic'image(ram_selected) & ")";
                end if;
            else
                -- Not in port 8 I/O T3, clear the flag so next T3 can capture
                io_captured_this_t3 <= '0';
            end if;
        end if;
    end process;

    -- ========================================================================
    -- DATA BUS MULTIPLEXING
    -- ========================================================================
    -- Bootstrap: During cycles 1-3 after interrupt, inject JMP to START_ADDR
    -- I/O Direction detection:
    -- INP instruction: 0100 MMM 1 - RR field (bits 5:4 of opcode) = 00 -> input ports 0-7
    -- OUT instruction: 01RR MMM 1 - RR field != 00 -> output ports 8-31
    -- During I/O cycle 2 T2, latched_address(13:12) contains RR field
    -- RR = 00 -> INP (drive bus with input data)
    -- RR != 00 -> OUT (let CPU drive bus, we just read it)
    --
    -- IMPORTANT: During I/O operations, the latched address contains the accumulator
    -- value (from T1) which may fall into ROM/RAM address ranges. We must NOT drive
    -- ROM/RAM data during I/O cycles - only during memory cycles!
    --
    -- For sample programs: RAM is pre-loaded with ROM contents and used for all
    -- reads in 0x0000-0x0FFF range. This allows the program to modify its own
    -- data area and read back the modified values.
    data_bus <= bootstrap_byte when (is_t1i = '1') else  -- T1I: inject JMP opcode
                bootstrap_byte when (bootstrap_cycle >= 1 and bootstrap_cycle <= 3 and is_t3 = '1') else  -- Inject addr bytes
                io_input_data when (is_io = '1' and latched_address(13 downto 12) = "00" and
                                   (is_t3 = '1' or is_t4 = '1' or is_t5 = '1')) else
                ram_data_out when (is_io = '0' and ram_selected = '1' and (is_t3 = '1' or is_t4 = '1' or is_t5 = '1')) else
                (others => 'Z');

    -- ========================================================================
    -- STIMULUS PROCESS
    -- ========================================================================
    stimulus : process
        variable runtime_ns : time;
    begin
        report "========================================";
        report "B8008 SERIAL I/O TESTBENCH";
        report "ROM: " & ROM_FILE;
        report "Runtime: " & integer'image(RUN_TIME_MS) & " ms";
        report "========================================";

        -- Reset sequence
        reset <= '1';
        interrupt <= '0';
        wait for 200 ns;

        reset <= '0';
        report "Reset released";
        wait for 100 ns;

        -- Bootstrap interrupt
        interrupt <= '1';
        wait for 1 ns;
        report "Bootstrap interrupt asserted";

        wait until (s2_out = '1' and s1_out = '1' and s0_out = '0');
        wait for 50 ns;
        interrupt <= '0';
        report "T1I detected - interrupt lowered, CPU running";

        -- Run for specified time
        runtime_ns := RUN_TIME_MS * 1 ms;
        wait for runtime_ns;

        -- Report summary
        report "========================================";
        report "SIMULATION COMPLETE";
        report "Total characters output: " & integer'image(serial_char_count);
        report "========================================";

        test_running <= false;
        wait;
    end process;

end architecture testbench;

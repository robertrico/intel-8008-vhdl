--------------------------------------------------------------------------------
-- interrupt_jam_tb.vhdl
--------------------------------------------------------------------------------
-- Interrupt jam generality (VPLAN INT-04/05, XP-03, XP-14): the spec
-- allows ANY instruction to be jammed during T1I, not just RST.
--
-- Runs test_programs/jam_test_as.mem and injects:
--   S1  NOP jam (0xC0) into a counted loop      - resume at un-advanced PC
--   S2  HLT jam into a counted loop             - CPU stops; RST7 wakes it
--   S3  3-byte JMP jam into an inescapable spin - TB supplies B2/B3 on the
--       bus during the two operand-fetch cycles; asserts only ONE T1I
--   S4  READY park with INT asserted during WAIT - no T1I until READY
--       returns and the in-flight instruction completes
--
-- Pass/fail is decided by the checkpoint dumps (check_jam_test.sh) plus
-- the severity-error assertions here.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity interrupt_jam_tb is
    generic (
        ROM_FILE : string := "test_programs/jam_test_as.mem"
    );
end entity interrupt_jam_tb;

architecture testbench of interrupt_jam_tb is

    component b8008_top is
        port (
            clk_in      : in  std_logic;
            reset       : in  std_logic;
            interrupt   : in  std_logic;
            int_vector  : in  std_logic_vector(2 downto 0) := "000";
            int_jam_byte : in std_logic_vector(7 downto 0) := (others => '0');
            int_jam_en   : in std_logic := '0';
            ready_in    : in  std_logic := '1';
            phi1_out    : out std_logic;
            phi2_out    : out std_logic;
            sync_out    : out std_logic;
            s0_out      : out std_logic;
            s1_out      : out std_logic;
            s2_out      : out std_logic;
            address_out : out std_logic_vector(13 downto 0);
            data_out    : out std_logic_vector(7 downto 0);
            ram_byte_0  : out std_logic_vector(7 downto 0);
            debug_reg_a         : out std_logic_vector(7 downto 0);
            debug_reg_b         : out std_logic_vector(7 downto 0);
            debug_reg_c         : out std_logic_vector(7 downto 0);
            debug_reg_d         : out std_logic_vector(7 downto 0);
            debug_reg_e         : out std_logic_vector(7 downto 0);
            debug_reg_h         : out std_logic_vector(7 downto 0);
            debug_reg_l         : out std_logic_vector(7 downto 0);
            debug_cycle         : out std_logic_vector(1 downto 0);
            debug_pc            : out std_logic_vector(13 downto 0);
            debug_ir            : out std_logic_vector(7 downto 0);
            debug_needs_address : out std_logic;
            debug_int_pending   : out std_logic;
            debug_flag_carry    : out std_logic;
            debug_flag_zero     : out std_logic;
            debug_flag_sign     : out std_logic;
            debug_flag_parity   : out std_logic;
            debug_io_port_8     : out std_logic_vector(7 downto 0);
            debug_io_port_9     : out std_logic_vector(7 downto 0);
            debug_io_port_10    : out std_logic_vector(7 downto 0);
            debug_state_half    : out std_logic;
            io_port_in          : in  std_logic_vector(7 downto 0);
            io_port_in_select   : in  std_logic_vector(2 downto 0);
            io_port_in_enable   : in  std_logic;
            io_port_out         : out std_logic_vector(7 downto 0);
            io_port_num_out     : out std_logic_vector(4 downto 0);
            io_port_write       : out std_logic;
            io_port_read        : out std_logic;
            rom_a               : out std_logic_vector(13 downto 0);
            rom_d               : in  std_logic_vector(7 downto 0);
            rom_ce_n            : out std_logic;
            rom_oe_n            : out std_logic
        );
    end component;

    component rom_8kx8 is
        generic (
            ROM_FILE : string := "test_programs/jam_test_as.mem"
        );
        port (
            ADDR     : in  std_logic_vector(12 downto 0);
            DATA_OUT : out std_logic_vector(7 downto 0);
            CS_N     : in  std_logic;
            OE_N     : in  std_logic
        );
    end component;

    constant CLK_PERIOD : time := 10 ns;  -- 100 MHz

    signal test_running : boolean := true;

    signal clk_in      : std_logic := '0';
    signal reset       : std_logic := '1';
    signal interrupt   : std_logic := '0';
    signal int_vector  : std_logic_vector(2 downto 0) := "000";
    signal int_jam_byte : std_logic_vector(7 downto 0) := (others => '0');
    signal int_jam_en   : std_logic := '0';
    signal ready_in    : std_logic := '1';
    signal phi1_out    : std_logic;
    signal phi2_out    : std_logic;
    signal sync_out    : std_logic;
    signal s0_out      : std_logic;
    signal s1_out      : std_logic;
    signal s2_out      : std_logic;
    signal address_out : std_logic_vector(13 downto 0);
    signal data_out    : std_logic_vector(7 downto 0);
    signal ram_byte_0  : std_logic_vector(7 downto 0);
    signal debug_reg_a, debug_reg_b, debug_reg_c, debug_reg_d : std_logic_vector(7 downto 0);
    signal debug_reg_e, debug_reg_h, debug_reg_l : std_logic_vector(7 downto 0);
    signal debug_cycle : std_logic_vector(1 downto 0);
    signal debug_pc    : std_logic_vector(13 downto 0);
    signal debug_ir    : std_logic_vector(7 downto 0);
    signal debug_needs_address, debug_int_pending : std_logic;
    signal debug_flag_carry, debug_flag_zero, debug_flag_sign, debug_flag_parity : std_logic;
    signal debug_io_port_8, debug_io_port_9, debug_io_port_10 : std_logic_vector(7 downto 0);
    signal debug_state_half : std_logic;

    signal io_port_in        : std_logic_vector(7 downto 0) := (others => '0');
    signal io_port_in_select : std_logic_vector(2 downto 0) := (others => '0');
    signal io_port_in_enable : std_logic := '0';
    signal io_port_out       : std_logic_vector(7 downto 0);
    signal io_port_num_out   : std_logic_vector(4 downto 0);
    signal io_port_write     : std_logic;
    signal io_port_read      : std_logic;

    signal rom_a    : std_logic_vector(13 downto 0);
    signal rom_d_rom : std_logic_vector(7 downto 0);  -- from the ROM model
    signal rom_d_dut : std_logic_vector(7 downto 0);  -- to the CPU
    signal rom_ce_n : std_logic;
    signal rom_oe_n : std_logic;

    -- TB-side bus override: models the interrupt controller holding the
    -- bus for the operand bytes of a multi-byte jammed instruction
    signal jam_bus_en   : std_logic := '0';
    signal jam_bus_byte : std_logic_vector(7 downto 0) := (others => '0');

    -- T1I observation (status 011: S0=0 S1=1 S2=1)
    signal in_t1i     : boolean;
    signal t1i_count  : natural := 0;

    -- State code helpers
    signal in_stopped : boolean;  -- 110: S0=1 S1=1 S2=0
    signal in_wait    : boolean;  -- 000
    signal in_t3      : boolean;  -- 100: S0=1 S1=0 S2=0

begin

    uut : b8008_top
        port map (
            clk_in      => clk_in,
            reset       => reset,
            interrupt   => interrupt,
            int_vector  => int_vector,
            int_jam_byte => int_jam_byte,
            int_jam_en   => int_jam_en,
            ready_in    => ready_in,
            phi1_out    => phi1_out,
            phi2_out    => phi2_out,
            sync_out    => sync_out,
            s0_out      => s0_out,
            s1_out      => s1_out,
            s2_out      => s2_out,
            address_out => address_out,
            data_out    => data_out,
            ram_byte_0  => ram_byte_0,
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
            debug_int_pending   => debug_int_pending,
            debug_flag_carry    => debug_flag_carry,
            debug_flag_zero     => debug_flag_zero,
            debug_flag_sign     => debug_flag_sign,
            debug_flag_parity   => debug_flag_parity,
            debug_io_port_8     => debug_io_port_8,
            debug_io_port_9     => debug_io_port_9,
            debug_io_port_10    => debug_io_port_10,
            debug_state_half    => debug_state_half,
            io_port_in          => io_port_in,
            io_port_in_select   => io_port_in_select,
            io_port_in_enable   => io_port_in_enable,
            io_port_out         => io_port_out,
            io_port_num_out     => io_port_num_out,
            io_port_write       => io_port_write,
            io_port_read        => io_port_read,
            rom_a               => rom_a,
            rom_d               => rom_d_dut,
            rom_ce_n            => rom_ce_n,
            rom_oe_n            => rom_oe_n
        );

    u_rom : rom_8kx8
        generic map ( ROM_FILE => ROM_FILE )
        port map (
            ADDR     => rom_a(12 downto 0),
            DATA_OUT => rom_d_rom,
            CS_N     => rom_ce_n,
            OE_N     => rom_oe_n
        );

    -- Interrupt-controller bus override for multi-byte jams
    rom_d_dut <= jam_bus_byte when jam_bus_en = '1' else rom_d_rom;

    -- Status decodes
    in_t1i     <= (s0_out = '0' and s1_out = '1' and s2_out = '1');
    in_stopped <= (s0_out = '1' and s1_out = '1' and s2_out = '0');
    in_wait    <= (s0_out = '0' and s1_out = '0' and s2_out = '0');
    in_t3      <= (s0_out = '1' and s1_out = '0' and s2_out = '0');

    -- Count T1I entries (rising edge of the T1I status)
    t1i_counter : process(clk_in)
        variable prev : boolean := false;
    begin
        if rising_edge(clk_in) then
            if in_t1i and not prev then
                t1i_count <= t1i_count + 1;
            end if;
            prev := in_t1i;
        end if;
    end process;

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

    stimulus : process
        variable t1i_before : natural;

        -- Jam one arbitrary byte via T1I and release the request
        procedure jam(byte : std_logic_vector(7 downto 0)) is
        begin
            int_jam_byte <= byte;
            int_jam_en   <= '1';
            interrupt    <= '1';
            wait until in_t1i;
            wait for 50 ns;
            interrupt <= '0';
            wait until not in_t1i;
            int_jam_en <= '0';
        end procedure;
    begin
        report "========================================";
        report "INTERRUPT JAM GENERALITY TEST";
        report "========================================";

        -- Bootstrap: RST 0
        reset <= '1';
        wait for 200 ns;
        reset <= '0';
        wait for 100 ns;
        interrupt <= '1';
        wait until in_t1i;
        wait for 50 ns;
        interrupt <= '0';
        report "Bootstrap RST 0 jammed";

        -- ---- S1: NOP jam into LOOP1 ----------------------------------
        wait for 1200 us;
        report "S1: jamming NOP (0xC0) into LOOP1";
        jam(x"C0");
        report "S1: NOP jam complete";

        -- ---- S2: HLT jam into LOOP2 ----------------------------------
        -- CP1 fires ~2.5 ms; LOOP2 spans ~2.5-5 ms
        wait for 2300 us;
        report "S2: jamming HLT (0x00) into LOOP2";
        jam(x"00");
        wait until in_stopped for 500 us;
        assert in_stopped
            report "ERROR: CPU did not stop after HLT jam" severity error;
        -- Must STAY stopped
        wait for 200 us;
        assert in_stopped
            report "ERROR: CPU did not remain stopped after HLT jam" severity error;
        report "S2: CPU stopped; waking with RST 7";
        int_vector <= "111";
        interrupt <= '1';
        wait until in_t1i;
        wait for 50 ns;
        interrupt <= '0';
        report "S2: RST 7 wake delivered";

        -- ---- S3: 3-byte JMP jam out of SPIN --------------------------
        -- CP2 fires, then the program enters SPIN; give it time
        wait for 3000 us;
        report "S3: jamming JMP 0x0200 (3 bytes) into SPIN";
        t1i_before := t1i_count;
        -- Cycle 1: T1I with the JMP opcode
        int_jam_byte <= x"44";
        int_jam_en   <= '1';
        interrupt    <= '1';
        wait until in_t1i;
        wait for 50 ns;
        interrupt <= '0';
        wait until not in_t1i;
        int_jam_en <= '0';
        -- The jam cycle itself still runs T2/T3 (fetch-shaped; the IR
        -- reload is suppressed) - let its T3 pass before serving operands
        wait until in_t3;
        wait until not in_t3;
        -- Cycles 2/3: hold the bus with B2 (low) then B3 (high), the
        -- interrupt-controller model for a multi-byte insertion
        jam_bus_byte <= x"00";          -- B2: target low = 0x00
        jam_bus_en   <= '1';
        wait until in_t3;               -- operand fetch 1 consumes B2
        wait until not in_t3;
        jam_bus_byte <= x"02";          -- B3: target high = 0x02
        wait until in_t3;               -- operand fetch 2 consumes B3
        wait until not in_t3;
        jam_bus_en <= '0';
        wait for 100 us;
        assert t1i_count = t1i_before + 1
            report "ERROR: multi-byte jam produced " &
                   integer'image(t1i_count - t1i_before) &
                   " T1I cycles (spec: only cycle 1 is T1I)" severity error;
        report "S3: JMP jam complete (single T1I confirmed)";

        -- ---- S4: INT during WAIT -------------------------------------
        -- CP3 fires at the landing pad; LOOP3 spans the next few ms
        wait for 1200 us;
        report "S4: parking CPU with READY low mid-LOOP3";
        ready_in <= '0';
        wait until in_wait for 500 us;
        assert in_wait
            report "ERROR: CPU never parked in WAIT" severity error;
        t1i_before := t1i_count;
        int_vector <= "111";
        interrupt <= '1';               -- INT while parked
        wait for 200 us;
        assert in_wait
            report "ERROR: CPU left WAIT while READY still low" severity error;
        assert t1i_count = t1i_before
            report "ERROR: T1I occurred during WAIT (interrupt must wait for READY)"
            severity error;
        report "S4: INT pending during WAIT, no T1I - releasing READY";
        ready_in <= '1';
        wait until in_t1i for 1000 us;
        wait for 100 ns;  -- let the T1I counter's clock edge land
        assert t1i_count = t1i_before + 1
            report "ERROR: interrupt not serviced after READY release" severity error;
        interrupt <= '0';
        report "S4: interrupt serviced after READY release";

        -- Let LOOP3 finish and the final checkpoints fire
        wait for 4000 us;

        report "========================================";
        report "INTERRUPT JAM TEST COMPLETE (T1I total: " &
               integer'image(t1i_count) & ")";
        report "========================================";

        test_running <= false;
        wait;
    end process;

end architecture testbench;

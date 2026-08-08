--------------------------------------------------------------------------------
-- b8008_top.vhdl
--------------------------------------------------------------------------------
-- Top-level system integrating b8008 CPU with external ROM and internal RAM
--
-- Memory Map:
--   0x0000 - 0x1FFF (8KB): External ROM (directly active through rom_a/rom_d/rom_ce_n/rom_oe_n)
--   0x2000 - 0x3FFF (8KB): RAM (data storage / loaded programs)
--
-- This module connects:
--   - b8008 CPU core
--   - External ROM interface (directly directly via rom_a/rom_d/rom_ce_n/rom_oe_n)
--   - ram_sync (8KB RAM for data storage)
--   - address_decoder (configurable ROM/RAM ranges)
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.b8008_types.all;

entity b8008_top is
    generic (
        -- Master clock frequency. Forwarded into b8008 → phase_clocks so the
        -- two-phase 8008 clock keeps its 0.8/0.6 µs widths whatever speed the
        -- board feeds clk_in at. Default 100 MHz preserves all existing TBs.
        CLK_FREQ_HZ   : integer := 100_000_000;
        -- Simulation-only RAM preload (.mem format); "" = zeros like silicon
        RAM_INIT_FILE : string  := "";
        -- Memory-map personality (defaults = b8008_monitor: ROM low, RAM high)
        ROM_BASE      : integer := 16#0000#;
        ROM_LAST      : integer := 16#0FFF#;
        RAM_BASE      : integer := 16#1000#;
        RAM_LAST      : integer := 16#3FFF#;
        RAM_ADDR_BITS : integer := 14;
        -- false (default): RAM lives inside this module (internal ram_sync),
        -- exactly as before -- backward compatible, nothing else changes.
        -- true: RAM is owned externally (e.g. a LiteX SoC); this module
        -- drives the ram_ext_* bus below instead of instantiating ram_sync.
        EXTERNAL_RAM  : boolean := false
    );
    port (
        -- External clock and reset
        clk_in      : in std_logic;
        reset       : in std_logic;
        -- Debug hold: drive low to freeze the CPU in place. Defaults to '1'
        -- (always running) so projects that don't wire a debug controller
        -- continue to work with no code change.
        run_enable  : in std_logic := '1';
        interrupt   : in std_logic;  -- Bootstrap interrupt (tie high after reset)
        int_vector  : in std_logic_vector(2 downto 0) := "000";  -- RST vector (0-7) to jam during T1I
        -- Optional arbitrary jam byte (testbench use): when int_jam_en='1'
        -- the T1I cycle jams int_jam_byte instead of the RST pattern -
        -- the spec allows ANY instruction to be jammed (UM p.10).
        int_jam_byte : in std_logic_vector(7 downto 0) := (others => '0');
        int_jam_en   : in std_logic := '0';
        ready_in    : in std_logic := '1';  -- READY: '0' parks the CPU in WAIT after T2

        -- Debug outputs
        phi1_out    : out std_logic;
        phi2_out    : out std_logic;
        sync_out    : out std_logic;
        s0_out      : out std_logic;
        s1_out      : out std_logic;
        s2_out      : out std_logic;

        -- Address and data for debugging
        address_out : out std_logic_vector(13 downto 0);
        data_out    : out std_logic_vector(7 downto 0);

        -- RAM debug output (location 0 for verification)
        ram_byte_0  : out std_logic_vector(7 downto 0);

        -- Debug outputs: CPU state and key registers
        debug_reg_a         : out std_logic_vector(7 downto 0);  -- A register
        debug_reg_b         : out std_logic_vector(7 downto 0);  -- B register
        debug_reg_c         : out std_logic_vector(7 downto 0);  -- C register
        debug_reg_d         : out std_logic_vector(7 downto 0);  -- D register
        debug_reg_e         : out std_logic_vector(7 downto 0);  -- E register
        debug_reg_h         : out std_logic_vector(7 downto 0);  -- H register
        debug_reg_l         : out std_logic_vector(7 downto 0);  -- L register
        debug_cycle         : out std_logic_vector(1 downto 0);
        debug_pc            : out std_logic_vector(13 downto 0);
        debug_ir            : out std_logic_vector(7 downto 0);
        debug_needs_address : out std_logic;
        debug_int_pending   : out std_logic;
        -- Debug flag outputs
        debug_flag_carry    : out std_logic;
        debug_flag_zero     : out std_logic;
        debug_flag_sign     : out std_logic;
        debug_flag_parity   : out std_logic;

        -- I/O port debug outputs (for verification)
        debug_io_port_8     : out std_logic_vector(7 downto 0);
        debug_io_port_9     : out std_logic_vector(7 downto 0);
        debug_io_port_10    : out std_logic_vector(7 downto 0);
        -- State timing debug
        debug_state_half    : out std_logic;  -- Which half of 2-cycle state (0=first, 1=second)

        -- External I/O port interface (directly active directly active accent active low accent active low accent active low for UART, etc.)
        -- Input port interface: external devices provide data for INP instructions
        io_port_in          : in  std_logic_vector(7 downto 0) := x"00";  -- External input data
        io_port_in_select   : in  std_logic_vector(2 downto 0) := "000";  -- Which port(s) use external input
        io_port_in_enable   : in  std_logic := '0';                       -- '1' = use io_port_in for selected port

        -- Output port interface: signals when OUT instruction executes
        io_port_out         : out std_logic_vector(7 downto 0);  -- Data written by OUT instruction
        io_port_num_out     : out std_logic_vector(4 downto 0);  -- Full port number (0-31)
        io_port_write       : out std_logic;                     -- Strobe: '1' for one phi2 cycle during OUT T3
        io_port_read        : out std_logic;                     -- Strobe: '1' for one phi2 cycle during INP T3

        -- External ROM interface
        rom_a               : out std_logic_vector(13 downto 0); -- ROM address rel. ROM_BASE (up to 16K)
        rom_d               : in  std_logic_vector(7 downto 0);  -- ROM data input
        rom_ce_n            : out std_logic;                     -- ROM chip enable (active low)
        rom_oe_n            : out std_logic;                     -- ROM output enable (active low)

        -- External RAM interface (used only when EXTERNAL_RAM => true; all
        -- signals in the clk_in domain). Memory-port contract: external RAM
        -- behaves exactly like ram_sync: on every rising clk_in edge,
        -- ram_ext_rdata becomes the registered read of ram_ext_addr
        -- (one-cycle latency, no CS gating on reads); a write occurs on the
        -- edge when ram_ext_cs_n='0' and ram_ext_rw_n='0'.
        ram_ext_addr  : out std_logic_vector(13 downto 0);         -- latched address, low RAM_ADDR_BITS valid
        ram_ext_wdata : out std_logic_vector(7 downto 0);
        ram_ext_rdata : in  std_logic_vector(7 downto 0) := x"00"; -- must be a 1-cycle synchronous read of ram_ext_addr
        ram_ext_rw_n  : out std_logic;                              -- 0 = write (ram_sync semantics)
        ram_ext_cs_n  : out std_logic                               -- 0 = selected
    );
end entity b8008_top;

architecture structural of b8008_top is

    -- Component: b8008 CPU
    component b8008 is
        generic (
            CLK_FREQ_HZ : integer := 100_000_000
        );
        port (
            clk_in         : in std_logic;
            reset          : in std_logic;
            run_enable     : in std_logic;
            phi1_out       : out std_logic;
            phi2_out       : out std_logic;
            phi1_rising_out  : out std_logic;
            phi1_falling_out : out std_logic;
            phi2_rising_out  : out std_logic;
            phi2_falling_out : out std_logic;
            data_bus_in    : in  std_logic_vector(7 downto 0);
            data_bus_out   : out std_logic_vector(7 downto 0);
            data_bus_oe    : out std_logic;
            sync_out       : out std_logic;
            s0_out         : out std_logic;
            s1_out         : out std_logic;
            s2_out         : out std_logic;
            ready_in       : in std_logic;
            interrupt      : in std_logic;
            -- Debug
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
            cycle_type          : out std_logic_vector(1 downto 0);
            -- Debug flag outputs
            debug_flag_carry    : out std_logic;
            debug_flag_zero     : out std_logic;
            debug_flag_sign     : out std_logic;
            debug_flag_parity   : out std_logic;
            -- State timing debug
            debug_state_half    : out std_logic
        );
    end component;

    -- Component: configurable address decoder (defaults = this memory map)
    component address_decoder is
        generic (
            ROM_BASE : integer := 16#0000#;
            ROM_LAST : integer := 16#1FFF#;
            RAM_BASE : integer := 16#2000#;
            RAM_LAST : integer := 16#23FF#
        );
        port (
            address  : in  std_logic_vector(13 downto 0);
            rom_sel  : out std_logic;
            ram_sel  : out std_logic;
            rom_cs_n : out std_logic;
            ram_cs_n : out std_logic
        );
    end component;

    -- Component: parameterized synchronous RAM (block RAM)
    component ram_sync is
        generic (
            ADDR_BITS : integer := 10;
            INIT_FILE : string  := ""
        );
        port (
            CLK      : in  std_logic;
            ADDR     : in  std_logic_vector(ADDR_BITS-1 downto 0);
            DATA_IN  : in  std_logic_vector(7 downto 0);
            DATA_OUT : out std_logic_vector(7 downto 0);
            RW_N     : in  std_logic;
            CS_N     : in  std_logic
        );
    end component;

    -- Internal signals
    signal address_bus : std_logic_vector(13 downto 0);
    signal data_bus    : std_logic_vector(7 downto 0);  -- Combined data bus (external bidirectional)
    signal cpu_data_in  : std_logic_vector(7 downto 0); -- Data TO CPU (no loop from cpu_data_out)
    -- Byte jammed during T1I: RST pattern from int_vector, or the
    -- arbitrary override when int_jam_en='1' (testbench use)
    signal jam_byte_sel : std_logic_vector(7 downto 0);
    signal cpu_data_out : std_logic_vector(7 downto 0); -- Data from CPU
    signal cpu_data_oe  : std_logic;                    -- CPU output enable
    signal phi1        : std_logic;
    signal phi2        : std_logic;
    signal phi1_rising  : std_logic;
    signal phi1_falling : std_logic;
    signal phi2_rising  : std_logic;
    signal phi2_falling : std_logic;

    -- Memory signals
    signal rom_cs_n_int : std_logic;  -- Internal copy for driving output
    signal ram_cs_n     : std_logic;
    signal ram_data_in : std_logic_vector(7 downto 0);
    signal ram_data_out: std_logic_vector(7 downto 0);
    signal ram_rw_n    : std_logic;

    -- Address decode
    signal rom_selected : std_logic;
    signal ram_selected : std_logic;
    signal is_write     : std_logic;
    signal is_io        : std_logic;  -- I/O cycle (PCC)
    signal cycle_type   : std_logic_vector(1 downto 0);  -- 00=PCI, 01=PCR, 10=PCC, 11=PCW

    -- Internal copies of state signals (VHDL-2008: cannot read from output ports)
    -- These capture the CPU state outputs for internal logic use
    signal s0_int       : std_logic;
    signal s1_int       : std_logic;
    signal s2_int       : std_logic;
    signal sync_int     : std_logic;

    -- Bootstrap flag: jam RST 0 only during first T1I after reset
    signal bootstrap_done : std_logic := '0';

    -- I/O Port Simulation
    -- Input ports (directly provide test values for INP instruction)
    -- Port 0: returns 0x55 (alternating bits)
    -- Port 1: returns 0xAA (alternating bits, inverted)
    -- Port 2: returns 0x42 (ASCII 'B')
    -- Port 3-7: returns port number
    signal io_input_data : std_logic_vector(7 downto 0);
    signal io_port_num   : std_logic_vector(2 downto 0);  -- Port number from T2 latched address

    -- Output ports (latch values written by OUT instruction)
    -- Port 8-15: Latch output data for verification
    signal io_output_port_8  : std_logic_vector(7 downto 0) := (others => '0');
    signal io_output_port_9  : std_logic_vector(7 downto 0) := (others => '0');
    signal io_output_port_10 : std_logic_vector(7 downto 0) := (others => '0');

    -- Checkpoint system: Port 31 (0x1F) is the assertion port
    -- When OUT 31 is executed, capture full CPU state for verification
    -- The accumulator value at that point is the checkpoint ID
    signal checkpoint_id : integer := 0;
    signal last_checkpoint_pc : std_logic_vector(13 downto 0) := (others => '1');  -- Track last checkpoint to avoid duplicates

    -- External address latches (like real 8008 external hardware)
    signal latched_address : std_logic_vector(13 downto 0) := (others => '0');

    -- External I/O port interface signals
    signal io_write_strobe : std_logic := '0';
    signal io_read_strobe  : std_logic := '0';
    signal io_full_port_num : std_logic_vector(4 downto 0) := (others => '0');

    -- Synthesis attributes to prevent optimization of I/O interface
    attribute keep : boolean;
    attribute keep of io_write_strobe : signal is true;
    attribute keep of io_read_strobe  : signal is true;
    attribute keep of io_full_port_num : signal is true;

    -- T-state decode from S[2:0]
    signal is_t1  : std_logic;
    signal is_t2  : std_logic;
    signal is_t3  : std_logic;
    signal is_t4  : std_logic;
    signal is_t5  : std_logic;

begin

    -- ========================================================================
    -- EXTERNAL ADDRESS LATCHING (Real 8008 Hardware Behavior)
    -- ========================================================================
    -- In real 8008, address is output on 8 bidirectional pins during T1/T2
    -- External latches capture the address so data can use same pins during T3
    -- Here we simulate this with internal latches

    -- Drive output ports from internal signals (VHDL-2008 fix)
    s0_out   <= s0_int;
    s1_out   <= s1_int;
    s2_out   <= s2_int;
    sync_out <= sync_int;

    -- Decode T-states from status signals (use internal signals)
    -- T1: S2=0, S1=1, S0=0 (binary 010)
    -- T2: S2=1, S1=0, S0=0 (binary 100)
    -- T3: S2=0, S1=0, S0=1 (binary 001)
    -- T4: S2=1, S1=1, S0=1 (binary 111)
    -- T5: S2=1, S1=0, S0=1 (binary 101)
    is_t1 <= '1' when (s2_int = '0' and s1_int = '1' and s0_int = '0') else '0';
    is_t2 <= '1' when (s2_int = '1' and s1_int = '0' and s0_int = '0') else '0';
    is_t3 <= '1' when (s2_int = '0' and s1_int = '0' and s0_int = '1') else '0';
    is_t4 <= '1' when (s2_int = '1' and s1_int = '1' and s0_int = '1') else '0';
    is_t5 <= '1' when (s2_int = '1' and s1_int = '0' and s0_int = '1') else '0';

    -- Latch address during T1 and T2 (when CPU outputs address on data bus)
    -- Real 8008 behavior: address is time-multiplexed on 8-bit data bus
    -- T1: Lower 8 bits on data bus (latch only during SYNC high - first half of T1)
    -- T2: Upper 6 bits on D[5:0], cycle type on D[7:6] (latch only during SYNC high)
    -- CRITICAL: Only latch during SYNC=1 (first half) to avoid re-latching after PC increments
    -- Hold latched address stable during T3 (when data bus used for data transfer)
    process(clk_in, reset)
    begin
        if reset = '1' then
            latched_address <= (others => '0');
        elsif rising_edge(clk_in) and phi1_rising = '1' then
            if is_t1 = '1' and sync_int = '1' then
                -- T1 first half (SYNC high): Latch lower 8 bits from data bus
                latched_address(7 downto 0) <= data_bus;
                report "ADDR_LATCH: T1 lower byte = 0x" & to_hstring(unsigned(data_bus));
            elsif is_t2 = '1' and sync_int = '1' then
                -- T2 first half (SYNC high): Latch upper 6 bits from data bus D[5:0]
                latched_address(13 downto 8) <= data_bus(5 downto 0);
                report "ADDR_LATCH: T2 upper byte = 0x" & to_hstring(unsigned(data_bus(5 downto 0))) &
                       " Full address = 0x" & to_hstring(unsigned(data_bus(5 downto 0) & latched_address(7 downto 0)));
            end if;
            -- During T3+: Hold latched value stable
        end if;
    end process;

    -- ========================================================================
    -- BOOTSTRAP CONTROL
    -- ========================================================================

    -- Set bootstrap_done flag after first T1I completes
    -- We detect when we LEAVE T1I state (transition to T2)
    process(clk_in, reset)
    begin
        if reset = '1' then
            bootstrap_done <= '0';
        elsif rising_edge(clk_in) and phi1_rising = '1' then
            -- When we're in T2 and bootstrap isn't done yet, T1I just completed
            if bootstrap_done = '0' and s2_int = '1' and s1_int = '0' and s0_int = '0' then
                bootstrap_done <= '1';
            end if;
        end if;
    end process;

    -- ========================================================================
    -- CPU INSTANCE
    -- ========================================================================

    u_cpu : b8008
        generic map (
            CLK_FREQ_HZ => CLK_FREQ_HZ
        )
        port map (
            clk_in      => clk_in,
            reset       => reset,
            run_enable  => run_enable,
            phi1_out    => phi1,
            phi2_out    => phi2,
            phi1_rising_out  => phi1_rising,
            phi1_falling_out => phi1_falling,
            phi2_rising_out  => phi2_rising,
            phi2_falling_out => phi2_falling,
            data_bus_in  => cpu_data_in,     -- CPU reads from input-only path (no loop)
            data_bus_out => cpu_data_out,    -- CPU outputs to separate signal
            data_bus_oe  => cpu_data_oe,     -- CPU output enable
            sync_out    => sync_int,
            s0_out      => s0_int,
            s1_out      => s1_int,
            s2_out      => s2_int,
            ready_in            => ready_in,
            interrupt           => interrupt,
            debug_reg_a         => debug_reg_a,
            debug_reg_b         => debug_reg_b,
            debug_reg_c         => debug_reg_c,
            debug_reg_d         => debug_reg_d,
            debug_reg_e         => debug_reg_e,
            debug_reg_h         => debug_reg_h,
            debug_reg_l         => debug_reg_l,
            debug_cycle         => debug_cycle,
            debug_pc            => debug_pc,
            debug_ir            => debug_ir,
            debug_needs_address => debug_needs_address,
            debug_int_pending   => debug_int_pending,
            cycle_type          => cycle_type,
            debug_flag_carry    => debug_flag_carry,
            debug_flag_zero     => debug_flag_zero,
            debug_flag_sign     => debug_flag_sign,
            debug_flag_parity   => debug_flag_parity,
            debug_state_half    => debug_state_half
        );

    -- ========================================================================
    -- MEMORY INSTANCES
    -- ========================================================================

    -- RAM: 8KB at 0x2000-0x3FFF (grown from 1KB for RAM-loaded programs)
    -- Uses LATCHED address (stable during T3 data transfer)
    -- Clocked on clk_in now (was phi1); CS_N + RW_N already gate writes
    -- to PCW/T3 windows, so multiple clk edges during that window just
    -- rewrite the same value.
    --
    -- EXTERNAL_RAM => false (default): internal ram_sync, unchanged path.
    -- EXTERNAL_RAM => true: no internal RAM; ram_data_out is fed from
    -- ram_ext_rdata and the ram_ext_* bus is driven instead (see contract
    -- above the port declarations). Assignments live inside each generate
    -- branch rather than a shared "when EXTERNAL_RAM else" -- GHDL trips
    -- on boolean generics used that way in a concurrent signal assignment.
    gen_ram_internal : if not EXTERNAL_RAM generate
        u_ram : ram_sync
            generic map (
                ADDR_BITS => RAM_ADDR_BITS,
                INIT_FILE => RAM_INIT_FILE
            )
            port map (
                CLK      => clk_in,
                ADDR     => latched_address(RAM_ADDR_BITS-1 downto 0),
                DATA_IN  => ram_data_in,
                DATA_OUT => ram_data_out,
                RW_N     => ram_rw_n,
                CS_N     => ram_cs_n
            );

        ram_ext_addr  <= (others => '0');
        ram_ext_wdata <= (others => '0');
        ram_ext_rw_n  <= '1';
        ram_ext_cs_n  <= '1';
    end generate gen_ram_internal;

    gen_ram_external : if EXTERNAL_RAM generate
        ram_data_out <= ram_ext_rdata;

        ram_ext_addr  <= std_logic_vector(resize(unsigned(latched_address(RAM_ADDR_BITS-1 downto 0)), 14));
        ram_ext_wdata <= ram_data_in;
        ram_ext_rw_n  <= ram_rw_n;
        ram_ext_cs_n  <= ram_cs_n;
    end generate gen_ram_external;

    -- Shadow of RAM location 0 for the ram_byte_0 debug output (the block RAM
    -- has no second read port; testbenches assert on this signal)
    process(clk_in)
    begin
        if rising_edge(clk_in) then
            if reset = '1' then
                ram_byte_0 <= (others => '0');
            elsif ram_cs_n = '0' and ram_rw_n = '0' and
                  unsigned(latched_address(RAM_ADDR_BITS-1 downto 0)) = 0 then
                ram_byte_0 <= ram_data_in;
            end if;
        end if;
    end process;

    -- ========================================================================
    -- ADDRESS DECODE LOGIC
    -- ========================================================================

    -- Decode the LATCHED address (stable during T3 data transfer).
    -- ROM range comes from the decoder's generic defaults; RAM grown to 8KB.
    u_decode : address_decoder
        generic map (
            ROM_BASE => ROM_BASE,
            ROM_LAST => ROM_LAST,
            RAM_BASE => RAM_BASE,
            RAM_LAST => RAM_LAST
        )
        port map (
            address  => latched_address,
            rom_sel  => rom_selected,
            ram_sel  => ram_selected,
            rom_cs_n => rom_cs_n_int,
            ram_cs_n => ram_cs_n
        );

    -- External ROM interface: address relative to ROM_BASE so a high-ROM
    -- personality (b8008_basic: ROM at 0x1000-0x3FFF) indexes from zero
    rom_a    <= std_logic_vector(resize(unsigned(latched_address) - ROM_BASE, 14));
    rom_ce_n <= rom_cs_n_int;
    rom_oe_n <= rom_cs_n_int;  -- Active during reads (directly active directly tied to CE for simplicity)

    -- ========================================================================
    -- DATA BUS MULTIPLEXING
    -- ========================================================================

    -- Decode cycle type for read/write control
    -- cycle_type: 00=PCI, 01=PCR, 10=PCC, 11=PCW
    -- PCW (cycle_type = "11") indicates memory write
    -- PCC (cycle_type = "10") indicates I/O operation
    is_write <= '1' when cycle_type = "11" else '0';
    is_io    <= '1' when cycle_type = "10" else '0';

    -- RAM RW_N: active low write enable
    -- Write (RW_N=0) during T3/T4/T5 of PCW cycles when RAM is selected
    ram_rw_n <= '0' when (is_write = '1' and ram_selected = '1' and
                         (is_t3 = '1' or is_t4 = '1' or is_t5 = '1')) else '1';

    -- RAM always receives data from bus (but only writes when RW_N=0)
    ram_data_in <= data_bus;

    -- ========================================================================
    -- I/O PORT SIMULATION
    -- ========================================================================

    -- Extract port number from latched address during I/O cycle
    -- Per isa.json: T1 outputs REG.A, T2 outputs REG.b (contains port number from opcode)
    -- INP encoding: 0100 MMM 1 where MMM (bits 3:1) is the port number
    -- OUT encoding: 01RR MMM 1 where MMM (bits 3:1) is the port number
    -- During T2, Reg.b is output. Data bus bits 5:0 are latched to address(13:8)
    -- So port number (opcode bits 3:1) ends up in address bits 11:9
    io_port_num <= latched_address(11 downto 9);  -- Opcode bits 3:1 (port number)

    -- Input port data multiplexer
    -- IMPORTANT: Default test values FIRST, then check for external override.
    -- This ensures synthesis doesn't optimize away paths when io_port_in is undriven.
    -- When io_port_in_enable='1' and port matches io_port_in_select, use external input.
    io_input_data <= x"55" when (io_port_in_enable = '0' and io_port_num = "000") else  -- Port 0: 0x55
                     x"AA" when (io_port_in_enable = '0' and io_port_num = "001") else  -- Port 1: 0xAA
                     x"42" when (io_port_in_enable = '0' and io_port_num = "010") else  -- Port 2: 0x42 ('B')
                     x"03" when (io_port_in_enable = '0' and io_port_num = "011") else  -- Port 3: 0x03
                     x"04" when (io_port_in_enable = '0' and io_port_num = "100") else  -- Port 4: 0x04
                     x"05" when (io_port_in_enable = '0' and io_port_num = "101") else  -- Port 5: 0x05
                     x"06" when (io_port_in_enable = '0' and io_port_num = "110") else  -- Port 6: 0x06
                     x"07" when (io_port_in_enable = '0' and io_port_num = "111") else  -- Port 7: 0x07
                     io_port_in when (io_port_in_enable = '1' and io_port_num = io_port_in_select) else
                     x"00";  -- Default fallback

    -- Calculate full port number (0-31) from address bits
    -- RR field (addr 13:12) gives base: 00=ports 0-7, 01=8-15, 10=16-23, 11=24-31
    -- MMM field (addr 11:9) gives offset within group
    io_full_port_num <= latched_address(13 downto 12) & io_port_num;

    -- Output port latches - capture data written by OUT instruction
    -- OUT instruction: CPU drives data_bus with accumulator value during T3
    -- Latch on clk_in gated by phi2_rising (equivalent to rising_edge(phi2),
    -- one clk cycle later, so the whole top stays on one clock domain)
    process(clk_in, reset)
        variable port_base : integer;
        variable is_out_cycle : std_logic;
        variable is_inp_cycle : std_logic;
    begin
        if reset = '1' then
            io_output_port_8  <= (others => '0');
            io_output_port_9  <= (others => '0');
            io_output_port_10 <= (others => '0');
            checkpoint_id <= 0;
            last_checkpoint_pc <= (others => '1');
            io_write_strobe <= '0';
            io_read_strobe  <= '0';
        elsif rising_edge(clk_in) and phi2_rising = '1' then
            -- Default: strobes off
            io_write_strobe <= '0';
            io_read_strobe  <= '0';

            -- Generate read strobe during T3 of I/O read (INP instruction)
            -- INP uses ports 0-7 (RR field = 00 in opcode 0100MMM1)
            -- RR field is opcode bits 5:4 which map to address bits 13:12
            is_inp_cycle := is_io and is_t3 and not latched_address(13) and not latched_address(12);
            if is_inp_cycle = '1' then
                io_read_strobe <= '1';
            end if;

            -- Latch output data during T3 of I/O write (OUT instruction)
            -- OUT uses ports 8-31 (RR field non-zero in opcode 01RRMMM1)
            -- RR field is opcode bits 5:4 which map to address bits 13:12
            -- INP has RR=00, OUT has RR≠00
            is_out_cycle := is_io and is_t3 and (latched_address(13) or latched_address(12));
            if is_out_cycle = '1' then
                -- Generate write strobe for external peripherals
                io_write_strobe <= '1';
                -- Calculate actual port number: base = RR * 8, port = base + MMM
                -- RR=01 -> ports 8-15, RR=10 -> ports 16-23, RR=11 -> ports 24-31
                port_base := to_integer(unsigned(latched_address(13 downto 12))) * 8;

                -- Check for CHECKPOINT port (port 31 = RR=11, MMM=111)
                if latched_address(13 downto 12) = "11" and io_port_num = "111" then
                    -- Port 31: CHECKPOINT assertion port
                    -- The A register contains the checkpoint ID (set by MVI A,N before OUT 31)
                    -- Only report if this is a new checkpoint (different PC than last)
                    if debug_pc /= last_checkpoint_pc then
                        checkpoint_id <= to_integer(unsigned(debug_reg_a));
                        last_checkpoint_pc <= debug_pc;
                        report "CHECKPOINT: ID=" & integer'image(to_integer(unsigned(debug_reg_a))) &
                               " PC=0x" & to_hstring(unsigned(debug_pc)) &
                               " A=0x" & to_hstring(unsigned(debug_reg_a)) &
                               " B=0x" & to_hstring(unsigned(debug_reg_b)) &
                               " C=0x" & to_hstring(unsigned(debug_reg_c)) &
                               " D=0x" & to_hstring(unsigned(debug_reg_d)) &
                               " E=0x" & to_hstring(unsigned(debug_reg_e)) &
                               " H=0x" & to_hstring(unsigned(debug_reg_h)) &
                               " L=0x" & to_hstring(unsigned(debug_reg_l)) &
                               " C=" & std_logic'image(debug_flag_carry)(2) &
                               " Z=" & std_logic'image(debug_flag_zero)(2) &
                               " S=" & std_logic'image(debug_flag_sign)(2) &
                               " P=" & std_logic'image(debug_flag_parity)(2);
                    end if;
                else
                    -- Regular output ports
                    case io_port_num is
                        when "000" =>
                            io_output_port_8 <= data_bus;
                            report "I/O: OUT port " & integer'image(port_base) & " = 0x" & to_hstring(unsigned(data_bus));
                        when "001" =>
                            io_output_port_9 <= data_bus;
                            report "I/O: OUT port " & integer'image(port_base + 1) & " = 0x" & to_hstring(unsigned(data_bus));
                        when "010" =>
                            io_output_port_10 <= data_bus;
                            report "I/O: OUT port " & integer'image(port_base + 2) & " = 0x" & to_hstring(unsigned(data_bus));
                        when others =>
                            report "I/O: OUT port " & integer'image(port_base + to_integer(unsigned(io_port_num))) &
                                   " = 0x" & to_hstring(unsigned(data_bus));
                    end case;
                end if;
            end if;
        end if;
    end process;

    -- Connect memory/IO data to CPU data bus
    -- Real 8008 behavior:
    --   T1: CPU outputs address lower byte on data bus (external hardware latches it)
    --   T2: CPU outputs address upper byte on data bus (external hardware latches it)
    --   T3-T5: External hardware (ROM/RAM/IO) drives data bus for CPU to read
    -- During T1I (interrupt acknowledge), jam RST 0 instruction (0x05) for bootstrap
    -- Data bus multiplexer: combines CPU output with memory/IO/interrupt data
    -- Priority order:
    -- 1. T1I: jam RST instruction (interrupt acknowledge)
    -- 2. CPU output enabled: CPU is driving address (T1/T2) or data (T3 write)
    -- 3. Memory/IO read: ROM, RAM, or I/O input during T3-T5
    -- 4. Default: zeros (should not occur in normal operation)
    --
    -- RST instruction opcode = 00 AAA 101 where AAA is the vector (0-7)
    -- RST 0 = 0x05, RST 1 = 0x0D, RST 2 = 0x15, RST 3 = 0x1D, etc.
    --
    -- cpu_data_in: Data TO the CPU - does NOT include cpu_data_out to break combinational loop
    -- This is what the CPU reads during T3-T5 (instruction fetch, memory read, I/O read)
    jam_byte_sel <= int_jam_byte when int_jam_en = '1' else ("00" & int_vector & "101");

    cpu_data_in <= jam_byte_sel when (s2_int = '1' and s1_int = '1' and s0_int = '0') else  -- T1I: jam instruction
                   io_input_data when (is_io = '1' and (is_t3 = '1' or is_t4 = '1' or is_t5 = '1') and
                                       latched_address(13 downto 12) = "00") else  -- INP: I/O input during T3/T4/T5
                   rom_d when (is_io = '0' and rom_selected = '1' and (is_t3 = '1' or is_t4 = '1' or is_t5 = '1')) else  -- External ROM during T3/T4/T5
                   ram_data_out when (is_io = '0' and ram_selected = '1' and (is_t3 = '1' or is_t4 = '1' or is_t5 = '1')) else  -- RAM during T3/T4/T5
                   (others => '0');  -- Default: zeros when CPU is driving or no valid source

    -- data_bus: Combined bus for external/debug use (includes CPU output)
    data_bus <= cpu_data_out when cpu_data_oe = '1' else cpu_data_in;

    -- ========================================================================
    -- DEBUG OUTPUTS
    -- ========================================================================

    phi1_out    <= phi1;
    phi2_out    <= phi2;
    address_out <= latched_address;  -- Latched from data bus during T1/T2
    data_out    <= data_bus;  -- Debug output: pass through as-is (may contain 'Z', 'X', etc.)

    -- I/O port debug outputs
    debug_io_port_8  <= io_output_port_8;
    debug_io_port_9  <= io_output_port_9;
    debug_io_port_10 <= io_output_port_10;

    -- External I/O port interface outputs
    io_port_out     <= data_bus;         -- Data being written (valid when io_port_write='1')
    io_port_num_out <= io_full_port_num; -- Port number (0-31)
    io_port_write   <= io_write_strobe;  -- Write strobe (one phi2 cycle during OUT T3)
    io_port_read    <= io_read_strobe;   -- Read strobe (one phi2 cycle during INP T3)

end architecture structural;

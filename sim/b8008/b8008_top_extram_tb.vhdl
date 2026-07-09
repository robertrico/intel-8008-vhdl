--------------------------------------------------------------------------------
-- b8008_top_extram_tb.vhdl
--------------------------------------------------------------------------------
-- Equivalence testbench for the b8008_top EXTERNAL_RAM option.
--
-- Instantiates two b8008_top DUTs driven by the exact same clock, reset,
-- interrupt bootstrap and ready sequence (copied from b8008_top_tb.vhdl):
--   DUT A - EXTERNAL_RAM => false (default): internal ram_sync, unchanged path
--   DUT B - EXTERNAL_RAM => true: RAM lives outside the top, wired through
--           ram_ext_addr/wdata/rdata/rw_n/cs_n to an external ram_sync
--           instance that implements the memory-port contract:
--
--   External RAM behaves exactly like ram_sync: on every rising clk_in
--   edge, ram_ext_rdata becomes the registered read of ram_ext_addr
--   (one-cycle latency, no CS gating on reads); a write occurs on the
--   edge when ram_ext_cs_n='0' and ram_ext_rw_n='0'.
--
-- Both DUTs run the same RAM-exercising program (ram_intensive_as) from
-- identical external ROMs. If EXTERNAL_RAM is truly a no-op on behavior,
-- A and B must produce bit-identical ram_byte_0 / debug_reg_a / debug_pc
-- at every sample point. Sampled every 100 us; any mismatch is FAIL.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.b8008_types.all;

entity b8008_top_extram_tb is
    generic (
        ROM_FILE : string := "test_programs/ram_intensive_as.mem"
    );
end entity b8008_top_extram_tb;

architecture testbench of b8008_top_extram_tb is

    -- Component declaration: b8008_top (with external ROM + external RAM interface)
    component b8008_top is
        generic (
            EXTERNAL_RAM  : boolean := false;
            RAM_ADDR_BITS : integer := 14;
            RAM_INIT_FILE : string  := ""
        );
        port (
            clk_in      : in  std_logic;
            reset       : in  std_logic;
            interrupt   : in  std_logic;
            int_vector  : in  std_logic_vector(2 downto 0) := "000";
            ready_in    : in  std_logic := '1';
            s0_out      : out std_logic;
            s1_out      : out std_logic;
            s2_out      : out std_logic;
            ram_byte_0  : out std_logic_vector(7 downto 0);
            debug_reg_a : out std_logic_vector(7 downto 0);
            debug_pc    : out std_logic_vector(13 downto 0);
            -- External ROM interface
            rom_a       : out std_logic_vector(13 downto 0);
            rom_d       : in  std_logic_vector(7 downto 0);
            rom_ce_n    : out std_logic;
            rom_oe_n    : out std_logic;
            -- External RAM interface (EXTERNAL_RAM => true only)
            ram_ext_addr  : out std_logic_vector(13 downto 0);
            ram_ext_wdata : out std_logic_vector(7 downto 0);
            ram_ext_rdata : in  std_logic_vector(7 downto 0) := x"00";
            ram_ext_rw_n  : out std_logic;
            ram_ext_cs_n  : out std_logic
        );
    end component;

    -- Component declaration: Synthesized ROM for testbench
    component rom_8kx8 is
        generic (
            ROM_FILE : string := "test_programs/alu_test_as.mem"
        );
        port (
            ADDR     : in  std_logic_vector(12 downto 0);
            DATA_OUT : out std_logic_vector(7 downto 0);
            CS_N     : in  std_logic;
            OE_N     : in  std_logic
        );
    end component;

    -- Component declaration: parameterized synchronous RAM (external RAM for DUT B)
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

    -- Shared stimulus signals (identical to both DUTs)
    signal clk_in      : std_logic := '0';
    signal reset       : std_logic := '1';
    signal interrupt   : std_logic := '0';
    signal ready_in    : std_logic := '1';
    signal int_vector  : std_logic_vector(2 downto 0) := "000";
    signal saw_wait_status : boolean := false;

    -- DUT A (internal RAM, defaults)
    signal a_s0_out, a_s1_out, a_s2_out : std_logic;
    signal a_ram_byte_0  : std_logic_vector(7 downto 0);
    signal a_debug_reg_a : std_logic_vector(7 downto 0);
    signal a_debug_pc    : std_logic_vector(13 downto 0);
    signal a_rom_a       : std_logic_vector(13 downto 0);
    signal a_rom_d       : std_logic_vector(7 downto 0);
    signal a_rom_ce_n    : std_logic;
    signal a_rom_oe_n    : std_logic;
    -- DUT A leaves the ram_ext_* bus unconnected (EXTERNAL_RAM => false)

    -- DUT B (external RAM)
    signal b_s0_out, b_s1_out, b_s2_out : std_logic;
    signal b_ram_byte_0  : std_logic_vector(7 downto 0);
    signal b_debug_reg_a : std_logic_vector(7 downto 0);
    signal b_debug_pc    : std_logic_vector(13 downto 0);
    signal b_rom_a       : std_logic_vector(13 downto 0);
    signal b_rom_d       : std_logic_vector(7 downto 0);
    signal b_rom_ce_n    : std_logic;
    signal b_rom_oe_n    : std_logic;
    signal b_ram_ext_addr  : std_logic_vector(13 downto 0);
    signal b_ram_ext_wdata : std_logic_vector(7 downto 0);
    signal b_ram_ext_rdata : std_logic_vector(7 downto 0);
    signal b_ram_ext_rw_n  : std_logic;
    signal b_ram_ext_cs_n  : std_logic;

    constant RAM_ADDR_BITS : integer := 14;

    -- Clock generation
    constant CLK_PERIOD : time := 10 ns;  -- 100 MHz
    signal test_running : boolean := true;

    -- Pass/fail tally
    signal mismatch_count : integer := 0;
    signal sample_count   : integer := 0;

begin

    -- ========================================================================
    -- DUT A: EXTERNAL_RAM => false (internal ram_sync, unchanged path)
    -- ========================================================================

    dut_a : b8008_top
        generic map (
            EXTERNAL_RAM => false
        )
        port map (
            clk_in      => clk_in,
            reset       => reset,
            interrupt   => interrupt,
            int_vector  => int_vector,
            ready_in    => ready_in,
            s0_out      => a_s0_out,
            s1_out      => a_s1_out,
            s2_out      => a_s2_out,
            ram_byte_0  => a_ram_byte_0,
            debug_reg_a => a_debug_reg_a,
            debug_pc    => a_debug_pc,
            rom_a       => a_rom_a,
            rom_d       => a_rom_d,
            rom_ce_n    => a_rom_ce_n,
            rom_oe_n    => a_rom_oe_n
        );

    u_rom_a : rom_8kx8
        generic map (
            ROM_FILE => ROM_FILE
        )
        port map (
            ADDR     => a_rom_a(12 downto 0),
            DATA_OUT => a_rom_d,
            CS_N     => a_rom_ce_n,
            OE_N     => a_rom_oe_n
        );

    -- ========================================================================
    -- DUT B: EXTERNAL_RAM => true, RAM owned outside the top
    -- ========================================================================

    dut_b : b8008_top
        generic map (
            EXTERNAL_RAM  => true,
            RAM_ADDR_BITS => RAM_ADDR_BITS
        )
        port map (
            clk_in      => clk_in,
            reset       => reset,
            interrupt   => interrupt,
            int_vector  => int_vector,
            ready_in    => ready_in,
            s0_out      => b_s0_out,
            s1_out      => b_s1_out,
            s2_out      => b_s2_out,
            ram_byte_0  => b_ram_byte_0,
            debug_reg_a => b_debug_reg_a,
            debug_pc    => b_debug_pc,
            rom_a       => b_rom_a,
            rom_d       => b_rom_d,
            rom_ce_n    => b_rom_ce_n,
            rom_oe_n    => b_rom_oe_n,
            ram_ext_addr  => b_ram_ext_addr,
            ram_ext_wdata => b_ram_ext_wdata,
            ram_ext_rdata => b_ram_ext_rdata,
            ram_ext_rw_n  => b_ram_ext_rw_n,
            ram_ext_cs_n  => b_ram_ext_cs_n
        );

    u_rom_b : rom_8kx8
        generic map (
            ROM_FILE => ROM_FILE
        )
        port map (
            ADDR     => b_rom_a(12 downto 0),
            DATA_OUT => b_rom_d,
            CS_N     => b_rom_ce_n,
            OE_N     => b_rom_oe_n
        );

    -- External RAM for DUT B, satisfying the memory-port contract above.
    -- Same INIT_FILE ("") as DUT A's internal ram_sync -- preload parity.
    u_ram_ext_b : ram_sync
        generic map (
            ADDR_BITS => RAM_ADDR_BITS,
            INIT_FILE => ""
        )
        port map (
            CLK      => clk_in,
            ADDR     => b_ram_ext_addr(RAM_ADDR_BITS-1 downto 0),
            DATA_IN  => b_ram_ext_wdata,
            DATA_OUT => b_ram_ext_rdata,
            RW_N     => b_ram_ext_rw_n,
            CS_N     => b_ram_ext_cs_n
        );

    -- ========================================================================
    -- CLOCK GENERATION (shared)
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

    -- Continuous WAIT-status watchdog for the READY/WAIT exercise below.
    -- Must run every clk_in edge (not just at the 100 us sample points)
    -- to actually catch the CPU parked in WAIT (status 000).
    wait_monitor : process(clk_in)
    begin
        if rising_edge(clk_in) then
            if a_s2_out = '0' and a_s1_out = '0' and a_s0_out = '0' then
                saw_wait_status <= true;
            end if;
        end if;
    end process;

    -- ========================================================================
    -- STIMULUS (bootstrap sequence copied from b8008_top_tb.vhdl) + MONITORING
    -- ========================================================================

    stimulus : process
    begin
        report "========================================";
        report "B8008_TOP EXTERNAL_RAM EQUIVALENCE TEST";
        report "Program: " & ROM_FILE;
        report "========================================";

        -- Hold reset and interrupt low
        reset <= '1';
        interrupt <= '0';
        wait for 200 ns;

        -- Release reset
        reset <= '0';
        report "Reset released - both CPUs in stopped state";
        wait for 100 ns;

        -- Assert bootstrap interrupt to start both CPUs
        interrupt <= '1';
        wait for 1 ns;
        report "Bootstrap interrupt asserted";

        -- Wait for T1I state on DUT A (S2='1', S1='1', S0='0'), then lower interrupt.
        -- Both DUTs share clk/reset/interrupt so they reach T1I in lockstep.
        wait until (a_s2_out = '1' and a_s1_out = '1' and a_s0_out = '0');
        wait for 50 ns;  -- Wait a bit into T1I
        interrupt <= '0';
        report "T1I detected - interrupt lowered";
        wait for 100 ns;

        report "Monitoring CPU execution (A=internal RAM, B=external RAM)...";

        -- Run for 30 ms in 100 us steps, sampling equivalence each step.
        -- Exercise READY/WAIT mid-run: both DUTs share ready_in so their
        -- WAIT-state behavior must also stay equivalent.
        for i in 1 to 300 loop
            wait for 100 us;
            sample_count <= sample_count + 1;

            if i = 15 then
                ready_in <= '0';
                report "READY dropped - both CPUs should park in WAIT";
            elsif i = 16 then
                assert saw_wait_status
                    report "ERROR: never saw WAIT status (000) while READY low"
                    severity error;
                ready_in <= '1';
                report "READY restored - both CPUs should resume";
            end if;

            if a_ram_byte_0 /= b_ram_byte_0 or
               a_debug_reg_a /= b_debug_reg_a or
               a_debug_pc /= b_debug_pc then
                mismatch_count <= mismatch_count + 1;
                report "FAIL @ " & time'image(now) & " sample " & integer'image(i) &
                       ": ram_byte_0 A=0x" & to_hstring(unsigned(a_ram_byte_0)) &
                       " B=0x" & to_hstring(unsigned(b_ram_byte_0)) &
                       " | debug_reg_a A=0x" & to_hstring(unsigned(a_debug_reg_a)) &
                       " B=0x" & to_hstring(unsigned(b_debug_reg_a)) &
                       " | debug_pc A=0x" & to_hstring(unsigned(a_debug_pc)) &
                       " B=0x" & to_hstring(unsigned(b_debug_pc))
                    severity error;
            end if;
        end loop;

        wait for 1 us;

        report "========================================";
        if mismatch_count = 0 then
            report "PASS: " & integer'image(sample_count) &
                   " samples, A and B stayed equivalent throughout";
        else
            report "FAIL: " & integer'image(mismatch_count) & " of " &
                   integer'image(sample_count) & " samples mismatched"
                severity error;
        end if;
        report "========================================";

        -- End simulation
        test_running <= false;
        wait;
    end process;

end architecture testbench;

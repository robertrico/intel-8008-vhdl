--------------------------------------------------------------------------------
-- hlt_int_pending_tb.vhdl
--------------------------------------------------------------------------------
-- XP-02: HLT executed while an interrupt is ALREADY pending (UM Fig 20,
-- the HLT-with-INT arc). The stored interrupt must wake the CPU without
-- the INT line being re-asserted.
--
-- Runs test_programs/xp02_test_as.mem:
--   1. Bootstrap RST 0 -> MAIN
--   2. TB pulses INT (2 us, then line low) during MVI A,55h with the
--      wake jam set to RST 1; asserts debug_int_pending latched
--   3. MAIN executes HLT with the interrupt pending
--   4. Assert: T1I arrives (bounded) with INT low the whole time -
--      a CPU that drops the pending interrupt on STOPPED entry hangs
--   5. Assert: handler ran (A=0x02, B=0xAA), final state STOPPED,
--      exactly 2 T1I total (bootstrap + pending-INT wake)
--
-- Pass/fail: severity-error assertions here ("ERROR:" lines) plus the
-- checkpoint dump (check_xp02_hlt_int_test.sh).
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity hlt_int_pending_tb is
    generic (
        ROM_FILE : string := "test_programs/xp02_test_as.mem"
    );
end entity hlt_int_pending_tb;

architecture testbench of hlt_int_pending_tb is

    constant CLK_PERIOD : time := 10 ns;  -- 100 MHz

    signal test_running : boolean := true;

    signal clk_in      : std_logic := '0';
    signal reset       : std_logic := '1';
    signal interrupt   : std_logic := '0';
    signal int_instruction : std_logic_vector(7 downto 0) := "00000101";
    signal ready_in    : std_logic := '1';
    signal phi1_out, phi2_out, sync_out : std_logic;
    signal s0_out, s1_out, s2_out : std_logic;
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
    signal rom_d    : std_logic_vector(7 downto 0);
    signal rom_ce_n : std_logic;
    signal rom_oe_n : std_logic;

    -- Status decodes (S0 S1 S2)
    signal in_t1i     : boolean;  -- 011
    signal in_stopped : boolean;  -- 110
    signal t1i_count  : natural := 0;
    signal stopped_seen : boolean := false;
    signal marker_seen  : boolean := false;
    signal hlt_seen     : boolean := false;  -- HLT (0x00) reached the IR

begin

    uut : entity work.b8008_top
        port map (
            clk_in      => clk_in,
            reset       => reset,
            interrupt   => interrupt,
            int_instruction => int_instruction,
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
            rom_d               => rom_d,
            rom_ce_n            => rom_ce_n,
            rom_oe_n            => rom_oe_n
        );

    u_rom : entity work.rom_8kx8
        generic map ( ROM_FILE => ROM_FILE )
        port map (
            ADDR     => rom_a(12 downto 0),
            DATA_OUT => rom_d,
            CS_N     => rom_ce_n,
            OE_N     => rom_oe_n
        );

    in_t1i     <= (s0_out = '0' and s1_out = '1' and s2_out = '1');
    in_stopped <= (s0_out = '1' and s1_out = '1' and s2_out = '0');

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

    -- HLT must actually execute: 0x00 in the IR after the marker MVI
    -- committed. (IR also resets to 0x00, hence the gate.)
    hlt_watch : process(clk_in)
    begin
        if rising_edge(clk_in) then
            if unsigned(debug_reg_a) = x"55" then
                marker_seen <= true;
            end if;
            if marker_seen and unsigned(debug_ir) = x"00" then
                hlt_seen <= true;
            end if;
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
        variable t_stopped : time := 0 ns;
        variable t_wake    : time := 0 ns;
    begin
        report "========================================";
        report "XP-02: HLT WITH INTERRUPT ALREADY PENDING";
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

        -- Arm: an INT pending at the MVI->HLT instruction boundary
        -- rightfully preempts HLT (boundary recognition), so the only
        -- window where "HLT executes with INT pending" exists is HLT's
        -- own cycle. Trigger on HLT reaching the IR (its T3), hold INT
        -- only until the pending FF confirms the latch, then release -
        -- the STORED interrupt is what must wake the CPU.
        wait until unsigned(debug_reg_a) = x"55" for 5 ms;
        assert unsigned(debug_reg_a) = x"55"
            report "ERROR: never reached the marker MVI A,55h" severity error;
        wait until hlt_seen for 1 ms;
        assert hlt_seen
            report "ERROR: HLT never reached the IR" severity error;
        report "HLT in IR - raising INT (wake jam = RST 1)";
        int_instruction <= "00001101";  -- RST 1
        interrupt <= '1';
        wait until debug_int_pending = '1' for 200 us;
        interrupt <= '0';               -- line LOW; only the FF remembers
        assert debug_int_pending = '1'
            report "ERROR: interrupt pulse was not latched as pending"
            severity error;
        report "Pending latched, INT line released";

        -- Watch for STOPPED entry (may be skipped if the RTL takes the
        -- Fig-20 arc straight to T1I) and require the pending-INT wake
        watch : for i in 1 to 50000 loop   -- 500 us bound
            if in_stopped and not stopped_seen then
                stopped_seen <= true;
                t_stopped := now;
            end if;
            if in_t1i then
                t_wake := now;
                exit watch;
            end if;
            wait for 10 ns;
        end loop;

        assert t_wake > 0 ns
            report "ERROR: pending interrupt never woke the CPU from HLT " &
                   "(stored INT lost on STOPPED entry)" severity error;

        if stopped_seen then
            report "STOPPED observed for " &
                   time'image(t_wake - t_stopped) & " before T1I wake";
        else
            report "No STOPPED status observed - direct HLT->T1I arc";
        end if;
        assert interrupt = '0'
            report "ERROR: TB bug - INT line was still high at wake"
            severity error;

        -- Handler must run to its final HLT with state intact
        wait until in_stopped for 2 ms;
        assert in_stopped
            report "ERROR: CPU did not reach the handler's final HLT"
            severity error;
        wait for 100 us;
        assert in_stopped
            report "ERROR: CPU did not STAY stopped at the handler's HLT"
            severity error;
        assert unsigned(debug_reg_a) = x"02"
            report "ERROR: handler did not run (A /= 0x02)" severity error;
        assert unsigned(debug_reg_b) = x"AA"
            report "ERROR: handler did not run (B /= 0xAA)" severity error;
        assert t1i_count = 2
            report "ERROR: expected exactly 2 T1I (bootstrap + wake), got " &
                   integer'image(t1i_count) severity error;

        report "========================================";
        report "XP-02 TEST COMPLETE (T1I total: " &
               integer'image(t1i_count) & ")";
        report "========================================";

        test_running <= false;
        wait;
    end process;

end architecture testbench;

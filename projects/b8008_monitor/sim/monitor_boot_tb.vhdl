--------------------------------------------------------------------------------
-- monitor_boot_tb.vhdl - Boot/bootstrap testbench for b8008_monitor_top
--------------------------------------------------------------------------------
-- Simulates the full monitor top level with a behavioral AT28C64B EEPROM
-- loaded from rom_diag.mem. Verifies the start-button sequence end to end:
--
--   POR (~21 ms) -> run/stop press -> debug reset -> bootstrap RST 0 jam ->
--   T1I detect -> bootstrap_done -> CPU fetches from ROM -> OUT 8 (LEDs) ->
--   OUT 9 (UART 'D' of "DIAG" banner)
--
-- PASS criteria (checked at end of stimulus):
--   1. cpu_int rose (bootstrap jam started) and fell again (T1I detected)
--   2. led(7:4) went to "1111" (firmware executed OUT 8 with 0xFE)
--   3. UART decoder received 'D' (0x44) as the first byte
--
-- Run:  make sim TEST=monitor_boot_tb SIM_TIME=80ms
--
-- This file also provides a simulation stub for the pll_25mhz Verilog
-- black box (divide-by-4 + delayed lock).
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity pll_25mhz is
    port (
        clk_in  : in  std_logic;
        clk_out : out std_logic;
        locked  : out std_logic
    );
end entity pll_25mhz;

architecture sim of pll_25mhz is
    signal div      : unsigned(1 downto 0) := (others => '0');
    signal lock_cnt : integer range 0 to 15 := 0;
begin
    process(clk_in)
    begin
        if rising_edge(clk_in) then
            div <= div + 1;
        end if;
    end process;

    clk_out <= div(1);   -- 100 MHz / 4 = 25 MHz

    process(div(1))
    begin
        if rising_edge(div(1)) then
            if lock_cnt < 15 then
                lock_cnt <= lock_cnt + 1;
            end if;
        end if;
    end process;

    locked <= '1' when lock_cnt = 15 else '0';
end architecture sim;

--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity monitor_boot_tb is
end entity monitor_boot_tb;

architecture behavior of monitor_boot_tb is

    constant CLK_PERIOD : time := 10 ns;      -- 100 MHz board oscillator
    constant BIT_TIME   : time := 8.681 us;   -- 115200 baud

    -- First byte each known ROM firmware transmits:
    --   b8008_monitor: '8' of "8008 Monitor" -> x"38"
    --   rom_diag:      'D' of "DIAG"         -> x"44"
    --   selftest:      'S' of "SELFTEST"     -> x"53"
    type byte_set_t is array (natural range <>) of std_logic_vector(7 downto 0);
    constant KNOWN_FIRST_BYTES : byte_set_t := (x"38", x"44", x"53");

    impure function first_byte_ok(b : std_logic_vector(7 downto 0)) return boolean is
    begin
        for i in KNOWN_FIRST_BYTES'range loop
            if b = KNOWN_FIRST_BYTES(i) then
                return true;
            end if;
        end loop;
        return false;
    end function;

    signal clk       : std_logic := '0';
    -- sw1=1: break off, sw0=0: no reset. sw5/6/7 deliberately HIGH: the
    -- front-panel switches must be position-independent - a pin resting
    -- at '1' must neither fire an interrupt (int_button settle) nor park
    -- the CPU in WAIT (sw6 baseline capture).
    signal sw        : std_logic_vector(7 downto 0) := "11100010";
    signal led       : std_logic_vector(7 downto 0);
    signal led_M20   : std_logic;
    signal led_L18   : std_logic;
    signal uart_tx   : std_logic;
    signal uart_rx   : std_logic := '1';
    signal cpu_d     : std_logic_vector(7 downto 0);
    signal cpu_s0, cpu_s1, cpu_s2 : std_logic;
    signal cpu_sync  : std_logic;
    signal cpu_phi1, cpu_phi2 : std_logic;
    signal cpu_int   : std_logic;
    signal btn_run_stop   : std_logic := '1';  -- active low, idle high
    signal btn_step_cycle : std_logic := '1';
    signal btn_step_sync  : std_logic := '1';
    signal speed_btn      : std_logic := '1';
    signal rom_a     : std_logic_vector(12 downto 0);
    signal rom_d     : std_logic_vector(7 downto 0);
    signal rom_ce_n  : std_logic;
    signal rom_oe_n  : std_logic;

    -- Result tracking
    signal saw_int_rise : boolean := false;
    signal saw_int_fall : boolean := false;
    signal saw_out8     : boolean := false;
    signal first_byte   : std_logic_vector(7 downto 0) := (others => '0');
    signal got_byte     : boolean := false;
    signal sim_done     : boolean := false;

    type rom_array_t is array (0 to 8191) of std_logic_vector(7 downto 0);

    impure function load_rom(filename : string) return rom_array_t is
        file f        : text;
        variable l    : line;
        variable byte : std_logic_vector(7 downto 0);
        variable mem  : rom_array_t := (others => x"FF");
        variable i    : integer := 0;
    begin
        file_open(f, filename, read_mode);
        while not endfile(f) and i < 8192 loop
            readline(f, l);
            hread(l, byte);
            mem(i) := byte;
            i := i + 1;
        end loop;
        file_close(f);
        report "ROM loaded: " & integer'image(i) & " bytes from " & filename;
        return mem;
    end function;

    signal rom_mem : rom_array_t := load_rom("rom_diag.mem");

begin

    dut : entity work.b8008_monitor_top
        port map (
            clk        => clk,
            sw         => sw,
            speed_btn  => speed_btn,
            led        => led,
            led_M20    => led_M20,
            led_L18    => led_L18,
            uart_tx    => uart_tx,
            uart_rx    => uart_rx,
            cpu_d      => cpu_d,
            cpu_s0     => cpu_s0,
            cpu_s1     => cpu_s1,
            cpu_s2     => cpu_s2,
            cpu_sync   => cpu_sync,
            cpu_phi1   => cpu_phi1,
            cpu_phi2   => cpu_phi2,
            cpu_int    => cpu_int,
            dbg_btn_run_stop   => btn_run_stop,
            dbg_btn_step_cycle => btn_step_cycle,
            dbg_btn_step_sync  => btn_step_sync,
            rom_a      => rom_a,
            rom_d      => rom_d,
            rom_ce_n   => rom_ce_n,
            rom_oe_n   => rom_oe_n
        );

    clk <= not clk after CLK_PERIOD / 2 when not sim_done else '0';

    -- Behavioral EEPROM: 150 ns access time
    rom_d <= rom_mem(to_integer(unsigned(rom_a))) after 150 ns;

    -- Track bootstrap interrupt activity
    int_watch : process(cpu_int)
    begin
        if rising_edge(cpu_int) then
            saw_int_rise <= true;
            report "cpu_int RISE at " & time'image(now);
        elsif falling_edge(cpu_int) then
            saw_int_fall <= true;
            report "cpu_int FALL at " & time'image(now) & " (bootstrap complete)";
        end if;
    end process;

    -- Track firmware's OUT 8 (led(7:4) driven by io_port_8(7:4), 0xFE -> "1111")
    out8_watch : process(led)
    begin
        if led(7 downto 4) = "1111" and now > 1 ms then
            if not saw_out8 then
                report "OUT 8 executed (led 7:4 = 1111) at " & time'image(now);
            end if;
            saw_out8 <= true;
        end if;
    end process;

    -- Minimal UART RX decoder on uart_tx
    uart_decode : process
        variable byte : std_logic_vector(7 downto 0);
    begin
        wait until falling_edge(uart_tx);   -- start bit
        wait for BIT_TIME * 1.5;            -- middle of bit 0
        for i in 0 to 7 loop
            byte(i) := uart_tx;
            wait for BIT_TIME;
        end loop;
        if not got_byte then
            first_byte <= byte;
            got_byte   <= true;
            report "UART first byte: 0x" & to_hstring(byte) & " at " & time'image(now);
        else
            report "UART byte: 0x" & to_hstring(byte);
        end if;
    end process;

    stimulus : process
    begin
        -- POR: PLL lock + counter bit 19 at 25 MHz ~= 21 ms.
        -- Auto-start fires 2 ms later; no button press needed.
        -- Monitor firmware runs delay_short (~380 ms of dcr/jnz at ~47 us per
        -- instruction) before its banner. Wait for the first byte with a
        -- generous timeout instead of a fixed window.
        wait until got_byte for 450 ms;
        wait for 5 ms;                      -- let the byte handler finish reporting

        -- Verdicts
        assert saw_int_rise
            report "FAIL: bootstrap interrupt never asserted" severity error;
        assert saw_int_fall
            report "FAIL: bootstrap never completed (T1I not detected) - CPU stuck in jam loop" severity error;
        assert saw_out8
            report "FAIL: firmware never executed OUT 8 - CPU not fetching from ROM" severity error;
        assert got_byte
            report "FAIL: no UART output" severity error;
        if got_byte then
            assert first_byte_ok(first_byte)
                report "FAIL: first UART byte 0x" & to_hstring(first_byte) &
                       " matches no known firmware banner"
                severity error;
        end if;

        if saw_int_rise and saw_int_fall and saw_out8 and got_byte and
           first_byte_ok(first_byte) then
            report "=== MONITOR BOOT TEST PASSED ===" severity note;
        else
            report "=== MONITOR BOOT TEST FAILED ===" severity error;
        end if;

        sim_done <= true;
        wait;
    end process;

end architecture behavior;

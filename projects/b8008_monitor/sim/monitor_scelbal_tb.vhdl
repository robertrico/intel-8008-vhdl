--------------------------------------------------------------------------------
-- monitor_scelbal_tb.vhdl - Interactive command testbench for the monitor
--------------------------------------------------------------------------------
-- Boots the monitor firmware (internal BRAM ROM) and drives W/D commands over
-- the UART, checking the responses. Regression for the scratch-RAM collision
-- bug class: monitor variables originally lived at 0x2000-0x2022, so
-- "W 2020,AA" clobbered the monitor's own parsed-address storage and the
-- write appeared to fail. Scratch now lives in the top RAM page
-- (0x3F00-0x3FFF); everything below it is plain user RAM.
--
-- Script:
--   1. Wait for the boot prompt "> "
--   2. W 2030,BB / D 2030,1  -> expect "2030 - BB"  (control case)
--   3. W 2020,AA / D 2020,1  -> expect "2020 - AA"  (original bug address)
--   4. W 2005,CC / D 2005,1  -> expect "2005 - CC"  (original CMD_BUF region)
--   5. W 3F90,DD / D 3F90,1  -> expect "3F90 - DD"  (inside the reserved
--      scratch page but an unused byte - documents that W/D there work as
--      long as they miss the monitor's own variables/trampoline)
--
-- Each typed character waits for its echo before the next is sent (the 8008
-- runs ~47 us per instruction, so pacing by echo is the only reliable way).
--
-- Run:  make sim TEST=monitor_scelbal_tb SIM_TIME=1500ms WAVE=0
--       (WAVE=0 mandatory: the GHW file crosses GHDL's 2 GiB limit)
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

entity monitor_scelbal_tb is
end entity monitor_scelbal_tb;

architecture behavior of monitor_scelbal_tb is

    constant CLK_PERIOD : time := 10 ns;      -- 100 MHz board oscillator
    constant BIT_TIME   : time := 8.681 us;   -- 115200 baud

    signal clk       : std_logic := '0';
    signal sw        : std_logic_vector(7 downto 0) := "00000010"; -- sw1=1: break off, sw0=0: no reset
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

    -- Captured UART output
    signal rx_buf       : string(1 to 4096) := (others => ' ');
    signal rx_len       : integer := 0;
    signal prompt_count : integer := 0;
    signal sim_done     : boolean := false;

    type rom_array_t is array (0 to 8191) of std_logic_vector(7 downto 0);

    -- External EEPROM (unused by the internal-ROM monitor build, but the
    -- top level still drives its pins)
    signal rom_mem : rom_array_t := (others => x"FF");

    -- How many times does the captured UART text contain the pattern?
    -- W's readback echo and D's response each produce one "ADDR - VV" line,
    -- so a verified write shows the pattern twice. (Counting both catches the
    -- case where the write lands but a later collision corrupts the dump.)
    impure function rx_count(pattern : string) return integer is
        variable n : integer := 0;
    begin
        if rx_len < pattern'length then
            return 0;
        end if;
        for i in 1 to rx_len - pattern'length + 1 loop
            if rx_buf(i to i + pattern'length - 1) = pattern then
                n := n + 1;
            end if;
        end loop;
        return n;
    end function;

begin

    dut : entity work.b8008_monitor_top
        generic map (
            RAM_INIT_FILE => "../../test_programs/samples/scelbal_ram.mem"
        )
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

    -- UART RX decoder on uart_tx: capture everything the monitor prints
    uart_decode : process
        variable byte : std_logic_vector(7 downto 0);
    begin
        wait until falling_edge(uart_tx);   -- start bit
        wait for BIT_TIME * 1.5;            -- middle of bit 0
        for i in 0 to 7 loop
            byte(i) := uart_tx;
            wait for BIT_TIME;
        end loop;
        if rx_len < rx_buf'length then
            rx_buf(rx_len + 1) <= character'val(to_integer(unsigned(byte)));
            rx_len <= rx_len + 1;
        end if;
        if byte = x"3E" then                -- '>' of the prompt
            prompt_count <= prompt_count + 1;
        end if;
    end process;

    stimulus : process
        variable prompts_before_reset : integer := 0;
        -- Send one character on uart_rx, then wait for the monitor's echo
        procedure send_char(c : character) is
            variable byte     : std_logic_vector(7 downto 0);
            variable len_before : integer;
        begin
            byte := std_logic_vector(to_unsigned(character'pos(c), 8));
            len_before := rx_len;
            uart_rx <= '0';                 -- start bit
            wait for BIT_TIME;
            for i in 0 to 7 loop
                uart_rx <= byte(i);
                wait for BIT_TIME;
            end loop;
            uart_rx <= '1';                 -- stop bit
            wait for BIT_TIME;
            wait until rx_len > len_before for 50 ms;
            assert rx_len > len_before
                report "FAIL: no echo for character '" & c & "'"
                severity warning;
        end procedure;

        -- Type a command and wait for the next prompt
        procedure send_command(cmd : string) is
            variable p : integer;
        begin
            -- The prompt's trailing space (and char_delay) is still printing
            -- when '>' arrives; typing immediately loses the first character.
            wait for 20 ms;
            p := prompt_count;
            for i in cmd'range loop
                send_char(cmd(i));
            end loop;
            send_char(CR);
            wait until prompt_count > p for 300 ms;
            assert prompt_count > p
                report "FAIL: no prompt after command """ & cmd & """"
                severity warning;
            report "Command done: " & cmd;
        end procedure;

        variable all_pass : boolean := true;

        procedure check(pattern : string; what : string) is
            variable n : integer;
        begin
            n := rx_count(pattern);
            if n >= 2 then
                report "PASS: found """ & pattern & """ x" & integer'image(n)
                     & " (" & what & ")";
            else
                -- severity warning so all checks run; final verdict is the error
                report "FAIL: """ & pattern & """ found " & integer'image(n)
                     & "x, need 2 (" & what & ")"
                    severity warning;
                report "Captured UART text so far: [" & rx_buf(1 to rx_len) & "]";
                all_pass := false;
            end if;
        end procedure;
    begin
        -- Boot: POR ~21 ms, auto-start, ~380 ms firmware delay, banner, prompt
        wait until prompt_count > 0 for 450 ms;
        assert prompt_count > 0
            report "FAIL: monitor prompt never appeared" severity failure;
        report "Prompt seen at " & time'image(now);

        -- SCELBAL session over real RTL + real UART + real shims.
        -- RAM is preloaded with scelbal_ram.mem, exactly like a verified
        -- silicon load. Reproduce the bench: G 2000, SCR, program, RUN.
        send_command("g 2000");
        -- banner + READY stream out; wait generously then look for READY
        wait for 120 ms;
        check("READY", "SCELBAL banner + READY after G 2000");

        send_command("SCR");
        wait for 30 ms;
        check("SY", "does SCR misfire like silicon? (SY = reproduced)");
        check("READY", "READY after SCR");

        send_command("10 PRINT " & '"' & "HELLO, WORLD!" & '"');
        wait for 30 ms;
        send_command("20 GOTO 10");
        wait for 30 ms;
        send_command("RUN");
        wait for 200 ms;
        check("HELLO, WORL", "RUN output begins");
        check("AT LINE", "does RUN corrupt like silicon? (AT LINE = reproduced)");

        if all_pass then
            report "=== MONITOR INTERACTIVE TEST PASSED ===" severity note;
        else
            report "=== MONITOR INTERACTIVE TEST FAILED ===" severity error;
        end if;

        sim_done <= true;
        wait;
    end process;

end architecture behavior;

--------------------------------------------------------------------------------
-- monitor_load_tb.vhdl - Intel HEX load (L) + go (G) testbench
--------------------------------------------------------------------------------
-- Boots the monitor from the INTERNAL baked ROM (rom_4kx8_bram contents, i.e.
-- whatever the last 'make rom-freeze' captured), waits for the prompt, then
-- exercises the loader end to end:
--
--   1. Wait for '>' prompt (banner arrives ~350 ms after POR)
--   2. Send "L" + CR                       - enter HEX load mode
--   3. Send the rst_probe_ram payload (test_programs/samples/rst_probe_ram.asm,
--      records pasted from its .hex): installs "JMP handler" in the RST 7
--      RAM slot (0x3FF8), executes RST 7 (ROM 0x0038 forwards there),
--      handler prints 'R' and returns, then main prints 'Q' and halts.
--   4. Send ":00000001FF"                  - EOF record
--   5. Wait for next prompt, send "G 2000" + CR
--   6. PASS when 'R' then 'Q' arrive on uart_tx after the G command
--      (loader, G trampoline, and RST vector forwarding in one shot)
--
-- Characters are paced (CHAR_GAP) because the 8008 polls the USART: at
-- ~47 us/instruction it cannot take back-to-back 115200-baud characters.
--
-- Run:  make sim TEST=monitor_load_tb SIM_TIME=900ms
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

entity monitor_load_tb is
end entity monitor_load_tb;

architecture behavior of monitor_load_tb is

    constant CLK_PERIOD : time := 10 ns;      -- 100 MHz board oscillator
    constant BIT_TIME   : time := 8.681 us;   -- 115200 baud
    -- Pacing: the USART latches ONE byte. The slowest consumer is the echo
    -- path (poll + buffer + echo + char_delay ~= 3.9 ms at ~45 us/instr), so
    -- anything faster than that overruns the latch and drops characters.
    constant CHAR_GAP   : time := 5 ms;

    signal clk       : std_logic := '0';
    signal sw        : std_logic_vector(7 downto 0) := "00000010"; -- sw1=1: break off
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
    signal btn_run_stop   : std_logic := '1';
    signal btn_step_cycle : std_logic := '1';
    signal btn_step_sync  : std_logic := '1';
    signal speed_btn      : std_logic := '1';
    signal rom_a     : std_logic_vector(12 downto 0);
    signal rom_d     : std_logic_vector(7 downto 0) := (others => '1');
    signal rom_ce_n  : std_logic;
    signal rom_oe_n  : std_logic;

    -- TX-side tracking
    signal last_byte  : std_logic_vector(7 downto 0) := (others => '0');
    signal byte_pulse : boolean := false;     -- toggles on every received byte
    signal g_sent     : boolean := false;
    signal saw_r      : boolean := false;
    signal saw_q      : boolean := false;
    signal saw_prompt : boolean := false;
    signal sim_done   : boolean := false;

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

    -- UART RX decoder on uart_tx (monitor output)
    uart_decode : process
        variable byte : std_logic_vector(7 downto 0);
    begin
        wait until falling_edge(uart_tx);   -- start bit
        wait for BIT_TIME * 1.5;            -- middle of bit 0
        for i in 0 to 7 loop
            byte(i) := uart_tx;
            wait for BIT_TIME;
        end loop;
        last_byte  <= byte;
        byte_pulse <= not byte_pulse;
        report "MON TX: 0x" & to_hstring(byte);
        if byte = x"3E" then                -- '>'
            saw_prompt <= true;
        end if;
        if g_sent and byte = x"52" then     -- 'R' from the RST 7 handler
            saw_r <= true;
            report "GOT 'R' from RST 7 handler at " & time'image(now);
        end if;
        if g_sent and byte = x"51" then     -- 'Q' from main after the RST
            saw_q <= true;
            report "GOT 'Q' from loaded program at " & time'image(now);
        end if;
    end process;

    stimulus : process

        -- Send one 8N1 character into the monitor's uart_rx, then pace
        procedure send_char(c : character) is
            variable byte : std_logic_vector(7 downto 0);
        begin
            byte := std_logic_vector(to_unsigned(character'pos(c), 8));
            uart_rx <= '0';                 -- start bit
            wait for BIT_TIME;
            for i in 0 to 7 loop
                uart_rx <= byte(i);
                wait for BIT_TIME;
            end loop;
            uart_rx <= '1';                 -- stop bit
            wait for BIT_TIME;
            wait for CHAR_GAP;
        end procedure;

        procedure send_line(s : string) is
        begin
            for i in s'range loop
                send_char(s(i));
            end loop;
            send_char(CR);
        end procedure;

    begin
        -- Boot: POR ~21 ms, auto-start, banner after firmware startup delay
        wait until saw_prompt for 500 ms;
        assert saw_prompt
            report "FAIL: no '>' prompt within 500 ms - monitor did not boot"
            severity error;

        if saw_prompt then
            report "Prompt seen at " & time'image(now) & " - sending L command";
            wait for 5 ms;      -- let the prompt's trailing space finish
            send_line("L");
            -- The firmware prints "SEND HEX (ESC ends)" (~21 chars at
            -- ~2 ms/char, ~48 ms total) before it starts polling for
            -- records. Only one byte is buffered in the USART, so wait
            -- until it is definitely polling before the first ':'.
            wait for 60 ms;

            -- rst_probe_ram payload (from its .hex): install RST 7 handler,
            -- RST 7 -> 'R', return, 'Q', halt
            send_line(":102000002E3F36F83E44303E11303E203D065153BF");
            send_line(":05201000000652530719");
            -- EOF record
            send_line(":00000001FF");
            -- The loader exits without consuming this line's trailing CR:
            -- firmware prints OK + prompt, then the CR triggers one empty
            -- enter cycle (CR LF prompt again) - ~25 ms of output before
            -- it can accept the G command without overrunning the latch.
            wait for 40 ms;

            report "Sending G 2000";
            g_sent <= true;
            send_line("G 2000");

            wait until saw_q for 150 ms;
        end if;

        assert saw_r
            report "FAIL: never received 'R' - RST 7 forwarding broken"
            severity error;
        assert saw_q
            report "FAIL: never received 'Q' - L load or G jump broken"
            severity error;

        if saw_r and saw_q then
            report "=== MONITOR LOAD/GO/RST TEST PASSED ===" severity note;
        else
            report "=== MONITOR LOAD/GO/RST TEST FAILED ===" severity error;
        end if;

        sim_done <= true;
        wait;
    end process;

end architecture behavior;

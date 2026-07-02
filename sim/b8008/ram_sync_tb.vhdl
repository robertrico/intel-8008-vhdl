--------------------------------------------------------------------------------
-- ram_sync_tb.vhdl - Testbench for the parameterized synchronous RAM
--------------------------------------------------------------------------------
-- Two instances under test:
--   u_1k : ADDR_BITS => 10 (1KB, drop-in for the old ram_1kx8_sync)
--   u_8k : ADDR_BITS => 13 (8KB, the new b8008_top data RAM)
--
-- Checks: synchronous write + one-clock-latency read at first/mid/last
-- address, write gating by CS_N and RW_N.
--
-- Run: make test-ram-sync
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ram_sync_tb is
end entity ram_sync_tb;

architecture behavior of ram_sync_tb is

    component ram_sync is
        generic (
            ADDR_BITS : integer := 10
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

    constant CLK_PERIOD : time := 10 ns;

    signal clk        : std_logic := '0';
    signal addr_1k    : std_logic_vector(9 downto 0)  := (others => '0');
    signal addr_8k    : std_logic_vector(12 downto 0) := (others => '0');
    signal data_in    : std_logic_vector(7 downto 0)  := (others => '0');
    signal dout_1k    : std_logic_vector(7 downto 0);
    signal dout_8k    : std_logic_vector(7 downto 0);
    signal rw_n       : std_logic := '1';
    signal cs_n       : std_logic := '1';
    signal sim_done   : boolean := false;
    signal fail_count : integer := 0;

begin

    u_1k : ram_sync
        generic map ( ADDR_BITS => 10 )
        port map (
            CLK      => clk,
            ADDR     => addr_1k,
            DATA_IN  => data_in,
            DATA_OUT => dout_1k,
            RW_N     => rw_n,
            CS_N     => cs_n
        );

    u_8k : ram_sync
        generic map ( ADDR_BITS => 13 )
        port map (
            CLK      => clk,
            ADDR     => addr_8k,
            DATA_IN  => data_in,
            DATA_OUT => dout_8k,
            RW_N     => rw_n,
            CS_N     => cs_n
        );

    clk <= not clk after CLK_PERIOD / 2 when not sim_done else '0';

    stimulus : process

        -- Write one byte to both RAMs at the same offset
        procedure wr(a : integer; d : integer) is
        begin
            addr_1k <= std_logic_vector(to_unsigned(a mod 1024, 10));
            addr_8k <= std_logic_vector(to_unsigned(a, 13));
            data_in <= std_logic_vector(to_unsigned(d, 8));
            cs_n    <= '0';
            rw_n    <= '0';
            wait until rising_edge(clk);
            wait for 1 ns;
            cs_n    <= '1';
            rw_n    <= '1';
        end procedure;

        -- Read both RAMs at an offset (one clock latency), check 8k value
        procedure rd_check(a : integer; exp_8k : integer; name : string) is
        begin
            addr_1k <= std_logic_vector(to_unsigned(a mod 1024, 10));
            addr_8k <= std_logic_vector(to_unsigned(a, 13));
            cs_n    <= '0';
            rw_n    <= '1';
            wait until rising_edge(clk);   -- registered read
            wait for 1 ns;
            cs_n    <= '1';
            assert dout_8k = std_logic_vector(to_unsigned(exp_8k, 8))
                report "FAIL [" & name & "] 8k read: expected 0x" &
                       to_hstring(to_unsigned(exp_8k, 8)) & " got 0x" &
                       to_hstring(unsigned(dout_8k))
                severity error;
            if dout_8k /= std_logic_vector(to_unsigned(exp_8k, 8)) then
                fail_count <= fail_count + 1;
            end if;
        end procedure;

    begin
        wait until rising_edge(clk);

        -- Write distinct data at first, mid, last of the 8K space
        wr(0,    16#A5#);
        wr(4096, 16#3C#);
        wr(8191, 16#7E#);

        -- Read back
        rd_check(0,    16#A5#, "first");
        rd_check(4096, 16#3C#, "mid");
        rd_check(8191, 16#7E#, "last");

        -- 1K instance: address 0 was written with 0xA5 (4096 mod 1024 = 0
        -- overwrote it with 0x3C, 8191 mod 1024 = 1023 got 0x7E)
        addr_1k <= (others => '0');
        cs_n    <= '0';
        wait until rising_edge(clk);
        wait for 1 ns;
        cs_n    <= '1';
        assert dout_1k = x"3C"
            report "FAIL [1k aliasing] expected 0x3C got 0x" &
                   to_hstring(unsigned(dout_1k))
            severity error;
        if dout_1k /= x"3C" then
            fail_count <= fail_count + 1;
        end if;

        -- Write gating: CS_N=1 must block the write
        addr_8k <= std_logic_vector(to_unsigned(0, 13));
        data_in <= x"FF";
        cs_n    <= '1';
        rw_n    <= '0';
        wait until rising_edge(clk);
        wait for 1 ns;
        rw_n    <= '1';
        rd_check(0, 16#A5#, "cs_n write gate");

        -- Write gating: RW_N=1 must block the write
        addr_8k <= std_logic_vector(to_unsigned(0, 13));
        data_in <= x"EE";
        cs_n    <= '0';
        rw_n    <= '1';
        wait until rising_edge(clk);
        wait for 1 ns;
        cs_n    <= '1';
        rd_check(0, 16#A5#, "rw_n write gate");

        if fail_count = 0 then
            report "=== RAM SYNC TEST PASSED ===" severity note;
        else
            report "=== RAM SYNC TEST FAILED: " & integer'image(fail_count) &
                   " checks failed ===" severity failure;
        end if;

        sim_done <= true;
        wait;
    end process;

end architecture behavior;

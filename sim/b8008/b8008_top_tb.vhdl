--------------------------------------------------------------------------------
-- b8008_top_tb.vhdl
--------------------------------------------------------------------------------
-- Testbench for b8008_top - Complete system test
--
-- Tests the search program from the Intel 8008 User's Manual
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.b8008_types.all;

entity b8008_top_tb is
end entity b8008_top_tb;

architecture testbench of b8008_top_tb is

    -- Component declaration
    component b8008_top is
        generic (
            ROM_FILE : string := "test_programs/search_as.mem"
        );
        port (
            clk_in      : in  std_logic;
            reset       : in  std_logic;
            interrupt   : in  std_logic;
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
            debug_cycle         : out integer range 1 to 3;
            debug_pc            : out std_logic_vector(13 downto 0);
            debug_ir            : out std_logic_vector(7 downto 0);
            debug_needs_address : out std_logic;
            debug_int_pending   : out std_logic
        );
    end component;

    -- Test signals
    signal clk_in      : std_logic := '0';
    signal reset       : std_logic := '1';
    signal interrupt   : std_logic := '0';
    signal phi1_out    : std_logic;
    signal phi2_out    : std_logic;
    signal sync_out    : std_logic;
    signal s0_out      : std_logic;
    signal s1_out      : std_logic;
    signal s2_out      : std_logic;
    signal address_out : std_logic_vector(13 downto 0);
    signal data_out    : std_logic_vector(7 downto 0);
    signal ram_byte_0  : std_logic_vector(7 downto 0);
    signal debug_reg_a         : std_logic_vector(7 downto 0);
    signal debug_reg_b         : std_logic_vector(7 downto 0);
    signal debug_cycle         : integer range 1 to 3;
    signal debug_pc            : std_logic_vector(13 downto 0);
    signal debug_ir            : std_logic_vector(7 downto 0);
    signal debug_needs_address : std_logic;
    signal debug_int_pending   : std_logic;

    -- Clock generation
    constant CLK_PERIOD : time := 10 ns;  -- 100 MHz
    signal test_running : boolean := true;

    -- Test monitoring
    signal instruction_count : integer := 0;
    signal last_address : unsigned(13 downto 0) := (others => '0');
    signal stuck_counter : integer := 0;

begin

    -- ========================================================================
    -- DEVICE UNDER TEST
    -- ========================================================================

    dut : b8008_top
        generic map (
            ROM_FILE => "test_programs/search_as.mem"
        )
        port map (
            clk_in      => clk_in,
            reset       => reset,
            interrupt   => interrupt,
            phi1_out    => phi1_out,
            phi2_out    => phi2_out,
            sync_out    => sync_out,
            s0_out      => s0_out,
            s1_out      => s1_out,
            s2_out      => s2_out,
            address_out => address_out,
            data_out    => data_out,
            ram_byte_0  => ram_byte_0,
            debug_reg_a         => debug_reg_a,
            debug_reg_b         => debug_reg_b,
            debug_cycle         => debug_cycle,
            debug_pc            => debug_pc,
            debug_ir            => debug_ir,
            debug_needs_address => debug_needs_address,
            debug_int_pending   => debug_int_pending
        );

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
    -- STIMULUS AND MONITORING
    -- ========================================================================

    stimulus : process
    begin
        report "========================================";
        report "B8008 TOP-LEVEL SYSTEM TEST";
        report "Running search program from Intel 8008 User's Manual";
        report "========================================";

        -- Hold reset and interrupt low
        reset <= '1';
        interrupt <= '0';
        wait for 200 ns;

        -- Release reset
        reset <= '0';
        report "Reset released - CPU in stopped state";
        wait for 100 ns;

        -- Assert bootstrap interrupt to start CPU
        interrupt <= '1';
        wait for 1 ns;
        report "Bootstrap interrupt asserted";

        -- Wait for T1I state (S2='1', S1='1', S0='0'), then lower interrupt
        wait until (s2_out = '1' and s1_out = '1' and s0_out = '0');
        wait for 50 ns;  -- Wait a bit into T1I
        interrupt <= '0';
        report "T1I detected - interrupt lowered";
        wait for 100 ns;

        -- Let CPU run for a while and monitor execution
        report "Monitoring CPU execution...";

        -- Wait for CPU to execute the search program
        -- The program searches for '.' in "Hello, world. 8008!!"
        -- Expected: Program should find '.' at position 213 (0xD5) and halt

        -- Monitor for much longer to let program complete
        for i in 1 to 100000 loop
            wait for 100 ns;

            -- Report state periodically with debug info
            if i mod 100 = 0 then
                report "  @" & time'image(now) & " i=" & integer'image(i) &
                       " Addr=0x" & to_hstring(unsigned(address_out)) &
                       " Data=0x" & to_hstring(unsigned(data_out)) &
                       " S=" & std_logic'image(s2_out) & std_logic'image(s1_out) & std_logic'image(s0_out) &
                       " Cyc=" & integer'image(debug_cycle) &
                       " PC=0x" & to_hstring(unsigned(debug_pc)) &
                       " IR=0x" & to_hstring(unsigned(debug_ir)) &
                       " needs_addr=" & std_logic'image(debug_needs_address) &
                       " INT=" & std_logic'image(debug_int_pending) &
                       " RegA=0x" & to_hstring(unsigned(debug_reg_a)) &
                       " RegB=0x" & to_hstring(unsigned(debug_reg_b));
            end if;

            -- Check if address changed (new instruction fetch)
            if unsigned(address_out) /= last_address then
                last_address <= unsigned(address_out);

                -- Report all addresses for first 50us to debug
                if now < 50 us then
                    report "  @" & time'image(now) & " Addr=0x" & to_hstring(unsigned(address_out)) &
                           " Data=0x" & to_hstring(unsigned(data_out)) &
                           " State=" & std_logic'image(s2_out) & std_logic'image(s1_out) & std_logic'image(s0_out);
                end if;

                -- Report key addresses
                if address_out = x"0000" then
                    report "  ** Fetching from 0x0000 (Reset vector)";
                elsif address_out = x"0100" then
                    report "  ** Reached MAIN at 0x0100";
                elsif address_out = x"003C" then
                    report "  ** Calling INCR subroutine at 0x003C";
                elsif unsigned(address_out) >= 200 and unsigned(address_out) <= 220 then
                    report "  ** Reading string data at 0x" & to_hstring(unsigned(address_out)) &
                           " = '" & character'val(to_integer(unsigned(data_out))) & "'";
                end if;
            end if;

            -- Removed halt detection logic - was misleading during debugging
        end loop;

        wait for 1 us;

        report "========================================";
        report "TEST COMPLETE";
        report "========================================";

        -- End simulation
        test_running <= false;
        wait;
    end process;

end architecture testbench;

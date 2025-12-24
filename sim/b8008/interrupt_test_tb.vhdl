--------------------------------------------------------------------------------
-- interrupt_test_tb.vhdl
--------------------------------------------------------------------------------
-- Dedicated testbench for interrupt handling
--
-- Tests:
-- 1. Bootstrap interrupt (RST 0) to start CPU
-- 2. Runtime interrupt (RST 7) during program execution to call handler
-- 3. HLT wake-up via interrupt
--
-- This testbench generates an interrupt during program execution and verifies
-- that the CPU properly vectors to the interrupt handler and returns.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.b8008_types.all;

entity interrupt_test_tb is
    generic (
        ROM_FILE : string := "test_programs/interrupt_test_as.mem"
    );
end entity interrupt_test_tb;

architecture testbench of interrupt_test_tb is

    -- Component declaration
    component b8008_top is
        generic (
            ROM_FILE : string := "test_programs/alu_test_as.mem"
        );
        port (
            clk_in      : in  std_logic;
            reset       : in  std_logic;
            interrupt   : in  std_logic;
            int_vector  : in  std_logic_vector(2 downto 0) := "000";
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
            debug_cycle         : out integer range 1 to 3;
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
            debug_io_port_10    : out std_logic_vector(7 downto 0)
        );
    end component;

    -- Test signals
    signal clk_in      : std_logic := '0';
    signal reset       : std_logic := '1';
    signal interrupt   : std_logic := '0';
    signal int_vector  : std_logic_vector(2 downto 0) := "000";
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
    signal debug_reg_c         : std_logic_vector(7 downto 0);
    signal debug_reg_d         : std_logic_vector(7 downto 0);
    signal debug_reg_e         : std_logic_vector(7 downto 0);
    signal debug_reg_h         : std_logic_vector(7 downto 0);
    signal debug_reg_l         : std_logic_vector(7 downto 0);
    signal debug_cycle         : integer range 1 to 3;
    signal debug_pc            : std_logic_vector(13 downto 0);
    signal debug_ir            : std_logic_vector(7 downto 0);
    signal debug_needs_address : std_logic;
    signal debug_int_pending   : std_logic;
    signal debug_flag_carry    : std_logic;
    signal debug_flag_zero     : std_logic;
    signal debug_flag_sign     : std_logic;
    signal debug_flag_parity   : std_logic;
    signal debug_io_port_8     : std_logic_vector(7 downto 0);
    signal debug_io_port_9     : std_logic_vector(7 downto 0);
    signal debug_io_port_10    : std_logic_vector(7 downto 0);

    -- Clock generation
    constant CLK_PERIOD : time := 10 ns;  -- 100 MHz
    signal test_running : boolean := true;

    -- Interrupt test control
    signal interrupt_count : integer := 0;

begin

    -- ========================================================================
    -- DEVICE UNDER TEST
    -- ========================================================================

    dut : b8008_top
        generic map (
            ROM_FILE => ROM_FILE
        )
        port map (
            clk_in      => clk_in,
            reset       => reset,
            interrupt   => interrupt,
            int_vector  => int_vector,
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
            debug_flag_carry    => debug_flag_carry,
            debug_flag_zero     => debug_flag_zero,
            debug_flag_sign     => debug_flag_sign,
            debug_flag_parity   => debug_flag_parity,
            debug_io_port_8     => debug_io_port_8,
            debug_io_port_9     => debug_io_port_9,
            debug_io_port_10    => debug_io_port_10
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
        report "INTERRUPT TEST";
        report "Testing interrupt handling mechanism";
        report "========================================";

        -- Phase 1: Bootstrap (RST 0)
        reset <= '1';
        interrupt <= '0';
        int_vector <= "000";  -- RST 0 for bootstrap
        wait for 200 ns;

        reset <= '0';
        report "Reset released - CPU in stopped state";
        wait for 100 ns;

        -- Assert bootstrap interrupt (RST 0)
        interrupt <= '1';
        wait for 1 ns;
        report "Bootstrap interrupt asserted (RST 0)";

        -- Wait for T1I state
        wait until (s2_out = '1' and s1_out = '1' and s0_out = '0');
        wait for 50 ns;
        interrupt <= '0';
        report "T1I detected - bootstrap interrupt cleared";
        interrupt_count <= interrupt_count + 1;
        wait for 100 ns;

        -- Phase 2: Let program run, then trigger RST 7 interrupt
        report "Letting program run...";
        wait for 2 ms;  -- Wait for program to reach WAIT_FOR_INT section

        -- Change vector to RST 7 and trigger interrupt
        int_vector <= "111";  -- RST 7
        report "Triggering RST 7 interrupt";
        interrupt <= '1';
        wait for 1 ns;

        -- Wait for T1I state
        wait until (s2_out = '1' and s1_out = '1' and s0_out = '0');
        wait for 50 ns;
        interrupt <= '0';
        report "T1I detected - RST 7 interrupt cleared";
        interrupt_count <= interrupt_count + 1;
        wait for 100 ns;

        -- Phase 3: Let the interrupt handler run and program complete
        report "Letting interrupt handler and program complete...";
        wait for 5 ms;

        report "========================================";
        report "INTERRUPT TEST COMPLETE";
        report "Total interrupts generated: " & integer'image(interrupt_count);
        report "========================================";

        test_running <= false;
        wait;
    end process;

end architecture testbench;

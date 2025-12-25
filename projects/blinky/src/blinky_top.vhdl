--------------------------------------------------------------------------------
-- Blinky Top Level - b8008 Block-Based Intel 8008 FPGA Implementation
--------------------------------------------------------------------------------
-- First hardware validation program for the b8008 CPU
--
-- Based on b8008_top with minimal FPGA integration:
--   - Generates bootstrap interrupt on reset
--   - Maps I/O port 8 to LEDs
--   - Runs blinky.asm program
--
-- Copyright (c) 2025 Robert Rico
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity blinky_top is
    port (
        -- System clock and reset
        clk         : in  std_logic;  -- 100 MHz system clock
        rst         : in  std_logic;  -- Active-low reset (from SW3-1)

        -- Board LEDs (active low)
        led_E16     : out std_logic;  -- Main blinky LED (LED0 from I/O port 8)
        led_D17     : out std_logic;  -- SYNC indicator
        led_D18     : out std_logic;  -- Phi1 clock (dim = running)
        led_E18     : out std_logic;  -- Phi2 clock (dim = running)
        led_F17     : out std_logic;  -- LED1 from I/O port 8
        led_F18     : out std_logic;  -- State T1 indicator
        led_E17     : out std_logic;  -- State T3 indicator
        led_F16     : out std_logic;  -- I/O cycle indicator
        led_M20     : out std_logic;  -- Interrupt pending
        led_L18     : out std_logic;  -- Always-on reference

        -- Button input
        speed_btn   : in  std_logic;

        -- CPU debug outputs (directly from b8008 for logic analyzer)
        cpu_d       : out std_logic_vector(7 downto 0);  -- Data bus
        cpu_s0      : out std_logic;
        cpu_s1      : out std_logic;
        cpu_s2      : out std_logic;
        cpu_sync    : out std_logic;
        cpu_phi1    : out std_logic;
        cpu_phi2    : out std_logic;
        cpu_ready   : out std_logic;
        cpu_int     : out std_logic;
        cpu_data_en : out std_logic
    );
end entity blinky_top;

architecture rtl of blinky_top is

    --------------------------------------------------------------------------------
    -- Component: b8008_top (CPU with ROM and RAM)
    --------------------------------------------------------------------------------
    component b8008_top is
        generic (
            ROM_FILE : string := "test_programs/alu_test_as.mem"
        );
        port (
            clk_in      : in std_logic;
            reset       : in std_logic;
            interrupt   : in std_logic;
            int_vector  : in std_logic_vector(2 downto 0);
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
            debug_io_port_10    : out std_logic_vector(7 downto 0)
        );
    end component;

    --------------------------------------------------------------------------------
    -- Internal Signals
    --------------------------------------------------------------------------------
    -- Clock and reset
    signal reset_sync   : std_logic_vector(1 downto 0) := (others => '1');
    signal reset_int    : std_logic;  -- Internal reset (active high)
    signal phi1         : std_logic;
    signal phi2         : std_logic;
    signal sync_sig     : std_logic;
    signal s0_sig       : std_logic;
    signal s1_sig       : std_logic;
    signal s2_sig       : std_logic;

    -- Bootstrap interrupt control
    signal bootstrap_int    : std_logic;  -- Interrupt signal for bootstrap
    signal bootstrap_done   : std_logic := '0';

    -- CPU debug signals
    signal address_sig      : std_logic_vector(13 downto 0);
    signal data_sig         : std_logic_vector(7 downto 0);
    signal int_pending_sig  : std_logic;

    -- I/O port outputs (directly from b8008_top)
    signal io_port_8    : std_logic_vector(7 downto 0);
    signal io_port_9    : std_logic_vector(7 downto 0);
    signal io_port_10   : std_logic_vector(7 downto 0);

    -- T-state decode
    signal is_t1        : std_logic;
    signal is_t3        : std_logic;
    signal is_io        : std_logic;

    -- Unused signals (required by port map)
    signal debug_reg_a, debug_reg_b, debug_reg_c : std_logic_vector(7 downto 0);
    signal debug_reg_d, debug_reg_e, debug_reg_h, debug_reg_l : std_logic_vector(7 downto 0);
    signal debug_cycle  : std_logic_vector(1 downto 0);
    signal debug_pc     : std_logic_vector(13 downto 0);
    signal debug_ir     : std_logic_vector(7 downto 0);
    signal debug_needs_address : std_logic;
    signal debug_flag_carry, debug_flag_zero, debug_flag_sign, debug_flag_parity : std_logic;
    signal ram_byte_0   : std_logic_vector(7 downto 0);

begin

    --------------------------------------------------------------------------------
    -- Reset Synchronization
    --------------------------------------------------------------------------------
    -- Synchronize external reset to avoid metastability
    -- SW3 switches are active-low: '0' = ON = normal operation, '1' = OFF = reset
    process(clk)
    begin
        if rising_edge(clk) then
            reset_sync <= reset_sync(0) & rst;
        end if;
    end process;

    -- Convert active-low reset to active-high for b8008
    reset_int <= reset_sync(1);  -- '1' = reset active

    --------------------------------------------------------------------------------
    -- Bootstrap Interrupt Control
    --------------------------------------------------------------------------------
    -- The 8008 requires a bootstrap interrupt (RST 0) to start execution at 0x0000
    -- Generate interrupt after reset releases, clear after T1I state detected
    process(clk, reset_int)
    begin
        if reset_int = '1' then
            bootstrap_int  <= '0';  -- Don't assert during reset
            bootstrap_done <= '0';
        elsif rising_edge(clk) then
            if bootstrap_done = '0' then
                -- Assert interrupt to trigger bootstrap
                bootstrap_int <= '1';

                -- Clear interrupt after T1I state detected (S2='1', S1='1', S0='0')
                -- This is when the interrupt has been acknowledged and RST 0 jammed
                if s2_sig = '1' and s1_sig = '1' and s0_sig = '0' then
                    bootstrap_int  <= '0';
                    bootstrap_done <= '1';
                end if;
            end if;
        end if;
    end process;

    --------------------------------------------------------------------------------
    -- b8008 CPU System Instance
    --------------------------------------------------------------------------------
    u_system : b8008_top
        generic map (
            ROM_FILE => "blinky.mem"
        )
        port map (
            clk_in      => clk,
            reset       => reset_int,
            interrupt   => bootstrap_int,
            int_vector  => "000",  -- RST 0 for bootstrap
            phi1_out    => phi1,
            phi2_out    => phi2,
            sync_out    => sync_sig,
            s0_out      => s0_sig,
            s1_out      => s1_sig,
            s2_out      => s2_sig,
            address_out => address_sig,
            data_out    => data_sig,
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
            debug_int_pending   => int_pending_sig,
            debug_flag_carry    => debug_flag_carry,
            debug_flag_zero     => debug_flag_zero,
            debug_flag_sign     => debug_flag_sign,
            debug_flag_parity   => debug_flag_parity,
            debug_io_port_8     => io_port_8,
            debug_io_port_9     => io_port_9,
            debug_io_port_10    => io_port_10
        );

    --------------------------------------------------------------------------------
    -- State Decode
    --------------------------------------------------------------------------------
    -- T1: S2=0, S1=1, S0=0 (binary 010)
    is_t1 <= '1' when (s2_sig = '0' and s1_sig = '1' and s0_sig = '0') else '0';

    -- T3: S2=0, S1=0, S0=1 (binary 001)
    is_t3 <= '1' when (s2_sig = '0' and s1_sig = '0' and s0_sig = '1') else '0';

    -- I/O cycle detection (simplified: check address range during T3)
    is_io <= '1' when (is_t3 = '1' and address_sig(13 downto 12) /= "00") else '0';

    --------------------------------------------------------------------------------
    -- LED Outputs (active low: '0' = LED ON)
    --------------------------------------------------------------------------------
    -- E16: Main blinky LED - LED0 from I/O port 8
    -- The blinky.asm program outputs 0xFE (LED on) or 0xFF (LED off) to port 8
    -- Since LEDs are active low, invert the bit: '0' in register = LED on
    led_E16 <= io_port_8(0);  -- Direct pass-through (0xFE bit0=0 -> LED ON)

    -- D17: SYNC indicator (appears dim when running)
    led_D17 <= not sync_sig;

    -- D18: Phi1 clock indicator (dim = running fast)
    led_D18 <= not phi1;

    -- E18: Phi2 clock indicator (dim = running fast)
    led_E18 <= not phi2;

    -- F17: LED1 from I/O port 8 (should stay off)
    led_F17 <= io_port_8(1);

    -- F18: T1 state indicator
    led_F18 <= not is_t1;

    -- E17: T3 state indicator
    led_E17 <= not is_t3;

    -- F16: I/O cycle indicator
    led_F16 <= not is_io;

    -- M20: Interrupt pending
    led_M20 <= not int_pending_sig;

    -- L18: Always-on reference (tied to NOT reset = on when running)
    led_L18 <= reset_int;  -- Off when running (active-low LED, reset='0' during run)

    --------------------------------------------------------------------------------
    -- CPU Debug Outputs (directly connected)
    --------------------------------------------------------------------------------
    cpu_d       <= data_sig;
    cpu_s0      <= s0_sig;
    cpu_s1      <= s1_sig;
    cpu_s2      <= s2_sig;
    cpu_sync    <= sync_sig;
    cpu_phi1    <= phi1;
    cpu_phi2    <= phi2;
    cpu_ready   <= '1';  -- Always ready
    cpu_int     <= bootstrap_int;
    cpu_data_en <= '1';  -- Bus always active

end architecture rtl;

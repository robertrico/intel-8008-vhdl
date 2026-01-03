--------------------------------------------------------------------------------
-- Example Top Level - b8008 Project Template
--------------------------------------------------------------------------------
-- Copy this project folder to create new b8008 programs.
--
-- To customize:
--   1. Copy this folder to projects/your_project/
--   2. Rename files (example.asm -> your_project.asm, etc.)
--   3. Change entity name below (example_top -> your_project_top)
--   4. Update ROM_FILE generic to match your .mem filename
--   5. Update Makefile with new names
--
-- IMPORTANT: Only use 100MHz clk for phase_clocks generation and POR.
--            All other logic must use phi1 or phi2.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity example_top is
    port (
        -- System clock (100 MHz LVDS)
        clk         : in  std_logic;

        -- DIP switches (directly active - active low means ON='0')
        sw          : in  std_logic_vector(7 downto 0);

        -- Button input
        speed_btn   : in  std_logic;

        -- LED outputs (directly active - directly active, accent active low)
        led         : out std_logic_vector(7 downto 0);
        led_M20     : out std_logic;
        led_L18     : out std_logic;

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

        -- Additional debug outputs for oscilloscope/logic analyzer
        dbg_reset_int      : out std_logic;  -- Internal reset signal (primary suspect!)
        dbg_bootstrap_int  : out std_logic;  -- Bootstrap interrupt active
        dbg_bootstrap_done : out std_logic;  -- Bootstrap completed
        dbg_state_half     : out std_logic;  -- Which half of 2-cycle state
        dbg_int_pending    : out std_logic;  -- CPU interrupt pending
        dbg_pc             : out std_logic_vector(7 downto 0)  -- PC low byte
    );
end entity example_top;

architecture rtl of example_top is

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
            debug_io_port_10    : out std_logic_vector(7 downto 0);
            debug_state_half    : out std_logic
        );
    end component;

    --------------------------------------------------------------------------------
    -- Internal Signals
    --------------------------------------------------------------------------------
    -- POR active signal - active high during reset, cleared after counter expires
    -- Use inverted logic: por_active starts '1', cleared to '0' when done
    signal por_active   : std_logic := '1';

    -- Reset from switch (synchronized to phi1)
    signal reset_sync   : std_logic_vector(2 downto 0) := (others => '1');
    signal reset_sw     : std_logic;  -- Reset from switch (active high)
    signal reset_int    : std_logic;  -- Combined reset: POR or switch (active high)

    -- CPU signals
    signal phi1         : std_logic;
    signal phi2         : std_logic;
    signal sync_sig     : std_logic;
    signal s0_sig       : std_logic;
    signal s1_sig       : std_logic;
    signal s2_sig       : std_logic;

    -- Bootstrap interrupt control
    signal bootstrap_int     : std_logic := '0';
    signal bootstrap_done    : std_logic := '0';
    signal bootstrap_counter : unsigned(7 downto 0) := (others => '0');

    -- CPU debug signals
    signal address_sig      : std_logic_vector(13 downto 0);
    signal data_sig         : std_logic_vector(7 downto 0);
    signal int_pending_sig  : std_logic;

    -- I/O port outputs (directly from b8008_top)
    signal io_port_8    : std_logic_vector(7 downto 0);
    signal io_port_9    : std_logic_vector(7 downto 0);
    signal io_port_10   : std_logic_vector(7 downto 0);

    -- Unused signals (required by port map)
    signal debug_reg_a, debug_reg_b, debug_reg_c : std_logic_vector(7 downto 0);
    signal debug_reg_d, debug_reg_e, debug_reg_h, debug_reg_l : std_logic_vector(7 downto 0);
    signal debug_cycle  : std_logic_vector(1 downto 0);
    signal debug_pc_sig : std_logic_vector(13 downto 0);
    signal debug_ir     : std_logic_vector(7 downto 0);
    signal debug_needs_address : std_logic;
    signal debug_flag_carry, debug_flag_zero, debug_flag_sign, debug_flag_parity : std_logic;
    signal ram_byte_0   : std_logic_vector(7 downto 0);
    signal state_half_sig : std_logic;

    -- Slow counter for visible LED blinking (debug) - runs on phi1
    -- Divides ~455kHz phi1 by 2^18 = ~1.7Hz for human-visible blinking
    signal slow_counter : unsigned(17 downto 0) := (others => '0');

    -- Raw clock counter - proves 100MHz is reaching FPGA
    -- Divides 100MHz by 2^26 = ~1.5Hz
    signal clk_counter : unsigned(25 downto 0) := (others => '0');

    -- Debug: Track if we ever see non-STOPPED states
    signal seen_not_stopped : std_logic := '0';  -- Latches if we ever exit STOPPED
    signal reset_pulse_count : unsigned(3 downto 0) := (others => '0');  -- Count resets after POR

begin

    --------------------------------------------------------------------------------
    -- Power-On Reset (POR) - ONLY place where clk is used directly
    --------------------------------------------------------------------------------
    -- FPGA flip-flops may power up in random states. This counter ensures
    -- we hold reset for ~10ms after power-up to allow everything to stabilize.
    -- NOTE: Must use clk here because phi1/phi2 are held static during reset!
    --
    -- Use inverted logic: por_active starts '1' (in reset), cleared to '0' when done
    -- This works regardless of FF initial state since we're clearing, not setting
    process(clk)
    begin
        if rising_edge(clk) then
            clk_counter <= clk_counter + 1;
            -- Clear por_active when bit 19 goes high (after ~5ms)
            if clk_counter(19) = '1' then
                por_active <= '0';
            end if;
        end if;
    end process;

    --------------------------------------------------------------------------------
    -- Reset Synchronization (using clk)
    --------------------------------------------------------------------------------
    -- SW3-1 (sw[0]) directly controls reset
    -- DIP switch: ON position (arrow up) = '0', OFF position (arrow down) = '1'
    -- We want: sw ON (='0') = normal operation, sw OFF (='1') = reset
    -- So reset_sw = sw(0) directly (no inversion needed)
    -- NOTE: Must use clk here because phi1 is static during reset!
    process(clk)
    begin
        if rising_edge(clk) then
            reset_sync <= reset_sync(1 downto 0) & sw(0);
        end if;
    end process;

    reset_sw <= reset_sync(2);  -- '1' = reset active (switch OFF/down)

    -- Combined reset: active during POR or when switch requests reset
    reset_int <= por_active or reset_sw;

    --------------------------------------------------------------------------------
    -- Bootstrap Interrupt Control (using phi2)
    --------------------------------------------------------------------------------
    -- The 8008 requires a bootstrap interrupt (RST 0) to start execution at 0x0000
    -- Generate interrupt after reset releases, hold for several phi2 cycles to ensure
    -- the CPU's interrupt_ready_ff latches it, then clear after T1I detected
    process(phi2, reset_int)
    begin
        if reset_int = '1' then
            bootstrap_int     <= '0';
            bootstrap_done    <= '0';
            bootstrap_counter <= (others => '0');
        elsif rising_edge(phi2) then
            if bootstrap_done = '0' then
                -- Assert interrupt and count cycles
                bootstrap_int <= '1';
                bootstrap_counter <= bootstrap_counter + 1;

                -- Hold interrupt for at least 16 cycles, then wait for T1I
                if bootstrap_counter >= 16 then
                    -- Clear interrupt after T1I state detected (S2='1', S1='1', S0='0')
                    if s2_sig = '1' and s1_sig = '1' and s0_sig = '0' then
                        bootstrap_int  <= '0';
                        bootstrap_done <= '1';
                    end if;
                end if;
            end if;
        end if;
    end process;

    --------------------------------------------------------------------------------
    -- b8008 CPU System Instance
    --------------------------------------------------------------------------------
    u_system : b8008_top
        generic map (
            ROM_FILE => "./example.mem"
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
            debug_pc            => debug_pc_sig,
            debug_ir            => debug_ir,
            debug_needs_address => debug_needs_address,
            debug_int_pending   => int_pending_sig,
            debug_flag_carry    => debug_flag_carry,
            debug_flag_zero     => debug_flag_zero,
            debug_flag_sign     => debug_flag_sign,
            debug_flag_parity   => debug_flag_parity,
            debug_io_port_8     => io_port_8,
            debug_io_port_9     => io_port_9,
            debug_io_port_10    => io_port_10,
            debug_state_half    => state_half_sig
        );

    --------------------------------------------------------------------------------
    -- Slow clock divider for visible LED debugging (using phi1)
    --------------------------------------------------------------------------------
    process(phi1)
    begin
        if rising_edge(phi1) then
            slow_counter <= slow_counter + 1;
        end if;
    end process;

    --------------------------------------------------------------------------------
    -- Debug: Track if we ever exit STOPPED state (S0=1, S1=1)
    -- STOPPED has S0=1, S1=1. Any other state will have different S0/S1 values.
    --------------------------------------------------------------------------------
    process(phi2, reset_int)
    begin
        if reset_int = '1' then
            seen_not_stopped <= '0';
        elsif rising_edge(phi2) then
            -- If we see anything other than STOPPED state, latch it
            -- STOPPED: S0=1, S1=1. If either is 0, we're not in STOPPED.
            if s0_sig = '0' or s1_sig = '0' then
                seen_not_stopped <= '1';
            end if;
        end if;
    end process;

    --------------------------------------------------------------------------------
    -- Debug: Count reset pulses after POR completes
    -- If reset_int pulses after por_active goes low, increment counter
    --------------------------------------------------------------------------------
    process(phi2)
        variable prev_reset : std_logic := '0';
    begin
        if rising_edge(phi2) then
            -- Detect rising edge of reset_int AFTER POR is done
            if por_active = '0' and reset_int = '1' and prev_reset = '0' then
                if reset_pulse_count < 15 then
                    reset_pulse_count <= reset_pulse_count + 1;
                end if;
            end if;
            prev_reset := reset_int;
        end if;
    end process;

    --------------------------------------------------------------------------------
    -- LED Outputs (directly active, accent active low)
    --------------------------------------------------------------------------------
    -- Drive LEDs from CPU I/O port 8 output (active low LEDs, active low data)
    -- io_port_8 directly drives LEDs: 0xFE = LED0 on, 0xFF = all off
    led <= io_port_8;

    -- M20: Interrupt pending
    led_M20 <= not int_pending_sig;

    -- L18: Always-on reference (tied to NOT reset = on when running)
    led_L18 <= reset_int;  -- Off when running (active-low LED, reset='0' during run)

    --------------------------------------------------------------------------------
    -- CPU Debug Outputs (directly connected)
    --------------------------------------------------------------------------------
    -- SWAPPED: cpu_d now shows PC, dbg_pc now shows data bus
    cpu_d       <= debug_pc_sig(7 downto 0);  -- PC low byte (swapped with data)
    cpu_s0      <= s0_sig;
    cpu_s1      <= s1_sig;
    cpu_s2      <= s2_sig;
    cpu_sync    <= sync_sig;
    cpu_phi1    <= phi1;
    cpu_phi2    <= phi2;
    cpu_ready   <= '1';  -- Always ready
    cpu_int     <= bootstrap_int;

    --------------------------------------------------------------------------------
    -- Additional Debug Outputs (for oscilloscope/logic analyzer)
    --------------------------------------------------------------------------------
    -- These are the key signals to investigate the T1I->STOPPED mystery
    dbg_reset_int      <= reset_int;       -- Primary suspect: is reset pulsing?
    dbg_bootstrap_int  <= bootstrap_int;   -- Bootstrap interrupt signal
    dbg_bootstrap_done <= bootstrap_done;  -- Has bootstrap completed?
    dbg_state_half     <= state_half_sig;  -- Which half of 2-cycle state
    dbg_int_pending    <= int_pending_sig; -- CPU interrupt pending signal
    dbg_pc             <= data_sig;  -- DATA BUS (swapped with PC for debugging)

end architecture rtl;

------------------------------------------------------------------
-- props.vhdl: decoder + machine_cycle_control + state_timing_generator
-- COMPOSITION cluster
--
-- The advance_state / cycle_done mutual exclusion is composition-
-- level only: module-locally false. Free decoder flags falsify it in
-- two unreal ways discovered while building this proof:
--   1. a mid-instruction decode flip (advance latched under one
--      instruction shape, cycle_done under another) - excluded by the
--      IR-load window contract below
--   2. a decode combination no opcode produces (HLT + needs_address
--      together) - excluded by instantiating the REAL decoder driven
--      by a free instruction byte
--   3. an IR byte that mutates BEFORE the half's phi1 pulse (MCC's
--      t3_rising arm samples the OLD instruction by design; the IR
--      loads later, at phi1_falling) - excluded by instantiating the
--      REAL instruction_register, which owns that timing
-- So the cluster is instruction_register + decoder + MCC + STG in
-- their real wiring; only the bus byte, the load strobe (confined to
-- T3, as memory_io_control drives it), and the phi pulses (one-clk,
-- non-coincident) are constrained environment.
--
-- This formalizes BOTH MAS section-4 TODO-props at once: the mutex,
-- under the decoder-flag validity window it depends on.
------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

library work;
use work.b8008_types.all;

entity mcc_stg_cluster_props is
    port (
        clk          : in std_logic;
        reset        : in std_logic;
        bus_in       : in std_logic_vector(7 downto 0);
        load_ir      : in std_logic;
        condition_met     : in std_logic;
        interrupt_pending : in std_logic;
        ready             : in std_logic
    );
end entity mcc_stg_cluster_props;

architecture formal of mcc_stg_cluster_props is
    signal t1, t2, t3, t4, t5, t1i, stopped, half : std_logic;
    signal s0, s1, s2 : std_logic;
    signal advance_state, cycle_done : std_logic;
    signal cycle_type : std_logic_vector(1 downto 0);
    signal current_cycle, next_cycle : integer range 0 to 3;

    signal d_needs_imm, d_needs_addr, d_is_io, d_is_write : std_logic;
    signal d_is_hlt, d_needs_t4t5, d_is_mem_ind : std_logic;
    signal d_is_alu, d_is_call, d_is_ret, d_is_rst : std_logic;
    signal d_writes_reg, d_reads_reg, d_uses_temp, d_inr_dcr : std_logic;
    signal d_bin_alu, d_rotate, d_test_true, d_eval, d_stop : std_logic;
    signal d_sss, d_ddd, d_rstv : std_logic_vector(2 downto 0);
    signal d_cc : std_logic_vector(1 downto 0);

    signal ir_byte : std_logic_vector(7 downto 0);
    signal ir_oe_dummy : std_logic;
    signal ir_b7, ir_b6, ir_b5, ir_b4, ir_b3, ir_b2, ir_b1, ir_b0 : std_logic;
    signal bus_p : std_logic_vector(7 downto 0);
    signal in_jam_cycle : std_logic := '0';

    -- Deterministic phase generator: the real phi cadence (rising,
    -- falling, phi2 phase, phi2_falling - one per clk, repeating),
    -- i.e. phase_clocks scaled to 4 clks per phi-cycle. Free pulses
    -- falsify the mutex unrealistically: a T-state with NO phi1 pulse
    -- leaves MCC's latches uncleared and its cycle counter stale.
    signal ph : natural range 0 to 3 := 0;
    signal phi1_rising, phi1_falling, phi2_falling : std_logic;
begin

    phase_gen: process(clk)
    begin
        if rising_edge(clk) then
            if ph = 3 then ph <= 0; else ph <= ph + 1; end if;
        end if;
    end process;
    phi1_rising  <= '1' when ph = 0 else '0';
    phi1_falling <= '1' when ph = 1 else '0';
    phi2_falling <= '1' when ph = 3 else '0';

    hist: process(clk)
    begin
        if rising_edge(clk) then
            bus_p <= bus_in;
            -- does the current machine cycle start with T1I? (mirrors
            -- memory_io_control's ir_loaded_from_interrupt semantics)
            if t1i = '1' then
                in_jam_cycle <= '1';
            elsif t1 = '1' then
                in_jam_cycle <= '0';
            end if;
        end if;
    end process;

    u_ir: entity work.instruction_register
        port map (
            clk => clk, phi1_falling => phi1_falling, reset => reset,
            internal_bus_in => bus_in,
            internal_bus_out => ir_byte, internal_bus_oe => ir_oe_dummy,
            load_ir => load_ir, output_ir => '0',
            ir_bit_7 => ir_b7, ir_bit_6 => ir_b6, ir_bit_5 => ir_b5,
            ir_bit_4 => ir_b4, ir_bit_3 => ir_b3, ir_bit_2 => ir_b2,
            ir_bit_1 => ir_b1, ir_bit_0 => ir_b0);

    u_dec: entity work.instruction_decoder
        port map (
            instruction_byte => ir_byte,
            instr_needs_immediate => d_needs_imm,
            instr_needs_address => d_needs_addr,
            instr_is_io => d_is_io, instr_is_write => d_is_write,
            instr_sss_field => d_sss, instr_ddd_field => d_ddd,
            instr_is_alu => d_is_alu, instr_is_call => d_is_call,
            instr_is_ret => d_is_ret, instr_is_rst => d_is_rst,
            instr_is_hlt => d_is_hlt,
            instr_writes_reg => d_writes_reg,
            instr_reads_reg => d_reads_reg,
            instr_is_mem_indirect => d_is_mem_ind,
            instr_uses_temp_regs => d_uses_temp,
            instr_is_inr_dcr => d_inr_dcr,
            instr_is_binary_alu => d_bin_alu,
            instr_is_rotate => d_rotate,
            instr_needs_t4t5 => d_needs_t4t5,
            rst_vector => d_rstv, condition_code => d_cc,
            test_true => d_test_true, eval_condition => d_eval,
            transition_to_stopped => d_stop);

    u_stg: entity work.state_timing_generator
        port map (
            clk => clk, phi2_falling => phi2_falling, reset => reset,
            advance_state => advance_state, cycle_done => cycle_done,
            interrupt_pending => interrupt_pending, ready => ready,
            transition_to_stopped => d_stop,
            state_t1 => t1, state_t2 => t2, state_t3 => t3,
            state_t4 => t4, state_t5 => t5, state_t1i => t1i,
            state_stopped => stopped, state_half => half,
            status_s0 => s0, status_s1 => s1, status_s2 => s2);

    u_mcc: entity work.machine_cycle_control
        port map (
            clk => clk, phi1_rising => phi1_rising, reset => reset,
            state_t1 => t1, state_t2 => t2, state_t3 => t3,
            state_t4 => t4, state_t5 => t5, state_t1i => t1i,
            state_half => half,
            instr_needs_immediate => d_needs_imm,
            instr_needs_address => d_needs_addr,
            instr_is_io => d_is_io, instr_is_write => d_is_write,
            instr_is_hlt => d_is_hlt,
            instr_needs_t4t5 => d_needs_t4t5,
            instr_is_mem_indirect => d_is_mem_ind,
            eval_condition => d_eval,
            condition_met => condition_met,
            advance_state => advance_state, cycle_done => cycle_done,
            cycle_type => cycle_type,
            current_cycle => current_cycle, next_cycle => next_cycle);

    default clock is rising_edge(clk);

    -- IR-load discipline (MAS section 4; memory_io_control behavior,
    -- verified by its cocotb scenario suite and check_jam_test.sh):
    --  a) loads happen only at a FETCH (PCI) T3 or during the T1I jam
    --     (a data cycle's T3 never reloads - discovered here: a free
    --     reload at a PCR T3 plants HLT mid-instruction and latches
    --     advance on top of the pending cycle_done)
    --  b) a T1I cycle ALWAYS jams (ir_load = state_half during T1I)
    --  c) a jam cycle's T3 never reloads (ir_loaded_from_interrupt)
    --  d) the fetched/jammed byte is stable across the loading state
    -- The mutex DEPENDS on this contract; the assume-guarantee link is
    -- discharged by the cocotb suites above.
    assume always (load_ir = '1') ->
        ((t3 = '1' and cycle_type = "00" and in_jam_cycle = '0') or t1i = '1');
    assume always ((t1i = '1') and (half = '1')) -> (load_ir = '1');
    assume always (t3 = '1' or t1i = '1') -> (bus_in = bus_p);

    -- THE obligation: instruction-complete and cycle-over-mid-
    -- instruction are mutually exclusive in composition
    assert always (not (advance_state = '1' and cycle_done = '1'));

    -- Reachability: both signals individually attainable in the loop
    cover {(advance_state = '1')};
    cover {(cycle_done = '1')};

end architecture formal;

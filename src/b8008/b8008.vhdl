--------------------------------------------------------------------------------
-- b8008.vhdl
--------------------------------------------------------------------------------
-- Intel 8008 Block-Based Implementation - Top-Level Integration
--
-- This is the top-level entity that:
--   1. Instantiates all 21 functional component modules
--   2. Wires internal signals between components
--   3. Provides external interface (address bus, data bus, control signals)
--   4. Manages internal tri-state bus arbitration
--
-- Architecture follows Intel 8008 Rev 2 block diagram:
--   - Two-phase non-overlapping clock (phi1/phi2)
--   - 14-bit address space
--   - 8-level internal stack
--   - Seven 8-bit registers (A, B, C, D, E, H, L)
--   - 5 timing states per machine cycle (T1-T5)
--   - 3 machine cycles maximum per instruction
--
-- For detailed integration plan, see: gameplan.txt
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.b8008_types.all;

entity b8008 is
    port (
        -- ====================================================================
        -- CLOCKS AND RESET
        -- ====================================================================
        clk_in : in std_logic;   -- Master clock input
        reset  : in std_logic;   -- Asynchronous reset (active high)

        -- When low, freezes the phase-clock state machine so the CPU holds
        -- its current state. Used by debug_clock_control for stop/step.
        -- Defaults to '1' (always run) for existing instantiations.
        run_enable : in std_logic := '1';

        phi1_out : out std_logic;  -- Phase 1 clock output (for debugging)
        phi2_out : out std_logic;  -- Phase 2 clock output (for debugging)

        -- One-cycle edge pulses on clk_in domain, so consumers of the CPU
        -- can gate their own clk_in-domain logic on phi transitions without
        -- being clocked by phi1/phi2 directly.
        phi1_rising_out  : out std_logic;
        phi1_falling_out : out std_logic;
        phi2_rising_out  : out std_logic;
        phi2_falling_out : out std_logic;

        -- ====================================================================
        -- DATA BUS (Address and data are time-multiplexed on this bus)
        -- Separate input/output for synthesis compatibility (GHDL doesn't synth inOut across hierarchy)
        -- ====================================================================
        data_bus_in  : in  std_logic_vector(7 downto 0);  -- Data from external memory/IO
        data_bus_out : out std_logic_vector(7 downto 0);  -- Data/address to external memory/IO
        data_bus_oe  : out std_logic;                     -- Output enable (active high = CPU drives bus)

        -- ====================================================================
        -- TIMING AND STATUS
        -- ====================================================================
        sync_out : out std_logic;  -- SYNC signal (high during first half of T-state)
        s0_out   : out std_logic;  -- Status bit 0
        s1_out   : out std_logic;  -- Status bit 1
        s2_out   : out std_logic;  -- Status bit 2

        -- ====================================================================
        -- CONTROL INPUTS
        -- ====================================================================
        ready_in  : in std_logic;  -- READY signal (halt CPU if '0')
        interrupt : in std_logic;  -- INTERRUPT request

        -- ====================================================================
        -- DEBUG OUTPUTS
        -- ====================================================================
        -- CPU Registers (A, B, C, D, E, H, L)
        debug_reg_a           : out std_logic_vector(7 downto 0);
        debug_reg_b           : out std_logic_vector(7 downto 0);
        debug_reg_c           : out std_logic_vector(7 downto 0);
        debug_reg_d           : out std_logic_vector(7 downto 0);
        debug_reg_e           : out std_logic_vector(7 downto 0);
        debug_reg_h           : out std_logic_vector(7 downto 0);
        debug_reg_l           : out std_logic_vector(7 downto 0);
        -- Control state
        debug_cycle           : out std_logic_vector(1 downto 0);  -- Cycle 1-3 (encoded as 00, 01, 10)
        debug_pc              : out std_logic_vector(13 downto 0);
        debug_ir              : out std_logic_vector(7 downto 0);
        debug_needs_address   : out std_logic;
        debug_int_pending     : out std_logic;
        -- Cycle type output for external memory control
        cycle_type            : out std_logic_vector(1 downto 0);  -- 00=PCI, 01=PCR, 10=PCC, 11=PCW
        -- Debug flag outputs
        debug_flag_carry      : out std_logic;
        debug_flag_zero       : out std_logic;
        debug_flag_sign       : out std_logic;
        debug_flag_parity     : out std_logic;
        -- State timing debug
        debug_state_half      : out std_logic   -- Which half of 2-cycle state (0=first, 1=second)
    );
end entity b8008;

architecture structural of b8008 is

    -- ========================================================================
    -- COMPONENT DECLARATIONS
    -- ========================================================================

    -- ------------------------------------------------------------------------
    -- PHASE 2: CLOCK AND TIMING
    -- ------------------------------------------------------------------------

    component phase_clocks is
        port (
            clk_in       : in std_logic;
            reset        : in std_logic;
            run_enable   : in std_logic;
            phi1         : out std_logic;
            phi2         : out std_logic;
            sync         : out std_logic;
            phi1_rising  : out std_logic;
            phi1_falling : out std_logic;
            phi2_rising  : out std_logic;
            phi2_falling : out std_logic
        );
    end component;

    component state_timing_generator is
        port (
            clk                   : in std_logic;
            phi2_falling          : in std_logic;
            reset                 : in std_logic;
            advance_state         : in std_logic;
            interrupt_pending     : in std_logic;
            ready                 : in std_logic;
            instr_is_hlt_flag     : in std_logic;
            transition_to_stopped : in std_logic;
            state_t1              : out std_logic;
            state_t2              : out std_logic;
            state_t3              : out std_logic;
            state_t4              : out std_logic;
            state_t5              : out std_logic;
            state_t1i             : out std_logic;
            state_stopped         : out std_logic;
            state_half            : out std_logic;
            status_s0             : out std_logic;
            status_s1             : out std_logic;
            status_s2             : out std_logic
        );
    end component;

    -- ------------------------------------------------------------------------
    -- PHASE 3: CONTROL AND DECODE
    -- ------------------------------------------------------------------------

    component machine_cycle_control is
        port (
            clk                   : in std_logic;
            phi1_rising           : in std_logic;
            reset                 : in std_logic;
            state_t1              : in std_logic;
            state_t2              : in std_logic;
            state_t3              : in std_logic;
            state_t4              : in std_logic;
            state_t5              : in std_logic;
            state_t1i             : in std_logic;
            instr_needs_immediate : in std_logic;
            instr_needs_address   : in std_logic;
            instr_is_io           : in std_logic;
            instr_is_write        : in std_logic;
            instr_is_hlt          : in std_logic;
            instr_needs_t4t5      : in std_logic;
            eval_condition        : in std_logic;
            condition_met         : in std_logic;
            advance_state         : out std_logic;
            instr_is_hlt_flag     : out std_logic;
            cycle_type            : out std_logic_vector(1 downto 0);
            current_cycle         : out integer range 0 to 3;
            next_cycle            : out integer range 0 to 3
        );
    end component;

    component instruction_decoder is
        port (
            instruction_byte      : in std_logic_vector(7 downto 0);
            instr_needs_immediate : out std_logic;
            instr_needs_address   : out std_logic;
            instr_is_io           : out std_logic;
            instr_is_write        : out std_logic;
            instr_sss_field       : out std_logic_vector(2 downto 0);
            instr_ddd_field       : out std_logic_vector(2 downto 0);
            instr_is_alu          : out std_logic;
            instr_is_call         : out std_logic;
            instr_is_ret          : out std_logic;
            instr_is_rst          : out std_logic;
            instr_is_hlt          : out std_logic;
            instr_writes_reg      : out std_logic;
            instr_reads_reg       : out std_logic;
            instr_is_mem_indirect : out std_logic;
            instr_uses_temp_regs  : out std_logic;
            instr_is_inr_dcr      : out std_logic;
            instr_is_binary_alu   : out std_logic;
            instr_is_rotate       : out std_logic;
            instr_needs_t4t5      : out std_logic;
            rst_vector            : out std_logic_vector(2 downto 0);
            condition_code        : out std_logic_vector(1 downto 0);
            test_true             : out std_logic;
            eval_condition        : out std_logic;
            transition_to_stopped : out std_logic
        );
    end component;

    component memory_io_control is
        port (
            clk                   : in std_logic;
            phi1_rising           : in std_logic;
            reset                 : in std_logic;
            state_t1              : in std_logic;
            state_t2              : in std_logic;
            state_t3              : in std_logic;
            state_t4              : in std_logic;
            state_t5              : in std_logic;
            state_t1i             : in std_logic;
            state_stopped         : in std_logic;
            state_half            : in std_logic;
            status_s0             : in std_logic;
            status_s1             : in std_logic;
            status_s2             : in std_logic;
            cycle_type            : in std_logic_vector(1 downto 0);
            current_cycle         : in integer range 0 to 3;
            next_cycle            : in integer range 0 to 3;
            advance_state         : in std_logic;
            instr_is_hlt_flag     : in std_logic;
            instr_needs_immediate : in std_logic;
            instr_needs_address   : in std_logic;
            instr_is_io           : in std_logic;
            instr_is_write        : in std_logic;
            instr_sss_field       : in std_logic_vector(2 downto 0);
            instr_ddd_field       : in std_logic_vector(2 downto 0);
            instr_is_alu          : in std_logic;
            instr_is_call         : in std_logic;
            instr_is_ret          : in std_logic;
            instr_is_rst          : in std_logic;
            instr_writes_reg      : in std_logic;
            instr_reads_reg       : in std_logic;
            instr_is_mem_indirect : in std_logic;
            eval_condition        : in std_logic;
            condition_met         : in std_logic;
            interrupt_pending     : in std_logic;
            ready_status          : in std_logic;
            ir_load               : out std_logic;
            ir_output_enable      : out std_logic;
            io_buffer_enable      : out std_logic;
            io_buffer_direction   : out std_logic;
            addr_select_sss       : out std_logic_vector(2 downto 0);
            addr_select_ddd       : out std_logic_vector(2 downto 0);
            scratchpad_select     : out std_logic_vector(2 downto 0);
            scratchpad_read       : out std_logic;
            scratchpad_write      : out std_logic;
            memory_read           : out std_logic;
            memory_write          : out std_logic;
            memory_refresh        : out std_logic;
            regfile_to_bus        : out std_logic;
            bus_to_regfile        : out std_logic;
            select_pc             : out std_logic;
            select_stack          : out std_logic;
            pc_load_from_regs     : out std_logic;
            pc_load_from_stack    : out std_logic;
            pc_load_from_rst      : out std_logic;
            refresh_increment     : out std_logic;
            stack_addr_select     : out std_logic;
            stack_push            : out std_logic;
            stack_pop             : out std_logic;
            stack_read            : out std_logic;
            stack_write           : out std_logic;
            pc_increment_lower    : out std_logic;
            pc_increment_upper    : out std_logic;
            pc_load               : out std_logic;
            pc_hold               : out std_logic;
            pc_carry_in           : in std_logic;
            pc_lower_byte         : in std_logic_vector(7 downto 0)
        );
    end component;

    component interrupt_ready_ff is
        port (
            clk               : in std_logic;
            phi2_rising       : in std_logic;
            reset             : in std_logic;
            int_request       : in std_logic;
            int_clear         : in std_logic;
            ready_in          : in std_logic;
            interrupt_pending : out std_logic;
            ready_status      : out std_logic
        );
    end component;

    -- ------------------------------------------------------------------------
    -- PHASE 4: PROGRAM COUNTER AND ADDRESSING
    -- ------------------------------------------------------------------------

    component program_counter is
        port (
            clk         : in  std_logic;
            phi1_rising : in  std_logic;
            reset       : in  std_logic;
            control     : in  pc_control_t;
            data_in     : in  address_t;
            pc_out      : out address_t;
            carry_out   : out std_logic
        );
    end component;

    component ahl_pointer is
        port (
            state_t1              : in std_logic;
            state_t2              : in std_logic;
            current_cycle         : in integer range 0 to 3;
            next_cycle            : in integer range 0 to 3;
            instr_is_mem_indirect : in std_logic;
            instr_needs_address   : in std_logic;
            ahl_select            : out std_logic_vector(2 downto 0);
            ahl_active            : out std_logic
        );
    end component;

    component mem_mux_refresh is
        port (
            pc_addr            : in address_t;
            stack_addr         : in address_t;
            reg_a              : in std_logic_vector(7 downto 0);
            reg_b              : in std_logic_vector(7 downto 0);
            rst_vector         : in std_logic_vector(2 downto 0);
            regfile_data_out   : in std_logic_vector(7 downto 0);
            regfile_data_in    : out std_logic_vector(7 downto 0);
            internal_bus_in    : in  std_logic_vector(7 downto 0);
            internal_bus_out   : out std_logic_vector(7 downto 0);
            internal_bus_oe    : out std_logic;
            select_pc          : in std_logic;
            select_stack       : in std_logic;
            pc_load_from_regs  : in std_logic;
            pc_load_from_stack : in std_logic;
            pc_load_from_rst   : in std_logic;
            regfile_to_bus     : in std_logic;
            bus_to_regfile     : in std_logic;
            pc_data_in         : out address_t
        );
    end component;

    -- Phase 5: Stack System
    component stack_pointer is
        port (
            clk         : in std_logic;
            phi1_rising : in std_logic;
            reset       : in std_logic;
            stack_push  : in std_logic;
            stack_pop   : in std_logic;
            sp_out      : out std_logic_vector(2 downto 0)
        );
    end component;

    component stack_addr_decoder is
        port (
            sp_in          : in std_logic_vector(2 downto 0);
            stack_read     : in std_logic;
            stack_write    : in std_logic;
            enable_level_0 : out std_logic;
            enable_level_1 : out std_logic;
            enable_level_2 : out std_logic;
            enable_level_3 : out std_logic;
            enable_level_4 : out std_logic;
            enable_level_5 : out std_logic;
            enable_level_6 : out std_logic;
            enable_level_7 : out std_logic;
            read_out       : out std_logic;
            write_out      : out std_logic
        );
    end component;

    component stack_memory is
        port (
            clk            : in std_logic;
            phi1_rising    : in std_logic;
            reset          : in std_logic;
            addr_in        : in address_t;
            enable_level_0 : in std_logic;
            enable_level_1 : in std_logic;
            enable_level_2 : in std_logic;
            enable_level_3 : in std_logic;
            enable_level_4 : in std_logic;
            enable_level_5 : in std_logic;
            enable_level_6 : in std_logic;
            enable_level_7 : in std_logic;
            stack_read     : in std_logic;
            stack_write    : in std_logic;
            addr_out       : out address_t
        );
    end component;

    -- Phase 6: Register File System
    component scratchpad_decoder is
        port (
            addr_in      : in std_logic_vector(2 downto 0);
            read_enable  : in std_logic;
            write_enable : in std_logic;
            enable_a     : out std_logic;
            enable_b     : out std_logic;
            enable_c     : out std_logic;
            enable_d     : out std_logic;
            enable_e     : out std_logic;
            enable_h     : out std_logic;
            enable_l     : out std_logic;
            enable_m     : out std_logic;
            read_out     : out std_logic;
            write_out    : out std_logic
        );
    end component;

    component register_file is
        port (
            clk             : in std_logic;
            phi2_rising     : in std_logic;
            reset           : in std_logic;
            data_in         : in std_logic_vector(7 downto 0);
            data_out        : out std_logic_vector(7 downto 0);
            enable_a        : in std_logic;
            enable_b        : in std_logic;
            enable_c        : in std_logic;
            enable_d        : in std_logic;
            enable_e        : in std_logic;
            enable_h        : in std_logic;
            enable_l        : in std_logic;
            read_enable     : in std_logic;
            write_enable    : in std_logic;
            accumulator_out : out std_logic_vector(7 downto 0);
            debug_reg_a     : out std_logic_vector(7 downto 0);
            debug_reg_b     : out std_logic_vector(7 downto 0);
            debug_reg_c     : out std_logic_vector(7 downto 0);
            debug_reg_d     : out std_logic_vector(7 downto 0);
            debug_reg_e     : out std_logic_vector(7 downto 0);
            debug_reg_h     : out std_logic_vector(7 downto 0);
            debug_reg_l     : out std_logic_vector(7 downto 0)
        );
    end component;

    -- Phase 7: Temp Registers
    component temp_registers is
        port (
            clk                 : in std_logic;
            phi2_rising         : in std_logic;
            reset               : in std_logic;
            load_reg_a          : in std_logic;
            load_reg_b          : in std_logic;
            output_reg_a        : in std_logic;
            output_reg_b        : in std_logic;
            internal_bus_in     : in  std_logic_vector(7 downto 0);
            internal_bus_out    : out std_logic_vector(7 downto 0);
            internal_bus_oe     : out std_logic;
            reg_a_out           : out std_logic_vector(7 downto 0);
            reg_b_out           : out std_logic_vector(7 downto 0)
        );
    end component;

    -- Phase 8: ALU and Flags
    component register_alu_control is
        port (
            clk                   : in std_logic;
            phi2_rising           : in std_logic;
            status_s0             : in std_logic;
            status_s1             : in std_logic;
            status_s2             : in std_logic;
            instr_is_alu_op       : in std_logic;
            instr_uses_temp_regs  : in std_logic;
            instr_needs_immediate : in std_logic;
            instr_writes_reg      : in std_logic;
            instr_is_write        : in std_logic;
            instr_is_io           : in std_logic;
            current_cycle         : in integer range 0 to 3;
            state_half            : in std_logic;
            interrupt             : in std_logic;
            load_reg_a            : out std_logic;
            load_reg_b            : out std_logic;
            alu_enable            : out std_logic;
            update_flags          : out std_logic;
            output_reg_a          : out std_logic;
            output_reg_b          : out std_logic;
            output_result         : out std_logic;
            output_flags          : out std_logic
        );
    end component;

    component alu is
        port (
            clk              : in std_logic;
            phi2_rising      : in std_logic;
            accumulator_in   : in std_logic_vector(7 downto 0);
            reg_b_in         : in std_logic_vector(7 downto 0);
            opcode           : in std_logic_vector(2 downto 0);
            is_inr_dcr       : in std_logic;
            is_rotate        : in std_logic;
            carry_in         : in std_logic;
            enable           : in std_logic;
            output_result    : in std_logic;
            internal_bus_out : out std_logic_vector(7 downto 0);
            internal_bus_oe  : out std_logic;
            result           : out std_logic_vector(8 downto 0);
            flag_carry       : out std_logic;
            flag_zero        : out std_logic;
            flag_sign        : out std_logic;
            flag_parity      : out std_logic
        );
    end component;

    component condition_flags is
        port (
            clk              : in std_logic;
            phi2_rising      : in std_logic;
            reset            : in std_logic;
            flag_carry_in    : in std_logic;
            flag_zero_in     : in std_logic;
            flag_sign_in     : in std_logic;
            flag_parity_in   : in std_logic;
            update_flags     : in std_logic;
            condition_code   : in std_logic_vector(1 downto 0);
            test_true        : in std_logic;
            eval_condition   : in std_logic;
            output_flags     : in std_logic;
            internal_bus_out : out std_logic_vector(7 downto 0);
            internal_bus_oe  : out std_logic;
            condition_met    : out std_logic;
            flag_carry       : out std_logic;
            flag_zero        : out std_logic;
            flag_sign        : out std_logic;
            flag_parity      : out std_logic
        );
    end component;

    -- Phase 9: External Interface
    component instruction_register is
        port (
            clk              : in std_logic;
            phi1_falling     : in std_logic;
            reset            : in std_logic;
            internal_bus_in  : in  std_logic_vector(7 downto 0);
            internal_bus_out : out std_logic_vector(7 downto 0);
            internal_bus_oe  : out std_logic;
            load_ir          : in std_logic;
            output_ir        : in std_logic;
            ir_bit_7         : out std_logic;
            ir_bit_6         : out std_logic;
            ir_bit_5         : out std_logic;
            ir_bit_4         : out std_logic;
            ir_bit_3         : out std_logic;
            ir_bit_2         : out std_logic;
            ir_bit_1         : out std_logic;
            ir_bit_0         : out std_logic
        );
    end component;

    component io_buffer is
        port (
            external_data_in  : in  std_logic_vector(7 downto 0);
            external_data_out : out std_logic_vector(7 downto 0);
            external_data_oe  : out std_logic;
            internal_bus_in   : in  std_logic_vector(7 downto 0);
            internal_bus_out  : out std_logic_vector(7 downto 0);
            internal_bus_oe   : out std_logic;
            enable            : in std_logic;
            direction         : in std_logic
        );
    end component;

    -- ========================================================================
    -- INTERNAL SIGNAL DECLARATIONS
    -- ========================================================================

    -- Clock signals
    signal phi1 : std_logic;
    signal phi2 : std_logic;
    signal phi1_rising  : std_logic;
    signal phi1_falling : std_logic;
    signal phi2_rising  : std_logic;
    signal phi2_falling : std_logic;

    -- Internal data bus - now a MUX instead of tri-state for synthesis compatibility
    -- Each module has separate output and output-enable signals
    signal internal_bus : std_logic_vector(7 downto 0);

    -- Per-module internal bus outputs and enables
    signal mem_mux_bus_out    : std_logic_vector(7 downto 0);
    signal mem_mux_bus_oe     : std_logic;
    signal temp_reg_bus_out   : std_logic_vector(7 downto 0);
    signal temp_reg_bus_oe    : std_logic;
    signal alu_bus_out        : std_logic_vector(7 downto 0);
    signal alu_bus_oe         : std_logic;
    signal cond_flags_bus_out : std_logic_vector(7 downto 0);
    signal cond_flags_bus_oe  : std_logic;
    signal ir_bus_out         : std_logic_vector(7 downto 0);
    signal ir_bus_oe          : std_logic;
    signal io_buffer_bus_out  : std_logic_vector(7 downto 0);
    signal io_buffer_bus_oe   : std_logic;

    -- State timing signals (from state_timing_generator)
    signal state_t1      : std_logic;
    signal state_t2      : std_logic;
    signal state_t3      : std_logic;
    signal state_t4      : std_logic;
    signal state_t5      : std_logic;
    signal state_t1i     : std_logic;
    signal state_stopped : std_logic;
    signal state_half    : std_logic;  -- Which half of 2-cycle state (0=first, 1=second)
    signal status_s0     : std_logic;
    signal status_s1     : std_logic;
    signal status_s2     : std_logic;
    signal sync          : std_logic;

    -- Machine cycle control signals
    -- Note: cycle_type is now an output port, not an internal signal
    signal current_cycle    : integer range 0 to 3;
    signal next_cycle       : integer range 0 to 3;  -- Predicted next cycle (valid at T1 start)
    signal advance_state    : std_logic;
    signal instr_is_hlt_flag : std_logic;  -- Latched HLT flag from machine_cycle_control

    -- Instruction decoder outputs
    signal instr_byte           : std_logic_vector(7 downto 0);
    signal instr_needs_immediate : std_logic;
    signal instr_needs_address   : std_logic;
    signal instr_is_io           : std_logic;
    signal instr_is_write        : std_logic;
    signal instr_sss_field       : std_logic_vector(2 downto 0);
    signal instr_ddd_field       : std_logic_vector(2 downto 0);
    signal instr_is_alu          : std_logic;
    signal instr_is_call         : std_logic;
    signal instr_is_ret          : std_logic;
    signal instr_is_rst          : std_logic;
    signal instr_is_hlt          : std_logic;
    signal instr_writes_reg      : std_logic;
    signal instr_reads_reg       : std_logic;
    signal instr_is_mem_indirect : std_logic;
    signal instr_uses_temp_regs  : std_logic;
    signal instr_is_inr_dcr      : std_logic;
    signal instr_is_binary_alu   : std_logic;
    signal instr_is_rotate       : std_logic;
    signal instr_needs_t4t5      : std_logic;
    signal rst_vector            : std_logic_vector(2 downto 0);
    signal condition_code        : std_logic_vector(1 downto 0);
    signal test_true             : std_logic;
    signal eval_condition        : std_logic;
    signal transition_to_stopped : std_logic;

    -- Condition flags
    signal condition_met : std_logic;
    signal flag_carry    : std_logic;
    signal flag_zero     : std_logic;
    signal flag_sign     : std_logic;
    signal flag_parity   : std_logic;

    -- Interrupt and ready status
    signal interrupt_pending : std_logic;
    signal ready_status      : std_logic;
    signal int_clear         : std_logic;  -- Clear interrupt when entering T1I

    -- Program counter signals
    signal pc_addr    : address_t;  -- unsigned(13 downto 0)
    signal pc_data_in : address_t;  -- unsigned(13 downto 0)
    signal pc_control : pc_control_t;  -- From b8008_types: increment_lower, increment_upper, load, hold
    signal pc_carry   : std_logic;  -- Carry flag from PC lower byte increment

    -- Address signals (sources for multiplexer)
    signal stack_addr        : address_t;
    signal selected_address  : address_t;  -- Multiplexed address (PC/Stack only - H:L come from regfile)

    -- Register file signals
    signal regfile_data_out : std_logic_vector(7 downto 0);
    signal regfile_data_in  : std_logic_vector(7 downto 0);
    signal regfile_enable_a : std_logic;
    signal regfile_enable_b : std_logic;
    signal regfile_enable_c : std_logic;
    signal regfile_enable_d : std_logic;
    signal regfile_enable_e : std_logic;
    signal regfile_enable_h : std_logic;
    signal regfile_enable_l : std_logic;
    signal regfile_enable_m : std_logic;
    signal regfile_read_enable  : std_logic;
    signal regfile_write_enable : std_logic;

    -- Temp register signals
    signal reg_a_out : std_logic_vector(7 downto 0);  -- Temp register A (for addresses)
    signal reg_b_out : std_logic_vector(7 downto 0);  -- Temp register B (for ALU operand)

    -- Accumulator direct output (hardwired to ALU)
    signal accumulator : std_logic_vector(7 downto 0);

    -- Debug signals from register file
    signal debug_reg_a_actual : std_logic_vector(7 downto 0);
    signal debug_reg_b_actual : std_logic_vector(7 downto 0);
    signal debug_reg_c_actual : std_logic_vector(7 downto 0);
    signal debug_reg_d_actual : std_logic_vector(7 downto 0);
    signal debug_reg_e_actual : std_logic_vector(7 downto 0);
    signal debug_reg_h_actual : std_logic_vector(7 downto 0);
    signal debug_reg_l_actual : std_logic_vector(7 downto 0);

    -- ALU signals
    signal alu_result      : std_logic_vector(8 downto 0);  -- 9 bits: carry + result
    signal alu_opcode      : std_logic_vector(2 downto 0);  -- From instruction bits 5:3
    signal alu_carry_in    : std_logic;
    signal alu_flag_carry  : std_logic;
    signal alu_flag_zero   : std_logic;
    signal alu_flag_sign   : std_logic;
    signal alu_flag_parity : std_logic;

    -- Stack signals
    signal sp                  : std_logic_vector(2 downto 0);  -- Stack pointer value
    signal stack_enable_0      : std_logic;
    signal stack_enable_1      : std_logic;
    signal stack_enable_2      : std_logic;
    signal stack_enable_3      : std_logic;
    signal stack_enable_4      : std_logic;
    signal stack_enable_5      : std_logic;
    signal stack_enable_6      : std_logic;
    signal stack_enable_7      : std_logic;
    signal stack_read_control  : std_logic;
    signal stack_write_control : std_logic;

    -- ========================================================================
    -- CONTROL SIGNALS (from memory_io_control)
    -- ========================================================================

    signal load_ir              : std_logic;  -- Load instruction register
    signal ir_output_enable     : std_logic;
    signal io_buffer_enable     : std_logic;
    signal io_buffer_direction  : std_logic;
    signal io_buffer_data_out   : std_logic_vector(7 downto 0);  -- Data from io_buffer to external
    signal io_buffer_oe         : std_logic;                     -- io_buffer output enable
    signal addr_select_sss      : std_logic_vector(2 downto 0);
    signal addr_select_ddd      : std_logic_vector(2 downto 0);
    signal scratchpad_select    : std_logic_vector(2 downto 0);
    signal scratchpad_read      : std_logic;
    signal scratchpad_write     : std_logic;
    signal memory_read          : std_logic;
    signal memory_write         : std_logic;
    signal memory_refresh       : std_logic;
    signal regfile_to_bus       : std_logic;
    signal bus_to_regfile       : std_logic;
    signal select_pc            : std_logic;
    signal select_stack         : std_logic;

    -- AHL scratchpad address selection signals
    signal ahl_scratchpad_addr  : std_logic_vector(2 downto 0);  -- From AHL module
    signal ahl_active           : std_logic;  -- AHL overrides SSS/DDD
    signal final_scratchpad_addr : std_logic_vector(2 downto 0);  -- Muxed scratchpad address
    signal pc_load_from_regs    : std_logic;
    signal pc_load_from_stack   : std_logic;
    signal pc_load_from_rst     : std_logic;
    signal refresh_increment    : std_logic;
    signal stack_addr_select    : std_logic;
    signal stack_push           : std_logic;
    signal stack_pop            : std_logic;
    signal stack_read           : std_logic;
    signal stack_write          : std_logic;
    signal pc_increment_lower   : std_logic;
    signal pc_increment_upper   : std_logic;
    signal pc_load              : std_logic;
    signal pc_hold              : std_logic;

    -- ========================================================================
    -- CONTROL SIGNALS (from register_alu_control)
    -- ========================================================================

    signal load_reg_a     : std_logic;
    signal load_reg_b     : std_logic;
    signal alu_enable     : std_logic;
    signal update_flags   : std_logic;
    signal output_reg_a   : std_logic;
    signal output_reg_b   : std_logic;
    signal output_result  : std_logic;
    signal output_flags   : std_logic;

begin

    -- ========================================================================
    -- OUTPUT ASSIGNMENTS
    -- ========================================================================

    -- Clock outputs (for debugging)
    phi1_out <= phi1;
    phi2_out <= phi2;
    phi1_rising_out  <= phi1_rising;
    phi1_falling_out <= phi1_falling;
    phi2_rising_out  <= phi2_rising;
    phi2_falling_out <= phi2_falling;

    -- Timing and status outputs
    sync_out <= sync;
    s0_out   <= status_s0;
    s1_out   <= status_s1;
    s2_out   <= status_s2;

    -- Address multiplexing onto data bus (Real 8008 behavior)
    -- T1: Output address low byte [7:0]
    -- T2: Output address high byte [13:8] on D[5:0], cycle type on D[7:6]
    -- Address multiplexer: Only PC and Stack (H:L addressed via register file)
    -- During memory operations, H and L are read from regfile and output on data bus
    selected_address <= stack_addr when select_stack = '1' else pc_addr;

    -- Scratchpad address multiplexer: AHL overrides SSS/DDD during cycle 2 T1/T2 of memory ops
    final_scratchpad_addr <= ahl_scratchpad_addr when ahl_active = '1' else scratchpad_select;

    -- Data bus driver: T1/T2 output address, T3+ io_buffer drives (when enabled)
    -- During H:L address cycles, io_buffer drives data_bus from internal_bus (H/L regs)
    -- - LrM/LMr (2-cycle): H:L at cycle 2 (instr_needs_address = '0')
    -- - LMI (3-cycle): H:L at cycle 3 (instr_needs_address = '1')
    -- During I/O cycle 2, io_buffer drives data_bus with A register (T1) or Reg.b (T2)
    -- - Per isa.json: INP/OUT cycle 2, T1: "REG.A TO OUT", T2: "REG.b TO OUT"
    -- Otherwise during T1/T2, output selected_address (PC or Stack)
    -- NOTE: Use next_cycle for T1 check because current_cycle hasn't updated yet at T1 start
    --
    -- For synthesis: separate output data and output enable signals instead of tri-state
    -- CPU drives during T1, T2 (address output), or when io_buffer outputs (T3 write)

    -- Data bus output multiplexer
    data_bus_out <= std_logic_vector(selected_address(7 downto 0)) when (state_t1 = '1' and not (ahl_active = '1') and
                                                                          not (instr_is_io = '1' and next_cycle = 1)) else
                    (cycle_type & std_logic_vector(selected_address(13 downto 8))) when (state_t2 = '1' and not (ahl_active = '1') and
                                                                                          not (instr_is_io = '1' and current_cycle = 1)) else
                    -- During io_buffer output enabled, use io_buffer's output data
                    io_buffer_data_out when io_buffer_oe = '1' else
                    -- Default: output zeros (will be masked by OE anyway)
                    (others => '0');

    -- Data bus output enable: CPU drives during T1/T2 (address) or when io_buffer outputs
    data_bus_oe <= '1' when (state_t1 = '1' and not (ahl_active = '1') and not (instr_is_io = '1' and next_cycle = 1)) else
                   '1' when (state_t2 = '1' and not (ahl_active = '1') and not (instr_is_io = '1' and current_cycle = 1)) else
                   io_buffer_oe;

    -- Debug outputs
    debug_reg_a         <= debug_reg_a_actual;
    debug_reg_b         <= debug_reg_b_actual;
    debug_reg_c         <= debug_reg_c_actual;
    debug_reg_d         <= debug_reg_d_actual;
    debug_reg_e         <= debug_reg_e_actual;
    debug_reg_h         <= debug_reg_h_actual;
    debug_reg_l         <= debug_reg_l_actual;
    debug_cycle         <= std_logic_vector(to_unsigned(current_cycle, 2));  -- 0->00, 1->01, 2->10
    debug_pc            <= std_logic_vector(pc_addr);
    debug_ir            <= instr_byte;
    debug_needs_address <= instr_needs_address;
    debug_int_pending   <= interrupt_pending;
    debug_flag_carry    <= flag_carry;
    debug_flag_zero     <= flag_zero;
    debug_flag_sign     <= flag_sign;
    debug_flag_parity   <= flag_parity;
    debug_state_half    <= state_half;

    -- PC control record construction
    pc_control.increment_lower <= pc_increment_lower;
    pc_control.increment_upper <= pc_increment_upper;
    pc_control.load            <= pc_load;
    pc_control.hold            <= pc_hold;

    -- ALU opcode selection:
    -- For regular ALU ops (10PPPSSS): opcode from bits 5:3 (PPP field)
    -- For INR/DCR (00DDD00X): opcode from instruction decoder (instr_sss_field = 000 for INR, 010 for DCR)
    -- For rotate (00XXX010): opcode from bits 5:3 (XXX field) via instr_sss_field
    alu_opcode <= instr_sss_field when (instr_is_inr_dcr = '1' or instr_is_rotate = '1') else instr_byte(5 downto 3);

    -- ALU carry input from condition flags
    alu_carry_in <= flag_carry;

    -- Interrupt clear signal (active when entering T1I state)
    int_clear <= state_t1i;

    -- Internal bus MUX: replaces tri-state bus for synthesis compatibility
    -- Priority encoding ensures only one driver at a time (control logic guarantees mutual exclusion)
    internal_bus <= io_buffer_bus_out  when io_buffer_bus_oe  = '1' else
                    mem_mux_bus_out    when mem_mux_bus_oe    = '1' else
                    temp_reg_bus_out   when temp_reg_bus_oe   = '1' else
                    alu_bus_out        when alu_bus_oe        = '1' else
                    cond_flags_bus_out when cond_flags_bus_oe = '1' else
                    ir_bus_out         when ir_bus_oe         = '1' else
                    (others => '0');  -- Default: zeros when no driver active

    -- Instruction byte assembly from IR bit outputs (will be connected in Phase 9)
    -- For now, instr_byte signal will be driven by instruction_register outputs
    -- Note: load_ir signal now comes from memory_io_control (proper control flow)

    -- ========================================================================
    -- MODULE INSTANTIATIONS
    -- ========================================================================

    -- ------------------------------------------------------------------------
    -- PHASE 2: CLOCK AND TIMING (Low Risk)
    -- ------------------------------------------------------------------------

    u_phase_clocks : phase_clocks
        port map (
            clk_in       => clk_in,
            reset        => reset,
            run_enable   => run_enable,
            phi1         => phi1,
            phi2         => phi2,
            sync         => sync,
            phi1_rising  => phi1_rising,
            phi1_falling => phi1_falling,
            phi2_rising  => phi2_rising,
            phi2_falling => phi2_falling
        );

    u_state_timing : state_timing_generator
        port map (
            clk                   => clk_in,
            phi2_falling          => phi2_falling,
            reset                 => reset,
            advance_state         => advance_state,
            interrupt_pending     => interrupt_pending,
            ready                 => ready_status,
            instr_is_hlt_flag     => instr_is_hlt_flag,
            transition_to_stopped => transition_to_stopped,
            state_t1              => state_t1,
            state_t2              => state_t2,
            state_t3              => state_t3,
            state_t4              => state_t4,
            state_t5              => state_t5,
            state_t1i             => state_t1i,
            state_stopped         => state_stopped,
            state_half            => state_half,
            status_s0             => status_s0,
            status_s1             => status_s1,
            status_s2             => status_s2
        );

    -- ------------------------------------------------------------------------
    -- PHASE 3: CONTROL AND DECODE (Medium Risk)
    -- ------------------------------------------------------------------------

    u_interrupt_ready : interrupt_ready_ff
        port map (
            clk               => clk_in,
            phi2_rising       => phi2_rising,
            reset             => reset,
            int_request       => interrupt,
            int_clear         => int_clear,
            ready_in          => ready_in,
            interrupt_pending => interrupt_pending,
            ready_status      => ready_status
        );

    u_machine_cycle : machine_cycle_control
        port map (
            clk                   => clk_in,
            phi1_rising           => phi1_rising,
            reset                 => reset,
            state_t1              => state_t1,
            state_t2              => state_t2,
            state_t3              => state_t3,
            state_t4              => state_t4,
            state_t5              => state_t5,
            state_t1i             => state_t1i,
            instr_needs_immediate => instr_needs_immediate,
            instr_needs_address   => instr_needs_address,
            instr_is_io           => instr_is_io,
            instr_is_write        => instr_is_write,
            instr_is_hlt          => instr_is_hlt,
            instr_needs_t4t5      => instr_needs_t4t5,
            eval_condition        => eval_condition,
            condition_met         => condition_met,
            advance_state         => advance_state,
            instr_is_hlt_flag     => instr_is_hlt_flag,
            cycle_type            => cycle_type,
            current_cycle         => current_cycle,
            next_cycle            => next_cycle
        );

    u_instr_decoder : instruction_decoder
        port map (
            instruction_byte      => instr_byte,
            instr_needs_immediate => instr_needs_immediate,
            instr_needs_address   => instr_needs_address,
            instr_is_io           => instr_is_io,
            instr_is_write        => instr_is_write,
            instr_sss_field       => instr_sss_field,
            instr_ddd_field       => instr_ddd_field,
            instr_is_alu          => instr_is_alu,
            instr_is_call         => instr_is_call,
            instr_is_ret          => instr_is_ret,
            instr_is_rst          => instr_is_rst,
            instr_is_hlt          => instr_is_hlt,
            instr_writes_reg      => instr_writes_reg,
            instr_reads_reg       => instr_reads_reg,
            instr_is_mem_indirect => instr_is_mem_indirect,
            instr_uses_temp_regs  => instr_uses_temp_regs,
            instr_is_inr_dcr      => instr_is_inr_dcr,
            instr_is_binary_alu   => instr_is_binary_alu,
            instr_is_rotate       => instr_is_rotate,
            instr_needs_t4t5      => instr_needs_t4t5,
            rst_vector            => rst_vector,
            condition_code        => condition_code,
            test_true             => test_true,
            eval_condition        => eval_condition,
            transition_to_stopped => transition_to_stopped
        );

    u_memory_io_control : memory_io_control
        port map (
            clk                   => clk_in,
            phi1_rising           => phi1_rising,
            reset                 => reset,
            state_t1              => state_t1,
            state_t2              => state_t2,
            state_t3              => state_t3,
            state_t4              => state_t4,
            state_t5              => state_t5,
            state_t1i             => state_t1i,
            state_stopped         => state_stopped,
            state_half            => state_half,
            status_s0             => status_s0,
            status_s1             => status_s1,
            status_s2             => status_s2,
            cycle_type            => cycle_type,
            current_cycle         => current_cycle,
            next_cycle            => next_cycle,
            advance_state         => advance_state,
            instr_is_hlt_flag     => instr_is_hlt_flag,
            instr_needs_immediate => instr_needs_immediate,
            instr_needs_address   => instr_needs_address,
            instr_is_io           => instr_is_io,
            instr_is_write        => instr_is_write,
            instr_sss_field       => instr_sss_field,
            instr_ddd_field       => instr_ddd_field,
            instr_is_alu          => instr_is_alu,
            instr_is_call         => instr_is_call,
            instr_is_ret          => instr_is_ret,
            instr_is_rst          => instr_is_rst,
            instr_writes_reg      => instr_writes_reg,
            instr_reads_reg       => instr_reads_reg,
            instr_is_mem_indirect => instr_is_mem_indirect,
            eval_condition        => eval_condition,
            condition_met         => condition_met,
            interrupt_pending     => interrupt_pending,
            ready_status          => ready_status,
            ir_load               => load_ir,
            ir_output_enable      => ir_output_enable,
            io_buffer_enable      => io_buffer_enable,
            io_buffer_direction   => io_buffer_direction,
            addr_select_sss       => addr_select_sss,
            addr_select_ddd       => addr_select_ddd,
            scratchpad_select     => scratchpad_select,
            scratchpad_read       => scratchpad_read,
            scratchpad_write      => scratchpad_write,
            memory_read           => memory_read,
            memory_write          => memory_write,
            memory_refresh        => memory_refresh,
            regfile_to_bus        => regfile_to_bus,
            bus_to_regfile        => bus_to_regfile,
            select_pc             => select_pc,
            select_stack          => select_stack,
            pc_load_from_regs     => pc_load_from_regs,
            pc_load_from_stack    => pc_load_from_stack,
            pc_load_from_rst      => pc_load_from_rst,
            refresh_increment     => refresh_increment,
            stack_addr_select     => stack_addr_select,
            stack_push            => stack_push,
            stack_pop             => stack_pop,
            stack_read            => stack_read,
            stack_write           => stack_write,
            pc_increment_lower    => pc_increment_lower,
            pc_increment_upper    => pc_increment_upper,
            pc_carry_in           => pc_carry,
            pc_lower_byte         => std_logic_vector(pc_addr(7 downto 0)),
            pc_load               => pc_load,
            pc_hold               => pc_hold
        );


    -- ------------------------------------------------------------------------
    -- PHASE 4: PROGRAM COUNTER AND ADDRESSING (Medium Risk)
    -- ------------------------------------------------------------------------

    u_program_counter : program_counter
        port map (
            clk         => clk_in,
            phi1_rising => phi1_rising,
            reset       => reset,
            control     => pc_control,
            data_in     => pc_data_in,
            pc_out      => pc_addr,
            carry_out   => pc_carry
        );

    u_ahl_pointer : ahl_pointer
        port map (
            state_t1              => state_t1,
            state_t2              => state_t2,
            current_cycle         => current_cycle,
            next_cycle            => next_cycle,
            instr_is_mem_indirect => instr_is_mem_indirect,
            instr_needs_address   => instr_needs_address,
            ahl_select            => ahl_scratchpad_addr,
            ahl_active            => ahl_active
        );

    u_mem_mux_refresh : mem_mux_refresh
        port map (
            pc_addr            => pc_addr,
            stack_addr         => stack_addr,
            reg_a              => reg_a_out,
            reg_b              => reg_b_out,
            rst_vector         => rst_vector,
            regfile_data_out   => regfile_data_out,
            regfile_data_in    => regfile_data_in,
            internal_bus_in    => internal_bus,
            internal_bus_out   => mem_mux_bus_out,
            internal_bus_oe    => mem_mux_bus_oe,
            select_pc          => select_pc,
            select_stack       => select_stack,
            pc_load_from_regs  => pc_load_from_regs,
            pc_load_from_stack => pc_load_from_stack,
            pc_load_from_rst   => pc_load_from_rst,
            regfile_to_bus     => regfile_to_bus,
            bus_to_regfile     => bus_to_regfile,
            pc_data_in         => pc_data_in
        );


    -- ------------------------------------------------------------------------
    -- PHASE 5: STACK SYSTEM (Low Risk)
    -- ------------------------------------------------------------------------

    u_stack_pointer : stack_pointer
        port map (
            clk         => clk_in,
            phi1_rising => phi1_rising,
            reset       => reset,
            stack_push  => stack_push,
            stack_pop   => stack_pop,
            sp_out      => sp
        );

    u_stack_addr_decoder : stack_addr_decoder
        port map (
            sp_in          => sp,
            stack_read     => stack_read,
            stack_write    => stack_write,
            enable_level_0 => stack_enable_0,
            enable_level_1 => stack_enable_1,
            enable_level_2 => stack_enable_2,
            enable_level_3 => stack_enable_3,
            enable_level_4 => stack_enable_4,
            enable_level_5 => stack_enable_5,
            enable_level_6 => stack_enable_6,
            enable_level_7 => stack_enable_7,
            read_out       => stack_read_control,
            write_out      => stack_write_control
        );

    u_stack_memory : stack_memory
        port map (
            clk            => clk_in,
            phi1_rising    => phi1_rising,
            reset          => reset,
            addr_in        => pc_addr,  -- PC address to store during CALL/RST
            enable_level_0 => stack_enable_0,
            enable_level_1 => stack_enable_1,
            enable_level_2 => stack_enable_2,
            enable_level_3 => stack_enable_3,
            enable_level_4 => stack_enable_4,
            enable_level_5 => stack_enable_5,
            enable_level_6 => stack_enable_6,
            enable_level_7 => stack_enable_7,
            stack_read     => stack_read_control,
            stack_write    => stack_write_control,
            addr_out       => stack_addr
        );

    -- ------------------------------------------------------------------------
    -- PHASE 6: REGISTER FILE SYSTEM (Low Risk)
    -- ------------------------------------------------------------------------

    u_scratchpad_decoder : scratchpad_decoder
        port map (
            addr_in      => final_scratchpad_addr,
            read_enable  => scratchpad_read,
            write_enable => scratchpad_write,
            enable_a     => regfile_enable_a,
            enable_b     => regfile_enable_b,
            enable_c     => regfile_enable_c,
            enable_d     => regfile_enable_d,
            enable_e     => regfile_enable_e,
            enable_h     => regfile_enable_h,
            enable_l     => regfile_enable_l,
            enable_m     => regfile_enable_m,
            read_out     => regfile_read_enable,
            write_out    => regfile_write_enable
        );

    u_register_file : register_file
        port map (
            clk             => clk_in,
            phi2_rising     => phi2_rising,
            reset           => reset,
            data_in         => regfile_data_in,
            data_out        => regfile_data_out,
            enable_a        => regfile_enable_a,
            enable_b        => regfile_enable_b,
            enable_c        => regfile_enable_c,
            enable_d        => regfile_enable_d,
            enable_e        => regfile_enable_e,
            enable_h        => regfile_enable_h,
            enable_l        => regfile_enable_l,
            read_enable     => regfile_read_enable,
            write_enable    => regfile_write_enable,
            accumulator_out => accumulator,
            debug_reg_a     => debug_reg_a_actual,
            debug_reg_b     => debug_reg_b_actual,
            debug_reg_c     => debug_reg_c_actual,
            debug_reg_d     => debug_reg_d_actual,
            debug_reg_e     => debug_reg_e_actual,
            debug_reg_h     => debug_reg_h_actual,
            debug_reg_l     => debug_reg_l_actual
        );

    -- ------------------------------------------------------------------------
    -- PHASE 7: TEMP REGISTERS (Low Risk)
    -- ------------------------------------------------------------------------

    u_register_alu_control : register_alu_control
        port map (
            clk                   => clk_in,
            phi2_rising           => phi2_rising,
            status_s0             => status_s0,
            status_s1             => status_s1,
            status_s2             => status_s2,
            instr_is_alu_op       => instr_is_alu,
            instr_uses_temp_regs  => instr_uses_temp_regs,
            instr_needs_immediate => instr_needs_immediate,
            instr_writes_reg      => instr_writes_reg,
            instr_is_write        => instr_is_write,
            instr_is_io           => instr_is_io,
            current_cycle         => current_cycle,
            state_half            => state_half,
            interrupt             => interrupt_pending,
            load_reg_a            => load_reg_a,
            load_reg_b            => load_reg_b,
            alu_enable            => alu_enable,
            update_flags          => update_flags,
            output_reg_a          => output_reg_a,
            output_reg_b          => output_reg_b,
            output_result         => output_result,
            output_flags          => output_flags
        );

    u_temp_registers : temp_registers
        port map (
            clk                 => clk_in,
            phi2_rising         => phi2_rising,
            reset               => reset,
            load_reg_a          => load_reg_a,
            load_reg_b          => load_reg_b,
            output_reg_a        => output_reg_a,
            output_reg_b        => output_reg_b,
            internal_bus_in     => internal_bus,
            internal_bus_out    => temp_reg_bus_out,
            internal_bus_oe     => temp_reg_bus_oe,
            reg_a_out           => reg_a_out,
            reg_b_out           => reg_b_out
        );

    -- ------------------------------------------------------------------------
    -- PHASE 8: ALU AND FLAGS (Medium Risk)
    -- ------------------------------------------------------------------------

    u_alu : alu
        port map (
            clk              => clk_in,
            phi2_rising      => phi2_rising,
            accumulator_in   => accumulator,         -- Direct from register file's A register
            reg_b_in         => reg_b_out,           -- From temp register b
            opcode           => alu_opcode,          -- PPP field (bits 5:3) from instruction
            is_inr_dcr       => instr_is_inr_dcr,    -- INR/DCR mode from instruction decoder
            is_rotate        => instr_is_rotate,     -- Rotate mode from instruction decoder
            carry_in         => flag_carry,
            enable           => alu_enable,
            output_result    => output_result,
            internal_bus_out => alu_bus_out,
            internal_bus_oe  => alu_bus_oe,
            result           => alu_result,
            flag_carry       => alu_flag_carry,
            flag_zero        => alu_flag_zero,
            flag_sign        => alu_flag_sign,
            flag_parity      => alu_flag_parity
        );

    u_condition_flags : condition_flags
        port map (
            clk              => clk_in,
            phi2_rising      => phi2_rising,
            reset            => reset,
            flag_carry_in    => alu_flag_carry,
            flag_zero_in     => alu_flag_zero,
            flag_sign_in     => alu_flag_sign,
            flag_parity_in   => alu_flag_parity,
            update_flags     => update_flags,
            condition_code   => condition_code,
            test_true        => test_true,
            eval_condition   => eval_condition,
            output_flags     => output_flags,
            internal_bus_out => cond_flags_bus_out,
            internal_bus_oe  => cond_flags_bus_oe,
            condition_met    => condition_met,
            flag_carry       => flag_carry,
            flag_zero        => flag_zero,
            flag_sign        => flag_sign,
            flag_parity      => flag_parity
        );

    -- ------------------------------------------------------------------------
    -- PHASE 9: EXTERNAL INTERFACE (Low Risk)
    -- ------------------------------------------------------------------------

    u_instruction_register : instruction_register
        port map (
            clk              => clk_in,
            phi1_falling     => phi1_falling,
            reset            => reset,
            internal_bus_in  => internal_bus,
            internal_bus_out => ir_bus_out,
            internal_bus_oe  => ir_bus_oe,
            load_ir          => load_ir,
            output_ir        => ir_output_enable,
            ir_bit_7         => instr_byte(7),
            ir_bit_6         => instr_byte(6),
            ir_bit_5         => instr_byte(5),
            ir_bit_4         => instr_byte(4),
            ir_bit_3         => instr_byte(3),
            ir_bit_2         => instr_byte(2),
            ir_bit_1         => instr_byte(1),
            ir_bit_0         => instr_byte(0)
        );

    u_io_buffer : io_buffer
        port map (
            external_data_in  => data_bus_in,
            external_data_out => io_buffer_data_out,
            external_data_oe  => io_buffer_oe,
            internal_bus_in   => internal_bus,
            internal_bus_out  => io_buffer_bus_out,
            internal_bus_oe   => io_buffer_bus_oe,
            enable            => io_buffer_enable,
            direction         => io_buffer_direction
        );

end architecture structural;

--------------------------------------------------------------------------------
-- memory_io_control_tb.vhdl
--------------------------------------------------------------------------------
-- Testbench for Memory and I/O Control
-- Tests: Basic T-state sequencing, I/O buffer control, memory operations
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.b8008_types.all;

entity memory_io_control_tb is
end entity memory_io_control_tb;

architecture test of memory_io_control_tb is

    component memory_io_control is
        port (
            phi1                  : in std_logic;
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
            current_cycle         : in integer range 1 to 3;
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
            pc_carry_in           : in  std_logic;
            pc_load               : out std_logic;
            pc_hold               : out std_logic
        );
    end component;

    -- Clock
    signal phi1 : std_logic := '0';
    constant phi1_period : time := 500 ns;

    -- Inputs
    signal reset                 : std_logic := '0';
    signal state_t1              : std_logic := '0';
    signal state_t2              : std_logic := '0';
    signal state_t3              : std_logic := '0';
    signal state_t4              : std_logic := '0';
    signal state_t5              : std_logic := '0';
    signal state_t1i             : std_logic := '0';
    signal state_stopped         : std_logic := '0';
    signal state_half            : std_logic := '0';
    signal status_s0             : std_logic := '0';
    signal status_s1             : std_logic := '0';
    signal status_s2             : std_logic := '0';
    signal cycle_type            : std_logic_vector(1 downto 0) := "00";
    signal current_cycle         : integer range 1 to 3 := 1;
    signal advance_state         : std_logic := '0';
    signal instr_is_hlt_flag     : std_logic := '0';
    signal instr_needs_immediate : std_logic := '0';
    signal instr_needs_address   : std_logic := '0';
    signal instr_is_io           : std_logic := '0';
    signal instr_is_write        : std_logic := '0';
    signal instr_sss_field       : std_logic_vector(2 downto 0) := (others => '0');
    signal instr_ddd_field       : std_logic_vector(2 downto 0) := (others => '0');
    signal instr_is_alu          : std_logic := '0';
    signal instr_is_call         : std_logic := '0';
    signal instr_is_ret          : std_logic := '0';
    signal instr_is_rst          : std_logic := '0';
    signal instr_writes_reg      : std_logic := '0';
    signal instr_reads_reg       : std_logic := '0';
    signal instr_is_mem_indirect : std_logic := '0';
    signal eval_condition        : std_logic := '0';
    signal condition_met         : std_logic := '0';
    signal interrupt_pending     : std_logic := '0';
    signal ready_status          : std_logic := '1';
    signal pc_carry_in           : std_logic := '0';

    -- Outputs
    signal ir_load             : std_logic;
    signal ir_output_enable    : std_logic;
    signal io_buffer_enable    : std_logic;
    signal io_buffer_direction : std_logic;
    signal addr_select_sss     : std_logic_vector(2 downto 0);
    signal addr_select_ddd     : std_logic_vector(2 downto 0);
    signal scratchpad_select   : std_logic_vector(2 downto 0);
    signal scratchpad_read     : std_logic;
    signal scratchpad_write    : std_logic;
    signal memory_read         : std_logic;
    signal memory_write        : std_logic;
    signal memory_refresh      : std_logic;
    signal regfile_to_bus      : std_logic;
    signal bus_to_regfile      : std_logic;
    signal select_pc           : std_logic;
    signal select_stack        : std_logic;
    signal pc_load_from_regs   : std_logic;
    signal pc_load_from_stack  : std_logic;
    signal pc_load_from_rst    : std_logic;
    signal refresh_increment   : std_logic;
    signal stack_addr_select   : std_logic;
    signal stack_push          : std_logic;
    signal stack_pop           : std_logic;
    signal stack_read          : std_logic;
    signal stack_write         : std_logic;
    signal pc_increment_lower  : std_logic;
    signal pc_increment_upper  : std_logic;
    signal pc_load             : std_logic;
    signal pc_hold             : std_logic;

begin

    -- Clock generation
    phi1 <= not phi1 after phi1_period / 2;

    uut : memory_io_control
        port map (
            phi1                  => phi1,
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
            ir_load               => ir_load,
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
            pc_carry_in           => pc_carry_in,
            pc_load               => pc_load,
            pc_hold               => pc_hold
        );

    test_process : process
        variable errors : integer := 0;
    begin
        report "========================================";
        report "Memory and I/O Control Test";
        report "========================================";

        reset <= '1';
        wait for phi1_period;
        reset <= '0';
        wait for phi1_period;

        -- Test 1: PCI cycle (instruction fetch) during T3
        report "";
        report "Test 1: PCI cycle T3 state (instruction fetch)";

        cycle_type   <= "00";  -- PCI
        current_cycle <= 1;
        state_t3     <= '1';
        wait for 50 ns;

        if io_buffer_enable /= '1' then
            report "  ERROR: I/O buffer should be enabled" severity error;
            errors := errors + 1;
        end if;

        if io_buffer_direction /= '0' then
            report "  ERROR: I/O buffer should be in read mode" severity error;
            errors := errors + 1;
        end if;

        if memory_read /= '1' then
            report "  ERROR: Memory read should be active" severity error;
            errors := errors + 1;
        else
            report "  PASS: PCI cycle enables read from memory";
        end if;

        state_t3 <= '0';
        wait for 50 ns;

        -- Test 2: PCR cycle (memory read) during T3
        report "";
        report "Test 2: PCR cycle T3 state (memory read from H:L)";

        cycle_type   <= "01";  -- PCR
        state_t3     <= '1';
        wait for 50 ns;

        if io_buffer_enable /= '1' or io_buffer_direction /= '0' or memory_read /= '1' then
            report "  ERROR: PCR should enable read" severity error;
            errors := errors + 1;
        else
            report "  PASS: PCR enables read from memory";
        end if;

        state_t3 <= '0';
        wait for 50 ns;

        -- Test 3: PCW cycle (memory write) during T3
        report "";
        report "Test 3: PCW cycle T3 state (memory write to H:L)";

        cycle_type   <= "11";  -- PCW
        state_t3     <= '1';
        wait for 50 ns;

        if io_buffer_enable /= '1' or io_buffer_direction /= '1' or memory_write /= '1' then
            report "  ERROR: PCW should enable write" severity error;
            errors := errors + 1;
        else
            report "  PASS: PCW enables write to memory";
        end if;

        state_t3 <= '0';
        wait for 50 ns;

        -- Test 4: PCC cycle (I/O read) during T3
        report "";
        report "Test 4: PCC cycle T3 state (I/O read - INP)";

        cycle_type     <= "10";  -- PCC
        instr_is_write <= '0';   -- INP (read)
        state_t3       <= '1';
        wait for 50 ns;

        if io_buffer_enable /= '1' or io_buffer_direction /= '0' then
            report "  ERROR: INP should enable read from I/O" severity error;
            errors := errors + 1;
        else
            report "  PASS: INP enables I/O read";
        end if;

        state_t3 <= '0';
        wait for 50 ns;

        -- Test 5: PCC cycle (I/O write) during T3
        report "";
        report "Test 5: PCC cycle T3 state (I/O write - OUT)";

        cycle_type     <= "10";  -- PCC
        instr_is_write <= '1';   -- OUT (write)
        state_t3       <= '1';
        wait for 50 ns;

        if io_buffer_enable /= '1' or io_buffer_direction /= '1' then
            report "  ERROR: OUT should enable write to I/O" severity error;
            errors := errors + 1;
        else
            report "  PASS: OUT enables I/O write";
        end if;

        state_t3 <= '0';
        wait for 50 ns;

        -- Test 6: T1 state (address output)
        report "";
        report "Test 6: T1 state (address from PC)";

        state_t1 <= '1';
        wait for 50 ns;

        if stack_addr_select /= '0' then
            report "  ERROR: Should select PC for address" severity error;
            errors := errors + 1;
        else
            report "  PASS: T1 selects PC for address output";
        end if;

        state_t1 <= '0';
        wait for 50 ns;

        -- ================================================================
        -- NEW MULTI-CYCLE INSTRUCTION TESTS
        -- ================================================================
        report "";
        report "========================================";
        report "TESTING MULTI-CYCLE INSTRUCTION HANDLING";
        report "========================================";

        -- Test 7: T4 cycle 2 - Register write (LrI instruction)
        report "";
        report "Test 7: T4 cycle 2 - Write register after immediate load";

        current_cycle      <= 2;
        instr_writes_reg   <= '1';
        instr_ddd_field    <= "011";  -- D register
        state_t4           <= '1';
        wait for 50 ns;

        if scratchpad_write /= '1' then
            report "  ERROR: Should enable scratchpad write" severity error;
            errors := errors + 1;
        end if;

        if scratchpad_select /= "011" then
            report "  ERROR: Should select register D (011)" severity error;
            errors := errors + 1;
        else
            report "  PASS: Register write in T4 correct";
        end if;

        state_t4 <= '0';
        instr_writes_reg <= '0';
        wait for 50 ns;

        -- Test 8: T4 cycle 3 - Stack push (CALL instruction)
        report "";
        report "Test 8: T4 cycle 3 - Stack push for CALL";

        current_cycle <= 3;
        instr_is_call <= '1';
        state_t4      <= '1';
        wait for 50 ns;

        if stack_push /= '1' then
            report "  ERROR: Should push to stack for CALL" severity error;
            errors := errors + 1;
        else
            report "  PASS: CALL stack push in T4 correct";
        end if;

        state_t4 <= '0';
        instr_is_call <= '0';
        wait for 50 ns;

        -- Test 9: T4 - Stack pop (RET instruction)
        -- RET pops stack during T4 (T5 keeps pc_load_from_stack set)
        report "";
        report "Test 9: T4 - Stack pop for RET";

        current_cycle <= 1;
        instr_is_ret  <= '1';
        state_t4      <= '1';
        wait for 50 ns;

        if stack_pop /= '1' then
            report "  ERROR: Should pop from stack for RET" severity error;
            errors := errors + 1;
        else
            report "  PASS: RET stack pop in T4 correct";
        end if;

        state_t4 <= '0';
        instr_is_ret <= '0';
        wait for 50 ns;

        -- Test 10: T4 - Stack push (RST instruction)
        -- RST pushes to stack during T4 (T5 loads PC from RST vector)
        report "";
        report "Test 10: T4 - Stack push for RST";

        current_cycle <= 1;
        instr_is_rst  <= '1';
        state_t4      <= '1';
        wait for 50 ns;

        if stack_push /= '1' then
            report "  ERROR: Should push to stack for RST" severity error;
            errors := errors + 1;
        else
            report "  PASS: RST stack push in T4 correct";
        end if;

        state_t4 <= '0';
        instr_is_rst <= '0';
        wait for 50 ns;

        -- Test 11: T4/T5 cycle 1 - Register read/write for MOV
        -- MOV uses T4 to read source (SSS) and T5 to write to dest (DDD)
        report "";
        report "Test 11: T4 cycle 1 - Register read for MOV";

        cycle_type       <= "00";  -- PCI (reset to safe value)
        current_cycle    <= 1;
        instr_reads_reg  <= '1';
        instr_writes_reg <= '1';
        instr_is_alu     <= '0';
        instr_needs_immediate <= '0';
        instr_sss_field  <= "010";  -- C register (source)
        instr_ddd_field  <= "001";  -- B register (dest)
        state_t4         <= '1';
        wait for 50 ns;

        if scratchpad_read /= '1' then
            report "  ERROR: Should enable scratchpad read at T4" severity error;
            errors := errors + 1;
        end if;

        if scratchpad_select /= "010" then
            report "  ERROR: Should select source register C (010) at T4" severity error;
            errors := errors + 1;
        else
            report "  PASS: MOV register read at T4 correct";
        end if;

        state_t4 <= '0';
        wait for 50 ns;

        -- Now test T5 for write
        report "";
        report "Test 11b: T5 cycle 1 - Register write for MOV";

        state_t5 <= '1';
        wait for 50 ns;

        if scratchpad_write /= '1' then
            report "  ERROR: Should enable scratchpad write at T5" severity error;
            errors := errors + 1;
        end if;

        if scratchpad_select /= "001" then
            report "  ERROR: Should select dest register B (001) at T5" severity error;
            errors := errors + 1;
        else
            report "  PASS: MOV register write at T5 correct";
        end if;

        state_t5 <= '0';
        instr_reads_reg <= '0';
        instr_writes_reg <= '0';
        wait for 50 ns;

        -- Test 12: PCW with register read (LMr - store register to memory)
        report "";
        report "Test 12: PCW - Memory write with register read";

        cycle_type      <= "11";  -- PCW
        instr_sss_field <= "101";  -- E register
        state_t3        <= '1';
        wait for 50 ns;

        if memory_write /= '1' then
            report "  ERROR: Should enable memory write" severity error;
            errors := errors + 1;
        end if;

        if scratchpad_select /= "101" then
            report "  ERROR: Should select register E (101)" severity error;
            errors := errors + 1;
        end if;

        if scratchpad_read /= '1' then
            report "  ERROR: Should read from scratchpad for memory write" severity error;
            errors := errors + 1;
        else
            report "  PASS: Memory write with register read correct";
        end if;

        state_t3 <= '0';
        wait for 50 ns;

        -- Test 13: PCC OUT - I/O write from accumulator
        report "";
        report "Test 13: PCC OUT - I/O write from A register";

        cycle_type     <= "10";  -- PCC
        instr_is_write <= '1';
        state_t3       <= '1';
        wait for 50 ns;

        if io_buffer_enable /= '1' or io_buffer_direction /= '1' then
            report "  ERROR: Should enable I/O write" severity error;
            errors := errors + 1;
        end if;

        if scratchpad_select /= "000" then
            report "  ERROR: Should select A register (000)" severity error;
            errors := errors + 1;
        end if;

        if scratchpad_read /= '1' then
            report "  ERROR: Should read from A for OUT" severity error;
            errors := errors + 1;
        else
            report "  PASS: OUT I/O write from A correct";
        end if;

        state_t3 <= '0';
        instr_is_write <= '0';
        wait for 50 ns;

        -- Summary
        report "";
        report "========================================";
        if errors = 0 then
            report "*** ALL TESTS PASSED ***";
        else
            report "*** TESTS FAILED: " & integer'image(errors) & " errors ***" severity error;
        end if;
        report "========================================";

        wait;
    end process;

end architecture test;

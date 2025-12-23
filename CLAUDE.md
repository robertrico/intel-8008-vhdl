# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is **b8008** - a block-based VHDL implementation of the Intel 8008 microprocessor (world's first 8-bit microprocessor from 1972). Unlike previous monolithic implementations, b8008 uses a **modular block-diagram approach** where each component (Program Counter, ALU, Register File, etc.) is a separate, simple module with explicit interfaces.

**IMPORTANT**: This is the third iteration of the Intel 8008 implementation:
- **s8008** (legacy) - Single-cycle implementation (in `src/components/s8008.vhdl`)
- **v8008** (legacy) - Attempted multi-cycle implementation (in `src/components/v8008.vhdl`)
- **b8008** (CURRENT) - Block-based, modular implementation (in `src/b8008/`)

**IGNORE ALL CODE IN**: `src/components/s8008.vhdl`, `src/components/v8008.vhdl`, and `projects/legacy_projects/`. These are deprecated implementations kept for reference only.

## Architecture Philosophy

### Block-Based Design

b8008 follows the Intel 8008 block diagram architecture:

```
┌─────────────────────────────────────────┐
│         Timing & Control Unit            │
│  (State Machine: T1→T2→T3→T4→T5)        │
│  Generates: pc_inc, reg_write, etc.      │
└──────────┬──────────────────────────────┘
           │ control signals
           ↓
┌──────────────────┐  ┌─────────────────┐
│  Program Counter │  │ Instruction Reg │
│  - increment     │  │ & Decoder       │
│  - load          │  └─────────────────┘
│  - hold          │
└──────────────────┘  ┌─────────────────┐
                      │  Register File  │
┌──────────────────┐  │  (A,B,C,D,E,H,L)│
│   Address Stack  │  └─────────────────┘
│   (8 x 14-bit)   │
└──────────────────┘  ┌─────────────────┐
                      │      ALU        │
                      │  (i8008_alu)    │
                      └─────────────────┘
```

**Key Principles:**
1. **Each module is simple** - Does ONE job, ~50-100 lines
2. **Explicit control signals** - No boolean logic soup, no conditional guards
3. **Modules are dumb** - No knowledge of instructions or other modules
4. **Test each module in isolation** - Every module has its own testbench

### Example: Program Counter Module

The program counter is 66 lines and does exactly three things:
- **Increment**: When `control.increment = '1'`, PC increments
- **Load**: When `control.load = '1'`, PC loads from `data_in`
- **Hold**: When `control.hold = '1'`, PC holds current value

It has NO knowledge of:
- Instructions (JMP, CALL, RST, etc.)
- Interrupts
- Timing states (T1, T2, T3, etc.)
- Other modules

## Key Development Commands

### CRITICAL: Always Use the Makefile

**NEVER run GHDL directly.** The Makefile handles:
- Correct compilation order and dependencies
- Proper GHDL flags (`--std=08`, `--work=work`)
- Build directory management
- All toolchain paths (GHDL, ASL assembler, hex converters)

```bash
# ❌ WRONG - Never do this
~/oss-cad-suite/bin/ghdl -a --std=08 some_file.vhdl
ghdl -r some_tb --stop-time=1ms

# ✅ CORRECT - Always use make targets
make test-b8008-top
make test-pc
make assemble PROG=my_test.asm
```

### Building and Testing

```bash
# Run the main system test (default program)
make test-b8008-top

# Run with a specific test program
make test-b8008-top PROG=search_as

# Test individual modules
make test-pc              # Program counter
make test-alu             # ALU
make test-instr-decoder   # Instruction decoder

# See all available make targets
make help

# See all available test programs
make show-programs

# Clean build artifacts
make clean
```

### Assembly Test Verification

**CRITICAL: Always use verification scripts when testing assembly programs.**

The `test_programs/verification_scripts/` directory contains automated verification scripts that:
- Parse simulation output for expected values
- Verify CPU register states and memory contents
- Report PASS/FAIL status with detailed error messages

```bash
# Run ALL verification tests (regression suite)
./test_programs/verification_scripts/run_all_tests.sh

# Run a specific verification test
./test_programs/verification_scripts/check_alu_test.sh
./test_programs/verification_scripts/check_search_test.sh
./test_programs/verification_scripts/check_ram_test.sh
./test_programs/verification_scripts/check_rotate_test.sh
./test_programs/verification_scripts/check_sign_parity_test.sh
./test_programs/verification_scripts/check_conditional_call_test.sh
./test_programs/verification_scripts/check_sign_parity_call_test.sh
./test_programs/verification_scripts/check_memory_alu_test.sh
./test_programs/verification_scripts/check_mvi_m_test.sh
./test_programs/verification_scripts/check_rst_test.sh
./test_programs/verification_scripts/check_io_test.sh
```

**Workflow for testing assembly programs:**
1. Write/modify the assembly program in `test_programs/`
2. Assemble with `make assemble PROG=my_test.asm`
3. Run the verification script: `./test_programs/verification_scripts/check_my_test.sh`
4. **NEVER** just run `make test-b8008-top` without verification - always use the scripts

## Directory Structure

```
intel-8008-vhdl/
├── Makefile                         # Simple, clean build system (41 lines)
├── src/
│   ├── b8008/                       # ✅ CURRENT: Block-based implementation
│   │   ├── ahl_pointer.vhdl
│   │   ├── alu.vhdl
│   │   ├── b8008_top.vhdl
│   │   ├── b8008_types.vhdl
│   │   ├── b8008.vhdl
│   │   ├── carry_lookahead.vhdl
│   │   ├── condition_flags.vhdl
│   │   ├── instruction_decoder.vhdl
│   │   ├── instruction_register.vhdl
│   │   ├── interrupt_ready_ff.vhdl
│   │   ├── io_buffer.vhdl
│   │   ├── machine_cycle_control.vhdl
│   │   ├── mem_mux_refresh.vhdl
│   │   ├── memory_io_control.vhdl
│   │   ├── program_counter.vhdl
│   │   ├── register_alu_control.vhdl
│   │   ├── register_file.vhdl
│   │   ├── scratchpad_addr_mux.vhdl
│   │   ├── scratchpad_decoder.vhdl
│   │   ├── sss_ddd_selector.vhdl
│   │   ├── stack_addr_decoder.vhdl
│   │   ├── stack_addr_mux.vhdl
│   │   ├── stack_memory.vhdl
│   │   ├── stack_pointer.vhdl
│   │   ├── state_timing_generator.vhdl
│   │   └── temp_registers.vhdl
│   ├── components/                  # Shared/reusable components
│   │   ├── phase_clocks.vhdl        # ✅ REUSABLE: Two-phase clock generator
│   │   ├── i8008_alu.vhdl           # ✅ REUSABLE: ALU (will be adapted for b8008)
│   │   ├── debouncer.vhdl           # ✅ REUSABLE: Button debouncer
│   │   ├── rom_2kx8.vhdl            # ✅ REUSABLE: 2KB ROM
│   │   ├── rom_4kx8.vhdl            # ✅ REUSABLE: 4KB ROM
│   │   └── legacy/                  # Legacy support components (DO NOT USE)
│   │       ├── memory_controller.vhdl
│   │       ├── interrupt_controller.vhdl
│   │       ├── io_controller.vhdl
│   │       ├── uart_rx.vhdl
│   │       └── uart_tx.vhdl
│   ├── s8008/                       # ⚠️ DEPRECATED: Single-cycle implementation
│   │   └── s8008.vhdl               # (IGNORE - legacy monolithic design)
│   └── v8008/                       # ⚠️ DEPRECATED: Multi-cycle implementation
│       └── v8008.vhdl               # (IGNORE - overly complex design)
├── sim/
│   ├── b8008/                       # ✅ CURRENT: Tests for b8008 modules
│   │   └── program_counter_tb.vhdl
│   └── units/                       # Unit tests for external peripheral components
├── build/
│   └── b8008/                       # Build artifacts for b8008
├── projects/
│   └── legacy_projects/             # ⚠️ DEPRECATED: Old s8008/v8008 FPGA projects
├── test_programs/                   # Assembly programs (.asm files)
│   └── verification_scripts/        # ✅ REQUIRED: Test verification scripts
│       ├── run_all_tests.sh         # Regression test runner
│       ├── check_alu_test.sh        # ALU instruction verification
│       ├── check_search_test.sh     # Memory search test verification
│       ├── check_ram_test.sh        # RAM read/write verification
│       ├── check_rotate_test.sh     # Rotate instruction verification
│       ├── check_conditional_call_test.sh
│       ├── check_sign_parity_call_test.sh
│       ├── check_memory_alu_test.sh
│       ├── check_mvi_m_test.sh
│       ├── check_rst_test.sh
│       └── check_io_test.sh
└── docs/                            # Documentation (datasheets, guides)
```

## b8008 Implementation Details

### Tool Requirements
- **OSS CAD Suite** required for GHDL (located at `~/oss-cad-suite`)
- Platform tested: macOS Sequoia 15.6.1

### Assembly Syntax (Future Use)
When we get to testing full programs, this project uses **8080 syntax** via AS Assembler:
- Use `MOV` instead of `Lrr`
- Use `MVI` instead of `LrI`
- Use `ADD`, `SUB` etc. instead of `ADr`, `SUr`

### Code Style

```vhdl
-- Good: Explicit, simple
if control.increment = '1' then
    pc <= pc + 1;
elsif control.load = '1' then
    pc <= data_in;
end if;

-- Bad: Conditional logic, instruction knowledge
if pc_inc and not (in_int_ack and is_jmp) then
    pc <= pc + 1;
end if;
```

### Debugging

If a test fails:
1. Check the module in isolation first
2. Verify control signals are correct
3. Look at waveforms if needed (future: add wave viewing support)
4. Each module should be simple enough to understand completely

## Common Mistakes to Avoid

1. **Don't run GHDL directly** - Always use `make` targets. The Makefile ensures correct compilation order, flags, and paths
2. **Don't skip verification scripts** - When testing assembly programs, always use `./test_programs/verification_scripts/` scripts, not raw simulation output
3. **Don't add conditional logic** - If you find yourself writing `if (is_jmp and not in_interrupt)`, you're doing it wrong
4. **Don't make modules smart** - Modules should be dumb and do what they're told
5. **Don't skip testing** - Every module needs a testbench
6. **Don't reference legacy code** - s8008 and v8008 are deprecated for good reasons
7. **Don't make monolithic designs** - Keep modules small and focused

## Questions?

If you're unsure about the approach:
1. Look at `program_counter.vhdl` as the reference example
2. Keep it simple - really simple
3. When in doubt, ask the user

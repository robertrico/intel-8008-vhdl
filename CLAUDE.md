# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is **b8008** - a block-based VHDL implementation of the Intel 8008 microprocessor (world's first 8-bit microprocessor from 1972). Unlike previous monolithic implementations, b8008 uses a **modular block-diagram approach** where each component (Program Counter, ALU, Register File, etc.) is a separate, simple module with explicit interfaces.

**IMPORTANT**: This is the third iteration of the Intel 8008 implementation:
- **s8008** (legacy) - Single-cycle implementation (in `src/s8008/`)
- **v8008** (legacy) - Attempted multi-cycle implementation (in `src/v8008/`)
- **b8008** (CURRENT) - Block-based, modular implementation (in `src/b8008/`)

**IGNORE ALL CODE IN**: `src/s8008/`, `src/v8008/`, and `projects/legacy_projects/`. These are deprecated implementations kept for reference only.

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
│  Address Stack   │  │ Instruction Reg │
│  (8 x 14-bit)    │  │ & Decoder       │
│  slot[SP] = PC   │  └─────────────────┘
│  - increment     │
│  - load          │  ┌─────────────────┐
│  - hold          │  │  Register File  │
└──────────────────┘  │  (A,B,C,D,E,H,L)│
                      └─────────────────┘
┌──────────────────┐
│  Stack Pointer   │  ┌─────────────────┐
│  (3-bit, wraps)  │  │      ALU        │
└──────────────────┘  │  (alu.vhdl)     │
                      └─────────────────┘
```

Note: per the real Intel block diagram the PC is one of the 8
address-stack registers (`stack_memory.vhdl`, selected by SP). CALL is
just SP moving on (the old slot keeps the return address); RET is SP
moving back. 7 nested returns; the 8th CALL wraps onto the oldest.

**Key Principles:**
1. **Each module is simple** - Does ONE job, ~50-100 lines
2. **Explicit control signals** - No boolean logic soup, no conditional guards
3. **Modules are dumb** - No knowledge of instructions or other modules
4. **Test each module in isolation** - Every module has its own testbench

### Example: Stack Pointer Module

The stack pointer is 69 lines and does exactly two things:
- **Push**: When `stack_push = '1'`, SP increments (wraps 7 -> 0)
- **Pop**: When `stack_pop = '1'`, SP decrements (wraps 0 -> 7)

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
make test-stack-memory
make assemble PROG=my_test.asm
```

### Building and Testing

```bash
# Run the main system test (default program)
make test-b8008-top

# Run with a specific test program
make test-b8008-top PROG=search_as

# Test individual modules
make test-stack-memory    # Address stack (PC-in-stack)
make test-alu             # ALU
make test-alu-exhaustive  # ALU: all 1,049,600 arithmetic+logical cases vs reference model
make test-carry-lookahead # Carry look-ahead (the ALU's adder)
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

# Run a specific verification test (one check_*.sh per test program - 35 total)
./test_programs/verification_scripts/check_alu_test.sh
./test_programs/verification_scripts/check_search_test.sh
./test_programs/verification_scripts/check_ready_wait_test.sh
# ... ls test_programs/verification_scripts/check_*.sh for the full list
```

**Workflow for testing assembly programs:**
1. Write/modify the assembly program in `test_programs/`
2. Assemble with `make assemble PROG=my_test.asm`
3. Run the verification script: `./test_programs/verification_scripts/check_my_test.sh`
4. **NEVER** just run `make test-b8008-top` without verification - always use the scripts

## Directory Structure

```
intel-8008-vhdl/
├── Makefile                         # Build system: sim, synth, formal, assembler targets (see 'make help')
├── src/
│   ├── b8008/                       # ✅ CURRENT: Block-based implementation
│   │   ├── address_decoder.vhdl
│   │   ├── ahl_pointer.vhdl
│   │   ├── alu.vhdl
│   │   ├── b8008_top.vhdl
│   │   ├── b8008_types.vhdl
│   │   ├── b8008.vhdl
│   │   ├── carry_lookahead.vhdl
│   │   ├── condition_flags.vhdl
│   │   ├── debug_clock_control.vhdl
│   │   ├── instruction_decoder.vhdl
│   │   ├── instruction_register.vhdl
│   │   ├── int_button.vhdl
│   │   ├── interrupt_ready_ff.vhdl
│   │   ├── io_buffer.vhdl
│   │   ├── machine_cycle_control.vhdl
│   │   ├── mem_mux_refresh.vhdl
│   │   ├── memory_io_control.vhdl
│   │   ├── ram_sync.vhdl
│   │   ├── register_alu_control.vhdl
│   │   ├── register_file.vhdl
│   │   ├── scratchpad_decoder.vhdl
│   │   ├── stack_memory.vhdl
│   │   ├── stack_pointer.vhdl
│   │   ├── state_timing_generator.vhdl
│   │   └── temp_registers.vhdl
│   ├── components/                  # Shared/reusable components
│   │   ├── phase_clocks.vhdl        # ✅ REUSABLE: Two-phase clock generator
│   │   ├── i8008_alu.vhdl           # legacy ALU (b8008 has its own alu.vhdl)
│   │   ├── debouncer.vhdl           # ✅ REUSABLE: Button debouncer
│   │   ├── uart_rx.vhdl / uart_tx.vhdl / usart.vhdl / b8008_usart.vhdl
│   │   ├── rom_1kx8/2kx8/4kx8/8kx8.vhdl, ram_4kx8.vhdl
│   │   └── legacy/                  # Legacy support components (DO NOT USE)
│   ├── s8008/                       # ⚠️ DEPRECATED: Single-cycle implementation + its TBs (IGNORE)
│   ├── v8008/                       # ⚠️ DEPRECATED: Multi-cycle implementation + its TBs (IGNORE)
│   └── synth/                       # Synthesis wrappers
├── sim/
│   ├── b8008/                       # ✅ CURRENT: VHDL testbenches for b8008 modules
│   ├── cocotb/                      # ✅ cocotb suites (decoder, stack_pointer, memory_io_control, b8008_top bus monitor)
│   └── units/                       # Unit tests for external peripheral components
├── formal/                          # ✅ SBY property suites + netlist miters (per-module), eqy/
├── build/
│   └── b8008/                       # Build artifacts for b8008
├── projects/
│   ├── b8008_basic/, b8008_monitor/ # FPGA board tops
│   └── legacy_projects/             # ⚠️ DEPRECATED: Old s8008/v8008 FPGA projects
├── test_programs/                   # Assembly programs (.asm files)
│   └── verification_scripts/        # ✅ REQUIRED: run_all_tests.sh + one check_*.sh per program (35 tests)
├── test_tools/                      # Log/trace analysis helpers
└── docs/                            # Documentation (datasheets, SPEC/MAS/VPLAN/BUS_PROTOCOL/TIMING/BRINGUP)
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
1. Look at `stack_pointer.vhdl` as the reference example
2. Keep it simple - really simple
3. When in doubt, ask the user

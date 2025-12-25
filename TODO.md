# TODO - b8008 Verification Roadmap

This document tracks what needs to be done before the b8008 is ready for FPGA hardware deployment.

## Current Status

- **24/24 verification tests pass**
- **All 48 instruction types implemented** (28 unique operation categories)
- **Block-based architecture complete**
- **Stack depth bug fixed** (RET was reading from wrong level)
- **Interrupt handling tested** (RST 0 bootstrap + RST 7 runtime interrupt)
- **Conditional RET bug fixed** (RZ/RNZ/etc. were ignoring condition flags)
- **Serial I/O tested** (hello_8008.asm outputs "HI\r\n0123456789 B8008-OK\r\n")
- **Estimated opcode coverage: ~90-95%** (see Confidence Report below)

---

## Confidence Report Summary

| Category | Confidence | Notes |
|----------|------------|-------|
| Instruction Decoder | 95% | All 48 instruction types decoded correctly |
| ALU Operations | 95% | Comprehensive testing of all register and immediate modes |
| Register Operations | 95% | All MOV r,r combinations tested via chains, swaps, NOPs |
| Memory Operations | 95% | MOV r,M and MOV M,r tested for all 14 variants |
| INR/DCR | 100% | All 12 variants tested with boundary conditions |
| Control Flow | 95% | JMP, CALL, RET, conditionals all tested |
| RST Instructions | 100% | All 8 vectors tested |
| I/O Operations | 100% | All 8 INP and all 24 OUT ports tested |
| Interrupts | 100% | Bootstrap (RST 0) and runtime interrupt (RST 7) tested |
| **Overall System** | **95%** | Ready for hardware with high confidence |

---

## High Priority

### [x] Add MOV r,M / MOV M,r Explicit Tests
- [x] Create dedicated test for all MOV r,M combinations
- [x] Create dedicated test for all MOV M,r combinations
- [x] Add verification script (`check_mov_mem_test.sh`)

### [x] Add Comprehensive INR/DCR Test
- [x] Test INR B, INR C, INR D, INR E, INR H, INR L (6 variants - no INR A exists)
- [x] Test DCR B, DCR C, DCR D, DCR E, DCR H, DCR L (6 variants - no DCR A exists)
- [x] Test boundary conditions: 0xFF + 1 → 0x00 with Zero flag, 0x00 - 1 → 0xFF
- [x] Add verification script (`check_inr_dcr_test.sh`)
- Note: INR/DCR don't affect the Carry flag per Intel 8008 spec

### [x] Add Systematic MOV r,r Test
- [x] Create test with all MOV r,r combinations (A,B,C,D,E,H,L sources/destinations)
- [x] Verify data propagation through register chain (forward and reverse)
- [x] Test register swaps (B<->C, D<->E, H<->L)
- [x] Test MOV X,X (NOP) preservation
- [x] Add verification script (`check_mov_rr_test.sh`)

---

## Medium Priority

### [x] Add RST 0, 5, 6, 7 Tests
- [x] RST 0 is special (address 0x0000) - tested via bootstrap
- [x] RST 5, 6, 7 tests added in `rst_full_test_as.asm`
- [x] Verification script: `check_rst_full_test.sh`

### [x] Add Flag Verification to Tests
- [x] Added debug flag outputs to b8008 and b8008_top
- [x] Created `flag_test_as.asm` with 8 flag tests
- [x] Verification script: `check_flag_test.sh`
- [x] Tests Carry, Zero, Sign, and Parity flags

### [x] Add Interrupt Test
`interrupt_ready_ff.vhdl` tested via dedicated interrupt testbench.
- [x] Create `interrupt_test_as.asm`
- [x] Test INT input sampling
- [x] Test T1I acknowledge cycle with RST instruction jamming
- [x] Test runtime interrupt (RST 7) waking from HLT
- [x] Create verification script (`check_interrupt_test.sh`)
- [x] Fixed IR reload bug after T1I (instruction was being overwritten from ROM)

### [x] Stack Depth Test
- [x] Test 6 nested CALLs (`stack_depth_test_as.asm`)
- [x] Fixed stack bug: RET was reading before SP decrement
- [x] Verification script: `check_stack_depth_test.sh`
- Note: Stack supports 8 levels (0-7), practical usable depth is 6-7 with bootstrap

### [x] Expand I/O Port Coverage
- [x] Test all 8 INP ports (0-7)
- [x] Test all 24 OUT ports (8-31, port 31 used for checkpoints)
- [x] Created `io_comprehensive_test_as.asm`
- [x] Verification script: `check_io_comprehensive_test.sh`

### [x] Add ALU Register Mode Coverage
- [x] Test ADD/ADC/SUB/SBB with all 7 source registers
- [x] Test ANA/XRA/ORA/CMP with all 7 source registers
- [x] Created `alu_reg_comprehensive_test_as.asm`
- [x] Verification script: `check_alu_reg_comprehensive_test.sh`

---

## Low Priority

### [ ] Cross-Validate with Reference Simulator
Run identical test programs on:
- SIMH 8008 simulator
- Compare final states bit-for-bit
- Document any discrepancies

### [ ] Cycle-Accurate Timing Tests
Verify instruction timing matches Intel spec:
- 1-cycle (5 states): MOV r,r, INR, DCR, rotate
- 2-cycle (8 states): MVI, MOV r,M, MOV M,r, ALU M, INP
- 3-cycle (11 states): JMP, CALL, MVI M

### [x] FPGA Synthesis Test
- [x] GHDL synthesis: 6665 lines Verilog netlist
- [x] Added `make synth` target to Makefile
- [x] Yosys+nextpnr: ECP5 85k place & route complete
  - Device utilization: 106 LUTs, 46 FFs, 106 I/O (0% of 85k device)
  - Max frequency: 217 MHz (clk_in), 227 MHz (phi2) - easily meets 12 MHz target
- [x] Timing closure verified: PASS at 12 MHz
- [x] Bitstream generation: 1.8 MB .bit file ready
- [x] Create b8008 version of blinky project
  - `make project P=blinky` builds complete system
  - 112 LUTs, 63 FFs (includes ROM + RAM + CPU)
  - Max frequency: 218 MHz (100 MHz target) - PASS
  - Bitstream: 276 KB

### [ ] Run Historical 8008 Software
Find and run real 8008 programs:
- BASIC interpreter fragments
- Utility programs from the era
- If real software runs, confidence increases dramatically

### [ ] Create Opcode Sweep Test
Write a test that executes EVERY unique opcode at least once:
- Exhaustive coverage of all 205+ valid opcodes
- Use checkpoints to verify each executed correctly
- This is the "gold standard" for instruction coverage

---

## Known Limitations

### No INR A or DCR A Instructions
- Opcode 0x00 (which would be INR A with DDD=000) is HLT instead
- Opcode 0x01 (which would be DCR A with DDD=000) is also HLT
- This is correct per Intel 8008 specification - the accumulator cannot be incremented/decremented directly
- To increment A, use `ADI 01h`. To decrement A, use `SUI 01h`

### READY Signal Untested
External wait state handling exists but has no test coverage.

---

## Test Coverage Matrix

| Instruction Type | Count | Tested | Coverage |
|-----------------|-------|--------|----------|
| HLT | 3 | 3 | **100%** |
| MOV r,r | 49 | 49 | **100%** |
| MOV r,M | 7 | 7 | **100%** |
| MOV M,r | 7 | 7 | **100%** |
| MVI r | 7 | 7 | **100%** |
| MVI M | 1 | 1 | **100%** |
| INR | 6 | 6 | **100%** |
| DCR | 6 | 6 | **100%** |
| ALU r (56 ops) | 56 | 56 | **100%** |
| ALU M | 8 | 8 | **100%** |
| ALU I | 8 | 8 | **100%** |
| Rotate | 4 | 4 | **100%** |
| JMP | 1 | 1 | **100%** |
| Jcc | 8 | 8 | **100%** |
| CALL | 1 | 1 | **100%** |
| Ccc | 8 | 8 | **100%** |
| RET | 1 | 1 | **100%** |
| Rcc | 8 | 8 | **100%** |
| RST | 8 | 8 | **100%** |
| INP | 8 | 8 | **100%** |
| OUT | 24 | 24 | **100%** |

Note: INR/DCR have 6 variants each (B,C,D,E,H,L) - no INR A or DCR A exists.

---

## Test Program Summary

| Test | What It Verifies | Status |
|------|------------------|--------|
| `alu_test_as.asm` | ADD, SUB, AND, XOR, OR, ADI, SUI, ANI, XRI, ORI, DCR, CMP, ADC, SBB | PASS |
| `alu_reg_comprehensive_test_as.asm` | All ALU register modes: ADD/SUB/ANA/ORA/XRA/CMP r with all registers | PASS |
| `rotate_carry_test_as.asm` | RLC, RRC, RAL, RAR, JC, JNC, RC, RNC, ADD M, SUB M | PASS |
| `conditional_call_test_as.asm` | ACI, SBI, CC, CNC, CNZ, CZ, RZ | PASS |
| `sign_parity_test_as.asm` | JP, JM, JPE, JPO, RP, RM, RPE, RPO | PASS |
| `sign_parity_call_test_as.asm` | CP, CM, CPO, CPE | PASS |
| `rst_test_as.asm` | RST 1, RST 2, RST 3, RST 4 | PASS |
| `rst_full_test_as.asm` | RST 1-7 (all vectors) | PASS |
| `io_test_as.asm` | INP 0-2, OUT 8-9 | PASS |
| `io_comprehensive_test_as.asm` | INP 0-7, OUT 8-30 (all ports) | PASS |
| `ram_intensive_as.asm` | MVI, MOV, memory operations | PASS |
| `memory_alu_test_as.asm` | ADC M, SBB M, ANA M, XRA M, ORA M, CMP M | PASS |
| `mvi_m_test_as.asm` | MVI M | PASS |
| `mov_mem_test_as.asm` | MOV r,M, MOV M,r (all 14 combinations) | PASS |
| `mov_rr_test_as.asm` | MOV r,r (all combinations via chains/swaps) | PASS |
| `inr_dcr_test_as.asm` | INR/DCR all registers, boundary conditions | PASS |
| `flag_test_as.asm` | Carry, Zero, Sign, Parity flags | PASS |
| `stack_depth_test_as.asm` | 6 nested CALLs/RETs | PASS |
| `search_as.asm` | Integrated algorithm test | PASS |
| `alu_full_coverage_test_as.asm` | ADC/SBB/ANA/ORA/XRA/CMP with all registers | PASS |
| `interrupt_test_as.asm` | Bootstrap RST 0, runtime RST 7 interrupt | PASS |
| `hlt_01_as.asm` | HLT opcode 0x01 | PASS |
| `hlt_ff_as.asm` | HLT opcode 0xFF | PASS |
| `hello_8008.asm` | Serial I/O, MOV A,M, PUTS routine, conditional RET | PASS |

---

## Verification Commands

```bash
# Run all tests
./test_programs/verification_scripts/run_all_tests.sh

# Run individual test
./test_programs/verification_scripts/check_alu_test.sh

# Run with specific program
make test-b8008-top PROG=alu_test_as SIM_TIME=30ms
```

---

## Completion Criteria for Hardware

Before FPGA deployment, ALL of the following must be true:

1. [x] All high priority items complete (INR/DCR test, MOV r,r test)
2. [x] All medium priority items complete (I/O, ALU coverage, interrupt test)
3. [x] Opcode coverage reaches 90%+ (currently ~95%)
4. [x] GHDL synthesis completes without errors (6665 lines Verilog)
5. [x] Yosys/nextpnr place & route (ECP5 85k: 106 LUTs, 46 FFs)
6. [x] Timing analysis passes (217 MHz / 227 MHz, target 12 MHz)
7. [ ] At least one test program runs on hardware


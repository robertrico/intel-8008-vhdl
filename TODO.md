# TODO - b8008 Verification Roadmap

This document tracks what needs to be done before the b8008 is ready for FPGA hardware deployment.

## Current Status

- **15/15 verification tests pass**
- **All 48 instruction types implemented** (28 unique operation categories)
- **Block-based architecture complete**
- **Stack depth bug fixed** (RET was reading from wrong level)
- **Estimated opcode coverage: ~55-60%** (see Confidence Report below)

---

## Confidence Report Summary

| Category | Confidence | Notes |
|----------|------------|-------|
| Instruction Decoder | 95% | All 48 instruction types decoded correctly |
| ALU Operations | 90% | Tested comprehensively, edge cases possible |
| Register Operations | 75% | MOV r,r works but limited explicit testing |
| Memory Operations | 85% | MOV r,M and MOV M,r tested for all 14 variants |
| Control Flow | 90% | JMP, CALL, RET, conditionals all tested |
| RST Instructions | 95% | All 8 vectors tested |
| I/O Operations | 40% | Only 5 of 32 I/O operations tested |
| **Overall System** | **75-80%** | Core functionality proven, gaps in edge cases |

---

## High Priority

### [x] Add MOV r,M / MOV M,r Explicit Tests
- [x] Create dedicated test for all MOV r,M combinations
- [x] Create dedicated test for all MOV M,r combinations
- [x] Add verification script (`check_mov_mem_test.sh`)

### [ ] Add Comprehensive INR/DCR Test
Current tests only use INR L and DCR L. Need to verify all register variants.
- [ ] Test INR B, INR C, INR D, INR E, INR H, INR L (6 variants - no INR A exists)
- [ ] Test DCR B, DCR C, DCR D, DCR E, DCR H, DCR L (6 variants - no DCR A exists)
- [ ] Test boundary conditions: 0xFF + 1 → 0x00 with Zero flag, 0x00 - 1 → 0xFF
- [ ] Add verification script (`check_inr_dcr_test.sh`)
- Note: INR/DCR don't affect the Carry flag per Intel 8008 spec

### [ ] Add Systematic MOV r,r Test
Only MOV A,A (NOP) is used extensively. Need to test all 36 register-to-register moves.
- [ ] Create test with all MOV r,r combinations (A,B,C,D,E,H,L sources/destinations)
- [ ] Verify data propagation through register chain
- [ ] Add verification script (`check_mov_rr_test.sh`)

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

### [ ] Add Interrupt Test
`interrupt_ready_ff.vhdl` exists but has no test.
- [ ] Create `interrupt_test_as.asm`
- [ ] Test INT input sampling
- [ ] Test T1I acknowledge cycle
- [ ] Create verification script

### [x] Stack Depth Test
- [x] Test 6 nested CALLs (`stack_depth_test_as.asm`)
- [x] Fixed stack bug: RET was reading before SP decrement
- [x] Verification script: `check_stack_depth_test.sh`
- Note: Stack supports 8 levels (0-7), practical usable depth is 6-7 with bootstrap

### [ ] Expand I/O Port Coverage
Currently only 5 of 32 I/O operations tested.
- [ ] Test all 8 INP ports (0-7) - currently only 0,1,2 tested
- [ ] Test more OUT ports (8-31) - currently only 8,9,31 tested
- [ ] Update `io_test_as.asm` or create `io_comprehensive_test_as.asm`
- [ ] Update verification script

### [ ] Add ALU Register Mode Coverage
Only ~27% of ALU register operations tested.
- [ ] Test ADD/ADC/SUB/SBB with all 7 source registers
- [ ] Test ANA/XRA/ORA/CMP with all 7 source registers
- [ ] Add to `alu_test_as.asm` or create `alu_comprehensive_test_as.asm`

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

### [ ] FPGA Synthesis Test
Before hardware deployment:
- Synthesize b8008 with Yosys
- Check resource utilization
- Verify timing closure
- Create b8008 version of blinky project

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
| HLT | 3 | 1+ | 33%+ |
| MOV r,r | 36 | ~5 | 14% |
| MOV r,M | 7 | 7 | **100%** |
| MOV M,r | 7 | 7 | **100%** |
| MVI r | 7 | 7 | **100%** |
| MVI M | 1 | 1 | **100%** |
| INR | 6 | 2-3 | 33-50% |
| DCR | 6 | 1 | 17% |
| ALU r (56 ops) | 56 | ~15 | 27% |
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
| INP | 8 | 3 | 38% |
| OUT | 24 | 3 | 13% |

Note: INR/DCR have 6 variants each (B,C,D,E,H,L) - no INR A or DCR A exists.

---

## Test Program Summary

| Test | What It Verifies | Status |
|------|------------------|--------|
| `alu_test_as.asm` | ADD, SUB, AND, XOR, OR, ADI, SUI, ANI, XRI, ORI, DCR, CMP, ADC, SBB | PASS |
| `rotate_carry_test_as.asm` | RLC, RRC, RAL, RAR, JC, JNC, RC, RNC, ADD M, SUB M | PASS |
| `conditional_call_test_as.asm` | ACI, SBI, CC, CNC, CNZ, CZ, RZ | PASS |
| `sign_parity_test_as.asm` | JP, JM, JPE, JPO, RP, RM, RPE, RPO | PASS |
| `sign_parity_call_test_as.asm` | CP, CM, CPO, CPE | PASS |
| `rst_test_as.asm` | RST 1, RST 2, RST 3, RST 4 | PASS |
| `rst_full_test_as.asm` | RST 1-7 (all vectors) | PASS |
| `io_test_as.asm` | INP 0-2, OUT 8-9 | PASS |
| `ram_intensive_as.asm` | MVI, MOV, memory operations | PASS |
| `memory_alu_test_as.asm` | ADC M, SBB M, ANA M, XRA M, ORA M, CMP M | PASS |
| `mvi_m_test_as.asm` | MVI M | PASS |
| `mov_mem_test_as.asm` | MOV r,M, MOV M,r (all 14 combinations) | PASS |
| `flag_test_as.asm` | Carry, Zero, Sign, Parity flags | PASS |
| `stack_depth_test_as.asm` | 6 nested CALLs/RETs | PASS |
| `search_as.asm` | Integrated algorithm test | PASS |

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

1. [ ] All high priority items complete (INR/DCR test, MOV r,r test)
2. [ ] All medium priority items complete (interrupt, I/O, ALU coverage)
3. [ ] Opcode coverage reaches 80%+
4. [ ] Synthesis completes without errors
5. [ ] Timing analysis passes
6. [ ] At least one test program runs on hardware

---

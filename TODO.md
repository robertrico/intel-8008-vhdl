# TODO - b8008 Verification Roadmap

This document tracks what needs to be done before the b8008 is ready for FPGA hardware deployment.

## Current Status

- **11/11 verification tests pass**
- **All 28 instruction categories implemented**
- **Block-based architecture complete**

---

## High Priority

### [ ] Add MOV r,M / MOV M,r Explicit Tests
The `mvi_m_test_as.asm` mentions MOV A,M but doesn't execute it.
- Create dedicated test for all MOV r,M combinations
- Create dedicated test for all MOV M,r combinations
- Add verification script

---

## Medium Priority

### [ ] Add RST 0, 5, 6, 7 Tests
Current `rst_test_as.asm` only tests RST 1-4.
- RST 0 is special (address 0x0000)
- RST 7 is edge case (address 0x0038)
- Add to existing test or create new one

### [ ] Add Flag Verification to Tests
Current tests only check register values, not flags.
- Add Carry flag verification
- Add Zero flag verification
- Add Sign flag verification
- Add Parity flag verification
- Test edge cases: 0x00, 0x80, 0xFF

### [ ] Add Interrupt Test
`interrupt_ready_ff.vhdl` exists but has no test.
- Create `interrupt_test_as.asm`
- Test INT input sampling
- Test T1I acknowledge cycle
- Create verification script

### [ ] Stack Depth Test
8-level stack not tested for limits.
- Test 8 nested CALLs
- Document overflow behavior
- Test RST within nested calls

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

---

## Known Limitations

### No INR A Instruction
Opcode 0x00 (which would be INR A with DDD=000) is HLT instead.
This is correct per Intel 8008 specification - not a bug.

### READY Signal Untested
External wait state handling exists but has no test coverage.

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
| `io_test_as.asm` | INP, OUT | PASS |
| `ram_intensive_as.asm` | MVI, MOV, memory operations | PASS |
| `memory_alu_test_as.asm` | ADC M, SBB M, ANA M, XRA M, ORA M, CMP M | PASS |
| `mvi_m_test_as.asm` | MVI M | PASS |
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

1. [ ] All high priority items complete
2. [ ] All medium priority items complete
3. [ ] `docs/instruction_coverage.md` shows 100% opcode coverage
4. [ ] Synthesis completes without errors
5. [ ] Timing analysis passes
6. [ ] At least one test program runs on hardware

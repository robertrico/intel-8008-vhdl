# Intel 8008 Instruction Coverage

This document tracks test coverage for every Intel 8008 opcode.

## Coverage Summary

| Category | Opcodes | Tested | Coverage |
|----------|---------|--------|----------|
| HLT | 2 | 2 | 100% |
| MOV r,r | 49 | partial | ~10% |
| MOV r,M | 7 | 0 | 0% |
| MOV M,r | 7 | 0 | 0% |
| MVI r | 7 | 7 | 100% |
| MVI M | 1 | 1 | 100% |
| INR | 7 | 7 | 100% |
| DCR | 7 | 7 | 100% |
| ALU r | 56 | partial | ~50% |
| ALU M | 8 | 8 | 100% |
| ALU I | 8 | 8 | 100% |
| Rotate | 4 | 4 | 100% |
| JMP | 1 | 1 | 100% |
| Jcc | 8 | 8 | 100% |
| CALL | 1 | 1 | 100% |
| Ccc | 8 | 8 | 100% |
| RET | 1 | 1 | 100% |
| Rcc | 8 | 8 | 100% |
| RST | 8 | 4 | 50% |
| INP | 8 | 3 | 38% |
| OUT | 24 | 2 | 8% |

---

## Opcode Matrix (0x00 - 0xFF)

Legend:
- `[x]` = Tested and verified
- `[ ]` = Not tested
- `N/A` = Invalid/undefined opcode

### 0x00 - 0x0F (Index/Control)

| Opcode | Mnemonic | Test File | Status |
|--------|----------|-----------|--------|
| 0x00 | HLT | all tests | [x] |
| 0x01 | HLT | - | [ ] |
| 0x02 | RLC | rotate_carry_test | [x] |
| 0x03 | RFc (RNC) | rotate_carry_test | [x] |
| 0x04 | ADI | alu_test | [x] |
| 0x05 | RST 0 | - | [ ] |
| 0x06 | MVI A | multiple | [x] |
| 0x07 | RET | multiple | [x] |
| 0x08 | INR B | alu_test | [x] |
| 0x09 | DCR B | - | [ ] |
| 0x0A | RRC | rotate_carry_test | [x] |
| 0x0B | RFc (RNZ) | conditional_call_test | [x] |
| 0x0C | ACI | conditional_call_test | [x] |
| 0x0D | RST 1 | rst_test | [x] |
| 0x0E | MVI B | multiple | [x] |
| 0x0F | RET | - | [ ] |

### 0x10 - 0x1F

| Opcode | Mnemonic | Test File | Status |
|--------|----------|-----------|--------|
| 0x10 | INR C | - | [ ] |
| 0x11 | DCR C | - | [ ] |
| 0x12 | RAL | rotate_carry_test | [x] |
| 0x13 | RTc (RC) | rotate_carry_test | [x] |
| 0x14 | SUI | alu_test | [x] |
| 0x15 | RST 2 | rst_test | [x] |
| 0x16 | MVI C | multiple | [x] |
| 0x17 | RET | - | [ ] |
| 0x18 | INR D | - | [ ] |
| 0x19 | DCR D | - | [ ] |
| 0x1A | RAR | rotate_carry_test | [x] |
| 0x1B | RTc (RZ) | conditional_call_test | [x] |
| 0x1C | SBI | conditional_call_test | [x] |
| 0x1D | RST 3 | rst_test | [x] |
| 0x1E | MVI D | multiple | [x] |
| 0x1F | RET | - | [ ] |

### 0x20 - 0x2F

| Opcode | Mnemonic | Test File | Status |
|--------|----------|-----------|--------|
| 0x20 | INR E | - | [ ] |
| 0x21 | DCR E | - | [ ] |
| 0x22 | N/A | - | N/A |
| 0x23 | RFc (RP) | sign_parity_test | [x] |
| 0x24 | ANI | alu_test | [x] |
| 0x25 | RST 4 | rst_test | [x] |
| 0x26 | MVI E | multiple | [x] |
| 0x27 | RET | - | [ ] |
| 0x28 | INR H | - | [ ] |
| 0x29 | DCR H | - | [ ] |
| 0x2A | N/A | - | N/A |
| 0x2B | RTc (RM) | sign_parity_test | [x] |
| 0x2C | XRI | alu_test | [x] |
| 0x2D | RST 5 | - | [ ] |
| 0x2E | MVI H | multiple | [x] |
| 0x2F | RET | - | [ ] |

### 0x30 - 0x3F

| Opcode | Mnemonic | Test File | Status |
|--------|----------|-----------|--------|
| 0x30 | INR L | - | [ ] |
| 0x31 | DCR L | alu_test | [x] |
| 0x32 | N/A | - | N/A |
| 0x33 | RFc (RPO) | sign_parity_test | [x] |
| 0x34 | ORI | alu_test | [x] |
| 0x35 | RST 6 | - | [ ] |
| 0x36 | MVI L | multiple | [x] |
| 0x37 | RET | - | [ ] |
| 0x38 | N/A | - | N/A |
| 0x39 | N/A | - | N/A |
| 0x3A | N/A | - | N/A |
| 0x3B | RTc (RPE) | sign_parity_test | [x] |
| 0x3C | CPI | alu_test | [x] |
| 0x3D | RST 7 | - | [ ] |
| 0x3E | MVI M | mvi_m_test | [x] |
| 0x3F | RET | - | [ ] |

### 0x40 - 0x4F (I/O and Jump)

| Opcode | Mnemonic | Test File | Status |
|--------|----------|-----------|--------|
| 0x40 | JFc (JNC) | rotate_carry_test | [x] |
| 0x41 | INP 0 | io_test | [x] |
| 0x42 | CFc (CNC) | conditional_call_test | [x] |
| 0x43 | INP 1 | io_test | [x] |
| 0x44 | JMP | multiple | [x] |
| 0x45 | INP 2 | io_test | [x] |
| 0x46 | CALL | multiple | [x] |
| 0x47 | INP 3 | - | [ ] |
| 0x48 | JTc (JC) | rotate_carry_test | [x] |
| 0x49 | INP 4 | - | [ ] |
| 0x4A | CTc (CC) | conditional_call_test | [x] |
| 0x4B | INP 5 | - | [ ] |
| 0x4C | JMP | - | [ ] |
| 0x4D | INP 6 | - | [ ] |
| 0x4E | CALL | - | [ ] |
| 0x4F | INP 7 | - | [ ] |

### 0x50 - 0x5F (Jump/Call/OUT)

| Opcode | Mnemonic | Test File | Status |
|--------|----------|-----------|--------|
| 0x50 | JFc (JNZ) | multiple | [x] |
| 0x51 | OUT 8 | io_test | [x] |
| 0x52 | CFc (CNZ) | conditional_call_test | [x] |
| 0x53 | OUT 9 | io_test | [x] |
| 0x54 | JMP | - | [ ] |
| 0x55 | OUT 10 | - | [ ] |
| 0x56 | CALL | - | [ ] |
| 0x57 | OUT 11 | - | [ ] |
| 0x58 | JTc (JZ) | multiple | [x] |
| 0x59 | OUT 12 | - | [ ] |
| 0x5A | CTc (CZ) | conditional_call_test | [x] |
| 0x5B | OUT 13 | - | [ ] |
| 0x5C | JMP | - | [ ] |
| 0x5D | OUT 14 | - | [ ] |
| 0x5E | CALL | - | [ ] |
| 0x5F | OUT 15 | - | [ ] |

### 0x60 - 0x6F (Jump/Call/OUT - Sign)

| Opcode | Mnemonic | Test File | Status |
|--------|----------|-----------|--------|
| 0x60 | JFc (JP) | sign_parity_test | [x] |
| 0x61 | OUT 16 | - | [ ] |
| 0x62 | CFc (CP) | sign_parity_call_test | [x] |
| 0x63 | OUT 17 | - | [ ] |
| 0x64 | JMP | - | [ ] |
| 0x65 | OUT 18 | - | [ ] |
| 0x66 | CALL | - | [ ] |
| 0x67 | OUT 19 | - | [ ] |
| 0x68 | JTc (JM) | sign_parity_test | [x] |
| 0x69 | OUT 20 | - | [ ] |
| 0x6A | CTc (CM) | sign_parity_call_test | [x] |
| 0x6B | OUT 21 | - | [ ] |
| 0x6C | JMP | - | [ ] |
| 0x6D | OUT 22 | - | [ ] |
| 0x6E | CALL | - | [ ] |
| 0x6F | OUT 23 | - | [ ] |

### 0x70 - 0x7F (Jump/Call/OUT - Parity)

| Opcode | Mnemonic | Test File | Status |
|--------|----------|-----------|--------|
| 0x70 | JFc (JPO) | sign_parity_test | [x] |
| 0x71 | OUT 24 | - | [ ] |
| 0x72 | CFc (CPO) | sign_parity_call_test | [x] |
| 0x73 | OUT 25 | - | [ ] |
| 0x74 | JMP | - | [ ] |
| 0x75 | OUT 26 | - | [ ] |
| 0x76 | CALL | - | [ ] |
| 0x77 | OUT 27 | - | [ ] |
| 0x78 | JTc (JPE) | sign_parity_test | [x] |
| 0x79 | OUT 28 | - | [ ] |
| 0x7A | CTc (CPE) | sign_parity_call_test | [x] |
| 0x7B | OUT 29 | - | [ ] |
| 0x7C | JMP | - | [ ] |
| 0x7D | OUT 30 | - | [ ] |
| 0x7E | CALL | - | [ ] |
| 0x7F | OUT 31 | - | [ ] |

### 0x80 - 0x8F (ALU - ADD/ADC)

| Opcode | Mnemonic | Test File | Status |
|--------|----------|-----------|--------|
| 0x80 | ADD A | - | [ ] |
| 0x81 | ADD B | alu_test | [x] |
| 0x82 | ADD C | - | [ ] |
| 0x83 | ADD D | - | [ ] |
| 0x84 | ADD E | - | [ ] |
| 0x85 | ADD H | - | [ ] |
| 0x86 | ADD L | - | [ ] |
| 0x87 | ADD M | rotate_carry_test | [x] |
| 0x88 | ADC A | - | [ ] |
| 0x89 | ADC B | alu_test | [x] |
| 0x8A | ADC C | - | [ ] |
| 0x8B | ADC D | - | [ ] |
| 0x8C | ADC E | - | [ ] |
| 0x8D | ADC H | - | [ ] |
| 0x8E | ADC L | - | [ ] |
| 0x8F | ADC M | memory_alu_test | [x] |

### 0x90 - 0x9F (ALU - SUB/SBB)

| Opcode | Mnemonic | Test File | Status |
|--------|----------|-----------|--------|
| 0x90 | SUB A | - | [ ] |
| 0x91 | SUB B | - | [ ] |
| 0x92 | SUB C | alu_test | [x] |
| 0x93 | SUB D | - | [ ] |
| 0x94 | SUB E | - | [ ] |
| 0x95 | SUB H | - | [ ] |
| 0x96 | SUB L | - | [ ] |
| 0x97 | SUB M | rotate_carry_test | [x] |
| 0x98 | SBB A | - | [ ] |
| 0x99 | SBB B | - | [ ] |
| 0x9A | SBB C | alu_test | [x] |
| 0x9B | SBB D | - | [ ] |
| 0x9C | SBB E | - | [ ] |
| 0x9D | SBB H | - | [ ] |
| 0x9E | SBB L | - | [ ] |
| 0x9F | SBB M | memory_alu_test | [x] |

### 0xA0 - 0xAF (ALU - AND/XOR)

| Opcode | Mnemonic | Test File | Status |
|--------|----------|-----------|--------|
| 0xA0 | ANA A | - | [ ] |
| 0xA1 | ANA B | - | [ ] |
| 0xA2 | ANA C | - | [ ] |
| 0xA3 | ANA D | alu_test | [x] |
| 0xA4 | ANA E | - | [ ] |
| 0xA5 | ANA H | - | [ ] |
| 0xA6 | ANA L | - | [ ] |
| 0xA7 | ANA M | memory_alu_test | [x] |
| 0xA8 | XRA A | - | [ ] |
| 0xA9 | XRA B | - | [ ] |
| 0xAA | XRA C | - | [ ] |
| 0xAB | XRA D | - | [ ] |
| 0xAC | XRA E | alu_test | [x] |
| 0xAD | XRA H | - | [ ] |
| 0xAE | XRA L | - | [ ] |
| 0xAF | XRA M | memory_alu_test | [x] |

### 0xB0 - 0xBF (ALU - OR/CMP)

| Opcode | Mnemonic | Test File | Status |
|--------|----------|-----------|--------|
| 0xB0 | ORA A | - | [ ] |
| 0xB1 | ORA B | - | [ ] |
| 0xB2 | ORA C | - | [ ] |
| 0xB3 | ORA D | - | [ ] |
| 0xB4 | ORA E | - | [ ] |
| 0xB5 | ORA H | alu_test | [x] |
| 0xB6 | ORA L | - | [ ] |
| 0xB7 | ORA M | memory_alu_test | [x] |
| 0xB8 | CMP A | - | [ ] |
| 0xB9 | CMP B | alu_test | [x] |
| 0xBA | CMP C | - | [ ] |
| 0xBB | CMP D | - | [ ] |
| 0xBC | CMP E | - | [ ] |
| 0xBD | CMP H | - | [ ] |
| 0xBE | CMP L | - | [ ] |
| 0xBF | CMP M | memory_alu_test | [x] |

### 0xC0 - 0xCF (MOV - to A/B)

| Opcode | Mnemonic | Test File | Status |
|--------|----------|-----------|--------|
| 0xC0 | MOV A,A | search_as | [x] |
| 0xC1 | MOV A,B | - | [ ] |
| 0xC2 | MOV A,C | rst_test | [x] |
| 0xC3 | MOV A,D | rst_test | [x] |
| 0xC4 | MOV A,E | rst_test | [x] |
| 0xC5 | MOV A,H | rst_test | [x] |
| 0xC6 | MOV A,L | - | [ ] |
| 0xC7 | MOV A,M | - | [ ] |
| 0xC8 | MOV B,A | alu_test | [x] |
| 0xC9 | MOV B,B | - | [ ] |
| 0xCA | MOV B,C | - | [ ] |
| 0xCB | MOV B,D | - | [ ] |
| 0xCC | MOV B,E | - | [ ] |
| 0xCD | MOV B,H | - | [ ] |
| 0xCE | MOV B,L | - | [ ] |
| 0xCF | MOV B,M | - | [ ] |

### 0xD0 - 0xDF (MOV - to C/D)

| Opcode | Mnemonic | Test File | Status |
|--------|----------|-----------|--------|
| 0xD0 | MOV C,A | alu_test | [x] |
| 0xD1 | MOV C,B | - | [ ] |
| 0xD2 | MOV C,C | - | [ ] |
| 0xD3 | MOV C,D | - | [ ] |
| 0xD4 | MOV C,E | - | [ ] |
| 0xD5 | MOV C,H | - | [ ] |
| 0xD6 | MOV C,L | - | [ ] |
| 0xD7 | MOV C,M | - | [ ] |
| 0xD8 | MOV D,A | alu_test | [x] |
| 0xD9 | MOV D,B | - | [ ] |
| 0xDA | MOV D,C | - | [ ] |
| 0xDB | MOV D,D | - | [ ] |
| 0xDC | MOV D,E | - | [ ] |
| 0xDD | MOV D,H | - | [ ] |
| 0xDE | MOV D,L | - | [ ] |
| 0xDF | MOV D,M | - | [ ] |

### 0xE0 - 0xEF (MOV - to E/H)

| Opcode | Mnemonic | Test File | Status |
|--------|----------|-----------|--------|
| 0xE0 | MOV E,A | alu_test | [x] |
| 0xE1 | MOV E,B | - | [ ] |
| 0xE2 | MOV E,C | - | [ ] |
| 0xE3 | MOV E,D | - | [ ] |
| 0xE4 | MOV E,E | - | [ ] |
| 0xE5 | MOV E,H | - | [ ] |
| 0xE6 | MOV E,L | - | [ ] |
| 0xE7 | MOV E,M | - | [ ] |
| 0xE8 | MOV H,A | alu_test | [x] |
| 0xE9 | MOV H,B | - | [ ] |
| 0xEA | MOV H,C | - | [ ] |
| 0xEB | MOV H,D | - | [ ] |
| 0xEC | MOV H,E | - | [ ] |
| 0xED | MOV H,H | - | [ ] |
| 0xEE | MOV H,L | - | [ ] |
| 0xEF | MOV H,M | - | [ ] |

### 0xF0 - 0xFF (MOV - to L/M + HLT)

| Opcode | Mnemonic | Test File | Status |
|--------|----------|-----------|--------|
| 0xF0 | MOV L,A | - | [ ] |
| 0xF1 | MOV L,B | - | [ ] |
| 0xF2 | MOV L,C | - | [ ] |
| 0xF3 | MOV L,D | - | [ ] |
| 0xF4 | MOV L,E | - | [ ] |
| 0xF5 | MOV L,H | - | [ ] |
| 0xF6 | MOV L,L | - | [ ] |
| 0xF7 | MOV L,M | - | [ ] |
| 0xF8 | MOV M,A | - | [ ] |
| 0xF9 | MOV M,B | - | [ ] |
| 0xFA | MOV M,C | - | [ ] |
| 0xFB | MOV M,D | - | [ ] |
| 0xFC | MOV M,E | - | [ ] |
| 0xFD | MOV M,H | - | [ ] |
| 0xFE | MOV M,L | - | [ ] |
| 0xFF | HLT | - | [ ] |

---

## Notes

### Opcode 0x00 vs INR A
The Intel 8008 uses opcode 0x00 for HLT, not INR A. This means there is no INR A instruction - the encoding that would be INR A (00 000 000) is repurposed as HLT.

### Duplicate RET Opcodes
Multiple RET opcodes exist (0x07, 0x0F, 0x17, 0x1F, 0x27, 0x2F, 0x37, 0x3F). These are all equivalent unconditional returns with different "don't care" bits.

### Duplicate JMP/CALL Opcodes
Similarly, JMP and CALL have multiple valid encodings with don't care bits in positions 5-3.

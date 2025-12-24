; HLT opcode 0xFF test
; Simple test: NOP then halt with opcode 0xFF
;
; Intel 8008 has 3 HLT opcodes: 0x00, 0x01, 0xFF
; This tests that 0xFF correctly halts the CPU.

        cpu     8008new
        page    0

CHKPT   equ     31

        org     0000h
        JMP     MAIN

        org     0100h
MAIN:
        MVI     A,01h
        OUT     CHKPT           ; CP1: About to execute HLT 0xFF
        db      0FFh            ; HLT opcode 0xFF

        end

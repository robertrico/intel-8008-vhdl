; Intel 8008 undefined-opcode characterization (SPEC SQ-12)
;
; 00 111 000 (0x38) and 00 111 001 (0x39) are the would-be INR M /
; DCR M slots. The 1972 datasheet excludes them from every definition
; (p.34: "DDD /= 111 - content of memory may not be incremented");
; the ONLY derivable constraint is that memory must not be written.
;
; This program pins b8008's implementation-defined behavior so SPEC
; can document it exactly:
;   - all registers unchanged
;   - memory unchanged (H:L points at a canary byte)
;   - flags update as INR/DCR of a dummy zero operand:
;       0x38 (INR-class): result 0x01 -> Z=0 S=0 P=0, C preserved
;       0x39 (DCR-class): result 0xFF -> Z=0 S=1 P=1, C preserved
;
; Checkpoint Results:
;   CP1: after 0x38 with C=1 dirty: regs intact, Z=0 S=0 P=0 C=1
;   CP2: after 0x39 with C=0 dirty: regs intact, Z=0 S=1 P=1 C=0
;   CP3: canary byte still 0x5A (memory untouched) -> B=0x5A
;
; Final Register State: B=0x5A, C=0x11, D=0x22, E=0x33

        cpu     8008new
        page    0

CHKPT   equ     31

        org     0000h
STARTUP:
        MOV     A,A
        MOV     A,A
        JMP     MAIN

        org     0100h
MAIN:
        ; Canary in RAM at 0x1080 via H:L (the M these opcodes must not touch)
        MVI     H,10h
        MVI     L,80h
        MVI     M,5Ah

        ; Register sentinels
        MVI     C,11h
        MVI     D,22h
        MVI     E,33h

        ; Dirty carry = 1, then execute 0x38
        MVI     A,01h
        MVI     B,0FFh
        ADD     B               ; 0x01+0xFF: C=1
        db      38h             ; would-be INR M
        ; C must be preserved (INR class spares carry)
        JNC     FAIL
        ; Expected flags from dummy 0+1=0x01: Z=0 S=0 P=0
        JZ      FAIL
        JM      FAIL
        JPE     FAIL
        MVI     A,01h
        OUT     CHKPT           ; CP1: C=0x11 D=0x22 E=0x33, C=1 Z=0 S=0 P=0

        ; Dirty carry = 0, then execute 0x39
        MVI     A,01h
        ADI     00h             ; C=0
        db      39h             ; would-be DCR M
        JC      FAIL
        ; Expected flags from dummy 0-1=0xFF: Z=0 S=1 P=1
        JZ      FAIL
        JP      FAIL
        JPO     FAIL
        MVI     A,02h
        OUT     CHKPT           ; CP2: C=0x11 D=0x22 E=0x33, C=0 Z=0 S=1 P=1

        ; Memory canary untouched?
        MOV     B,M             ; B = mem[0x1080]
        MVI     A,03h
        OUT     CHKPT           ; CP3: B=0x5A

        MVI     A,00h
        HLT

FAIL:
        MVI     A,0FFh
        HLT

        end

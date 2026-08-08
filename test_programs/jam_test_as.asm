; Intel 8008 interrupt-jam generality test (VPLAN INT-04/05, XP-03, XP-14)
;
; The spec allows ANY instruction to be jammed during T1I, not just RST
; (UM p.10). The testbench (interrupt_jam_tb) jams:
;   S1: NOP (0xC0, MOV A,A) into LOOP1 - execution must resume at the
;       un-advanced PC; the loop count must be exact
;   S2: HLT into LOOP2 - the CPU must actually stop mid-loop; a RST 7
;       wake (D counts handler entries) must resume the loop exactly
;   S3: a 3-byte JMP into the SPIN trap - the TB supplies B2/B3 on the
;       bus during the two operand-fetch cycles (only cycle 1 is T1I);
;       landing at JAM_TARGET is the only way out of the spin
;   S4: READY park mid-LOOP3 with INT asserted during WAIT - no T1I
;       until READY returns and the instruction completes; the handler
;       then runs once and the loop count stays exact
;
; Checkpoint Results:
;   CP1: after LOOP1 - C=0x10, D=0x00 (NOP jam invisible)
;   CP2: after LOOP2 - C=0x10, D=0x01 (HLT jam + RST7 wake)
;   CP3: at JAM_TARGET - D=0x01 (jammed JMP landed)
;   CP4: after LOOP3 - C=0x10, D=0x02 (INT-during-WAIT serviced once)
;   CP5: final
;
; Final Register State: C=0x10, D=0x02

        cpu     8008new
        page    0

CHKPT   equ     31

; RST 0 = bootstrap vector
        org     0000h
STARTUP:
        MOV     A,A
        MOV     A,A
        JMP     MAIN

; RST 7 handler: count handler entries in D
        org     0038h
HANDLER:
        INR     D
        RET

        org     0100h
MAIN:
        MVI     C,00h           ; loop counter
        MVI     D,00h           ; handler-entry counter

        ; Phase 1: NOP jam lands mid-loop
LOOP1:
        INR     C
        MOV     A,C
        CPI     10h
        JNZ     LOOP1
        MVI     A,01h
        OUT     CHKPT           ; CP1: C=0x10 D=0x00

        ; Phase 2: HLT jam lands mid-loop; RST 7 wakes the CPU
        MVI     C,00h
LOOP2:
        INR     C
        MOV     A,C
        CPI     10h
        JNZ     LOOP2
        MVI     A,02h
        OUT     CHKPT           ; CP2: C=0x10 D=0x01

        ; Phase 3: inescapable spin - only a jammed JMP gets out
SPIN:
        JMP     SPIN

; Landing pad for the jammed JMP 0x0200
        org     0200h
JAM_TARGET:
        MVI     A,03h
        OUT     CHKPT           ; CP3: jammed JMP landed, D=0x01

        ; Phase 4: READY park + INT during WAIT
        MVI     C,00h
LOOP3:
        INR     C
        MOV     A,C
        CPI     10h
        JNZ     LOOP3
        MVI     A,04h
        OUT     CHKPT           ; CP4: C=0x10 D=0x02

        MVI     A,05h
        OUT     CHKPT           ; CP5: final
        HLT

        end

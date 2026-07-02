; Intel 8008 Address-Stack Depth Characterization Program
; For AS Macro Assembler
;
; KNOWN FIDELITY DEVIATION (pending PC-in-stack re-architecture decision;
; see docs/superpowers/specs/2026-07-02-silicon-gaps-design.md):
;
;   Real 8008: PC lives inside the 8 address-stack registers -> only 7
;   return slots. The 8th nested CALL wraps SP 7->0 onto the oldest
;   context, and the unwind's final RET lands on the WRAP pad past L8's
;   RET (that stack register froze as L8's live PC) - CP2 fires.
;
;   b8008 today: separate program_counter block + 8 return-only slots ->
;   all 8 nested CALLs unwind cleanly back to MAIN - CP3 fires.
;
; Uses OUT 31 checkpoints for assertion-based verification.
;
; Checkpoint Results (current b8008 architecture):
;   CP1: descent complete (inside L8, before its RET), B=0x08
;   CP2: real-8008 wrap pad - does NOT fire on b8008 today
;   CP3: fires - 8 returns unwound to MAIN
;
; Final Register State (current b8008 architecture):
;   A: 0xFF (MAIN reached)  B: 0x08 (descent counter reached 8)

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
        MVI     B,00h               ; descent counter
        CALL    L1
        ; b8008's split-PC design returns here; a real 8008 never does
        MVI     A,03h
        OUT     CHKPT               ; CP3: 8 returns unwound to MAIN
        MVI     A,0FFh
        HLT

L1:     INR     B
        CALL    L2
        RET
L2:     INR     B
        CALL    L3
        RET
L3:     INR     B
        CALL    L4
        RET
L4:     INR     B
        CALL    L5
        RET
L5:     INR     B
        CALL    L6
        RET
L6:     INR     B
        CALL    L7
        RET
L7:     INR     B
        CALL    L8                  ; 8th CALL: SP wraps 7->0
        RET
L8:     INR     B
        MVI     A,01h
        OUT     CHKPT               ; CP1: descent complete, B=8
        RET                         ; reg 0 freezes pointing at WRAP

WRAP:
        MVI     A,02h
        OUT     CHKPT               ; CP2: wraparound proven
        MVI     A,00h
        HLT

        end

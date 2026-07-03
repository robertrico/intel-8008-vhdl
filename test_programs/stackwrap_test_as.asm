; Intel 8008 Address-Stack Wraparound Test Program
; For AS Macro Assembler
;
; The PC lives inside the 8 address-stack registers (PC-in-stack) -> 7
; nested return contexts. The 8th nested CALL wraps SP onto the oldest
; context, and the unwind's final RET lands on the WRAP pad past L8's
; RET (that stack register froze as L8's live PC) - CP2 fires.
;
; CP3 firing (a clean return to MAIN) means the stack held all 8
; returns - the old split-PC deviation; that is now a regression.
;
; Uses OUT 31 checkpoints for assertion-based verification.
;
; Checkpoint Results:
;   CP1: descent complete (inside L8, before its RET), B=0x08
;   CP2: WRAP pad reached via the wrapped final RET
;   CP3: never (split-PC regression signature)
;
; Final Register State:
;   A: 0x00 (WRAP reached)  B: 0x08 (descent counter reached 8)

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

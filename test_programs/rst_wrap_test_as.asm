; Intel 8008 RST-at-stack-wrap test (VPLAN XP-06 residual)
;
; stackwrap_test proves the 8th nested CALL wraps SP onto the oldest
; context. This program proves the same for RST: after 7 nested CALLs
; (SP at the last free slot), RST 1 performs the 8th push - SP wraps,
; the oldest context (MAIN's flow) is destroyed, and the vector loads
; into the wrapped slot.
;
; Unwind: the vector's RET returns into L7 after the RST; L7..L1 RETs
; unwind normally; the FINAL RET lands on the wrapped slot, which froze
; at the address after the vector's RET (post-increment convention) -
; the RWRAP pad. A clean return to MAIN instead means the wrap didn't
; happen (split-PC regression signature).
;
; Checkpoint Results:
;   CP1: descent complete (inside L7, before RST), B=0x07
;   CP2: RST 1 vector reached, B=0x07
;   CP3: RWRAP pad reached via the wrapped final RET
;   CP4: never (clean return to MAIN = regression)
;
; Final Register State:
;   A: 0x00 (RWRAP reached)  B: 0x07 (descent counter)

        cpu     8008new
        page    0

CHKPT   equ     31

        org     0000h
STARTUP:
        MOV     A,A
        MOV     A,A
        JMP     MAIN

; RST 1 vector at 0x0008
        org     0008h
VEC:
        MVI     A,02h
        OUT     CHKPT               ; CP2: vector reached (8th push wrapped SP)
        RET                         ; pops back into L7 after the RST
RWRAP:                              ; wrapped slot froze pointing here
        MVI     A,03h
        OUT     CHKPT               ; CP3: wraparound-by-RST proven
        MVI     A,00h
        HLT

        org     0100h
MAIN:
        MVI     B,00h               ; descent counter
        CALL    L1
        ; a real 8008 never returns here - MAIN's context was destroyed
        MVI     A,04h
        OUT     CHKPT               ; CP4: regression signature
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
        MVI     A,01h
        OUT     CHKPT               ; CP1: descent complete, B=7
        RST     1                   ; 8th push: SP wraps onto oldest slot
        RET                         ; resumes here after vector RET, unwinds

        end

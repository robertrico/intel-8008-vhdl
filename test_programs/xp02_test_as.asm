; XP-02: HLT executed with an interrupt ALREADY pending
;
; The TB latches INT (short pulse, line back low) while MVI A,55h is
; executing, then lets the CPU run into HLT. Per the 8008 state diagram
; (UM Fig 20, HLT-with-INT arc) the stored interrupt must wake the CPU
; immediately - no re-assertion of the INT line.
;
; Wake jam is RST 1 -> handler at 0x0008 proves execution resumed with
; state intact, then halts for good (no interrupt pending that time).
;
; Checkpoints:
;   CP1: main reached, about to arm the interrupt window
;   CP2: wake handler ran (A=0x02, B=0xAA at the final HLT)
;   CP3: must NEVER fire (would mean HLT fell through)

        cpu     8008new
        page    0

CHKPT   equ     31

        org     0000h           ; bootstrap RST 0 lands here
        JMP     MAIN

        org     0008h           ; RST 1 handler: the pending-INT wake
WAKE:
        MVI     B,0AAh
        MVI     A,02h
        OUT     CHKPT           ; CP2: wake handler ran
        HLT                     ; final stop - nothing pending now

        org     0100h
MAIN:
        MVI     A,01h
        OUT     CHKPT           ; CP1: TB arms the interrupt on A=0x55
        MVI     A,55h           ; INT pulse lands during/after this
        HLT                     ; interrupt already pending HERE
        ; Sentinel: only reachable if HLT fails to halt
        MVI     A,03h
        OUT     CHKPT           ; CP3: must never fire

        end

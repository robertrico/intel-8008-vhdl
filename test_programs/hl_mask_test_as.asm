; Intel 8008 H[7:6] don't-care masking test (VPLAN BUS-10 residual, XP-13)
;
; The M address is {H[5:0], L}: bits 7:6 of H are masked out of the
; 14-bit address. Period code relied on this. No test ever set
; H[7:6] /= 00.
;
; All four H values 0x10 / 0x50 / 0x90 / 0xD0 must alias the same
; physical byte 0x1080 (RAM): write through one form, read through
; another, in every combination of the four quadrants.
;
; Checkpoint Results:
;   CP1: wrote 0xAA via H=0x10, read via H=0xD0 -> B=0xAA
;   CP2: wrote 0x55 via H=0x90, read via H=0x10 -> C=0x55
;   CP3: read via H=0x50 -> D=0x55
;
; Final Register State: B=0xAA, C=0x55, D=0x55

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
        MVI     L,80h           ; low byte of the shared address

        ; Write via the 00 quadrant, read via the 11 quadrant
        MVI     H,10h           ; H[7:6]=00 -> 0x1080
        MVI     M,0AAh
        MVI     H,0D0h          ; H[7:6]=11 -> must still be 0x1080
        MOV     B,M
        MVI     A,01h
        OUT     CHKPT           ; CP1: B=0xAA

        ; Write via the 10 quadrant, read via the 00 quadrant
        MVI     H,90h           ; H[7:6]=10
        MVI     M,55h
        MVI     H,10h
        MOV     C,M
        MVI     A,02h
        OUT     CHKPT           ; CP2: C=0x55

        ; Read via the 01 quadrant
        MVI     H,50h           ; H[7:6]=01
        MOV     D,M
        MVI     A,03h
        OUT     CHKPT           ; CP3: D=0x55

        MVI     A,00h
        HLT

        end

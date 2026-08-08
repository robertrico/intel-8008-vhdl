; Intel 8008 14-bit PC wrap test (VPLAN STK-07, XP-12 residual)
;
; The PC is 14 bits: sequential fetch past 0x3FFF must wrap to 0x0000.
; No program has ever executed at the top of memory.
;
; RAM covers 0x1000-0x3FFF in the test map, so the program copies four
; NOPs to 0x3FFC..0x3FFF at runtime (MVI M via H:L), jumps there, and
; lets the fetch stream run off the end of the address space. The PC
; wraps to 0x0000 (the reset vector in ROM); register E carries a
; sentinel so the second pass through STARTUP routes to the wrapped
; checkpoint instead of re-running the setup.
;
; Checkpoint Results:
;   CP1: setup complete, about to jump to 0x3FFC (E=0xA5)
;   CP2: reached via the 0x3FFF->0x0000 wrap (E=0xA5 still)
;
; Final Register State: E=0xA5, H=0x3F, L=0xFF

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
        ; Second pass? (E sentinel set means we got here via the wrap)
        MOV     A,E
        CPI     0A5h
        JZ      WRAPPED

        ; First pass: plant 4 NOPs at the top of memory
        MVI     E,0A5h          ; wrap sentinel
        MVI     H,3Fh
        MVI     L,0FCh          ; H:L = 0x3FFC
        MVI     M,0C0h          ; NOP (MOV A,A) at 0x3FFC
        INR     L
        MVI     M,0C0h          ; 0x3FFD
        INR     L
        MVI     M,0C0h          ; 0x3FFE
        INR     L
        MVI     M,0C0h          ; 0x3FFF
        MVI     A,01h
        OUT     CHKPT           ; CP1: E=0xA5, jumping to the top of memory
        JMP     3FFCh           ; execute the NOPs; fetch wraps to 0x0000

WRAPPED:
        MVI     A,02h
        OUT     CHKPT           ; CP2: PC wrapped 0x3FFF -> 0x0000
        MVI     A,00h
        HLT

        end

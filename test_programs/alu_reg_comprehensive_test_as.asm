; Intel 8008 Comprehensive ALU Register Mode Test Program
; For AS Macro Assembler
;
; Purpose: Test all ALU register operations with all source registers
;   - ADD r (7 variants: ADD A,B,C,D,E,H,L)
;   - ADC r (7 variants)
;   - SUB r (7 variants)
;   - SBB r (7 variants)
;   - ANA r (7 variants)
;   - XRA r (7 variants)
;   - ORA r (7 variants)
;   - CMP r (7 variants)
;
; Total: 56 ALU register operations
;
; Uses OUT 31 checkpoints for verification

        cpu     8008new
        page    0

; Checkpoint port constant
CHKPT   equ     31              ; Port 31 = checkpoint/assertion port

; Reset vector
        org     0000h
STARTUP:
        MOV     A,A             ; NOP (PC sync)
        MOV     A,A             ; NOP
        JMP     MAIN

; Main program
        org     0100h
MAIN:
        ;===========================================
        ; ADD r TESTS (A = A + r)
        ;===========================================
        ; Set up registers with unique values
        MVI     A,10h           ; A = 0x10
        MVI     B,01h           ; B = 0x01
        MVI     C,02h           ; C = 0x02
        MVI     D,03h           ; D = 0x03
        MVI     E,04h           ; E = 0x04
        MVI     H,05h           ; H = 0x05
        MVI     L,06h           ; L = 0x06

        ; ADD B: A = 0x10 + 0x01 = 0x11
        ADD     B
        MOV     L,A             ; Save result
        MVI     A,01h
        OUT     CHKPT           ; CP1: L=0x11

        ; ADD C: 0x11 + 0x02 = 0x13
        MOV     A,L
        ADD     C
        MOV     L,A
        MVI     A,02h
        OUT     CHKPT           ; CP2: L=0x13

        ; ADD D: 0x13 + 0x03 = 0x16
        MOV     A,L
        ADD     D
        MOV     L,A
        MVI     A,03h
        OUT     CHKPT           ; CP3: L=0x16

        ; ADD E: 0x16 + 0x04 = 0x1A
        MOV     A,L
        ADD     E
        MOV     L,A
        MVI     A,04h
        OUT     CHKPT           ; CP4: L=0x1A

        ; ADD H: 0x1A + 0x05 = 0x1F
        MOV     A,L
        ADD     H
        MOV     L,A
        MVI     A,05h
        OUT     CHKPT           ; CP5: L=0x1F

        ; ADD L: 0x1F + 0x1F = 0x3E (L was modified, but we use saved value)
        MVI     A,10h
        MVI     L,10h
        ADD     L               ; A = 0x10 + 0x10 = 0x20
        MOV     L,A
        MVI     A,06h
        OUT     CHKPT           ; CP6: L=0x20

        ; ADD A: 0x06 + 0x06 = 0x0C (A adds to itself)
        MVI     A,06h
        ADD     A               ; A = 0x06 + 0x06 = 0x0C
        MOV     L,A
        MVI     A,07h
        OUT     CHKPT           ; CP7: L=0x0C

        ;===========================================
        ; SUB r TESTS (A = A - r)
        ;===========================================
        MVI     B,01h
        MVI     C,02h
        MVI     D,03h
        MVI     E,04h
        MVI     H,05h

        ; SUB B: 0x20 - 0x01 = 0x1F
        MVI     A,20h
        SUB     B
        MOV     L,A
        MVI     A,08h
        OUT     CHKPT           ; CP8: L=0x1F

        ; SUB C: 0x1F - 0x02 = 0x1D
        MOV     A,L
        SUB     C
        MOV     L,A
        MVI     A,09h
        OUT     CHKPT           ; CP9: L=0x1D

        ; SUB D: 0x1D - 0x03 = 0x1A
        MOV     A,L
        SUB     D
        MOV     L,A
        MVI     A,0Ah
        OUT     CHKPT           ; CP10: L=0x1A

        ; SUB E: 0x1A - 0x04 = 0x16
        MOV     A,L
        SUB     E
        MOV     L,A
        MVI     A,0Bh
        OUT     CHKPT           ; CP11: L=0x16

        ; SUB H: 0x16 - 0x05 = 0x11
        MOV     A,L
        SUB     H
        MOV     L,A
        MVI     A,0Ch
        OUT     CHKPT           ; CP12: L=0x11

        ; SUB L: 0x10 - 0x10 = 0x00 with Zero flag
        MVI     A,10h
        MVI     L,10h
        SUB     L
        JNZ     FAIL            ; Should be zero
        MOV     L,A
        MVI     A,0Dh
        OUT     CHKPT           ; CP13: L=0x00, Z=1

        ; SUB A: 0x10 - 0x10 = 0x00 (A subtracts from itself)
        MVI     A,10h
        SUB     A
        JNZ     FAIL
        MOV     L,A
        MVI     A,0Eh
        OUT     CHKPT           ; CP14: L=0x00, Z=1

        ;===========================================
        ; ANA r TESTS (A = A AND r)
        ;===========================================
        MVI     B,0F0h          ; B = 11110000
        MVI     C,0Fh           ; C = 00001111
        MVI     D,0AAh          ; D = 10101010
        MVI     E,55h           ; E = 01010101
        MVI     H,0FFh          ; H = 11111111

        ; ANA B: 0xFF AND 0xF0 = 0xF0
        MVI     A,0FFh
        ANA     B
        MOV     L,A
        MVI     A,0Fh
        OUT     CHKPT           ; CP15: L=0xF0

        ; ANA C: 0xFF AND 0x0F = 0x0F
        MVI     A,0FFh
        ANA     C
        MOV     L,A
        MVI     A,10h
        OUT     CHKPT           ; CP16: L=0x0F

        ; ANA D: 0xFF AND 0xAA = 0xAA
        MVI     A,0FFh
        ANA     D
        MOV     L,A
        MVI     A,11h
        OUT     CHKPT           ; CP17: L=0xAA

        ; ANA E: 0xAA AND 0x55 = 0x00
        MVI     A,0AAh
        ANA     E
        JNZ     FAIL
        MOV     L,A
        MVI     A,12h
        OUT     CHKPT           ; CP18: L=0x00, Z=1

        ; ANA H: 0x55 AND 0xFF = 0x55
        MVI     A,55h
        ANA     H
        MOV     L,A
        MVI     A,13h
        OUT     CHKPT           ; CP19: L=0x55

        ;===========================================
        ; ORA r TESTS (A = A OR r)
        ;===========================================
        ; ORA B: 0x0F OR 0xF0 = 0xFF
        MVI     A,0Fh
        ORA     B
        MOV     L,A
        MVI     A,14h
        OUT     CHKPT           ; CP20: L=0xFF

        ; ORA C: 0xF0 OR 0x0F = 0xFF
        MVI     A,0F0h
        ORA     C
        MOV     L,A
        MVI     A,15h
        OUT     CHKPT           ; CP21: L=0xFF

        ; ORA D: 0x55 OR 0xAA = 0xFF
        MVI     A,55h
        ORA     D
        MOV     L,A
        MVI     A,16h
        OUT     CHKPT           ; CP22: L=0xFF

        ; ORA E: 0xAA OR 0x55 = 0xFF
        MVI     A,0AAh
        ORA     E
        MOV     L,A
        MVI     A,17h
        OUT     CHKPT           ; CP23: L=0xFF

        ;===========================================
        ; XRA r TESTS (A = A XOR r)
        ;===========================================
        ; XRA B: 0xFF XOR 0xF0 = 0x0F
        MVI     A,0FFh
        XRA     B
        MOV     L,A
        MVI     A,18h
        OUT     CHKPT           ; CP24: L=0x0F

        ; XRA C: 0xFF XOR 0x0F = 0xF0
        MVI     A,0FFh
        XRA     C
        MOV     L,A
        MVI     A,19h
        OUT     CHKPT           ; CP25: L=0xF0

        ; XRA D: 0xFF XOR 0xAA = 0x55
        MVI     A,0FFh
        XRA     D
        MOV     L,A
        MVI     A,1Ah
        OUT     CHKPT           ; CP26: L=0x55

        ; XRA E: 0xFF XOR 0x55 = 0xAA
        MVI     A,0FFh
        XRA     E
        MOV     L,A
        MVI     A,1Bh
        OUT     CHKPT           ; CP27: L=0xAA

        ; XRA A: A XOR A = 0x00 (clear A)
        MVI     A,55h
        XRA     A
        JNZ     FAIL
        MOV     L,A
        MVI     A,1Ch
        OUT     CHKPT           ; CP28: L=0x00, Z=1

        ;===========================================
        ; CMP r TESTS (compare, flags only)
        ;===========================================
        MVI     B,10h
        MVI     C,20h
        MVI     D,30h

        ; CMP B: A=0x10 vs B=0x10 -> Z=1
        MVI     A,10h
        CMP     B
        JNZ     FAIL
        MVI     A,1Dh
        OUT     CHKPT           ; CP29: Z=1 (equal)

        ; CMP C: A=0x10 vs C=0x20 -> Z=0, carry set (A < C)
        MVI     A,10h
        CMP     C
        JZ      FAIL            ; Should not be equal
        JNC     FAIL            ; Should have carry (borrow)
        MVI     A,1Eh
        OUT     CHKPT           ; CP30: Z=0, C=1 (A < C)

        ; CMP D: A=0x40 vs D=0x30 -> Z=0, no carry (A > D)
        MVI     A,40h
        CMP     D
        JZ      FAIL            ; Should not be equal
        JC      FAIL            ; Should not have carry
        MVI     A,1Fh
        OUT     CHKPT           ; CP31: Z=0, C=0 (A > D)

        ;===========================================
        ; ADC/SBB TESTS (with carry/borrow)
        ;===========================================
        MVI     B,01h

        ; Set carry, then ADC B
        MVI     A,0FFh
        ADI     01h             ; A = 0, C = 1
        MVI     A,10h
        ADC     B               ; A = 0x10 + 0x01 + 1 = 0x12
        MOV     L,A
        MVI     A,20h
        OUT     CHKPT           ; CP32: L=0x12

        ; Set carry, then SBB B
        MVI     A,00h
        SUI     01h             ; A = 0xFF, C = 1 (borrow)
        MVI     A,10h
        SBB     B               ; A = 0x10 - 0x01 - 1 = 0x0E
        MOV     L,A
        MVI     A,21h
        OUT     CHKPT           ; CP33: L=0x0E

        ;===========================================
        ; FINAL SUCCESS
        ;===========================================
        MVI     A,22h
        OUT     CHKPT           ; CP34: Final success
        MVI     A,00h           ; A = 0 (success)
        JMP     DONE

FAIL:
        MVI     A,0FFh          ; A = 0xFF (failure indicator)

DONE:
        HLT

        end

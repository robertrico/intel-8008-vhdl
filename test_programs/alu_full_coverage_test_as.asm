; Intel 8008 ALU Full Coverage Test Program
; For AS Macro Assembler
;
; Purpose: Fill gaps in ALU register coverage to reach 100%
; Covers operations NOT tested in alu_reg_comprehensive_test_as.asm:
;   - ANA A, ANA L
;   - ORA A, ORA H, ORA L
;   - XRA H, XRA L
;   - CMP A, CMP E, CMP H, CMP L
;   - ADC A, ADC C, ADC D, ADC E, ADC H, ADC L
;   - SBB A, SBB C, SBB D, SBB E, SBB H, SBB L
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
        ; ANA MISSING TESTS
        ;===========================================

        ; ANA L: 0xFF AND 0x55 = 0x55
        MVI     L,55h
        MVI     A,0FFh
        ANA     L
        MOV     L,A             ; Save result
        MVI     A,01h
        OUT     CHKPT           ; CP1: L=0x55

        ; ANA A: 0xAA AND 0xAA = 0xAA (no change)
        MVI     A,0AAh
        ANA     A
        MOV     L,A
        MVI     A,02h
        OUT     CHKPT           ; CP2: L=0xAA

        ;===========================================
        ; ORA MISSING TESTS
        ;===========================================

        ; ORA H: 0x0F OR 0xF0 = 0xFF
        MVI     H,0F0h
        MVI     A,0Fh
        ORA     H
        MOV     L,A
        MVI     A,03h
        OUT     CHKPT           ; CP3: L=0xFF

        ; ORA L: 0x55 OR 0xAA = 0xFF
        MVI     L,0AAh
        MVI     A,55h
        ORA     L
        MOV     L,A
        MVI     A,04h
        OUT     CHKPT           ; CP4: L=0xFF

        ; ORA A: 0x55 OR 0x55 = 0x55 (no change)
        MVI     A,55h
        ORA     A
        MOV     L,A
        MVI     A,05h
        OUT     CHKPT           ; CP5: L=0x55

        ;===========================================
        ; XRA MISSING TESTS
        ;===========================================

        ; XRA H: 0xFF XOR 0xF0 = 0x0F
        MVI     H,0F0h
        MVI     A,0FFh
        XRA     H
        MOV     L,A
        MVI     A,06h
        OUT     CHKPT           ; CP6: L=0x0F

        ; XRA L: 0xFF XOR 0x55 = 0xAA
        MVI     L,55h
        MVI     A,0FFh
        XRA     L
        MOV     L,A
        MVI     A,07h
        OUT     CHKPT           ; CP7: L=0xAA

        ;===========================================
        ; CMP MISSING TESTS
        ;===========================================
        MVI     E,20h
        MVI     H,30h

        ; CMP E: A=0x20 vs E=0x20 -> Z=1
        MVI     A,20h
        CMP     E
        JNZ     FAIL
        MVI     A,08h
        OUT     CHKPT           ; CP8: Z=1

        ; CMP H: A=0x20 vs H=0x30 -> Z=0, C=1 (A < H)
        MVI     A,20h
        CMP     H
        JZ      FAIL
        JNC     FAIL
        MVI     A,09h
        OUT     CHKPT           ; CP9: Z=0, C=1

        ; CMP L: A=0xFF vs L=0xAA -> Z=0, C=0 (A > L)
        MVI     L,0AAh
        MVI     A,0FFh
        CMP     L
        JZ      FAIL
        JC      FAIL
        MVI     A,0Ah
        OUT     CHKPT           ; CP10: Z=0, C=0

        ; CMP A: A=0x55 vs A=0x55 -> Z=1
        MVI     A,55h
        CMP     A
        JNZ     FAIL
        MVI     A,0Bh
        OUT     CHKPT           ; CP11: Z=1

        ;===========================================
        ; ADC MISSING TESTS (with carry)
        ;===========================================
        MVI     C,01h
        MVI     D,02h
        MVI     E,03h
        MVI     H,04h
        MVI     L,05h

        ; ADC C: Set carry, then ADC C
        MVI     A,0FFh
        ADI     01h             ; C=1
        MVI     A,10h
        ADC     C               ; A = 0x10 + 0x01 + 1 = 0x12
        MOV     L,A
        MVI     A,0Ch
        OUT     CHKPT           ; CP12: L=0x12

        ; ADC D: Set carry, then ADC D
        MVI     A,0FFh
        ADI     01h             ; C=1
        MVI     A,10h
        ADC     D               ; A = 0x10 + 0x02 + 1 = 0x13
        MOV     L,A
        MVI     A,0Dh
        OUT     CHKPT           ; CP13: L=0x13

        ; ADC E: Set carry, then ADC E
        MVI     A,0FFh
        ADI     01h             ; C=1
        MVI     A,10h
        ADC     E               ; A = 0x10 + 0x03 + 1 = 0x14
        MOV     L,A
        MVI     A,0Eh
        OUT     CHKPT           ; CP14: L=0x14

        ; ADC H: Set carry, then ADC H
        MVI     A,0FFh
        ADI     01h             ; C=1
        MVI     A,10h
        ADC     H               ; A = 0x10 + 0x04 + 1 = 0x15
        MOV     L,A
        MVI     A,0Fh
        OUT     CHKPT           ; CP15: L=0x15

        ; ADC L: Set carry, then ADC L (L=0x15 from previous)
        MVI     A,0FFh
        ADI     01h             ; C=1
        MVI     A,10h
        ADC     L               ; A = 0x10 + 0x15 + 1 = 0x26
        MOV     L,A
        MVI     A,10h
        OUT     CHKPT           ; CP16: L=0x26

        ; ADC A: Set carry, then ADC A (A adds to itself + carry)
        MVI     A,0FFh
        ADI     01h             ; C=1
        MVI     A,10h
        ADC     A               ; A = 0x10 + 0x10 + 1 = 0x21
        MOV     L,A
        MVI     A,11h
        OUT     CHKPT           ; CP17: L=0x21

        ;===========================================
        ; SBB MISSING TESTS (with borrow)
        ;===========================================
        MVI     C,01h
        MVI     D,02h
        MVI     E,03h
        MVI     H,04h

        ; SBB C: Set borrow, then SBB C
        MVI     A,00h
        SUI     01h             ; C=1 (borrow)
        MVI     A,20h
        SBB     C               ; A = 0x20 - 0x01 - 1 = 0x1E
        MOV     L,A
        MVI     A,12h
        OUT     CHKPT           ; CP18: L=0x1E

        ; SBB D: Set borrow, then SBB D
        MVI     A,00h
        SUI     01h             ; C=1 (borrow)
        MVI     A,20h
        SBB     D               ; A = 0x20 - 0x02 - 1 = 0x1D
        MOV     L,A
        MVI     A,13h
        OUT     CHKPT           ; CP19: L=0x1D

        ; SBB E: Set borrow, then SBB E
        MVI     A,00h
        SUI     01h             ; C=1 (borrow)
        MVI     A,20h
        SBB     E               ; A = 0x20 - 0x03 - 1 = 0x1C
        MOV     L,A
        MVI     A,14h
        OUT     CHKPT           ; CP20: L=0x1C

        ; SBB H: Set borrow, then SBB H
        MVI     A,00h
        SUI     01h             ; C=1 (borrow)
        MVI     A,20h
        SBB     H               ; A = 0x20 - 0x04 - 1 = 0x1B
        MOV     L,A
        MVI     A,15h
        OUT     CHKPT           ; CP21: L=0x1B

        ; SBB L: Set borrow, then SBB L (L=0x1B from previous)
        MVI     A,00h
        SUI     01h             ; C=1 (borrow)
        MVI     A,30h
        SBB     L               ; A = 0x30 - 0x1B - 1 = 0x14
        MOV     L,A
        MVI     A,16h
        OUT     CHKPT           ; CP22: L=0x14

        ; SBB A: Set borrow, then SBB A (A subtracts from itself + borrow)
        MVI     A,00h
        SUI     01h             ; C=1 (borrow)
        MVI     A,20h
        SBB     A               ; A = 0x20 - 0x20 - 1 = 0xFF (underflow)
        MOV     L,A
        MVI     A,17h
        OUT     CHKPT           ; CP23: L=0xFF

        ;===========================================
        ; FINAL SUCCESS
        ;===========================================
        MVI     A,18h
        OUT     CHKPT           ; CP24: Final success
        MVI     A,00h           ; A = 0 (success)
        JMP     DONE

FAIL:
        MVI     A,0FFh          ; A = 0xFF (failure indicator)

DONE:
        HLT

        end

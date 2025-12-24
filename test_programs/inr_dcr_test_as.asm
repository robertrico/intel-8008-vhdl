; Intel 8008 INR/DCR Comprehensive Test Program
; For AS Macro Assembler
;
; Purpose: Test all INR and DCR register variants
;   - INR B, C, D, E, H, L (6 variants - no INR A exists)
;   - DCR B, C, D, E, H, L (6 variants - no DCR A exists)
;   - Boundary conditions: 0xFF + 1 -> 0x00, 0x00 - 1 -> 0xFF
;   - Zero flag on 0xFF + 1 and decrement to 0
;   - Sign flag on 0x7F + 1 = 0x80 (negative)
;
; Note: INR/DCR do NOT affect the Carry flag per Intel 8008 spec!
;
; Checkpoint Results (stored in D and E registers for verification):
;   CP1:  INR B test    - B=0x06 (5+1=6)
;   CP2:  INR C test    - C=0x0B (10+1=11)
;   CP3:  INR D test    - D=0x15 (20+1=21)
;   CP4:  INR E test    - E=0x2B (42+1=43)
;   CP5:  INR H test    - H=0x65 (100+1=101)
;   CP6:  INR L test    - L=0xC9 (200+1=201)
;   CP7:  DCR B test    - B=0x05 (6-1=5)
;   CP8:  DCR C test    - C=0x0A (11-1=10)
;   CP9:  DCR D test    - D=0x14 (21-1=20)
;   CP10: DCR E test    - E=0x2A (43-1=42)
;   CP11: DCR H test    - H=0x64 (101-1=100)
;   CP12: DCR L test    - L=0xC8 (201-1=200)
;   CP13: Boundary test - B=0x00 (0xFF+1 wraps to 0, Z=1)
;   CP14: Boundary test - B=0xFF (0x00-1 wraps to 0xFF)
;   CP15: Sign test     - C=0x80 (0x7F+1=0x80, S=1)
;   CP16: Final         - A=0x00 (success)

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
        ; TEST 1: INR B
        ; B = 5 + 1 = 6
        ;===========================================
        MVI     B,05h           ; B = 5
        INR     B               ; B = B + 1 = 6
        ; CHECKPOINT 1: Verify INR B result
        MVI     A,01h
        OUT     CHKPT           ; CP1: B=0x06

        ;===========================================
        ; TEST 2: INR C
        ; C = 10 + 1 = 11
        ;===========================================
        MVI     C,0Ah           ; C = 10
        INR     C               ; C = C + 1 = 11
        ; CHECKPOINT 2: Verify INR C result
        MVI     A,02h
        OUT     CHKPT           ; CP2: C=0x0B

        ;===========================================
        ; TEST 3: INR D
        ; D = 20 + 1 = 21
        ;===========================================
        MVI     D,14h           ; D = 20
        INR     D               ; D = D + 1 = 21
        ; CHECKPOINT 3: Verify INR D result
        MVI     A,03h
        OUT     CHKPT           ; CP3: D=0x15

        ;===========================================
        ; TEST 4: INR E
        ; E = 42 + 1 = 43
        ;===========================================
        MVI     E,2Ah           ; E = 42
        INR     E               ; E = E + 1 = 43
        ; CHECKPOINT 4: Verify INR E result
        MVI     A,04h
        OUT     CHKPT           ; CP4: E=0x2B

        ;===========================================
        ; TEST 5: INR H
        ; H = 100 + 1 = 101
        ;===========================================
        MVI     H,64h           ; H = 100
        INR     H               ; H = H + 1 = 101
        ; CHECKPOINT 5: Verify INR H result
        MVI     A,05h
        OUT     CHKPT           ; CP5: H=0x65

        ;===========================================
        ; TEST 6: INR L
        ; L = 200 + 1 = 201
        ;===========================================
        MVI     L,0C8h          ; L = 200
        INR     L               ; L = L + 1 = 201
        ; CHECKPOINT 6: Verify INR L result
        MVI     A,06h
        OUT     CHKPT           ; CP6: L=0xC9

        ;===========================================
        ; TEST 7: DCR B
        ; B = 6 - 1 = 5
        ;===========================================
        ; B is already 6 from INR test
        DCR     B               ; B = B - 1 = 5
        ; CHECKPOINT 7: Verify DCR B result
        MVI     A,07h
        OUT     CHKPT           ; CP7: B=0x05

        ;===========================================
        ; TEST 8: DCR C
        ; C = 11 - 1 = 10
        ;===========================================
        ; C is already 11 from INR test
        DCR     C               ; C = C - 1 = 10
        ; CHECKPOINT 8: Verify DCR C result
        MVI     A,08h
        OUT     CHKPT           ; CP8: C=0x0A

        ;===========================================
        ; TEST 9: DCR D
        ; D = 21 - 1 = 20
        ;===========================================
        ; D is already 21 from INR test
        DCR     D               ; D = D - 1 = 20
        ; CHECKPOINT 9: Verify DCR D result
        MVI     A,09h
        OUT     CHKPT           ; CP9: D=0x14

        ;===========================================
        ; TEST 10: DCR E
        ; E = 43 - 1 = 42
        ;===========================================
        ; E is already 43 from INR test
        DCR     E               ; E = E - 1 = 42
        ; CHECKPOINT 10: Verify DCR E result
        MVI     A,0Ah
        OUT     CHKPT           ; CP10: E=0x2A

        ;===========================================
        ; TEST 11: DCR H
        ; H = 101 - 1 = 100
        ;===========================================
        ; H is already 101 from INR test
        DCR     H               ; H = H - 1 = 100
        ; CHECKPOINT 11: Verify DCR H result
        MVI     A,0Bh
        OUT     CHKPT           ; CP11: H=0x64

        ;===========================================
        ; TEST 12: DCR L
        ; L = 201 - 1 = 200
        ;===========================================
        ; L is already 201 from INR test
        DCR     L               ; L = L - 1 = 200
        ; CHECKPOINT 12: Verify DCR L result
        MVI     A,0Ch
        OUT     CHKPT           ; CP12: L=0xC8

        ;===========================================
        ; TEST 13: Boundary - 0xFF + 1 = 0x00 with Zero flag
        ; INR does NOT affect Carry, but DOES set Zero flag
        ;===========================================
        MVI     B,0FFh          ; B = 255
        INR     B               ; B = 0 (wrapped), Z=1
        JNZ     FAIL            ; Should NOT jump (Z=1)
        ; CHECKPOINT 13: Verify wrap and Zero flag
        MVI     A,0Dh
        OUT     CHKPT           ; CP13: B=0x00, Z=1

        ;===========================================
        ; TEST 14: Boundary - 0x00 - 1 = 0xFF
        ; DCR does NOT affect Carry
        ;===========================================
        ; B is already 0 from previous test
        DCR     B               ; B = 0xFF
        JZ      FAIL            ; Should NOT jump (Z=0)
        ; CHECKPOINT 14: Verify wrap
        MVI     A,0Eh
        OUT     CHKPT           ; CP14: B=0xFF

        ;===========================================
        ; TEST 15: Sign flag - 0x7F + 1 = 0x80 (negative)
        ;===========================================
        MVI     C,7Fh           ; C = 127
        INR     C               ; C = 128 (0x80), S=1
        JP      FAIL            ; Should NOT jump (S=1, negative)
        ; CHECKPOINT 15: Verify sign flag set
        MVI     A,0Fh
        OUT     CHKPT           ; CP15: C=0x80, S=1

        ;===========================================
        ; FINAL: Set A to 0 for success indicator
        ;===========================================
        MVI     A,00h           ; A = 0 (success)
        ; CHECKPOINT 16: Final success
        MVI     A,10h
        OUT     CHKPT           ; CP16: Success checkpoint
        MVI     A,00h           ; Restore A=0
        JMP     DONE

FAIL:
        MVI     A,0FFh          ; A = 0xFF (failure indicator)

DONE:
        HLT

        end

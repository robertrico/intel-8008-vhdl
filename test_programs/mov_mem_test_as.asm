; Intel 8008 MOV r,M / MOV M,r Instruction Test Program
; For AS Macro Assembler
;
; Purpose: Comprehensive test of all memory MOV operations
;   - MOV r,M: Load from memory at [H:L] to register r
;   - MOV M,r: Store register r to memory at [H:L]
;
; This tests ALL register combinations:
;   MOV A,M, MOV B,M, MOV C,M, MOV D,M, MOV E,M, MOV H,M, MOV L,M
;   MOV M,A, MOV M,B, MOV M,C, MOV M,D, MOV M,E, MOV M,H, MOV M,L
;
; Uses OUT 31 checkpoints for assertion-based verification.
;
; Checkpoint Results:
;   CP1:  After MOV A,M - L=0x11
;   CP2:  After MOV B,M - L=0x22 (saved B)
;   CP3:  After MOV C,M - L=0x33
;   CP4:  After MOV D,M - L=0x44
;   CP5:  After MOV E,M - L=0x55
;   CP6:  After MOV H,M - L=0x66 (H changed!)
;   CP7:  After MOV L,M - L=0x77 (L changed!)
;   CP8:  After MOV M,A - L=0xAA (readback)
;   CP9:  After MOV M,B - L=0x08 (readback, B=8)
;   CP10: After MOV M,C - L=0xBB (readback)
;   CP11: After MOV M,D - L=0xCC (readback)
;   CP12: After MOV M,E - L=0xDD (readback)
;   CP13: After MOV M,H - L=0x10 (readback, H=0x10)
;   CP14: After MOV M,L - L=0x0E (readback, L=0x0E)
;   CP15: Final        - A=0x00
;
; RAM is mapped at 0x1000-0x13FF
; Test uses RAM addresses 0x1000-0x100F
;
; Expected final state:
;   A = 0x00 (success indicator)
;   B = 0x0E (14 tests passed)

        cpu     8008new
        page    0

; Checkpoint port constant
CHKPT   equ     31              ; Port 31 = checkpoint/assertion port

; Reset vector at 0x0000
        org     0000h
STARTUP:
        MOV     A,A             ; NOP (PC sync)
        MOV     A,A             ; NOP
        JMP     MAIN

; Main program at 0x0100
        org     0100h

MAIN:
        MVI     B,00h           ; B = test counter (0)

        ;===========================================
        ; SETUP: Initialize test data in RAM
        ; Write known values to RAM for reading tests
        ;===========================================
        MVI     H,10h           ; H = 0x10 (high byte of RAM)
        MVI     L,00h           ; L = 0x00

        ; Store test values at 0x1000-0x1006
        MVI     M,11h           ; [0x1000] = 0x11 (for MOV A,M)
        INR     L               ; L = 0x01
        MVI     M,22h           ; [0x1001] = 0x22 (for MOV B,M)
        INR     L               ; L = 0x02
        MVI     M,33h           ; [0x1002] = 0x33 (for MOV C,M)
        INR     L               ; L = 0x03
        MVI     M,44h           ; [0x1003] = 0x44 (for MOV D,M)
        INR     L               ; L = 0x04
        MVI     M,55h           ; [0x1004] = 0x55 (for MOV E,M)
        INR     L               ; L = 0x05
        MVI     M,66h           ; [0x1005] = 0x66 (for MOV H,M - tricky!)
        INR     L               ; L = 0x06
        MVI     M,77h           ; [0x1006] = 0x77 (for MOV L,M - tricky!)

        ;===========================================
        ; PART 1: MOV r,M Tests (Read from memory)
        ;===========================================

        ;-------------------------------------------
        ; TEST 1: MOV A,M - Load A from [H:L]
        ;-------------------------------------------
        MVI     H,10h
        MVI     L,00h           ; H:L = 0x1000
        MOV     A,M             ; A = [0x1000] = 0x11
        ; CHECKPOINT 1: Verify MOV A,M
        MOV     L,A             ; Save A to L
        MVI     A,01h
        OUT     CHKPT           ; CP1: L=0x11
        MOV     A,L             ; Restore A

        CPI     11h             ; Check A = 0x11
        JNZ     FAIL
        INR     B               ; B = 1

        ;-------------------------------------------
        ; TEST 2: MOV B,M - Load B from [H:L]
        ;-------------------------------------------
        MVI     H,10h
        MVI     L,01h           ; H:L = 0x1001
        MVI     C,00h           ; Save B count in temp
        MOV     C,B             ; C = B (save counter)
        MOV     B,M             ; B = [0x1001] = 0x22
        ; CHECKPOINT 2: Verify MOV B,M
        MOV     L,B             ; Save B to L
        MVI     A,02h
        OUT     CHKPT           ; CP2: L=0x22

        MOV     A,B             ; A = B for comparison
        CPI     22h             ; Check A = 0x22
        JNZ     FAIL
        MOV     B,C             ; Restore B from C
        INR     B               ; B = 2

        ;-------------------------------------------
        ; TEST 3: MOV C,M - Load C from [H:L]
        ;-------------------------------------------
        MVI     H,10h
        MVI     L,02h           ; H:L = 0x1002
        MOV     C,M             ; C = [0x1002] = 0x33
        ; CHECKPOINT 3: Verify MOV C,M
        MOV     L,C             ; Save C to L
        MVI     A,03h
        OUT     CHKPT           ; CP3: L=0x33

        MOV     A,C             ; A = C for comparison
        CPI     33h             ; Check A = 0x33
        JNZ     FAIL
        INR     B               ; B = 3

        ;-------------------------------------------
        ; TEST 4: MOV D,M - Load D from [H:L]
        ;-------------------------------------------
        MVI     H,10h
        MVI     L,03h           ; H:L = 0x1003
        MOV     D,M             ; D = [0x1003] = 0x44
        ; CHECKPOINT 4: Verify MOV D,M
        MOV     L,D             ; Save D to L
        MVI     A,04h
        OUT     CHKPT           ; CP4: L=0x44

        MOV     A,D             ; A = D for comparison
        CPI     44h             ; Check A = 0x44
        JNZ     FAIL
        INR     B               ; B = 4

        ;-------------------------------------------
        ; TEST 5: MOV E,M - Load E from [H:L]
        ;-------------------------------------------
        MVI     H,10h
        MVI     L,04h           ; H:L = 0x1004
        MOV     E,M             ; E = [0x1004] = 0x55
        ; CHECKPOINT 5: Verify MOV E,M
        MOV     L,E             ; Save E to L
        MVI     A,05h
        OUT     CHKPT           ; CP5: L=0x55

        MOV     A,E             ; A = E for comparison
        CPI     55h             ; Check A = 0x55
        JNZ     FAIL
        INR     B               ; B = 5

        ;-------------------------------------------
        ; TEST 6: MOV H,M - Load H from [H:L]
        ; TRICKY: This changes H which changes the pointer!
        ;-------------------------------------------
        MVI     H,10h
        MVI     L,05h           ; H:L = 0x1005
        MOV     H,M             ; H = [0x1005] = 0x66, now H:L = 0x6605
        ; CHECKPOINT 6: Verify MOV H,M
        MOV     L,H             ; Save H to L (H is now 0x66)
        MVI     A,06h
        OUT     CHKPT           ; CP6: L=0x66

        MOV     A,H             ; A = H for comparison
        CPI     66h             ; Check A = 0x66
        JNZ     FAIL
        INR     B               ; B = 6

        ;-------------------------------------------
        ; TEST 7: MOV L,M - Load L from [H:L]
        ; TRICKY: This changes L which changes the pointer!
        ;-------------------------------------------
        MVI     H,10h
        MVI     L,06h           ; H:L = 0x1006
        MOV     L,M             ; L = [0x1006] = 0x77, now H:L = 0x1077
        ; CHECKPOINT 7: Verify MOV L,M (L is now 0x77)
        ; Can't save L to L! Save to E temporarily
        MOV     E,L             ; Save L to E
        MVI     A,07h
        OUT     CHKPT           ; CP7: E=0x77

        MOV     A,L             ; A = L for comparison
        CPI     77h             ; Check A = 0x77
        JNZ     FAIL
        INR     B               ; B = 7 (all MOV r,M passed!)

        ;===========================================
        ; PART 2: MOV M,r Tests (Write to memory)
        ;===========================================

        ;-------------------------------------------
        ; TEST 8: MOV M,A - Store A to [H:L]
        ;-------------------------------------------
        MVI     H,10h
        MVI     L,08h           ; H:L = 0x1008
        MVI     A,0AAh          ; A = 0xAA
        MOV     M,A             ; [0x1008] = A = 0xAA
        ; Read back and verify
        MVI     A,00h           ; Clear A
        MOV     A,M             ; A = [0x1008]
        ; CHECKPOINT 8: Verify MOV M,A
        MOV     L,A             ; Save A to L
        MVI     A,08h
        OUT     CHKPT           ; CP8: L=0xAA
        MOV     A,L             ; Restore A

        CPI     0AAh            ; Check A = 0xAA
        JNZ     FAIL
        INR     B               ; B = 8

        ;-------------------------------------------
        ; TEST 9: MOV M,B - Store B to [H:L]
        ;-------------------------------------------
        MVI     H,10h
        MVI     L,09h           ; H:L = 0x1009
        MOV     M,B             ; [0x1009] = B = 0x08
        ; Read back and verify
        MOV     A,M             ; A = [0x1009]
        ; CHECKPOINT 9: Verify MOV M,B
        MOV     L,A             ; Save A to L
        MVI     A,09h
        OUT     CHKPT           ; CP9: L=0x08
        MOV     A,L             ; Restore A

        CPI     08h             ; Check A = 0x08
        JNZ     FAIL
        INR     B               ; B = 9

        ;-------------------------------------------
        ; TEST 10: MOV M,C - Store C to [H:L]
        ;-------------------------------------------
        MVI     H,10h
        MVI     L,0Ah           ; H:L = 0x100A
        MVI     C,0BBh          ; C = 0xBB
        MOV     M,C             ; [0x100A] = C = 0xBB
        ; Read back and verify
        MOV     A,M             ; A = [0x100A]
        ; CHECKPOINT 10: Verify MOV M,C
        MOV     L,A             ; Save A to L
        MVI     A,0Ah
        OUT     CHKPT           ; CP10: L=0xBB
        MOV     A,L             ; Restore A

        CPI     0BBh            ; Check A = 0xBB
        JNZ     FAIL
        INR     B               ; B = 10

        ;-------------------------------------------
        ; TEST 11: MOV M,D - Store D to [H:L]
        ;-------------------------------------------
        MVI     H,10h
        MVI     L,0Bh           ; H:L = 0x100B
        MVI     D,0CCh          ; D = 0xCC
        MOV     M,D             ; [0x100B] = D = 0xCC
        ; Read back and verify
        MOV     A,M             ; A = [0x100B]
        ; CHECKPOINT 11: Verify MOV M,D
        MOV     L,A             ; Save A to L
        MVI     A,0Bh
        OUT     CHKPT           ; CP11: L=0xCC
        MOV     A,L             ; Restore A

        CPI     0CCh            ; Check A = 0xCC
        JNZ     FAIL
        INR     B               ; B = 11

        ;-------------------------------------------
        ; TEST 12: MOV M,E - Store E to [H:L]
        ;-------------------------------------------
        MVI     H,10h
        MVI     L,0Ch           ; H:L = 0x100C
        MVI     E,0DDh          ; E = 0xDD
        MOV     M,E             ; [0x100C] = E = 0xDD
        ; Read back and verify
        MOV     A,M             ; A = [0x100C]
        ; CHECKPOINT 12: Verify MOV M,E
        MOV     L,A             ; Save A to L
        MVI     A,0Ch
        OUT     CHKPT           ; CP12: L=0xDD
        MOV     A,L             ; Restore A

        CPI     0DDh            ; Check A = 0xDD
        JNZ     FAIL
        INR     B               ; B = 12

        ;-------------------------------------------
        ; TEST 13: MOV M,H - Store H to [H:L]
        ;-------------------------------------------
        MVI     H,10h
        MVI     L,0Dh           ; H:L = 0x100D
        MOV     M,H             ; [0x100D] = H = 0x10
        ; Read back and verify
        MOV     A,M             ; A = [0x100D]
        ; CHECKPOINT 13: Verify MOV M,H
        MOV     L,A             ; Save A to L
        MVI     A,0Dh
        OUT     CHKPT           ; CP13: L=0x10
        MOV     A,L             ; Restore A

        CPI     10h             ; Check A = 0x10
        JNZ     FAIL
        INR     B               ; B = 13

        ;-------------------------------------------
        ; TEST 14: MOV M,L - Store L to [H:L]
        ;-------------------------------------------
        MVI     H,10h
        MVI     L,0Eh           ; H:L = 0x100E, L = 0x0E
        MOV     M,L             ; [0x100E] = L = 0x0E
        ; Read back and verify
        MOV     A,M             ; A = [0x100E]
        ; CHECKPOINT 14: Verify MOV M,L
        MOV     L,A             ; Save A to L
        MVI     A,0Eh
        OUT     CHKPT           ; CP14: L=0x0E
        MOV     A,L             ; Restore A

        CPI     0Eh             ; Check A = 0x0E
        JNZ     FAIL
        INR     B               ; B = 14 (all MOV M,r passed!)

        ;===========================================
        ; All tests passed! Set success marker
        ;===========================================
        ; CHECKPOINT 15: Final success
        MVI     A,0Fh
        OUT     CHKPT           ; CP15: success
        MVI     A,00h           ; A = 0x00 (success)
        JMP     DONE

FAIL:
        MVI     A,0FFh          ; A = 0xFF (failure marker)

DONE:
        HLT

        end

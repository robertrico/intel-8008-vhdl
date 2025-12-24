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
; RAM is mapped at 0x1000-0x13FF
; Test uses RAM addresses 0x1000-0x100F
;
; Expected final state:
;   A = 0x00 (success indicator)
;   B = 0x0E (14 tests passed)
;
; ASSERTION MARKERS for verification script:
;   TEST_1_COMPLETE: B=0x01 after MOV A,M test
;   TEST_7_COMPLETE: B=0x07 after all MOV r,M tests
;   TEST_14_COMPLETE: B=0x0E after all MOV M,r tests
;   FINAL_SUCCESS: A=0x00, B=0x0E

        cpu     8008new
        page    0

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
        CPI     11h             ; Check A = 0x11
        JNZ     FAIL
        INR     B               ; B = 1 (TEST_1_COMPLETE)

        ;-------------------------------------------
        ; TEST 2: MOV B,M - Load B from [H:L]
        ; Note: We need to preserve B for counting, use C temp
        ; Actually, we'll increment B differently
        ;-------------------------------------------
        MVI     L,01h           ; H:L = 0x1001
        MVI     C,00h           ; Save B count in temp
        MOV     C,B             ; C = B (save counter)
        MOV     B,M             ; B = [0x1001] = 0x22
        MOV     A,B             ; A = B for comparison
        CPI     22h             ; Check A = 0x22
        JNZ     FAIL
        MOV     B,C             ; Restore B from C
        INR     B               ; B = 2

        ;-------------------------------------------
        ; TEST 3: MOV C,M - Load C from [H:L]
        ;-------------------------------------------
        MVI     L,02h           ; H:L = 0x1002
        MOV     C,M             ; C = [0x1002] = 0x33
        MOV     A,C             ; A = C for comparison
        CPI     33h             ; Check A = 0x33
        JNZ     FAIL
        INR     B               ; B = 3

        ;-------------------------------------------
        ; TEST 4: MOV D,M - Load D from [H:L]
        ;-------------------------------------------
        MVI     L,03h           ; H:L = 0x1003
        MOV     D,M             ; D = [0x1003] = 0x44
        MOV     A,D             ; A = D for comparison
        CPI     44h             ; Check A = 0x44
        JNZ     FAIL
        INR     B               ; B = 4

        ;-------------------------------------------
        ; TEST 5: MOV E,M - Load E from [H:L]
        ;-------------------------------------------
        MVI     L,04h           ; H:L = 0x1004
        MOV     E,M             ; E = [0x1004] = 0x55
        MOV     A,E             ; A = E for comparison
        CPI     55h             ; Check A = 0x55
        JNZ     FAIL
        INR     B               ; B = 5

        ;-------------------------------------------
        ; TEST 6: MOV H,M - Load H from [H:L]
        ; TRICKY: This changes H which changes the pointer!
        ; Strategy: Read [0x1005]=0x66 into H, H becomes 0x66
        ; Then read what's at [0x6606] - but that's ROM!
        ; We need to verify H changed correctly
        ;-------------------------------------------
        MVI     H,10h
        MVI     L,05h           ; H:L = 0x1005
        MOV     H,M             ; H = [0x1005] = 0x66, now H:L = 0x6605
        MOV     A,H             ; A = H for comparison
        CPI     66h             ; Check A = 0x66
        JNZ     FAIL
        INR     B               ; B = 6

        ;-------------------------------------------
        ; TEST 7: MOV L,M - Load L from [H:L]
        ; TRICKY: This changes L which changes the pointer!
        ; Strategy: Set H:L=0x1006, read [0x1006]=0x77 into L
        ; L becomes 0x77, so H:L = 0x1077
        ;-------------------------------------------
        MVI     H,10h
        MVI     L,06h           ; H:L = 0x1006
        MOV     L,M             ; L = [0x1006] = 0x77, now H:L = 0x1077
        MOV     A,L             ; A = L for comparison
        CPI     77h             ; Check A = 0x77
        JNZ     FAIL
        INR     B               ; B = 7 (TEST_7_COMPLETE - all MOV r,M passed!)

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
        CPI     0AAh            ; Check A = 0xAA
        JNZ     FAIL
        INR     B               ; B = 8

        ;-------------------------------------------
        ; TEST 9: MOV M,B - Store B to [H:L]
        ; B currently = 8 (our counter), so store that
        ;-------------------------------------------
        MVI     L,09h           ; H:L = 0x1009
        MOV     M,B             ; [0x1009] = B = 0x08
        ; Read back and verify
        MOV     A,M             ; A = [0x1009]
        CPI     08h             ; Check A = 0x08
        JNZ     FAIL
        INR     B               ; B = 9

        ;-------------------------------------------
        ; TEST 10: MOV M,C - Store C to [H:L]
        ;-------------------------------------------
        MVI     L,0Ah           ; H:L = 0x100A
        MVI     C,0BBh          ; C = 0xBB
        MOV     M,C             ; [0x100A] = C = 0xBB
        ; Read back and verify
        MOV     A,M             ; A = [0x100A]
        CPI     0BBh            ; Check A = 0xBB
        JNZ     FAIL
        INR     B               ; B = 10

        ;-------------------------------------------
        ; TEST 11: MOV M,D - Store D to [H:L]
        ;-------------------------------------------
        MVI     L,0Bh           ; H:L = 0x100B
        MVI     D,0CCh          ; D = 0xCC
        MOV     M,D             ; [0x100B] = D = 0xCC
        ; Read back and verify
        MOV     A,M             ; A = [0x100B]
        CPI     0CCh            ; Check A = 0xCC
        JNZ     FAIL
        INR     B               ; B = 11

        ;-------------------------------------------
        ; TEST 12: MOV M,E - Store E to [H:L]
        ;-------------------------------------------
        MVI     L,0Ch           ; H:L = 0x100C
        MVI     E,0DDh          ; E = 0xDD
        MOV     M,E             ; [0x100C] = E = 0xDD
        ; Read back and verify
        MOV     A,M             ; A = [0x100C]
        CPI     0DDh            ; Check A = 0xDD
        JNZ     FAIL
        INR     B               ; B = 12

        ;-------------------------------------------
        ; TEST 13: MOV M,H - Store H to [H:L]
        ; H = 0x10, so stores 0x10 to memory
        ;-------------------------------------------
        MVI     L,0Dh           ; H:L = 0x100D
        MOV     M,H             ; [0x100D] = H = 0x10
        ; Read back and verify
        MOV     A,M             ; A = [0x100D]
        CPI     10h             ; Check A = 0x10
        JNZ     FAIL
        INR     B               ; B = 13

        ;-------------------------------------------
        ; TEST 14: MOV M,L - Store L to [H:L]
        ; L = 0x0D (from above), so stores 0x0D to memory
        ;-------------------------------------------
        MVI     L,0Eh           ; H:L = 0x100E, L = 0x0E
        MOV     M,L             ; [0x100E] = L = 0x0E
        ; Read back and verify
        MOV     A,M             ; A = [0x100E]
        CPI     0Eh             ; Check A = 0x0E
        JNZ     FAIL
        INR     B               ; B = 14 (TEST_14_COMPLETE - all MOV M,r passed!)

        ;===========================================
        ; All tests passed! Set success marker
        ;===========================================
        MVI     A,00h           ; A = 0x00 (success)
        JMP     DONE

FAIL:
        MVI     A,0FFh          ; A = 0xFF (failure marker)

DONE:
        HLT

        end

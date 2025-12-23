; Intel 8008 MVI M (Memory Immediate) Test Program
; For AS Macro Assembler
;
; Purpose: Test MVI M instruction (Move Immediate to Memory)
;   - MVI M,data (opcode 00111110 = 0x3E)
;
; MVI M is a 3-cycle instruction that stores an immediate byte
; to memory at the address pointed to by H:L registers.
;
; Test data is stored at address 0x1000-0x100F (RAM space)
; RAM is mapped at 0x1000-0x13FF
; Expected final state:
;   A = 0x00 (success)
;   B = 0x04 (4 tests completed)

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
        ; TEST 1: MVI M - Write 0xAA to memory at 0x1000
        ;===========================================
        MVI     H,10h
        MVI     L,00h           ; H:L = 0x1000 (RAM space)
        MVI     M,0AAh          ; Write 0xAA to memory[0x1000]

        ; Read it back using MOV r,M
        MOV     A,M             ; A = memory[0x1000]
        CPI     0AAh            ; Check A = 0xAA
        JNZ     FAIL
        INR     B               ; Test 1 passed, B = 1

        ;===========================================
        ; TEST 2: MVI M - Write 0x55 to different address
        ;===========================================
        MVI     L,01h           ; H:L = 0x1001
        MVI     M,55h           ; Write 0x55 to memory[0x1001]

        ; Read it back
        MOV     A,M             ; A = memory[0x1001]
        CPI     55h             ; Check A = 0x55
        JNZ     FAIL
        INR     B               ; Test 2 passed, B = 2

        ;===========================================
        ; TEST 3: MVI M - Verify first write wasn't corrupted
        ; Go back and check that 0x1000 still has 0xAA
        ;===========================================
        MVI     L,00h           ; H:L = 0x1000
        MOV     A,M             ; A = memory[0x1000]
        CPI     0AAh            ; Should still be 0xAA
        JNZ     FAIL
        INR     B               ; Test 3 passed, B = 3

        ;===========================================
        ; TEST 4: MVI M - Write 0x00 to memory
        ; Test that 0x00 can be written (edge case)
        ;===========================================
        MVI     L,02h           ; H:L = 0x1002
        MVI     M,00h           ; Write 0x00 to memory[0x1002]

        ; Read it back - need to be careful here
        ; If we use MOV A,M when memory has 0x00, A should be 0
        MOV     A,M             ; A = memory[0x1002]
        CPI     00h             ; Check A = 0x00
        JNZ     FAIL

        ; Double-check by writing a different value and reading back
        MVI     M,0FFh          ; Write 0xFF to same location
        MOV     A,M             ; A = memory[0x1002]
        CPI     0FFh            ; Check A = 0xFF
        JNZ     FAIL
        INR     B               ; Test 4 passed, B = 4

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

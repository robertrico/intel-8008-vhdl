; Intel 8008 MVI M (Memory Immediate) Test Program
; For AS Macro Assembler
;
; Purpose: Test MVI M instruction (Move Immediate to Memory)
;   - MVI M,data (opcode 00111110 = 0x3E)
;
; MVI M is a 3-cycle instruction that stores an immediate byte
; to memory at the address pointed to by H:L registers.
;
; Uses OUT 31 checkpoints for assertion-based verification.
;
; Checkpoint Results:
;   CP1:  After MVI M,0xAA - L=0xAA (read back from memory)
;   CP2:  After MVI M,0x55 - L=0x55 (read back from memory)
;   CP3:  Verify first write - L=0xAA (still intact)
;   CP4:  After MVI M,0x00 - L=0x00 (can write zero)
;   CP5:  After MVI M,0xFF - L=0xFF (can write 0xFF)
;   CP6:  Final            - success
;
; Test data is stored at address 0x1000-0x100F (RAM space)
; RAM is mapped at 0x1000-0x13FF
; Expected final state:
;   A = 0x00 (success)
;   B = 0x04 (4 tests completed)

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
        ; TEST 1: MVI M - Write 0xAA to memory at 0x1000
        ;===========================================
        MVI     H,10h
        MVI     L,00h           ; H:L = 0x1000 (RAM space)
        MVI     M,0AAh          ; Write 0xAA to memory[0x1000]

        ; Read it back using MOV r,M
        MOV     A,M             ; A = memory[0x1000]
        ; CHECKPOINT 1: Verify MVI M wrote 0xAA
        MOV     L,A             ; Save A to L for checkpoint
        MVI     A,01h
        OUT     CHKPT           ; CP1: L=0xAA
        MOV     A,L             ; Restore A

        CPI     0AAh            ; Check A = 0xAA
        JNZ     FAIL
        INR     B               ; Test 1 passed, B = 1

        ;===========================================
        ; TEST 2: MVI M - Write 0x55 to different address
        ;===========================================
        MVI     H,10h           ; Make sure H is set
        MVI     L,01h           ; H:L = 0x1001
        MVI     M,55h           ; Write 0x55 to memory[0x1001]

        ; Read it back
        MOV     A,M             ; A = memory[0x1001]
        ; CHECKPOINT 2: Verify MVI M wrote 0x55
        MOV     L,A             ; Save A to L for checkpoint
        MVI     A,02h
        OUT     CHKPT           ; CP2: L=0x55
        MOV     A,L             ; Restore A

        CPI     55h             ; Check A = 0x55
        JNZ     FAIL
        INR     B               ; Test 2 passed, B = 2

        ;===========================================
        ; TEST 3: MVI M - Verify first write wasn't corrupted
        ; Go back and check that 0x1000 still has 0xAA
        ;===========================================
        MVI     H,10h           ; Make sure H is set
        MVI     L,00h           ; H:L = 0x1000
        MOV     A,M             ; A = memory[0x1000]
        ; CHECKPOINT 3: Verify first write still intact
        MOV     L,A             ; Save A to L for checkpoint
        MVI     A,03h
        OUT     CHKPT           ; CP3: L=0xAA
        MOV     A,L             ; Restore A

        CPI     0AAh            ; Should still be 0xAA
        JNZ     FAIL
        INR     B               ; Test 3 passed, B = 3

        ;===========================================
        ; TEST 4: MVI M - Write 0x00 to memory
        ; Test that 0x00 can be written (edge case)
        ;===========================================
        MVI     H,10h           ; Make sure H is set
        MVI     L,02h           ; H:L = 0x1002
        MVI     M,00h           ; Write 0x00 to memory[0x1002]

        ; Read it back - need to be careful here
        ; If we use MOV A,M when memory has 0x00, A should be 0
        MOV     A,M             ; A = memory[0x1002]
        ; CHECKPOINT 4: Verify MVI M wrote 0x00
        MOV     L,A             ; Save A to L for checkpoint
        MVI     A,04h
        OUT     CHKPT           ; CP4: L=0x00
        MOV     A,L             ; Restore A

        CPI     00h             ; Check A = 0x00
        JNZ     FAIL

        ; Double-check by writing a different value and reading back
        MVI     H,10h           ; Make sure H is set
        MVI     L,02h           ; H:L = 0x1002
        MVI     M,0FFh          ; Write 0xFF to same location
        MOV     A,M             ; A = memory[0x1002]
        ; CHECKPOINT 5: Verify MVI M wrote 0xFF
        MOV     L,A             ; Save A to L for checkpoint
        MVI     A,05h
        OUT     CHKPT           ; CP5: L=0xFF
        MOV     A,L             ; Restore A

        CPI     0FFh            ; Check A = 0xFF
        JNZ     FAIL
        INR     B               ; Test 4 passed, B = 4

        ;===========================================
        ; All tests passed! Set success marker
        ;===========================================
        ; CHECKPOINT 6: Final success
        MVI     A,06h
        OUT     CHKPT           ; CP6: success
        MVI     A,00h           ; A = 0x00 (success)
        JMP     DONE

FAIL:
        MVI     A,0FFh          ; A = 0xFF (failure marker)

DONE:
        HLT

        end

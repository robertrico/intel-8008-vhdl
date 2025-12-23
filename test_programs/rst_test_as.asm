; Intel 8008 RST (Restart) Instruction Test Program
; For AS Macro Assembler
;
; Purpose: Test RST instruction (software interrupt/subroutine call to fixed addresses)
;   - RST 0: Jump to 0x0000 (opcode 0x05)
;   - RST 1: Jump to 0x0008 (opcode 0x0D)
;   - RST 2: Jump to 0x0010 (opcode 0x15)
;   - RST 3: Jump to 0x0018 (opcode 0x1D)
;   - RST 4: Jump to 0x0020 (opcode 0x25)
;   - RST 5: Jump to 0x0028 (opcode 0x2D)
;   - RST 6: Jump to 0x0030 (opcode 0x35)
;   - RST 7: Jump to 0x0038 (opcode 0x3D)
;
; RST is a 1-cycle instruction that:
;   - Pushes current PC to stack (like CALL)
;   - Jumps to address AAA * 8 (where AAA is the 3-bit vector)
;
; Expected final state:
;   A = 0x00 (success)
;   B = 0x04 (4 RST handlers called)

        cpu     8008new
        page    0

; RST vectors (must be at specific addresses)
; Each vector has 8 bytes of space

; RST 0 vector at 0x0000 (bootstrap handler - jumps to MAIN)
        org     0000h
RST0_VEC:
        MOV     A,A             ; NOP (PC sync)
        MOV     A,A             ; NOP
        JMP     MAIN            ; Go to main program

; RST 1 vector at 0x0008 (test handler 1)
        org     0008h
RST1_VEC:
        INR     B               ; Increment test counter
        MVI     C,01h           ; Mark RST 1 was called
        RET                     ; Return to caller

; RST 2 vector at 0x0010 (test handler 2)
        org     0010h
RST2_VEC:
        INR     B               ; Increment test counter
        MVI     D,02h           ; Mark RST 2 was called
        RET                     ; Return to caller

; RST 3 vector at 0x0018 (test handler 3)
        org     0018h
RST3_VEC:
        INR     B               ; Increment test counter
        MVI     E,03h           ; Mark RST 3 was called
        RET                     ; Return to caller

; RST 4 vector at 0x0020 (test handler 4)
        org     0020h
RST4_VEC:
        INR     B               ; Increment test counter
        MVI     H,04h           ; Mark RST 4 was called
        RET                     ; Return to caller

; Main program at 0x0100 (after all RST vectors)
        org     0100h

MAIN:
        MVI     B,00h           ; B = test counter (0)
        MVI     C,00h           ; C = 0 (will be set to 1 by RST 1)
        MVI     D,00h           ; D = 0 (will be set to 2 by RST 2)
        MVI     E,00h           ; E = 0 (will be set to 3 by RST 3)
        MVI     H,00h           ; H = 0 (will be set to 4 by RST 4)

        ;===========================================
        ; TEST 1: RST 1 (jump to 0x0008)
        ;===========================================
        RST     1               ; Call RST 1 handler
        ; Returns here, B should be 1, C should be 1

        MOV     A,C             ; A = C
        CPI     01h             ; Check C = 1 (RST 1 marker)
        JNZ     FAIL

        ;===========================================
        ; TEST 2: RST 2 (jump to 0x0010)
        ;===========================================
        RST     2               ; Call RST 2 handler
        ; Returns here, B should be 2, D should be 2

        MOV     A,D             ; A = D
        CPI     02h             ; Check D = 2 (RST 2 marker)
        JNZ     FAIL

        ;===========================================
        ; TEST 3: RST 3 (jump to 0x0018)
        ;===========================================
        RST     3               ; Call RST 3 handler
        ; Returns here, B should be 3, E should be 3

        MOV     A,E             ; A = E
        CPI     03h             ; Check E = 3 (RST 3 marker)
        JNZ     FAIL

        ;===========================================
        ; TEST 4: RST 4 (jump to 0x0020)
        ;===========================================
        RST     4               ; Call RST 4 handler
        ; Returns here, B should be 4, H should be 4

        MOV     A,H             ; A = H
        CPI     04h             ; Check H = 4 (RST 4 marker)
        JNZ     FAIL

        ;===========================================
        ; Verify test counter
        ;===========================================
        MOV     A,B             ; A = B (test counter)
        CPI     04h             ; Should be 4 (4 RST handlers called)
        JNZ     FAIL

        ;===========================================
        ; All tests passed!
        ;===========================================
        MVI     A,00h           ; A = 0x00 (success)
        JMP     DONE

FAIL:
        MVI     A,0FFh          ; A = 0xFF (failure marker)

DONE:
        HLT

        end

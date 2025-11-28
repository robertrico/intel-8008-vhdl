; Intel 8008 RAM Intensive Test Program
; Rewritten for AS Macro Assembler
;
; Purpose: Comprehensive RAM testing with multiple operations
;   1. Fill RAM block with incrementing pattern (0-15)
;   2. Read back and accumulate sum
;   3. Write inverted pattern
;   4. Read back and verify
;
; This program exercises:
;   - Sequential RAM writes (16 bytes)
;   - Sequential RAM reads (32 bytes total)
;   - Arithmetic operations
;   - Nested loops
;   - Subroutine calls
;
; Memory Map:
;   ROM: 0x0000-0x0FFF (4KB)
;   RAM: 0x1000-0x13FF (1KB)
;   Test data: 0x1000-0x100F (16 bytes)
;
; Expected Results (in registers at halt):
;   A: Final verification value (last inverted = 0xF0)
;   B: First inverted value (should be 0xFF)
;   C: Array length (0x10 = 16)
;   D: Sum of 0-15 (should be 0x78 = 120 decimal)
;   E: Last inverted value (should be 0xF0)
;   H: RAM base high (0x08)
;   L: Final address offset (0x0F)
;

        cpu     8008new
        page    0

; Reset vector
        org     0000h
STARTUP:
        MOV     A,A                 ; PC = 0x0000
        MOV     A,A                 ; PC = 0x0001
        JMP     MAIN                ; PC = 0x0002

; Main program
        org     0100h
MAIN:
        ; Initialize array length in C
        MVI     C,10h               ; C = 16 (array size)

        ; Phase 1: Fill RAM with ascending pattern (0..15)
        CALL    FILL_RAM

        ; Phase 2: Calculate sum of array
        CALL    CALC_SUM
        MOV     D,A                 ; Save sum in D

        ; Phase 3: Write inverted pattern
        CALL    INVERT_RAM

        ; Phase 4: Verify first inverted value
        CALL    VERIFY

        ; Halt with results in registers
        HLT

;-----------------------------------------------------------------------------
; FILL_RAM: Fill RAM[0x1000-0x100F] with ascending values (0..15)
; Inputs: C = array size (16)
; Modifies: A, H, L, E
;-----------------------------------------------------------------------------
FILL_RAM:
        MVI     H,10h               ; H = RAM base high (0x10)
        MVI     L,00h               ; L = RAM base low
        MVI     E,00h               ; E = current value (start at 0)

FILL_LOOP:
        MOV     A,E                 ; A = current value
        MOV     M,A                 ; Write to RAM[H:L]

        ; Increment value
        INR     E                   ; E++

        ; Increment address
        INR     L                   ; Next RAM location

        ; Check if we've written 16 bytes
        MOV     A,L
        CPI     10h
        JNZ     FILL_LOOP           ; Continue if L != 16

        RET

;-----------------------------------------------------------------------------
; CALC_SUM: Calculate sum of all bytes in array
; Inputs: C = array size
; Outputs: A = sum (checksum)
; Modifies: A, H, L, E
;-----------------------------------------------------------------------------
CALC_SUM:
        MVI     H,10h               ; H = RAM base high (0x10)
        MVI     L,00h               ; L = RAM base low
        MVI     E,00h               ; E = accumulator (sum)

SUM_LOOP:
        MOV     A,M                 ; A = RAM[H:L]
        ADD     E                   ; A = A + sum
        MOV     E,A                 ; E = new sum

        INR     L                   ; Next address

        ; Check if done (L = 16)
        MOV     A,L
        CPI     10h
        JNZ     SUM_LOOP

        MOV     A,E                 ; A = final sum (should be 0x78)
        RET

;-----------------------------------------------------------------------------
; INVERT_RAM: Write inverted pattern to RAM
; Inverts each byte in place (XOR with 0xFF)
; Inputs: C = array size
; Modifies: A, H, L, E
;-----------------------------------------------------------------------------
INVERT_RAM:
        MVI     H,10h               ; H = RAM base high (0x10)
        MVI     L,00h               ; L = RAM base low

INVERT_LOOP:
        MOV     A,M                 ; A = RAM[H:L]
        XRI     0FFh                ; A = A XOR 0xFF (invert all bits)
        MOV     M,A                 ; Write back inverted value

        INR     L                   ; Next address

        ; Check if done (L = 16)
        MOV     A,L
        CPI     10h
        JNZ     INVERT_LOOP

        RET

;-----------------------------------------------------------------------------
; VERIFY: Check first and last inverted values
; Inputs: None
; Outputs: B = first inverted value (should be 0xFF from original 0x00)
;          E = last inverted value (should be 0xF0 from original 0x0F)
; Modifies: A, B, E, H, L
;-----------------------------------------------------------------------------
VERIFY:
        ; Check first inverted value (should be 0xFF)
        MVI     H,10h
        MVI     L,00h
        MOV     A,M                 ; A = first value
        MOV     B,A                 ; B = first value

        ; Check last inverted value (should be 0xF0)
        MVI     L,0Fh               ; Point to last element
        MOV     A,M                 ; A = last value
        MOV     E,A                 ; E = last value

        RET

        end

; Intel 8008 Stack Depth Test Program (Simplified)
; For AS Macro Assembler
;
; Test 6 nested CALLs (approaching limit)
;
; Expected final state:
;   A = 0x00 (success)
;   B = 0x06 (6 subroutine entries)
;   C = 0x06 (6 subroutine exits)

        cpu     8008new
        page    0

; Reset vector at 0x0000
        org     0000h
STARTUP:
        MOV     A,A             ; NOP
        MOV     A,A             ; NOP
        JMP     MAIN

; ============================================
; MAIN PROGRAM
; ============================================
        org     0100h

MAIN:
        MVI     B,00h           ; B = call counter
        MVI     C,00h           ; C = return counter

        ; Start the chain of nested calls (3 levels only)
        CALL    SUB1

        ; After all returns, verify counters
        MOV     A,B
        CPI     06h             ; Should be 6
        JNZ     FAIL

        MOV     A,C
        CPI     06h             ; Should be 6
        JNZ     FAIL

        ; Success!
        MVI     A,00h
        JMP     DONE

FAIL:
        MVI     A,0FFh          ; Failure marker

DONE:
        HLT

; ============================================
; SUBROUTINES (6 levels)
; ============================================

SUB1:
        INR     B               ; B = 1
        CALL    SUB2
        INR     C               ; C = 6 (last to return)
        RET

SUB2:
        INR     B               ; B = 2
        CALL    SUB3
        INR     C               ; C = 5
        RET

SUB3:
        INR     B               ; B = 3
        CALL    SUB4
        INR     C               ; C = 4
        RET

SUB4:
        INR     B               ; B = 4
        CALL    SUB5
        INR     C               ; C = 3
        RET

SUB5:
        INR     B               ; B = 5
        CALL    SUB6
        INR     C               ; C = 2
        RET

SUB6:
        INR     B               ; B = 6 (deepest)
        INR     C               ; C = 1 (first to return)
        RET

        end

; Intel 8008 Stack Depth Test Program (Simplified)
; For AS Macro Assembler
;
; Test 7 nested CALLs (the spec-guaranteed depth: 8 slots, PC uses one)
;
; Expected final state:
;   A = 0x00 (success)
;   B = 0x07 (7 subroutine entries)
;   C = 0x07 (7 subroutine exits)
;
; Checkpoint Results:
;   CP1: Entry SUB1 - B=0x01
;   CP2: Entry SUB2 - B=0x02
;   CP3: Entry SUB3 - B=0x03
;   CP4: Entry SUB4 - B=0x04
;   CP5: Entry SUB5 - B=0x05
;   CP6: Entry SUB6 - B=0x06
;   CP7: Entry SUB7 - B=0x07 (deepest)
;   CP8: Final      - B=0x07, C=0x07

        cpu     8008new
        page    0

; Checkpoint port constant
CHKPT   equ     31              ; Port 31 = checkpoint/assertion port

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

        ; Start the chain of nested calls (7 levels)
        CALL    SUB1

        ; After all returns, verify counters
        MOV     A,B
        CPI     07h             ; Should be 7
        JNZ     FAIL

        MOV     A,C
        CPI     07h             ; Should be 7
        JNZ     FAIL

        ; Success!
        ; CHECKPOINT 8: Final success
        MOV     L,B             ; Save B to L (should be 0x07)
        MVI     A,08h
        OUT     CHKPT           ; CP8: B=0x07, C=0x07

        MVI     A,00h
        JMP     DONE

FAIL:
        MVI     A,0FFh          ; Failure marker

DONE:
        HLT

; ============================================
; SUBROUTINES (7 levels)
; ============================================

SUB1:
        INR     B               ; B = 1
        ; CHECKPOINT 1: Entry SUB1
        MOV     L,B             ; Save B to L
        MVI     A,01h
        OUT     CHKPT           ; CP1: B=0x01
        CALL    SUB2
        INR     C               ; C = 7 (last to return)
        RET

SUB2:
        INR     B               ; B = 2
        ; CHECKPOINT 2: Entry SUB2
        MOV     L,B             ; Save B to L
        MVI     A,02h
        OUT     CHKPT           ; CP2: B=0x02
        CALL    SUB3
        INR     C               ; C = 6
        RET

SUB3:
        INR     B               ; B = 3
        ; CHECKPOINT 3: Entry SUB3
        MOV     L,B             ; Save B to L
        MVI     A,03h
        OUT     CHKPT           ; CP3: B=0x03
        CALL    SUB4
        INR     C               ; C = 5
        RET

SUB4:
        INR     B               ; B = 4
        ; CHECKPOINT 4: Entry SUB4
        MOV     L,B             ; Save B to L
        MVI     A,04h
        OUT     CHKPT           ; CP4: B=0x04
        CALL    SUB5
        INR     C               ; C = 4
        RET

SUB5:
        INR     B               ; B = 5
        ; CHECKPOINT 5: Entry SUB5
        MOV     L,B             ; Save B to L
        MVI     A,05h
        OUT     CHKPT           ; CP5: B=0x05
        CALL    SUB6
        INR     C               ; C = 3
        RET

SUB6:
        INR     B               ; B = 6
        ; CHECKPOINT 6: Entry SUB6
        MOV     L,B             ; Save B to L
        MVI     A,06h
        OUT     CHKPT           ; CP6: B=0x06
        CALL    SUB7
        INR     C               ; C = 2
        RET

SUB7:
        INR     B               ; B = 7 (deepest - spec-guaranteed depth)
        ; CHECKPOINT 7: Entry SUB7 (deepest)
        MOV     L,B             ; Save B to L
        MVI     A,07h
        OUT     CHKPT           ; CP7: B=0x07
        INR     C               ; C = 1 (first to return)
        RET

        end

; Intel 8008 Character Search Program
; Rewritten for AS Macro Assembler
; Source: Intel 8008 User's Manual
;
; Purpose: Searches memory for a period character ('.')
; Tests memory read operations and character comparison
; Uses H:L register pair for memory addressing
;
; Test data: "Hello, world. 8008!!" stored starting at location 200
;
; Checkpoint Results:
;   CP1: Found period - E=0xD4 (position 212 where period found)
;
; Final Register State:
;   A = 0x2E (period character '.')
;   H = 0x2E (copied from A)
;   L = 0xD4 (position 212)

        cpu     8008new
        page    0

; Checkpoint port constant
CHKPT   equ     31              ; Port 31 = checkpoint/assertion port

; Start at address 0x0000 to execute from reset
        org     0000h
STARTUP:
        MOV A,A                 ; PC = 0x0000; this should be on PC twice, one for T1I and another for T1 next
        MOV A,A                 ; PC = 0x0001
        JMP     MAIN            ; PC = 0x0002

; Test string data at location 200 (0xC8)
; Search range is 200-220, so max 20 characters
        org     00C8h
STRING: db      "Hello, world. 8008!!"

; Main program
        org     0100h
MAIN:

; Location 100 (decimal): Load L with 200
        MVI     L,200           ; Load L immediate with 200

; Location 102: Load H with 0
        MVI     H,0             ; Load H immediate with 0

; Loop: Fetch character from memory
LOOP:   MOV     A,M             ; Load A from memory[H:L]

; Location 105: Compare with period ('.')
        CPI     2Eh             ; Compare immediate with '.'

; Location 107: If equal, go to return
        JZ      FOUND           ; Jump if Zero flag set

; Location 110: Call increment H&L subroutine
        CALL    INCR            ; Call subroutine

; Location 113: Load L to A
        MOV     A,L             ; Load L to A

; Location 114: Compare with 220
        CPI     220             ; Check if past end

; Location 116: If unequal, go to loop
        JNZ     LOOP            ; Jump if Not Zero

; Found: Save location and Halt
FOUND:
        ; CHECKPOINT 1: Found the period
        MOV     E,L             ; Save L to E
        MVI     A,01h
        OUT     CHKPT           ; CP1: L=0xD4 (position 212)

        MOV     A,E             ; Restore L value to A
        MOV     H,L             ; Copy L to H for verification
        MOV     L,H
        MOV     H,A
        HLT                     ; HLT - Found the period!

; INCR: Increment H&L subroutine (at location 60 decimal = 0x003C)
        org     003Ch
INCR:   INR     L               ; Increment L

; Location 61: Return if not zero
        RNZ                     ; Return if Not Zero (L didn't wrap to 0)

; Location 62: Increment H
        INR     H               ; Increment H

; Location 63: Return
        RET                     ; Return

        end

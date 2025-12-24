; Intel 8008 "Hello 8008!" Serial Output Program
; For AS Macro Assembler
;
; Purpose: Simple serial output test that demonstrates the 8008 works
; with bit-banged UART at 2400 baud. Outputs a greeting message,
; then counts from 0-9 to show the CPU can do computation.
;
; This is designed to complete quickly in simulation - no floating point!
;
; Output:
;   HELLO 8008!
;   0123456789
;   B8008 OK
;
; Uses port 8 for bit-banged serial output (LSB = serial bit)
;
; Assemble with: asl hello_8008.asm && p2hex -f intel hello_8008.p hello_8008.hex
;
; Copyright (c) 2025

        cpu     8008new
        page    0
        include "bitfuncs.inc"

; Port definitions
OUTPORT equ     08H             ; Serial output port

; Reset vector at 0x0000
        org     0000h
        JMP     START

; Main program
        org     0040h
START:
        ; Test 1: Output "HI " directly (simple test)
        MVI     A,'H'
        CALL    ECHO
        MVI     A,'I'
        CALL    ECHO
        MVI     A,' '
        CALL    ECHO

        ; Test 2: Output digits 0-9 using a loop (tests INR, CPI, JNZ)
        MVI     C,'0'           ; Start with ASCII '0'
DIGIT_LOOP:
        MOV     A,C
        CALL    ECHO
        INR     C               ; Next digit
        MOV     A,C
        CPI     '9'+1           ; Past '9'?
        JNZ     DIGIT_LOOP      ; Keep looping if not

        ; Output space
        MVI     A,' '
        CALL    ECHO

        ; Test 3: Output string from memory using MOV A,M (tests memory indirect)
        MVI     H,00H           ; Point to MSG at 0x00C0
        MVI     L,0C0H
        CALL    PUTS

        ; Output CR/LF
        MVI     A,0DH
        CALL    ECHO
        MVI     A,0AH
        CALL    ECHO

        ; All done!
        HLT

;------------------------------------------------------------------------
; PUTS - Output null-terminated string via HL pointer
; Tests: MOV A,M (memory indirect read), CPI, RZ, INR L, JMP
;------------------------------------------------------------------------
PUTS:
        MOV     A,M             ; Get character from memory at [HL]
        CPI     00H             ; Null terminator?
        RZ                      ; Return if end of string
        CALL    ECHO            ; Output character
        INR     L               ; Next character (assumes string < 256 bytes)
        JMP     PUTS

;------------------------------------------------------------------------
; Character output subroutine
; Sends the character in A out from the serial port.
; Transmits 1 start bit, 8 data bits and 1 stop bit at 2400 bps.
; Uses A and B.
; Returns with the original character in A
;------------------------------------------------------------------------
ECHO:
        ANI     7FH             ; Mask off MSB
        MOV     B,A             ; Save character in B
        XRA     A               ; Clear A for start bit (0)
        OUT     OUTPORT         ; Send start bit
        MOV     A,B             ; Restore character
        MOV     A,B             ; Timing adjustment
        MVI     B,0FDH          ; Timing adjustment
        MVI     B,0FDH          ; Timing adjustment
        CALL    DELAY           ; Timing adjustment

        ; Send bits 0 through 7
        CALL    PUTBIT          ; Bit 0
        CALL    PUTBIT          ; Bit 1
        CALL    PUTBIT          ; Bit 2
        CALL    PUTBIT          ; Bit 3
        CALL    PUTBIT          ; Bit 4
        CALL    PUTBIT          ; Bit 5
        CALL    PUTBIT          ; Bit 6
        CALL    PUTBIT          ; Bit 7

        ; Send stop bit
        MOV     B,A             ; Save character
        MVI     A,1             ; '1' for stop bit
        OUT     OUTPORT         ; Send stop bit
        MOV     A,B             ; Restore character
        ORI     80H             ; Restore MSB
        MVI     B,0FCH          ; Timing adjustment
        CALL    DELAY           ; Timing adjustment
        RET

PUTBIT:
        OUT     OUTPORT         ; Output LSB of character
        MVI     B,0FDH          ; Timing adjustment
        MVI     B,0FDH          ; Timing adjustment
        CALL    DELAY           ; Timing adjustment
        RRC                     ; Shift right for next bit
        RET

;------------------------------------------------------------------------
; Delay loop: microseconds = (((255-B)*16)+19) * 4
;------------------------------------------------------------------------
DELAY:
        INR     B
        JNZ     DELAY
        RET

;------------------------------------------------------------------------
; String data at 0x00C0
;------------------------------------------------------------------------
        org     00C0h
MSG:
        db      "B8008-OK",00H

        end

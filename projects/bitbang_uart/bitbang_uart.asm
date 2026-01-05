; ================================================================================
; BITBANG_UART.ASM - b8008 Bitbanged UART Demo
; ================================================================================
; Demonstrates classic 1970s-style bitbanged serial I/O at 2400 baud.
;
; 1. TX test: Sends "Hello, 8008 1972!" on startup
; 2. Echo mode: Shows "Ready > " prompt, echoes typed characters
;
; I/O Ports (classic SCELBI convention):
;   IN 0:   Serial input bit (bit 0 = RX line)
;   OUT 8:  Serial output bit (bit 0 = TX line)
;
; Serial Settings:
;   Baud Rate: 2400 bps
;   Format: 8N1 (8 data bits, no parity, 1 stop bit)
;
; Bitbang routines adapted from:
;   - mandelbrot.asm by Mark G. Arnold (TX routine)
;   - hexspawn.asm (RX routine with echo)
;
; Connect FTDI USB-to-serial adapter and open terminal at 2400 baud.
; ================================================================================

        cpu 8008new
        org 0000h

; ================================================================================
; RST 0 VECTOR - REQUIRED Entry Point
; ================================================================================
rst0_vector:
        jmp main                ; Jump to main program

; ================================================================================
; CONSTANTS
; ================================================================================
CR      equ     0Dh             ; Carriage return
LF      equ     0Ah             ; Line feed
OUTPORT equ     08h             ; Serial output port

; ================================================================================
; MAIN PROGRAM
; ================================================================================
main:
        ; Send startup message
        call send_hello

        ; Fall through to echo loop

; ================================================================================
; ECHO_LOOP - Main echo loop with prompt
; ================================================================================
echo_loop:
        ; Print the prompt
        call send_ready

; ================================================================================
; WAIT_CHAR - Wait for and echo characters
; ================================================================================
wait_char:
        ; Wait for a character via bitbanged RX
        call INPUT              ; Returns char in A

        ; Check for Enter key (CR)
        cpi CR
        jz handle_enter

        ; Echo the character back via bitbanged TX
        call ECHO

        jmp wait_char

; ================================================================================
; HANDLE_ENTER - Handle Enter key (new line + new prompt)
; ================================================================================
handle_enter:
        ; Send CR+LF
        mvi a,CR
        call ECHO
        mvi a,LF
        call ECHO

        ; Reprint the prompt
        jmp echo_loop

; ================================================================================
; SEND_HELLO - Send "Hello, 8008 1972!" startup message
; ================================================================================
send_hello:
        mvi a,'H'
        call ECHO
        mvi a,'e'
        call ECHO
        mvi a,'l'
        call ECHO
        mvi a,'l'
        call ECHO
        mvi a,'o'
        call ECHO
        mvi a,','
        call ECHO
        mvi a,' '
        call ECHO
        mvi a,'8'
        call ECHO
        mvi a,'0'
        call ECHO
        mvi a,'0'
        call ECHO
        mvi a,'8'
        call ECHO
        mvi a,' '
        call ECHO
        mvi a,'1'
        call ECHO
        mvi a,'9'
        call ECHO
        mvi a,'7'
        call ECHO
        mvi a,'2'
        call ECHO
        mvi a,'!'
        call ECHO
        mvi a,CR
        call ECHO
        mvi a,LF
        call ECHO
        ret

; ================================================================================
; SEND_READY - Send "Ready > " prompt
; ================================================================================
send_ready:
        mvi a,'R'
        call ECHO
        mvi a,'e'
        call ECHO
        mvi a,'a'
        call ECHO
        mvi a,'d'
        call ECHO
        mvi a,'y'
        call ECHO
        mvi a,' '
        call ECHO
        mvi a,'>'
        call ECHO
        mvi a,' '
        call ECHO
        ret

; ================================================================================
; ECHO - Character output subroutine (from mandelbrot.asm)
; ================================================================================
; Sends the character in A out from the serial port.
; Transmits 1 start bit, 8 data bits and 1 stop bit at 2400 bps.
; Uses A and B.
; Returns with the original character in A.
; ================================================================================
ECHO:   ani 7Fh                 ; mask off the most significant bit of the character
        mov b,a                 ; save the character from A to B
        xra a                   ; clear A for the start bit
        out OUTPORT             ; send the start bit
        mov a,b                 ; restore the character from B to A
        mov a,b                 ; timing adjustment
        mvi b,0FDh              ; timing adjustment
        mvi b,0FDh              ; timing adjustment
        call delay              ; timing adjustment

                                ; send bits 0 through 7
        call putbit             ; transmit bit 0
        call putbit             ; transmit bit 1
        call putbit             ; transmit bit 2
        call putbit             ; transmit bit 3
        call putbit             ; transmit bit 4
        call putbit             ; transmit bit 5
        call putbit             ; transmit bit 6
        call putbit             ; transmit bit 7

                                ; send the stop bit
        mov b,a                 ; save the character from A to B
        mvi a,1                 ; '1' for the stop bit
        out OUTPORT             ; send the stop bit
        mov a,b                 ; restore the original character from B to A
        ori 80h                 ; restore the most significant bit of the character
        mvi b,0FCh              ; timing adjustment
        call delay              ; timing adjustment
        ret                     ; return to caller

putbit: out OUTPORT             ; output the least significant bit of the character in A
        mvi b,0FDh              ; timing adjustment
        mvi b,0FDh              ; timing adjustment
        call delay              ; timing adjustment
        rrc                     ; shift the character in A right
        ret

; ================================================================================
; delay - Timing delay subroutine
; ================================================================================
; delay in microseconds = (((255-value in B)*16)+19) * 4 microseconds
; ================================================================================
delay:  inr b
        jnz delay
        ret

; ================================================================================
; INPUT - Character input subroutine (simplified - no echo during receive)
; ================================================================================
; Wait for a character from the serial port.
; Returns the character in A. Does NOT echo - caller must echo separately.
; ================================================================================
INPUT:  in 0                    ; get input from serial port
        rar                     ; rotate the received serial bit right into carry
        jc INPUT                ; jump if start bit not detected (line high = 1)

        ; start bit detected (line went low). wait ~half bit time to sample center
        mvi b,0FEh              ; delay to center of start bit
        call delay

        ; Now sample 8 data bits at 1 bit-time intervals
        mvi c,0                 ; C will accumulate the received byte
        call getbit             ; get bit 0
        call getbit             ; get bit 1
        call getbit             ; get bit 2
        call getbit             ; get bit 3
        call getbit             ; get bit 4
        call getbit             ; get bit 5
        call getbit             ; get bit 6
        call getbit             ; get bit 7

        ; Wait for stop bit (should be high)
        mvi b,0FDh
        call delay

        mov a,c                 ; return character in A
        ani 7Fh                 ; mask to 7-bit ASCII
        ret

; getbit - sample one bit and shift into C (LSB first)
getbit: mvi b,0FDh              ; delay one bit time
        call delay
        in 0                    ; read serial line
        rar                     ; bit 0 -> carry
        mov a,c                 ; get accumulated bits
        rar                     ; shift carry into MSB, shift right
        mov c,a                 ; save back
        ret

        end

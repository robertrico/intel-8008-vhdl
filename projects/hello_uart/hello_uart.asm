; ================================================================================
; HELLO_UART.ASM - b8008 UART Demo
; ================================================================================
; Sends "Hello, 8008!" via UART using direct byte-at-a-time mode.
;
; I/O Ports:
;   OUT 9:  Direct UART TX - sends byte immediately (115200 baud)
;   OUT 8:  LED bank (active low, used for status indication)
;
; UART Settings:
;   Baud Rate: 115200
;   Format: 8N1 (8 data bits, no parity, 1 stop bit)
;
; Connect FTDI USB-to-serial adapter and open terminal at 115200 baud.
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

; ================================================================================
; MAIN PROGRAM
; ================================================================================
main:
        ; Turn on LED0 to show we're starting
        mvi a,0FEh              ; LED0 on (active low)
        out 8

        ; Small startup delay
        call delay_short

main_loop:
        ; Send the greeting message
        call send_hello

        ; Toggle LED1 to show activity
        mvi a,0FDh              ; LED1 on
        out 8

        ; Wait between messages (about 1 second)
        call delay_long

        ; Turn off LED1
        mvi a,0FFh              ; All LEDs off
        out 8

        ; Wait again
        call delay_long

        jmp main_loop           ; Loop forever

; ================================================================================
; SEND_HELLO - Send "Hello, 8008!" followed by CR/LF
; ================================================================================
send_hello:
        ; Send each character via OUT 9 (direct UART TX)
        mvi a,'H'
        out 9
        call char_delay

        mvi a,'e'
        out 9
        call char_delay

        mvi a,'l'
        out 9
        call char_delay

        mvi a,'l'
        out 9
        call char_delay

        mvi a,'o'
        out 9
        call char_delay

        mvi a,','
        out 9
        call char_delay

        mvi a,' '
        out 9
        call char_delay

        mvi a,'8'
        out 9
        call char_delay

        mvi a,'0'
        out 9
        call char_delay

        mvi a,'0'
        out 9
        call char_delay

        mvi a,'8'
        out 9
        call char_delay

        mvi a,'!'
        out 9
        call char_delay

        ; Send CR/LF for newline
        mvi a,CR
        out 9
        call char_delay

        mvi a,LF
        out 9
        call char_delay

        ret

; ================================================================================
; CHAR_DELAY - Small delay between characters
; ================================================================================
; At 115200 baud, each character takes ~87us to transmit.
; The 8008 runs at ~455kHz, so each instruction cycle is ~2.2us.
; A short delay ensures the UART TX buffer is ready for next byte.
;
char_delay:
        mvi b,20                ; ~100 instruction cycles
char_delay_loop:
        dcr b
        jnz char_delay_loop
        ret

; ================================================================================
; DELAY_SHORT - Short delay (~50ms)
; ================================================================================
delay_short:
        mvi b,100
delay_short_outer:
        mvi c,40
delay_short_inner:
        dcr c
        jnz delay_short_inner
        dcr b
        jnz delay_short_outer
        ret

; ================================================================================
; DELAY_LONG - Long delay (~500ms)
; ================================================================================
; Approximately 0.5 second delay at 455kHz CPU clock.
;
delay_long:
        mvi b,200               ; Outer loop counter
delay_long_outer:
        mvi c,80                ; Inner loop counter
delay_long_inner:
        dcr c
        jnz delay_long_inner

        dcr b
        jnz delay_long_outer

        ret

        end

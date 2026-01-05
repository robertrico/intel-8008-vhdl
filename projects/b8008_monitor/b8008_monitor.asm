; ================================================================================
; B8008_MONITOR.ASM - Interactive Console for b8008 CPU
; ================================================================================
; Interactive monitor with command processing.
;
; I/O Ports:
;   IN 1:   UART RX - bit 7 = ready flag, bits 6:0 = received data
;           Ready flag clears automatically when CPU reads the port
;   OUT 8:  LED bank (active low, used for status indication)
;   OUT 9:  Direct UART TX - sends byte immediately (115200 baud)
;
; UART Settings:
;   Baud Rate: 115200
;   Format: 8N1 (8 data bits, no parity, 1 stop bit)
;
; Connect FTDI USB-to-serial adapter and open terminal at 115200 baud.
; Local echo should be OFF in terminal (the 8008 will echo characters).
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
RX_READY equ    80h             ; Bit 7 mask for RX ready flag

; ================================================================================
; MAIN PROGRAM
; ================================================================================
main:
        ; Turn on LED0 to show we're starting
        mvi a,0FEh              ; LED0 on (active low)
        out 8

        ; Small startup delay
        call delay_short

        ; Send the banner then prompt
        call send_banner
        call send_prompt

        ; Fall through to echo loop

; ================================================================================
; COMMAND_LOOP - Main command loop
; ================================================================================
; Waits for a character from UART, processes commands or echoes.
;
command_loop:
        ; Poll UART RX for incoming character
        call uart_rx_wait       ; Returns received char in A

        ; Save character in C (B is used by char_delay)
        mov c,a

        ; Check for Enter key (CR)
        cpi LF
        jz handle_enter

        ; Check for Enter key (LF - some terminals send this)
        cpi CR
        jz handle_enter

        ; Check for 'H' or 'h' - Help command
        cpi 'H'
        jz handle_help
        cpi 'h'
        jz handle_help

        ; Not a command, echo the character back
        mov a,c
        out 9
        call char_delay

        ; Toggle LED1 briefly to show activity
        mvi a,0FDh              ; LED1 on
        out 8
        call delay_tiny
        mvi a,0FEh              ; LED0 on, LED1 off
        out 8

        jmp command_loop

; ================================================================================
; HANDLE_ENTER - Handle Enter key (new line + new prompt)
; ================================================================================
handle_enter:
        ; Send CR+LF
        mvi a,CR
        out 9
        call char_delay

        mvi a,LF
        out 9
        call char_delay

        ; Reprint the prompt
        call send_prompt

        jmp command_loop

; ================================================================================
; HANDLE_HELP - Display help menu
; ================================================================================
handle_help:
        ; Echo the 'H' back
        mov a,c
        out 9
        call char_delay

        ; New line
        mvi a,CR
        out 9
        call char_delay
        mvi a,LF
        out 9
        call char_delay

        ; Print "Help Menu"
        call send_help

        ; Print prompt
        call send_prompt

        jmp command_loop

; ================================================================================
; UART_RX_WAIT - Wait for and receive a character from UART
; ================================================================================
; Polls IN 1 until bit 7 (ready flag) is set, then returns the received
; character in the accumulator (bits 6:0).
; The ready flag is automatically cleared when IN 1 is executed.
;
; Returns: A = received character (7-bit ASCII)
; Destroys: A, B
;
uart_rx_wait:
        in 1                    ; Read UART status/data (clears ready flag)
        mov b,a                 ; Save the full byte (flag + data)
        ani RX_READY            ; Check bit 7 (ready flag)
        jz uart_rx_wait         ; Not ready, keep polling

        ; Ready flag was set - data is in B, extract the character
        mov a,b                 ; Restore the byte
        ani 7Fh                 ; Mask off bit 7 to get 7-bit ASCII
        ret

; ================================================================================
; SEND_BANNER - Send "8008 Monitor" + CR/LF
; ================================================================================
send_banner:
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

        mvi a,' '
        out 9
        call char_delay

        mvi a,'M'
        out 9
        call char_delay

        mvi a,'o'
        out 9
        call char_delay

        mvi a,'n'
        out 9
        call char_delay

        mvi a,'i'
        out 9
        call char_delay

        mvi a,'t'
        out 9
        call char_delay

        mvi a,'o'
        out 9
        call char_delay

        mvi a,'r'
        out 9
        call char_delay

        mvi a,CR
        out 9
        call char_delay

        mvi a,LF
        out 9
        call char_delay

        ret

; ================================================================================
; SEND_PROMPT - Send "> "
; ================================================================================
send_prompt:
        mvi a,'>'
        out 9
        call char_delay

        mvi a,' '
        out 9
        call char_delay

        ret

; ================================================================================
; SEND_HELP - Send help menu
; ================================================================================
send_help:
        ; "Help Menu" + CR/LF
        mvi a,'H'
        out 9
        call char_delay
        mvi a,'e'
        out 9
        call char_delay
        mvi a,'l'
        out 9
        call char_delay
        mvi a,'p'
        out 9
        call char_delay
        mvi a,' '
        out 9
        call char_delay
        mvi a,'M'
        out 9
        call char_delay
        mvi a,'e'
        out 9
        call char_delay
        mvi a,'n'
        out 9
        call char_delay
        mvi a,'u'
        out 9
        call char_delay
        mvi a,CR
        out 9
        call char_delay
        mvi a,LF
        out 9
        call char_delay

        ; "  H: Show Help" + CR/LF
        mvi a,' '
        out 9
        call char_delay
        mvi a,' '
        out 9
        call char_delay
        mvi a,'H'
        out 9
        call char_delay
        mvi a,':'
        out 9
        call char_delay
        mvi a,' '
        out 9
        call char_delay
        mvi a,'S'
        out 9
        call char_delay
        mvi a,'h'
        out 9
        call char_delay
        mvi a,'o'
        out 9
        call char_delay
        mvi a,'w'
        out 9
        call char_delay
        mvi a,' '
        out 9
        call char_delay
        mvi a,'H'
        out 9
        call char_delay
        mvi a,'e'
        out 9
        call char_delay
        mvi a,'l'
        out 9
        call char_delay
        mvi a,'p'
        out 9
        call char_delay
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
; DELAY_TINY - Very short delay for LED blink
; ================================================================================
delay_tiny:
        mvi b,10
delay_tiny_loop:
        dcr b
        jnz delay_tiny_loop
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

        end

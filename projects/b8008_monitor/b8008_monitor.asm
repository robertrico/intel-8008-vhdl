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

; Command buffer (in RAM, which starts at 0x1000)
CMD_LEN equ     1000h           ; Buffer length storage (1 byte)
CMD_BUF equ     1001h           ; Command buffer start address (16 bytes: 0x1001-0x1010)
CMD_MAX equ     16              ; Maximum command length

; ================================================================================
; MAIN PROGRAM
; ================================================================================
main:
	; Reset system
	mvi a,0
	mvi b,0
	mvi c,0
	mvi d,0
	mvi e,0
	xra a

        ; Turn on LED0 to show we're starting
        mvi a,0FEh              ; LED0 on (active low)
        out 8

        ; Initialize command buffer length to 0
        call clear_buffer

        ; Small startup delay
        call delay_short

        ; Send the banner then prompt
        call send_banner
        call send_prompt


        ; Fall through to echo loop

; ================================================================================
; COMMAND_LOOP - Main command loop
; ================================================================================
; Waits for a character from UART, buffers it, and echoes back.
; Commands are parsed only when Enter is pressed.
;
command_loop:

        ; Poll UART RX for incoming character
        call uart_rx_wait       ; Returns received char in A

        ; Save character in C (used by add_to_buffer)
        mov c,a

        ; Check for Enter key (CR)
        cpi CR
        jz handle_enter

        ; Check for Enter key (LF - some terminals send this)
        cpi LF
        jz handle_enter

        ; Regular character - add to buffer
        call add_to_buffer      ; C = char

	mvi a,0FEh
	out 8

        ; Echo the character back
        mov a,c
        out 9
        call char_delay

        jmp command_loop

; ================================================================================
; HANDLE_ENTER - Handle Enter key (new line + new prompt)
; ================================================================================
handle_enter:
	call delay_tiny
        ; Parse and execute command in buffer (currently a stub)
        call parse_command

        ; Clear buffer for next command
        call clear_buffer

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
; CLEAR_BUFFER - Reset command buffer length to 0
; ================================================================================
; Destroys: A, H, L
;
clear_buffer:
        mvi h,10h               ; CMD_LEN high byte
        mvi l,00h               ; CMD_LEN low byte
        mvi m,0                 ; Store 0 to buffer length
        ret

; ================================================================================
; ADD_TO_BUFFER - Add character to command buffer
; ================================================================================
; Input:  C = character to add
; Output: B = 1 if added successfully, 0 if buffer full
; Destroys: A, B, D, H, L
;
add_to_buffer:
        ; Load current buffer length
        mvi h,10h
        mvi l,00h               ; Point to CMD_LEN (0x1000)
        mov a,m                 ; A = current length

        ; Check if buffer is full
        cpi CMD_MAX             ; Compare with max (16)
        jnc buffer_full         ; Jump if length >= 16

        ; Calculate target address: CMD_BUF + length = 0x1001 + length
        mov d,a                 ; Save length in D
        adi 01h                 ; A = length + 1 (low byte of target address)
        mov l,a                 ; HL = 0x1000 + length + 1 = 0x1001 + length

        ; Store the character
        mov m,c                 ; Store character at buffer[length]

        ; Increment and save new length
        mvi l,00h               ; Point back to CMD_LEN (0x1000)
        mov a,d                 ; Get saved length
        adi 1                   ; Increment
        mov m,a                 ; Store new length

        mvi b,1                 ; Return success
        ret

buffer_full:
        mvi b,0                 ; Return failure
        ret

; ================================================================================
; PARSE_COMMAND - Parse and execute command in buffer
; ================================================================================
; Checks the first character in the buffer and dispatches to the appropriate
; command handler.
;
; Commands:
;   H or h - Show help menu
;
; Destroys: A, H, L
;
parse_command:
        ; Point HL to first character in buffer (CMD_BUF = 0x1001)
        mvi h,10h
        mvi l,01h
        mov a,m                 ; Load first character

        ; Check for 'H'
        cpi 'H'
        jz cmd_help

        ; Check for 'h'
        cpi 'h'
        jz cmd_help

        ; Unknown command - just return
        ret

cmd_help:
        call send_help
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

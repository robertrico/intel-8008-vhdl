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

; Dump command variables (RAM)
DUMP_ADDR_H equ 1020h           ; Dump address high byte
DUMP_ADDR_L equ 1021h           ; Dump address low byte
DUMP_COUNT  equ 1022h           ; Dump byte count (1-255, 0 means 1)

; ================================================================================
; MAIN PROGRAM
; ================================================================================
main:
	mvi a,0
	mvi b,0
	mvi c,0
	mvi d,0
	mvi e,0
	mvi h,0
	mvi l,0

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

        ; Send CR+LF before running command
        mvi a,CR
        out 9
        call char_delay
        mvi a,LF
        out 9
        call char_delay

        ; Parse and execute command in buffer
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

        ; "  D addr[,n]: Dump" + CR/LF
        mvi a,' '
        out 9
        call char_delay
        mvi a,' '
        out 9
        call char_delay
        mvi a,'D'
        out 9
        call char_delay
        mvi a,' '
        out 9
        call char_delay
        mvi a,'a'
        out 9
        call char_delay
        mvi a,'d'
        out 9
        call char_delay
        mvi a,'d'
        out 9
        call char_delay
        mvi a,'r'
        out 9
        call char_delay
        mvi a,'['
        out 9
        call char_delay
        mvi a,','
        out 9
        call char_delay
        mvi a,'n'
        out 9
        call char_delay
        mvi a,']'
        out 9
        call char_delay
        mvi a,':'
        out 9
        call char_delay
        mvi a,' '
        out 9
        call char_delay
        mvi a,'D'
        out 9
        call char_delay
        mvi a,'u'
        out 9
        call char_delay
        mvi a,'m'
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

        ; Check for 'D'
        cpi 'D'
        jz cmd_dump

        ; Check for 'd'
        cpi 'd'
        jz cmd_dump

        ; Unknown command - just return
        ret

cmd_help:
        call send_help
        ret

; ================================================================================
; CMD_DUMP - Dump memory contents
; ================================================================================
; Format: D addr[,count]
;   D 1000     - dumps single byte at 0x1000
;   D 1000,4   - dumps 4 bytes starting at 0x1000
;
; Output format: ADDR - XX [XX XX ...]
;
cmd_dump:
        ; Parse the address and count from buffer
        call parse_dump_args    ; Sets DUMP_ADDR_H/L and DUMP_COUNT

        ; Get count (0 means 1)
        mvi h,10h
        mvi l,22h               ; DUMP_COUNT
        mov a,m
        ora a                   ; Check if zero
        jnz dump_loop_start
        mvi a,1                 ; Default to 1 if zero
        mov m,a

dump_loop_start:
        ; Load address into DE (we'll use HL for memory access)
        mvi h,10h
        mvi l,20h               ; DUMP_ADDR_H
        mov d,m                 ; D = high byte
        inr l
        mov e,m                 ; E = low byte

        ; Send address
        mov a,d
        call send_hex_byte
        mov a,e
        call send_hex_byte

        ; Send " - "
        mvi a,' '
        out 9
        call char_delay
        mvi a,'-'
        out 9
        call char_delay
        mvi a,' '
        out 9
        call char_delay

dump_loop:
        ; Read byte at address DE
        mov h,d
        mov l,e
        mov a,m                 ; A = byte at [HL]

        ; Send as hex
        call send_hex_byte

        ; Decrement count
        mvi h,10h
        mvi l,22h               ; DUMP_COUNT
        mov a,m
        sui 1                   ; Decrement (8008 has no DCR A)
        mov m,a
        jz dump_done            ; Count reached zero

        ; Increment address in DE
        inr e
        jnz dump_no_carry
        inr d
dump_no_carry:

        ; Send space between bytes
        mvi a,' '
        out 9
        call char_delay

        jmp dump_loop

dump_done:
        ret

; ================================================================================
; PARSE_DUMP_ARGS - Parse address and optional count from command buffer
; ================================================================================
; Buffer format: "D addr" or "D addr,count"
; Sets DUMP_ADDR_H, DUMP_ADDR_L, DUMP_COUNT
;
; Destroys: A, B, C, D, E, H, L
;
parse_dump_args:
        ; Initialize count to 1
        mvi h,10h
        mvi l,22h               ; DUMP_COUNT
        mvi m,1

        ; Initialize address to 0
        mvi l,20h               ; DUMP_ADDR_H
        mvi m,0
        inr l
        mvi m,0                 ; DUMP_ADDR_L = 0

        ; Start at buffer position 2 (skip 'D' and space)
        ; Buffer index in E
        mvi e,2                 ; Start after "D "

parse_addr_loop:
        ; Check buffer bounds first (compare E with CMD_LEN)
        mvi h,10h
        mvi l,00h               ; CMD_LEN at 0x1000
        mov a,m                 ; A = buffer length
        mov b,a                 ; Save length in B
        mov a,e
        cmp b                   ; Compare index with length
        jnc parse_addr_done     ; Index >= length, stop

        ; Get character at CMD_BUF + E
        mvi h,10h
        mvi l,01h               ; CMD_BUF base
        mov a,e
        add l
        mov l,a                 ; HL = CMD_BUF + E

        mov a,m                 ; A = character

        ; Check for comma (end of address, start of count)
        cpi ','
        jz parse_count_start

        ; Check for null/end (spaces count as end too)
        cpi ' '
        jz parse_addr_done
        cpi 0
        jz parse_addr_done

        ; Convert hex char to nibble
        call hex_char_to_nibble ; A = nibble value (0-15), carry set if invalid
        jc parse_addr_done      ; Invalid char, stop parsing

        ; Shift address left 4 bits and add new nibble
        ; DUMP_ADDR = (DUMP_ADDR << 4) | nibble
        mov c,a                 ; Save nibble in C

        ; Load current address into D (high) and A (low)
        mvi h,10h
        mvi l,20h
        mov d,m                 ; D = high byte
        inr l
        mov a,m                 ; A = low byte

        ; Shift left 4 bits: move high nibble of low byte to low nibble of high byte
        ; D = (D << 4) | (A >> 4)
        ; A = (A << 4) | nibble

        mov b,a                 ; Save low byte in B

        ; Shift A left 4 (lose high nibble)
        rlc
        rlc
        rlc
        rlc
        ani 0F0h                ; Keep only shifted bits
        ora c                   ; Add new nibble
        mov c,a                 ; Save new low byte in C

        ; Get high nibble of old low byte
        mov a,b
        rlc
        rlc
        rlc
        rlc
        ani 0Fh                 ; Keep only high nibble (now in low position)
        mov b,a                 ; B = high nibble of old low byte

        ; Shift D left 4 and add B
        mov a,d
        rlc
        rlc
        rlc
        rlc
        ani 0F0h
        ora b                   ; Add carry from low byte
        mov d,a                 ; D = new high byte

        ; Store back
        mvi h,10h
        mvi l,20h
        mov m,d                 ; Store high byte
        inr l
        mov m,c                 ; Store low byte

        ; Next character
        inr e
        jmp parse_addr_loop

parse_addr_done:
        ret

parse_count_start:
        ; Skip the comma
        inr e

        ; Initialize count to 0 (we'll build it up)
        mvi h,10h
        mvi l,22h
        mvi m,0

        ; Skip any spaces after comma
parse_count_skip_spaces:
        ; Check buffer bounds first (compare E with CMD_LEN)
        mvi h,10h
        mvi l,00h               ; CMD_LEN at 0x1000
        mov a,m                 ; A = buffer length
        mov b,a                 ; Save length in B
        mov a,e
        cmp b                   ; Compare index with length
        jnc parse_count_done    ; Index >= length, stop

        ; Get character at CMD_BUF + E
        mvi h,10h
        mvi l,01h
        mov a,e
        add l
        mov l,a
        mov a,m                 ; A = character

        ; Skip spaces
        cpi ' '
        jnz parse_count_loop_entry
        inr e
        jmp parse_count_skip_spaces

parse_count_loop:
        ; Check buffer bounds first
        mvi h,10h
        mvi l,00h               ; CMD_LEN
        mov a,m
        mov b,a
        mov a,e
        cmp b
        jnc parse_count_done    ; Index >= length, stop

        ; Get character at CMD_BUF + E
        mvi h,10h
        mvi l,01h
        mov a,e
        add l
        mov l,a

        mov a,m                 ; A = character

parse_count_loop_entry:
        ; Check for end
        cpi ' '
        jz parse_count_done
        cpi 0
        jz parse_count_done

        ; Convert hex char to nibble
        call hex_char_to_nibble
        jc parse_count_done     ; Invalid char, stop

        ; count = (count << 4) | nibble
        mov c,a                 ; Save nibble in C

        mvi h,10h
        mvi l,22h
        mov a,m                 ; A = current count

        ; Shift left 4
        rlc
        rlc
        rlc
        rlc
        ani 0F0h
        ora c                   ; Add new nibble

        mov m,a                 ; Store back

        inr e
        jmp parse_count_loop

parse_count_done:
        ret

; ================================================================================
; HEX_CHAR_TO_NIBBLE - Convert hex ASCII character to nibble value
; ================================================================================
; Input:  A = ASCII character ('0'-'9', 'A'-'F', 'a'-'f')
; Output: A = nibble value (0-15), carry clear
;         If invalid, carry set
;
; Destroys: A
;
hex_char_to_nibble:
        ; Check for '0'-'9'
        cpi '0'
        jc hex_invalid          ; Below '0'
        cpi '9'+1
        jc hex_digit            ; '0'-'9'

        ; Check for 'A'-'F'
        cpi 'A'
        jc hex_invalid          ; Between '9' and 'A'
        cpi 'F'+1
        jc hex_upper            ; 'A'-'F'

        ; Check for 'a'-'f'
        cpi 'a'
        jc hex_invalid          ; Between 'F' and 'a'
        cpi 'f'+1
        jc hex_lower            ; 'a'-'f'

        ; Above 'f'
hex_invalid:
        ; Set carry to indicate error (8008 has no STC)
        mvi a,0
        sui 1                   ; 0 - 1 sets carry
        ret

hex_digit:
        sui '0'                 ; Convert '0'-'9' to 0-9
        ora a                   ; Clear carry
        ret

hex_upper:
        sui 'A'-10              ; Convert 'A'-'F' to 10-15
        ora a                   ; Clear carry
        ret

hex_lower:
        sui 'a'-10              ; Convert 'a'-'f' to 10-15
        ora a                   ; Clear carry
        ret

; ================================================================================
; SEND_HEX_BYTE - Send a byte as two hex digits
; ================================================================================
; Input:  A = byte to send
; Destroys: A, B
;
send_hex_byte:
        mov b,a                 ; Save byte in B

        ; Send high nibble
        rlc
        rlc
        rlc
        rlc
        ani 0Fh
        call send_hex_nibble

        ; Send low nibble
        mov a,b
        ani 0Fh
        call send_hex_nibble

        ret

; ================================================================================
; SEND_HEX_NIBBLE - Send a nibble as one hex digit
; ================================================================================
; Input:  A = nibble (0-15)
; Destroys: A
;
send_hex_nibble:
        cpi 10
        jc nibble_digit         ; 0-9
        ; 10-15: convert to 'A'-'F'
        adi 'A'-10
        jmp nibble_out
nibble_digit:
        adi '0'                 ; 0-9 to '0'-'9'
nibble_out:
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

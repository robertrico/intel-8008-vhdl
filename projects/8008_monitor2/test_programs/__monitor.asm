; monitor.asm
; Intel 8008 Monitor Program - Phase 2: Memory Operations
;
; Functionality:
; 1. Print startup banner on boot
; 2. Enter command loop with "8008>" prompt
; 3. Accept buffered command input (terminated by CR/LF)
; 4. Commands (case-insensitive):
;    '?' - Help (list all commands)
;    'h' - Hello (print version banner)
;    's' - Reset (software reset)
;    'r' - Read memory byte at address (Phase 2)
;    'd' - Dump 16 bytes of memory (Phase 2)
;
; I/O Ports:
;   Port 0 (IN):  TX Status (bit 0 = tx_busy)
;   Port 3 (IN):  RX Data (read clears rx_ready)
;   Port 4 (IN):  RX Status (bit 0 = rx_ready)
;   Port 10 (OUT): TX Data
;   Note: Ports 1 and 2 are reserved for interrupt controller
;
; Memory Map:
;   ROM: 0x0000-0x07FF (2KB) - Monitor program
;   RAM: 0x0800-0x09FF (512B) - User area
;   RAM: 0x0A00-0x0AFF (256B) - Command buffer & variables
;   RAM: 0x0B00-0x0BFF (256B) - Stack

            cpu 8008new         ; use "new" 8008 mnemonics
            org 0000H

;==============================================================================
; Interrupt Vector Table
; RST 0-7 vectors at 0x0000, 0x0008, 0x0010, 0x0018, 0x0020, 0x0028, 0x0030, 0x0038
; Each vector jumps to main (RST 0) or just returns (RST 1-7)
;==============================================================================

; RST 0 vector - Entry point and startup interrupt handler
rst0_vector:
            jmp main              ; Jump to actual start code

            org 0008H
; RST 1 vector - Unused interrupt (just return)
rst1_vector:
            ret                   ; Return from interrupt

            org 0010H
; RST 2 vector - Unused interrupt (just return)
rst2_vector:
            ret                   ; Return from interrupt

            org 0018H
; RST 3 vector - Unused interrupt (just return)
rst3_vector:
            ret                   ; Return from interrupt

            org 0020H
; RST 4 vector - Unused interrupt (just return)
rst4_vector:
            ret                   ; Return from interrupt

            org 0028H
; RST 5 vector - Unused interrupt (just return)
rst5_vector:
            ret                   ; Return from interrupt

            org 0030H
; RST 6 vector - Unused interrupt (just return)
rst6_vector:
            ret                   ; Return from interrupt

            org 0038H
; RST 7 vector - Unused interrupt (just return)
rst7_vector:
            ret                   ; Return from interrupt

;==============================================================================
; RAM Variables (0x0A00 area)
; cmd_buffer: 0x0A00 - Command input buffer (up to 128 bytes)
; cmd_length: 0x0A80 - Current command length (1 byte)
; temp_h: 0x0A81 - Temporary storage for H register
; temp_l: 0x0A82 - Temporary storage for L register
;==============================================================================
temp_h      equ 0A81H
temp_l      equ 0A82H

;==============================================================================
; Entry Point (code continues from here after RST 0 vector jumps to main)
;==============================================================================
            org 0040H
main:
            ; Debug: Boot marker
            mvi a,'*'
            call uart_tx_char

            ; Disable all interrupts (set mask to 0x00)
            mvi a,00H
            out 9                 ; Write to interrupt mask register (port 9)

            ; Debug: Before banner
            mvi a,'1'
            call uart_tx_char

            ; Print startup banner
            call print_banner

            ; Debug: After banner
            mvi a,'2'
            call uart_tx_char

;==============================================================================
; Main Command Loop
;==============================================================================
command_loop:
            ; Print prompt "8008>"
            call print_prompt

            ; Read a line of input (until CR)
            call read_line

            ; Process the command (first character in buffer)
            mvi h,0AH             ; H = high byte of cmd_buffer address (0x0A00)
            mvi l,00H             ; L = low byte of cmd_buffer address
            mov a,m               ; A = first character of command

            ; Skip empty commands (just Enter pressed)
            cpi 0DH               ; Check if first char is CR
            jz command_loop

            ; Convert to uppercase for case-insensitive matching
            call to_upper
            mov d,a               ; Save uppercase command in D

            ; Dispatch command
            ; Check for '?' - Help
            cpi '?'
            jz cmd_help

            ; Check for 'H' - Hello
            cpi 'H'
            jz cmd_hello

            ; Check for 'S' - Reset (software reset)
            cpi 'S'
            jz cmd_reset

            ; Check for 'R' - Read memory
            cpi 'R'
            jz cmd_read_mem

            ; Check for 'D' - Dump memory
            cpi 'D'
            jz cmd_dump_mem

            ; Check for 'E' - Echo test
            cpi 'E'
            jz cmd_echo_test

            ; Unknown command
            call print_unknown
            jmp command_loop

;==============================================================================
; Command: Help ('?')
;==============================================================================
cmd_help:
            call print_help
            jmp command_loop

;==============================================================================
; Command: Hello ('h')
;==============================================================================
cmd_hello:
            call print_banner
            jmp command_loop

;==============================================================================
; Command: Reset ('r')
;==============================================================================
cmd_reset:
            call print_reset_msg
            ; Jump back to start (software reset)
            jmp main

;==============================================================================
; Command: Read Memory ('R')
; Format: R <addr>
; Example: R 0800 -> reads byte at address 0x0800
;==============================================================================
cmd_read_mem:
            ; Print space after command letter for cleaner input
            mvi a,' '
            call uart_tx_char

            ; Get 4-digit hex address from user (reads from serial)
            call get_four
            jc cmd_read_error     ; Error if carry set (escape pressed)

            ; H,L now contains the address

            ; Print result: "ADDR: XX\r\n"
            ; Print address (from H,L)
            call print_crlf
            mov a,h
            call print_hex_byte
            mov a,l
            call print_hex_byte

            ; Print ": "
            mvi a,':'
            call uart_tx_char
            mvi a,' '
            call uart_tx_char

            ; Now read the byte at that address
            mov a,m               ; A = byte at M[HL]

            ; Print byte value
            call print_hex_byte
            call print_crlf

            jmp command_loop

cmd_read_error:
            call print_crlf
            call print_syntax_error
            jmp command_loop

;==============================================================================
; Command: Dump Memory ('D')
; Format: D <addr>
; Example: D 0800 -> dumps 16 bytes starting at 0x0800
;==============================================================================
cmd_dump_mem:
            ; Print space after command letter for cleaner input
            mvi a,' '
            call uart_tx_char

            ; Get 4-digit hex address from user (reads from serial)
            call get_four
            jc cmd_dump_error     ; Error if carry set (escape pressed)

            ; H,L now contains the start address

            ; Print 16 bytes in format:
            ; ADDR: XX XX XX XX XX XX XX XX XX XX XX XX XX XX XX XX

            ; Print address
            call print_crlf
            mov a,h
            call print_hex_byte
            mov a,l
            call print_hex_byte
            mvi a,':'
            call uart_tx_char
            mvi a,' '
            call uart_tx_char

            ; Print 16 bytes
            mvi d,16              ; Counter for 16 bytes

dump_loop:
            mov a,m               ; A = byte at M[HL]
            call print_hex_byte
            mvi a,' '
            call uart_tx_char

            ; Increment address (HL++)
            inr l
            mov a,l
            cpi 0
            jnz dump_no_carry
            ; Handle carry to high byte
            inr h

dump_no_carry:
            ; Decrement counter
            dcr d
            mov a,d
            cpi 0
            jnz dump_loop

            call print_crlf
            jmp command_loop

cmd_dump_error:
            call print_crlf
            call print_syntax_error
            jmp command_loop

;==============================================================================
; Command: Echo Test ('E')
; Format: E
; Purpose: Read an entire line, then echo it back
;          This tests if UART RX is reading ALL characters correctly
;==============================================================================
cmd_echo_test:
            ; Print newline
            call print_crlf

            ; Read entire line into buffer at 0x0A81
            ; Buffer starts at 0x0A81, length stored at 0x0A80
            mvi h,0AH
            mvi l,81H
            mvi c,0               ; Character counter

echo_read_loop:
            ; Read one character
            call uart_rx_char

            ; Echo it immediately (for visual feedback)
            mov b,a               ; Save character
            call uart_tx_char
            mov a,b               ; Restore character

            ; Check if it's Enter (0x0D)
            cpi 0DH
            jz echo_print_back

            ; Store in buffer
            mov m,a               ; M[HL] = A
            inr l                 ; Increment buffer pointer
            inr c                 ; Increment counter

            ; Check for buffer overflow (max 127 chars)
            mov a,c
            cpi 127
            jnc echo_read_loop    ; If full, ignore more chars

            jmp echo_read_loop

echo_print_back:
            ; Print "ECHO: "
            call print_crlf
            mvi a,'E'
            call uart_tx_char
            mvi a,'C'
            call uart_tx_char
            mvi a,'H'
            call uart_tx_char
            mvi a,'O'
            call uart_tx_char
            mvi a,':'
            call uart_tx_char
            mvi a,' '
            call uart_tx_char

            ; Print back the buffered line
            mvi h,0AH
            mvi l,81H             ; Reset to buffer start
            mov b,c               ; B = character count

echo_print_loop:
            mov a,b
            cpi 0
            jz echo_done          ; If count is 0, done

            mov a,m               ; A = M[HL]
            call uart_tx_char
            inr l                 ; Next character
            dcr b                 ; Decrement counter
            jmp echo_print_loop

echo_done:
            call print_crlf
            jmp command_loop

;==============================================================================
; Subroutine: uart_tx_char
; Purpose: Wait for TX ready and transmit character in A register
; Input: A = character to transmit
; Modifies: B (preserves A via B)
;==============================================================================
uart_tx_char:
            mov b,a               ; Save character to B
wait_tx:
            in 0                  ; Read TX status (port 0)
            ani 01H               ; Check tx_busy bit
            jnz wait_tx           ; If busy, keep waiting
            mov a,b               ; Restore character
            out 10                ; Send to TX data port
            ret

;==============================================================================
; Subroutine: uart_rx_char
; Purpose: Wait for RX ready and read a single character
; Output: A = received character
; Modifies: A
;==============================================================================
uart_rx_char:
wait_rx:
            in 4                  ; Read RX status (port 4)
            ani 01H               ; Check rx_ready bit
            jz wait_rx            ; If no data, keep waiting
            in 3                  ; Read RX data (port 3, clears rx_ready)
            ret

;==============================================================================
; Subroutine: read_line
; Purpose: Read a line of input into cmd_buffer until CR is received
;          Supports backspace for editing
; Output: cmd_buffer contains the command string
;         cmd_length contains the length (excluding CR)
; Modifies: A, B, C, H, L
;==============================================================================
read_line:
            ; Initialize buffer pointer and length
            mvi h,0AH             ; H = high byte of buffer address (0x0A00)
            mvi l,00H             ; L = low byte of buffer address
            mvi c,0               ; C = current position in buffer

read_char:
            ; Read one character
            call uart_rx_char
            mov b,a               ; Save character in B

            ; Check for CR (0x0D) - end of line
            cpi 0DH
            jz read_done

            ; Check for LF (0x0A) - ignore it (some terminals send CR+LF)
            cpi 0AH
            jz read_char

            ; Check for backspace (0x08 or 0x7F)
            cpi 08H
            jz handle_backspace
            mov a,b
            cpi 7FH
            jz handle_backspace

            ; Check buffer overflow (max 127 chars)
            mov a,c
            cpi 127
            jnc read_char         ; If buffer full, ignore character

            ; Echo the character
            mov a,b
            call uart_tx_char

            ; Store character in buffer
            mov m,a               ; M[HL] = A

            ; Increment buffer pointer and length
            inr l                 ; Increment L (HL++)
            inr c                 ; Increment length counter
            jmp read_char

handle_backspace:
            ; Check if buffer is empty
            mov a,c
            cpi 0
            jz read_char          ; Nothing to delete

            ; Decrement buffer pointer and length
            dcr l                 ; Decrement L (HL--)
            dcr c                 ; Decrement length counter

            ; Echo backspace sequence: BS, space, BS
            mvi a,08H             ; Backspace
            call uart_tx_char
            mvi a,' '             ; Space (erase character)
            call uart_tx_char
            mvi a,08H             ; Backspace again
            call uart_tx_char
            jmp read_char

read_done:
            ; Store CR at end of buffer
            mov a,b               ; A = CR
            mov m,a               ; M[HL] = CR

            ; Echo CR+LF
            call print_crlf

            ; Save length to memory
            mvi h,0AH             ; H = high byte (0x0A80)
            mvi l,80H             ; L = low byte
            mov a,c
            mov m,a               ; Store length

            ret

;==============================================================================
; Subroutine: print_crlf
; Purpose: Print carriage return and line feed
; Modifies: A
;==============================================================================
print_crlf:
            mvi a,0DH             ; CR
            call uart_tx_char
            mvi a,0AH             ; LF
            call uart_tx_char
            ret

;==============================================================================
; Subroutine: print_prompt
; Purpose: Print "8008> "
; Modifies: A
;==============================================================================
print_prompt:
            mvi a,'8'
            call uart_tx_char
            mvi a,'0'
            call uart_tx_char
            mvi a,'0'
            call uart_tx_char
            mvi a,'8'
            call uart_tx_char
            mvi a,'>'
            call uart_tx_char
            mvi a,' '
            call uart_tx_char
            ret

;==============================================================================
; Subroutine: print_banner
; Purpose: Print "Intel 8008 Monitor v1.0\r\n"
; Modifies: A
;==============================================================================
print_banner:
            mvi a,'I'
            call uart_tx_char
            mvi a,'n'
            call uart_tx_char
            mvi a,'t'
            call uart_tx_char
            mvi a,'e'
            call uart_tx_char
            mvi a,'l'
            call uart_tx_char
            mvi a,' '
            call uart_tx_char
            mvi a,'8'
            call uart_tx_char
            mvi a,'0'
            call uart_tx_char
            mvi a,'0'
            call uart_tx_char
            mvi a,'8'
            call uart_tx_char
            mvi a,' '
            call uart_tx_char
            mvi a,'M'
            call uart_tx_char
            mvi a,'o'
            call uart_tx_char
            mvi a,'n'
            call uart_tx_char
            mvi a,'i'
            call uart_tx_char
            mvi a,'t'
            call uart_tx_char
            mvi a,'o'
            call uart_tx_char
            mvi a,'r'
            call uart_tx_char
            mvi a,' '
            call uart_tx_char
            mvi a,'v'
            call uart_tx_char
            mvi a,'1'
            call uart_tx_char
            mvi a,'.'
            call uart_tx_char
            mvi a,'0'
            call uart_tx_char
            call print_crlf
            ret

;==============================================================================
; Subroutine: print_help
; Purpose: Print help text listing all commands
; Modifies: A
;==============================================================================
print_help:
            ; "Commands:\r\n"
            mvi a,'C'
            call uart_tx_char
            mvi a,'o'
            call uart_tx_char
            mvi a,'m'
            call uart_tx_char
            mvi a,'m'
            call uart_tx_char
            mvi a,'a'
            call uart_tx_char
            mvi a,'n'
            call uart_tx_char
            mvi a,'d'
            call uart_tx_char
            mvi a,'s'
            call uart_tx_char
            mvi a,':'
            call uart_tx_char
            call print_crlf

            ; "  ? - Help\r\n"
            mvi a,' '
            call uart_tx_char
            mvi a,' '
            call uart_tx_char
            mvi a,'?'
            call uart_tx_char
            mvi a,' '
            call uart_tx_char
            mvi a,'-'
            call uart_tx_char
            mvi a,' '
            call uart_tx_char
            mvi a,'H'
            call uart_tx_char
            mvi a,'e'
            call uart_tx_char
            mvi a,'l'
            call uart_tx_char
            mvi a,'p'
            call uart_tx_char
            call print_crlf

            ; "  h - Hello\r\n"
            mvi a,' '
            call uart_tx_char
            mvi a,' '
            call uart_tx_char
            mvi a,'h'
            call uart_tx_char
            mvi a,' '
            call uart_tx_char
            mvi a,'-'
            call uart_tx_char
            mvi a,' '
            call uart_tx_char
            mvi a,'H'
            call uart_tx_char
            mvi a,'e'
            call uart_tx_char
            mvi a,'l'
            call uart_tx_char
            mvi a,'l'
            call uart_tx_char
            mvi a,'o'
            call uart_tx_char
            call print_crlf

            ; "  s - Reset\r\n"
            mvi a,' '
            call uart_tx_char
            mvi a,' '
            call uart_tx_char
            mvi a,'s'
            call uart_tx_char
            mvi a,' '
            call uart_tx_char
            mvi a,'-'
            call uart_tx_char
            mvi a,' '
            call uart_tx_char
            mvi a,'R'
            call uart_tx_char
            mvi a,'e'
            call uart_tx_char
            mvi a,'s'
            call uart_tx_char
            mvi a,'e'
            call uart_tx_char
            mvi a,'t'
            call uart_tx_char
            call print_crlf

            ; "  r - Read memory\r\n"
            mvi a,' '
            call uart_tx_char
            mvi a,' '
            call uart_tx_char
            mvi a,'r'
            call uart_tx_char
            mvi a,' '
            call uart_tx_char
            mvi a,'-'
            call uart_tx_char
            mvi a,' '
            call uart_tx_char
            mvi a,'R'
            call uart_tx_char
            mvi a,'e'
            call uart_tx_char
            mvi a,'a'
            call uart_tx_char
            mvi a,'d'
            call uart_tx_char
            mvi a,' '
            call uart_tx_char
            mvi a,'m'
            call uart_tx_char
            mvi a,'e'
            call uart_tx_char
            mvi a,'m'
            call uart_tx_char
            mvi a,'o'
            call uart_tx_char
            mvi a,'r'
            call uart_tx_char
            mvi a,'y'
            call uart_tx_char
            call print_crlf

            ; "  d - Dump memory\r\n"
            mvi a,' '
            call uart_tx_char
            mvi a,' '
            call uart_tx_char
            mvi a,'d'
            call uart_tx_char
            mvi a,' '
            call uart_tx_char
            mvi a,'-'
            call uart_tx_char
            mvi a,' '
            call uart_tx_char
            mvi a,'D'
            call uart_tx_char
            mvi a,'u'
            call uart_tx_char
            mvi a,'m'
            call uart_tx_char
            mvi a,'p'
            call uart_tx_char
            mvi a,' '
            call uart_tx_char
            mvi a,'m'
            call uart_tx_char
            mvi a,'e'
            call uart_tx_char
            mvi a,'m'
            call uart_tx_char
            mvi a,'o'
            call uart_tx_char
            mvi a,'r'
            call uart_tx_char
            mvi a,'y'
            call uart_tx_char
            call print_crlf

            ; "  e - Echo test\r\n"
            mvi a,' '
            call uart_tx_char
            mvi a,' '
            call uart_tx_char
            mvi a,'e'
            call uart_tx_char
            mvi a,' '
            call uart_tx_char
            mvi a,'-'
            call uart_tx_char
            mvi a,' '
            call uart_tx_char
            mvi a,'E'
            call uart_tx_char
            mvi a,'c'
            call uart_tx_char
            mvi a,'h'
            call uart_tx_char
            mvi a,'o'
            call uart_tx_char
            mvi a,' '
            call uart_tx_char
            mvi a,'t'
            call uart_tx_char
            mvi a,'e'
            call uart_tx_char
            mvi a,'s'
            call uart_tx_char
            mvi a,'t'
            call uart_tx_char
            call print_crlf
            ret

;==============================================================================
; Subroutine: print_unknown
; Purpose: Print "Unknown command\r\n"
; Modifies: A
;==============================================================================
print_unknown:
            mvi a,'U'
            call uart_tx_char
            mvi a,'n'
            call uart_tx_char
            mvi a,'k'
            call uart_tx_char
            mvi a,'n'
            call uart_tx_char
            mvi a,'o'
            call uart_tx_char
            mvi a,'w'
            call uart_tx_char
            mvi a,'n'
            call uart_tx_char
            mvi a,' '
            call uart_tx_char
            mvi a,'c'
            call uart_tx_char
            mvi a,'o'
            call uart_tx_char
            mvi a,'m'
            call uart_tx_char
            mvi a,'m'
            call uart_tx_char
            mvi a,'a'
            call uart_tx_char
            mvi a,'n'
            call uart_tx_char
            mvi a,'d'
            call uart_tx_char
            call print_crlf
            ret

;==============================================================================
; Subroutine: print_syntax_error
; Purpose: Print "Syntax error\r\n"
; Modifies: A
;==============================================================================
print_syntax_error:
            mvi a,'S'
            call uart_tx_char
            mvi a,'y'
            call uart_tx_char
            mvi a,'n'
            call uart_tx_char
            mvi a,'t'
            call uart_tx_char
            mvi a,'a'
            call uart_tx_char
            mvi a,'x'
            call uart_tx_char
            mvi a,' '
            call uart_tx_char
            mvi a,'e'
            call uart_tx_char
            mvi a,'r'
            call uart_tx_char
            mvi a,'r'
            call uart_tx_char
            mvi a,'o'
            call uart_tx_char
            mvi a,'r'
            call uart_tx_char
            call print_crlf
            ret

;==============================================================================
; Subroutine: print_reset_msg
; Purpose: Print "Resetting...\r\n"
; Modifies: A
;==============================================================================
print_reset_msg:
            mvi a,'R'
            call uart_tx_char
            mvi a,'e'
            call uart_tx_char
            mvi a,'s'
            call uart_tx_char
            mvi a,'e'
            call uart_tx_char
            mvi a,'t'
            call uart_tx_char
            mvi a,'t'
            call uart_tx_char
            mvi a,'i'
            call uart_tx_char
            mvi a,'n'
            call uart_tx_char
            mvi a,'g'
            call uart_tx_char
            mvi a,'.'
            call uart_tx_char
            mvi a,'.'
            call uart_tx_char
            mvi a,'.'
            call uart_tx_char
            call print_crlf
            ret

;==============================================================================
; Subroutine: print_hex_byte
; Purpose: Print a byte in hexadecimal format (e.g., "3F")
; Input: A = byte to print
; Modifies: A, B, C
;==============================================================================
print_hex_byte:
            mov c,a               ; Save original byte

            ; Print high nibble
            rrc                   ; Rotate right 4 times to get high nibble
            rrc
            rrc
            rrc
            ani 0FH               ; Mask to get low 4 bits
            call print_hex_digit

            ; Print low nibble
            mov a,c               ; Restore original byte
            ani 0FH               ; Mask to get low 4 bits
            call print_hex_digit
            ret

;==============================================================================
; Subroutine: print_hex_digit
; Purpose: Print a single hex digit (0-F)
; Input: A = value 0-15
; Modifies: A
;==============================================================================
print_hex_digit:
            cpi 10                ; Is it 0-9 or A-F?
            jc print_digit_0_9    ; Jump if < 10

            ; Print A-F
            sui 10                ; Convert 10-15 to 0-5
            adi 'A'               ; Add ASCII 'A'
            call uart_tx_char
            ret

print_digit_0_9:
            adi '0'               ; Add ASCII '0'
            call uart_tx_char
            ret

;==============================================================================
; Hex Input Routines (ported from Jim Loos' monitor)
;==============================================================================

;------------------------------------------------------------------------
; convert an ascii character in A to its hex equivalent.
; return value in lower nibble, upper nibble zeros
; uses A and E.
;------------------------------------------------------------------------
ascii2hex:  cpi 'a'
            jc ascii2hex1           ; jump if already upper case...
            sui 20H                 ; else convert to upper case
ascii2hex1: sui 30H
            mov e,a                 ; save the result in E
            sui 0AH                 ; subtract 10 decimal
            jc  ascii2hex2
            mov a,e                 ; restore the value
            sui 7
            mov e,a
ascii2hex2: mov a,e
            ret

;------------------------------------------------------------------
; get an ASCII hex character 0-F in A from the serial port.
; echo the character if it's a valid hex digit.
; return with the carry flag set if ENTER, ESCAPE, or SPACE
; uses A, B, and E
;------------------------------------------------------------------
get_hex:    call uart_rx_char
            ani 01111111B           ; mask out most significant bit
            cpi 0DH
            jz get_hex3             ; jump if enter key
            cpi 1BH
            jz get_hex3             ; jump if escape key
            cpi 20H
            jz get_hex3             ; jump if space
            cpi '0'
            jc get_hex              ; try again if less than '0'
            cpi 'a'
            jc get_hex1             ; jump if already upper case...
            sui 20H                 ; else convert to upper case
get_hex1:   cpi 'G'
            jnc get_hex             ; try again if greater than 'F'
            cpi ':'
            jc get_hex2             ; continue if '0'-'9'
            cpi 'A'
            jc get_hex              ; try again if less than 'A'

get_hex2:   mov b,a                 ; save the character in B
            call uart_tx_char       ; echo the character
            xra a                   ; clear A to clear carry flag
            mov a,b                 ; restore the character
            ret                     ; return with carry cleared and character in A

get_hex3:   mov b,a
            mvi a,1
            rrc                     ; set carry flag
            mov a,b
            ret                     ; return with carry set and character in A

;------------------------------------------------------------------------
; get two hex digits from the serial port and convert them into a
; byte returned in A.  enter key exits if fewer than two digits.
; returns with carry flag set if escape key is pressed.
; uses A, B, C and E
;------------------------------------------------------------------------
get_two:    call get_hex            ; get the first character
            jc get_two5             ; jump if space, enter or escape

; the first character is a valid hex digit 0-F
            call ascii2hex          ; convert to hex nibble
            rlc                     ; rotate into the most significant nibble
            rlc
            rlc
            rlc
            ani 0F0H                ; mask out least significant nibble
            mov c,a                 ; save the first digit in C as the most significant nibble

            call get_hex            ; get the second character
            jnc get_two2
            cpi 0DH                 ; enter key?
            jnz get_two5            ; jump if space or escape
            mov a,c                 ; retrieve the first digit
            rrc                     ; rotate the first digit back to the least significant nibble
            rrc
            rrc
            rrc
            ani 0FH                 ; mask out the most significant nibble
            mov b,a                 ; save the first digit in B
            jmp get_two3

; the second character is a valid hex digit 0-F
get_two2:   call ascii2hex          ; convert to hex nibble
            ani 0FH                 ; mask out the most significant bits
            ora c                   ; combine the two nibbles
            mov b,a
get_two3:   xra a                   ; clear A to clear carry flag
            mov a,b
            ret

; return with carry flag set
get_two5:   mov b,a
            mvi a,1
            rrc                     ; set the carry flag
            mov a,b
            ret

;------------------------------------------------------------------------
; reads four hex digits from the serial port and converts them into two
; bytes returned in H and L.  enter key exits with fewer than four digits.
; returns with carry flag set if escape key is pressed.
; in addition to H and L, uses A, B, C and E.
;------------------------------------------------------------------------
get_four:   call get_hex            ; get the first character
            jnc get_four2           ; not space, enter nor escape
            cpi 1BH                 ; escape key?
            jnz get_four            ; go back for another try
get_four1:  mvi a,1
            rrc                     ; set the carry flag
            mvi a,1BH
            mvi h,0
            mvi l,0
            ret                     ; return with escape in A and carry set
; the first digit is a valid hex digit 0-F
get_four2:  call ascii2hex          ; convert to hex nibble
            rlc                     ; rotate into the most significant nibble
            rlc
            rlc
            rlc
            ani 0F0H                ; mask out least significant nibble
            mov l,a                 ; save the first nibble in L

; get the second character
get_four3:  call get_hex            ; get the second character
            jnc get_four5
            cpi 1BH                 ; escape key?
            jz get_four1
            cpi 0DH                 ; enter key?
            jnz get_four3
            mov a,l                 ; recall the first nibble from L
            rrc                     ; rotate back to least significant nibble
            rrc
            rrc
            rrc
            ani 0FH                 ; mask out most significant nibble
            mov l,a                 ; put the first digit in L
get_four4:  mvi h,0                 ; clear H
            xra a                   ; clear A to clear carry flag
            ret

; the second character is a valid hex digit 0-F
get_four5:  call ascii2hex          ; convert to hex nibble
            ani 0FH                 ; mask out the most significant bits
            ora l                   ; combine the two nibbles
            mov l,a                 ; save the first two digits in L

; the first two digits are in L. get the third character
get_four6:  call get_hex            ; get the third character
            jnc get_four7           ; not space, escape nor enter
            cpi 1BH                 ; escape key?
            jz get_four1
            cpi 0DH                 ; enter key?
            jnz get_four6           ; go back for another try
            jmp get_four4           ; exit with carry clear

; the third character is a valid hex digit 0-F
get_four7:  call ascii2hex          ; convert to hex nibble
            rlc                     ; rotate into the most significant nibble
            rlc
            rlc
            rlc
            ani 0F0H                ; mask out least significant nibble
            mov h,a                 ; save the nibble in H

; the first two digits are in L. the third digit is in H. get the fourth character
get_four8:  call get_hex            ; get the fourth character
            jnc get_four9
            cpi 1BH                 ; escape key?
            jz get_four1
            cpi 0DH                 ; enter key?
            jnz get_four8           ; go back for another try

; enter key pressed...
            mov a,h                 ; retrieve the third digit from H
            rrc                     ; rotate the third digit back to least significant nibble
            rrc
            rrc
            rrc
            ani 0FH                 ; mask out most significant nibble
            mov h,a
; the first two digits are in L, the third digit is in H
            mov b,h                 ; save the third digit in B
            mov c,l                 ; save the first two digits in C

            mov a,l
            rlc                     ; rotate the second digit to the most significant nibble
            rlc
            rlc
            rlc
            ani 0F0H                ; mask bits
            ora h                   ; combine the second and third digits
            mov l,a                 ; second and third digits now in L

            mov a,c                 ; get the first two digits from C
            rrc                     ; rotate the first digit to the least significant nibble
            rrc
            rrc
            rrc
            ani 0FH                 ; mask out the most significant bits
            mov h,a                 ; first digit now in H
            xra a                   ; clear A to clear carry flag
            ret

; the fourth character is a valid hex digit 0-F
get_four9:  call ascii2hex          ; convert to hex nibble
            ani 0FH                 ; mask out the most significant bits
            ora h                   ; combine the two nibbles
            mov c,l                 ; save the first two digits in C
            mov l,a                 ; save the last two digits in L
            mov h,c                 ; save the first two digits in H
            xra a                   ; clear A to clear carry flag
            ret

;==============================================================================
; Subroutine: debug_print_hl
; Purpose: Print H and L registers in format "[HL=XXYY]" for debugging
; Input: H, L = values to print
; Output: None
; Modifies: A, B, C (but preserves H, L)
;==============================================================================
debug_print_hl:
            ; Save H and L
            mov b,h
            mov c,l

            ; Print "[HL="
            mvi a,'['
            call uart_tx_char
            mvi a,'H'
            call uart_tx_char
            mvi a,'L'
            call uart_tx_char
            mvi a,'='
            call uart_tx_char

            ; Print H
            mov a,b
            call print_hex_byte

            ; Print L
            mov a,c
            call print_hex_byte

            ; Print "]"
            mvi a,']'
            call uart_tx_char

            ; Restore H and L
            mov h,b
            mov l,c
            ret

;==============================================================================
; Subroutine: to_upper
; Purpose: Convert lowercase letter to uppercase (a-z -> A-Z)
; Input: A = character
; Output: A = uppercase character (if input was lowercase), unchanged otherwise
; Modifies: A
;==============================================================================
to_upper:
            ; Check if character is lowercase (a-z)
            cpi 'a'
            jc to_upper_done      ; Less than 'a', not lowercase
            cpi 'z' + 1
            jnc to_upper_done     ; Greater than 'z', not lowercase

            ; Convert to uppercase by subtracting 32 (0x20)
            sui 20H               ; 'a' - 0x20 = 'A'

to_upper_done:
            ret

            end

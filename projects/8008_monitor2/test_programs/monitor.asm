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
            ; Point to buffer after command letter
            mvi h,0AH             ; H = high byte (0x0A00)
            mvi l,01H             ; L = low byte + 1 (skip 'R')
            call skip_spaces

            ; Parse 4-digit hex address
            call parse_hex_word
            jc cmd_read_error     ; Error if carry set

            ; D,E now contains the address

            ; Move to H,L for memory access
            mov h,d               ; H = high byte of address
            mov l,e               ; L = low byte of address

            ; Print result: "ADDR: XX\r\n"
            ; Print address (from H,L)
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
            call print_syntax_error
            jmp command_loop

;==============================================================================
; Command: Dump Memory ('D')
; Format: D <addr>
; Example: D 0800 -> dumps 16 bytes starting at 0x0800
;==============================================================================
cmd_dump_mem:
            ; Point to buffer after command letter
            mvi h,0AH             ; H = high byte (0x0A00)
            mvi l,01H             ; L = low byte + 1 (skip 'D')
            call skip_spaces

            ; Parse 4-digit hex address
            call parse_hex_word
            jc cmd_dump_error     ; Error if carry set

            ; D,E now contains the start address
            mov h,d               ; H = high byte of address
            mov l,e               ; L = low byte of address

            ; Print 16 bytes in format:
            ; ADDR: XX XX XX XX XX XX XX XX XX XX XX XX XX XX XX XX

            ; Print address (use H,L since we just copied D,E there)
            mov a,h
            call print_hex_byte
            mov a,l
            call print_hex_byte
            mvi a,':'
            call uart_tx_char
            mvi a,' '
            call uart_tx_char

            ; Print 16 bytes
            mvi d,16              ; Counter for 16 bytes (use D, it's free after move to H,L)

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
            call print_syntax_error
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
; Subroutine: parse_hex_digit
; Purpose: Convert ASCII hex character to value (0-15)
; Input: A = ASCII character ('0'-'9', 'A'-'F', 'a'-'f')
; Output: A = value 0-15, Carry flag clear if valid
;         Carry flag set if invalid character
; Modifies: A
;==============================================================================
parse_hex_digit:
            ; Check if '0'-'9'
            cpi '0'
            jc parse_hex_invalid  ; Less than '0'
            cpi '9' + 1
            jc parse_hex_digit_0_9

            ; Check if 'A'-'F'
            cpi 'A'
            jc parse_hex_invalid
            cpi 'F' + 1
            jc parse_hex_digit_upper

            ; Check if 'a'-'f'
            cpi 'a'
            jc parse_hex_invalid
            cpi 'f' + 1
            jc parse_hex_digit_lower

parse_hex_invalid:
            ; Set carry flag to indicate error
            mvi a,0FFH
            adi 1                 ; Set carry
            ret

parse_hex_digit_0_9:
            sui '0'               ; Convert to 0-9
            ret                   ; Carry is clear

parse_hex_digit_upper:
            sui 'A'               ; Convert to 0-5
            adi 10                ; Add 10 to get 10-15
            ret

parse_hex_digit_lower:
            sui 'a'               ; Convert to 0-5
            adi 10                ; Add 10 to get 10-15
            ret

;==============================================================================
; Subroutine: parse_hex_byte
; Purpose: Parse 2-character hex string from buffer to byte value
; Input: H,L = pointer to first hex character in buffer
; Output: A = parsed byte value
;         H,L = pointer advanced by 2
;         Carry flag set if parse error
; Modifies: A, B, H, L
;==============================================================================
parse_hex_byte:
            ; Parse high nibble
            mov a,m               ; A = first character
            call parse_hex_digit
            jc parse_byte_error   ; Error if carry set

            ; Shift to high nibble (rotate left 4 times)
            rlc
            rlc
            rlc
            rlc
            mov b,a               ; B = high nibble << 4

            ; Advance pointer
            inr l

            ; Parse low nibble
            mov a,m               ; A = second character
            call parse_hex_digit
            jc parse_byte_error   ; Error if carry set

            ; Combine nibbles
            ora b                 ; A = (high << 4) | low

            ; Advance pointer
            inr l

            ; Clear carry to indicate success
            ani 0FFH              ; Clears carry
            ret

parse_byte_error:
            mvi a,0FFH
            adi 1                 ; Set carry
            ret

;==============================================================================
; Subroutine: parse_hex_word
; Purpose: Parse 4-character hex string from buffer to 16-bit address
; Input: H,L = pointer to first hex character
; Output: D = high byte of address
;         E = low byte of address
;         H,L = pointer advanced by 4
;         Carry flag set if parse error
; Modifies: A, B, D, E, H, L
;==============================================================================
parse_hex_word:
            ; Parse high byte (first 2 chars)
            call parse_hex_byte
            jc parse_word_error
            mov d,a               ; D = high byte

            ; Parse low byte (next 2 chars)
            call parse_hex_byte
            jc parse_word_error
            mov e,a               ; E = low byte

            ; Clear carry to indicate success
            ani 0FFH
            ret

parse_word_error:
            mvi a,0FFH
            adi 1                 ; Set carry
            ret

;==============================================================================
; Subroutine: skip_spaces
; Purpose: Skip space characters in command buffer
; Input: H,L = pointer to current position in buffer
; Output: H,L = pointer to first non-space character
; Modifies: A, H, L
;==============================================================================
skip_spaces:
            mov a,m               ; A = current character
            cpi ' '               ; Is it a space?
            rnz                   ; If not space, return immediately

            ; It's a space, skip it
            inr l
            jmp skip_spaces       ; Loop to check next character

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

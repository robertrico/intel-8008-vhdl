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
;   ROM: 0x0000-0x0FFF (4KB)
;     - Code: 0x0000-0x0EFF
;     - Shift LUT: 0x0F00-0x0F0F (16 bytes, nibble << 4 lookup)
;   RAM: 0x1000-0x13FF (1KB)
;     - Command buffer: 0x1000-0x107F (128 bytes)
;     - cmd_length: 0x1080 (1 byte)
;     - temp_h: 0x1081 (1 byte)
;     - temp_l: 0x1082 (1 byte)
;     - value_buffer: 0x1083-0x1086 (4 bytes, parsed hex nibbles)

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
; RAM Variables (0x1000 area)
; cmd_buffer: 0x1000-0x107F - Command input buffer (128 bytes)
; cmd_length: 0x1080 - Current command length (1 byte)
; temp_h: 0x1081 - Temporary storage for H register (unused)
; temp_l: 0x1082 - Temporary storage for L register (unused)
; value_buffer: 0x1083-0x1086 - Parsed hex nibbles (4 bytes)
;==============================================================================
cmd_buf_h   equ 10H           ; High byte of command buffer address
cmd_buf_l   equ 00H           ; Low byte of command buffer address
cmd_len_h   equ 10H           ; High byte of length storage
cmd_len_l   equ 80H           ; Low byte of length storage
temp_h      equ 1081H
temp_l      equ 1082H
val_buf_h   equ 10H           ; High byte of value buffer (0x1083-0x1086)

;==============================================================================
; Entry Point (code continues from here after RST 0 vector jumps to main)
;==============================================================================
            org 0040H
main:
            ; Disable all interrupts (set mask to 0x00)
            mvi a,00H
            out 9                 ; Write to interrupt mask register (port 9)

            ; IMMEDIATE TEST: ORA C before anything else
            mvi a,30H             ; A = 0x30
            mvi c,04H             ; C = 0x04
            ora c                 ; A = 0x30 | 0x04 = should be 0x34
            mov b,a               ; Save result in B

            ; Run MOV diagnostic test (will print the ORA result)
            call test_mov_diagnostic

            ; Print startup banner
            call print_banner


;==============================================================================
; Main Loop
;==============================================================================
command_loop:
            ; Print prompt "8008>"
            call print_prompt

            ; Read a line of input (until CR)
            call read_line

            ; Process the command (first character in buffer)
            mvi h,cmd_buf_h       ; H = high byte of cmd_buffer address
            mvi l,cmd_buf_l       ; L = low byte of cmd_buffer address
            mov a,m               ; A = first character of command

            ; Skip empty commands (just Enter pressed)
            cpi 0DH               ; Check if first char is CR
            jz command_loop

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

            ; Check for 'P' - Print (register stress test)
            cpi 'P'
            jz cmd_print

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
; NOP - Does nothing, just returns to command loop
;==============================================================================
cmd_read_mem:
            jmp command_loop

;==============================================================================
; Command: Dump Memory ('D')
; NOP - Does nothing, just returns to command loop
;==============================================================================
cmd_dump_mem:
            jmp command_loop

;==============================================================================
; Command: Print ('P')
; Format: P <text>
; Purpose: Echo back the input text, but stress-test by cycling each character
;          through all registers (A→B→C→D→E→back to A) before printing
; This will help identify register clobbering issues
;==============================================================================
cmd_print:
            ; Point to buffer after command letter
            mvi h,cmd_buf_h             ; H = high byte (0x0A00)
            mvi l,01H             ; L = low byte + 1 (skip 'P')

print_loop:
            ; Load character from buffer
            mov a,m               ; A = character

            ; Check for end of line (CR, LF, or null)
            cpi 0DH               ; CR?
            jz print_done
            cpi 0AH               ; LF?
            jz print_done
            cpi 0                 ; Null?
            jz print_done

            ; Cycle through registers: A→B→C→D→E→A
            mov b,a               ; A → B
            mov a,b               ; B → A (verify)
            mov c,a               ; A → C
            mov a,c               ; C → A (verify)
            mov d,a               ; A → D
            mov a,d               ; D → A (verify)
            mov e,a               ; A → E
            mov a,e               ; E → A (verify)

            ; Now print the character (should still be intact)
            call uart_tx_char

            ; Move to next character
            inr l
            jmp print_loop

print_done:
            call print_crlf
            jmp command_loop

;==============================================================================
; Subroutine: uart_tx_char
; Purpose: Wait for TX ready and transmit character in A register
; Input: A = character to transmit
; Modifies: E (preserves A via E)
;==============================================================================
uart_tx_char:
            mov e,a               ; Save character to E
wait_tx:
            in 0                  ; Read TX status (port 0)
            ani 01H               ; Check tx_busy bit
            jnz wait_tx           ; If busy, keep waiting
            mov a,e               ; Restore character
            out 10                ; Send to TX data port
            ret

;==============================================================================
; Subroutine: uart_rx_line
; Purpose: Read characters until CR (0x0D), store in buffer at 0x0800
;          Echo each character as typed
; Modifies: A, B, H, L
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
            mvi h,cmd_buf_h             ; H = high byte of buffer address (0x0A00)
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
            mvi h,cmd_len_h       ; H = high byte of length storage
            mvi l,cmd_len_l       ; L = low byte of length storage
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
; Purpose: Print "Intel 8008 Monitor 2.0\r\n"
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
            mvi a,'3'
            call uart_tx_char
            call print_crlf
            ret

;==============================================================================
; Subroutine: print_you_said
; Purpose: Print "You said \""
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
; Subroutine: ascii2hex
; Purpose: Convert ASCII hex character ('0'-'9', 'A'-'F', 'a'-'f') to binary
; Input: A = ASCII character
; Output: A = hex value (0x00-0x0F), or 0xFF if invalid
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
; Subroutine: test_mov_diagnostic
; Purpose: Test parsing 4 hex characters and reading memory at those addresses
; Test 1: Write "1234" to cmd_buf, parse it, read memory at 0x1234
; Test 2: Write "1030" to cmd_buf, parse it, read memory at 0x1030
; Output: "1234=XX 1030=XX" where XX should be different values
; Modifies: A, B, C, D, E, H, L
;==============================================================================
test_mov_diagnostic:
            ; Diagnostic: Print ORA C result from boot (B register preserved from main)
            mvi a,'O'
            call uart_tx_char
            mvi a,'='
            call uart_tx_char
            mov a,b               ; B contains result from main's ORA C test
            call print_hex_byte
            mvi a,' '
            call uart_tx_char

            ; Diagnostic: Test SUI instruction with '4'
            mvi a,'4'             ; A = 0x34 (ASCII '4')
            sui '0'               ; A = 0x34 - 0x30 = should be 0x04
            mov b,a               ; Save result

            mvi a,'S'
            call uart_tx_char
            mvi a,'='
            call uart_tx_char
            mov a,b
            call print_hex_byte
            mvi a,' '
            call uart_tx_char

            ; Diagnostic: Test ascii_to_hex_nibble with '3'
            mvi a,'3'
            call ascii_to_hex_nibble
            mov b,a               ; Save result

            mvi a,'T'
            call uart_tx_char
            mvi a,'='
            call uart_tx_char
            mov a,b
            call print_hex_byte
            mvi a,' '
            call uart_tx_char

            ; Diagnostic: Test E register preservation
            mvi e,04H             ; Set E = 4
            mvi h,0FH             ; Do some operations that shouldn't touch E
            mvi l,03H
            mov a,m               ; Read from lookup table
            mov b,e               ; Get E value into B

            mvi a,'E'
            call uart_tx_char
            mvi a,'='
            call uart_tx_char
            mov a,b
            call print_hex_byte
            mvi a,' '
            call uart_tx_char

            ; Diagnostic: Test combining two nibbles (3 and 4 -> 0x34)
            mvi b,03H             ; High nibble = 3
            mvi c,04H             ; Low nibble = 4

            ; Combine using lookup table and ORA
            mov a,b               ; A = 3
            mov l,a               ; L = 3 (index into lookup table)
            mvi h,0FH             ; Point to shift_lut
            mov a,m               ; A = 0x30 (3 << 4)
            ora c                 ; A = 0x30 | 0x04 = 0x34
            mov b,a               ; Save result

            mvi a,'N'
            call uart_tx_char
            mvi a,'='
            call uart_tx_char
            mov a,b
            call print_hex_byte
            mvi a,' '
            call uart_tx_char

            ; Test 1: Write "D 1234" to cmd_buf and read memory at 0x1234
            ; Initialize buffer pointer
            mvi h,cmd_buf_h       ; H = 0x10 (high byte of cmd_buf)
            mvi l,cmd_buf_l       ; L = 0x00 (low byte of cmd_buf)

            ; Store "D 1234" character by character
            mvi a,'D'
            call store_char_in_buf
            mvi a,' '
            call store_char_in_buf
            mvi a,'1'
            call store_char_in_buf
            mvi a,'2'
            call store_char_in_buf
            mvi a,'3'
            call store_char_in_buf
            mvi a,'4'
            call store_char_in_buf

            ; Call stub to parse and read (returns dummy value in A)
            call parse_and_read
            mov b,a               ; Save result in B

            ; Print "1234="
            mvi a,'1'
            call uart_tx_char
            mvi a,'2'
            call uart_tx_char
            mvi a,'3'
            call uart_tx_char
            mvi a,'4'
            call uart_tx_char
            mvi a,'='
            call uart_tx_char

            ; Print hex value
            mov a,b               ; Restore result
            call print_hex_byte

            ; Print space separator
            mvi a,' '
            call uart_tx_char

            ; Test 2: Write "D 0204" to cmd_buf and read memory at 0x0204
            ; Reset buffer pointer
            mvi h,cmd_buf_h       ; H = 0x10
            mvi l,cmd_buf_l       ; L = 0x00

            ; Store "D 0204" character by character
            mvi a,'D'
            call store_char_in_buf
            mvi a,' '
            call store_char_in_buf
            mvi a,'0'
            call store_char_in_buf
            mvi a,'2'
            call store_char_in_buf
            mvi a,'0'
            call store_char_in_buf
            mvi a,'4'
            call store_char_in_buf

            ; Call stub to parse and read (returns dummy value in A)
            call parse_and_read
            mov b,a               ; Save result in B

            ; Print "0204="
            mvi a,'0'
            call uart_tx_char
            mvi a,'2'
            call uart_tx_char
            mvi a,'0'
            call uart_tx_char
            mvi a,'4'
            call uart_tx_char
            mvi a,'='
            call uart_tx_char

            ; Print hex value
            mov a,b               ; Restore result
            call print_hex_byte

            ; Print CRLF
            call print_crlf

            ret

;==============================================================================
; Subroutine: store_char_in_buf
; Purpose: Store character in A at buffer position HL and increment L
; Input: A = character to store, HL = buffer address
; Output: HL incremented to next position
; Modifies: L
;==============================================================================
store_char_in_buf:
            mov m,a               ; Store A at memory[HL]
            inr l                 ; Increment L to next position
            ret

;==============================================================================
; Subroutine: ascii_to_hex_nibble
; Purpose: Convert ASCII hex character to nibble value
; Input: A = ASCII character ('0'-'9', 'A'-'F', 'a'-'f')
; Output: A = nibble value (0x00-0x0F)
; Modifies: A
;==============================================================================
ascii_to_hex_nibble:
            ; Check if it's '0'-'9'
            cpi '0'
            jc invalid_hex        ; Less than '0' - invalid
            cpi '9'+1
            jc convert_digit      ; Between '0' and '9'

            ; Check if it's 'A'-'F'
            cpi 'A'
            jc invalid_hex        ; Between '9' and 'A' - invalid
            cpi 'F'+1
            jc convert_upper      ; Between 'A' and 'F'

            ; Check if it's 'a'-'f'
            cpi 'a'
            jc invalid_hex        ; Between 'F' and 'a' - invalid
            cpi 'f'+1
            jc convert_lower      ; Between 'a' and 'f'

invalid_hex:
            ; Return 0 for invalid characters
            mvi a,0
            ret

convert_digit:
            ; '0'-'9': subtract '0'
            sui '0'
            ret

convert_upper:
            ; 'A'-'F': subtract 'A' and add 10
            sui 'A'
            adi 10
            ret

convert_lower:
            ; 'a'-'f': subtract 'a' and add 10
            sui 'a'
            adi 10
            ret

;==============================================================================
; Subroutine: parse_and_read
; Purpose: Parse hex address from cmd_buf and read memory at that address
; Input: cmd_buf contains "D XXXX" where XXXX is hex address
; Output: A = memory byte at parsed address
; Modifies: A, B, C, D, H, L
; NOTE: Currently returns the low byte of parsed address as test data
;==============================================================================
parse_and_read:
            ; Parse 4 hex characters from cmd_buf[2..5] into HL
            ; Result will be in HL register pair

            ; Parse first hex digit (high nibble of H)
            mvi h,cmd_buf_h       ; Point to cmd_buf
            mvi l,02H             ; Offset 2 (first hex char after "D ")
            mov a,m               ; A = first hex char
            call ascii_to_hex_nibble  ; Convert to nibble
            mov b,a               ; Save in B

            ; Parse second hex digit (low nibble of H)
            mvi h,cmd_buf_h
            mvi l,03H             ; Offset 3
            mov a,m
            call ascii_to_hex_nibble
            mov c,a               ; Save in C

            ; Parse third hex digit (high nibble of L)
            mvi h,cmd_buf_h
            mvi l,04H             ; Offset 4
            mov a,m
            call ascii_to_hex_nibble
            mov d,a               ; Save in D

            ; Parse fourth hex digit (low nibble of L)
            mvi h,cmd_buf_h
            mvi l,05H             ; Offset 5
            mov a,m
            call ascii_to_hex_nibble
            mov e,a               ; Save in E (now we have all 4 nibbles: B,C,D,E)

            ; Combine nibbles into HL
            ; H = (B << 4) | C
            ; L = (D << 4) | E

            ; Combine high byte: H = (B << 4) | C
            ; Use lookup table at 0x0F00 to shift B left 4 bits
            mov a,b               ; A = high nibble of H
            mov l,a               ; Use as index
            mvi h,0FH             ; Point to shift_lut
            mov a,m               ; A = B << 4
            ora c                 ; A = (B << 4) | C
            mov b,a               ; Save high byte in B (reusing B after combining)

            ; Combine low byte: L = (D << 4) | E
            mov a,d               ; A = high nibble of L
            mov l,a               ; Use as index
            mvi h,0FH             ; Point to shift_lut
            mov a,m               ; A = D << 4
            ora e                 ; A = (D << 4) | E
            mov l,a               ; L = low byte of address

            ; Restore high byte from B
            mov h,b               ; H = high byte of address

            ; For now, return L (low byte) as the "memory value"
            ; TODO: Later we'll do: mov a,m to read actual memory
            mov a,l               ; Return low byte of parsed address
            ret

;==============================================================================
; Subroutine: print_hex_digit
; Purpose: Print a single hex digit (0-F)
; Input: A = value 0-15
; Output: Prints '0'-'9' or 'A'-'F'
; Modifies: A
;==============================================================================
print_hex_digit:
            cpi 10                ; Compare with 10 (is it 0-9 or A-F?)
            jc print_digit_0_9    ; Jump if A < 10 (carry set)

            ; Print A-F (value is 10-15)
            sui 10                ; Subtract 10 (convert 10-15 to 0-5)
            adi 'A'               ; Add ASCII 'A' (convert to 'A'-'F')
            call uart_tx_char
            ret

print_digit_0_9:
            ; Print 0-9 (value is 0-9)
            adi '0'               ; Add ASCII '0' (convert to '0'-'9')
            call uart_tx_char
            ret

;==============================================================================
; Subroutine: print_hex_byte
; Purpose: Print a byte in hexadecimal (2 hex digits)
; Input: A = byte to print
; Modifies: A, C
;==============================================================================
print_hex_byte:
            mov c,a               ; Save original byte in C

            ; Print high nibble (upper 4 bits)
            rrc                   ; Rotate right 4 times to get high nibble
            rrc
            rrc
            rrc
            ani 00001111B         ; Mask to get only low 4 bits (the shifted nibble)
            call print_hex_digit

            ; Print low nibble (lower 4 bits)
            mov a,c               ; Restore original byte
            ani 00001111B         ; Mask to get low 4 bits
            call print_hex_digit
            ret

;==============================================================================
; Lookup Table: Nibble Shift (at 0x0F00)
; Purpose: Convert nibble value (0-15) to shifted byte (0x00, 0x10, ..., 0xF0)
; Usage: Load nibble into A, use as offset: mvi h,0FH / mov l,a / mov a,m
;==============================================================================
            org 0F00H
shift_lut:
            db 00H                ; 0 << 4 = 0x00
            db 10H                ; 1 << 4 = 0x10
            db 20H                ; 2 << 4 = 0x20
            db 30H                ; 3 << 4 = 0x30
            db 40H                ; 4 << 4 = 0x40
            db 50H                ; 5 << 4 = 0x50
            db 60H                ; 6 << 4 = 0x60
            db 70H                ; 7 << 4 = 0x70
            db 80H                ; 8 << 4 = 0x80
            db 90H                ; 9 << 4 = 0x90
            db 0A0H               ; 10 << 4 = 0xA0
            db 0B0H               ; 11 << 4 = 0xB0
            db 0C0H               ; 12 << 4 = 0xC0
            db 0D0H               ; 13 << 4 = 0xD0
            db 0E0H               ; 14 << 4 = 0xE0
            db 0F0H               ; 15 << 4 = 0xF0

            end

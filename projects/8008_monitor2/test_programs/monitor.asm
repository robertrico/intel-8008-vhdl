; monitor.asm
; Intel 8008 Monitor Program - Phase 1: Minimal Monitor Core
;
; Functionality:
; 1. Print startup banner on boot
; 2. Enter command loop with "8008>" prompt
; 3. Accept single-character commands:
;    '?' - Help (list all commands)
;    'h' - Hello (print version banner)
;    'r' - Reset (software reset via interrupt)
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

.8008
.org 0x0000

;==============================================================================
; Entry Point
;==============================================================================
main:
    ; Disable all interrupts (set mask to 0x00)
    mvi a, 0x00
    out 9                 ; Write to interrupt mask register (port 9)

    ; Print startup banner
    call print_banner

;==============================================================================
; Main Command Loop
;==============================================================================
command_loop:
    ; Print prompt "8008>"
    call print_prompt

    ; Read single character command
    call uart_rx_char
    mov d, a              ; Save command in D (uart_tx_char uses B!)

    ; Echo the command character
    call uart_tx_char
    call print_crlf

    ; DEBUG: Print received character value in hex
    mvi a, 'R'
    call uart_tx_char
    mvi a, 'X'
    call uart_tx_char
    mvi a, '='
    call uart_tx_char
    mov a, d
    call print_hex_byte
    call print_crlf

    ; Dispatch command
    mov a, d              ; Restore command

    ; Check for '?' - Help
    ; DEBUG: Show comparison
    mvi a, '?'
    call uart_tx_char
    mvi a, '='
    call uart_tx_char
    mvi a, '?'
    call print_hex_byte
    mvi a, ' '
    call uart_tx_char

    mov a, d
    cpi '?'
    jz cmd_help

    ; Check for 'h' - Hello
    mvi a, 'h'
    call uart_tx_char
    mvi a, '='
    call uart_tx_char
    mvi a, 'h'
    call print_hex_byte
    mvi a, ' '
    call uart_tx_char

    mov a, d
    cpi 'h'
    jz cmd_hello

    ; Check for 'r' - Reset
    mvi a, 'r'
    call uart_tx_char
    mvi a, '='
    call uart_tx_char
    mvi a, 'r'
    call print_hex_byte
    call print_crlf

    mov a, d
    cpi 'r'
    jz cmd_reset

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
; Subroutine: uart_tx_char
; Purpose: Wait for TX ready and transmit character in A register
; Input: A = character to transmit
; Modifies: B (preserves A via B)
;==============================================================================
uart_tx_char:
    mov b, a              ; Save character to B
wait_tx:
    in 0                  ; Read TX status (port 0)
    ani 0x01              ; Check tx_busy bit
    jnz wait_tx           ; If busy, keep waiting
    mov a, b              ; Restore character
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
    ani 0x01              ; Check rx_ready bit
    jz wait_rx            ; If no data, keep waiting
    in 3                  ; Read RX data (port 3, clears rx_ready)
    ret

;==============================================================================
; Subroutine: print_crlf
; Purpose: Print carriage return and line feed
; Modifies: A
;==============================================================================
print_crlf:
    mvi a, 0x0D           ; CR
    call uart_tx_char
    mvi a, 0x0A           ; LF
    call uart_tx_char
    ret

;==============================================================================
; Subroutine: print_prompt
; Purpose: Print "8008> "
; Modifies: A
;==============================================================================
print_prompt:
    mvi a, '8'
    call uart_tx_char
    mvi a, '0'
    call uart_tx_char
    mvi a, '0'
    call uart_tx_char
    mvi a, '8'
    call uart_tx_char
    mvi a, '>'
    call uart_tx_char
    mvi a, ' '
    call uart_tx_char
    ret

;==============================================================================
; Subroutine: print_banner
; Purpose: Print "Intel 8008 Monitor v1.0\r\n"
; Modifies: A
;==============================================================================
print_banner:
    mvi a, 'I'
    call uart_tx_char
    mvi a, 'n'
    call uart_tx_char
    mvi a, 't'
    call uart_tx_char
    mvi a, 'e'
    call uart_tx_char
    mvi a, 'l'
    call uart_tx_char
    mvi a, ' '
    call uart_tx_char
    mvi a, '8'
    call uart_tx_char
    mvi a, '0'
    call uart_tx_char
    mvi a, '0'
    call uart_tx_char
    mvi a, '8'
    call uart_tx_char
    mvi a, ' '
    call uart_tx_char
    mvi a, 'M'
    call uart_tx_char
    mvi a, 'o'
    call uart_tx_char
    mvi a, 'n'
    call uart_tx_char
    mvi a, 'i'
    call uart_tx_char
    mvi a, 't'
    call uart_tx_char
    mvi a, 'o'
    call uart_tx_char
    mvi a, 'r'
    call uart_tx_char
    mvi a, ' '
    call uart_tx_char
    mvi a, 'v'
    call uart_tx_char
    mvi a, '1'
    call uart_tx_char
    mvi a, '.'
    call uart_tx_char
    mvi a, '0'
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
    mvi a, 'C'
    call uart_tx_char
    mvi a, 'o'
    call uart_tx_char
    mvi a, 'm'
    call uart_tx_char
    mvi a, 'm'
    call uart_tx_char
    mvi a, 'a'
    call uart_tx_char
    mvi a, 'n'
    call uart_tx_char
    mvi a, 'd'
    call uart_tx_char
    mvi a, 's'
    call uart_tx_char
    mvi a, ':'
    call uart_tx_char
    call print_crlf

    ; "  ? - Help\r\n"
    mvi a, ' '
    call uart_tx_char
    mvi a, ' '
    call uart_tx_char
    mvi a, '?'
    call uart_tx_char
    mvi a, ' '
    call uart_tx_char
    mvi a, '-'
    call uart_tx_char
    mvi a, ' '
    call uart_tx_char
    mvi a, 'H'
    call uart_tx_char
    mvi a, 'e'
    call uart_tx_char
    mvi a, 'l'
    call uart_tx_char
    mvi a, 'p'
    call uart_tx_char
    call print_crlf

    ; "  h - Hello\r\n"
    mvi a, ' '
    call uart_tx_char
    mvi a, ' '
    call uart_tx_char
    mvi a, 'h'
    call uart_tx_char
    mvi a, ' '
    call uart_tx_char
    mvi a, '-'
    call uart_tx_char
    mvi a, ' '
    call uart_tx_char
    mvi a, 'H'
    call uart_tx_char
    mvi a, 'e'
    call uart_tx_char
    mvi a, 'l'
    call uart_tx_char
    mvi a, 'l'
    call uart_tx_char
    mvi a, 'o'
    call uart_tx_char
    call print_crlf

    ; "  r - Reset\r\n"
    mvi a, ' '
    call uart_tx_char
    mvi a, ' '
    call uart_tx_char
    mvi a, 'r'
    call uart_tx_char
    mvi a, ' '
    call uart_tx_char
    mvi a, '-'
    call uart_tx_char
    mvi a, ' '
    call uart_tx_char
    mvi a, 'R'
    call uart_tx_char
    mvi a, 'e'
    call uart_tx_char
    mvi a, 's'
    call uart_tx_char
    mvi a, 'e'
    call uart_tx_char
    mvi a, 't'
    call uart_tx_char
    call print_crlf
    ret

;==============================================================================
; Subroutine: print_unknown
; Purpose: Print "Unknown command\r\n"
; Modifies: A
;==============================================================================
print_unknown:
    mvi a, 'U'
    call uart_tx_char
    mvi a, 'n'
    call uart_tx_char
    mvi a, 'k'
    call uart_tx_char
    mvi a, 'n'
    call uart_tx_char
    mvi a, 'o'
    call uart_tx_char
    mvi a, 'w'
    call uart_tx_char
    mvi a, 'n'
    call uart_tx_char
    mvi a, ' '
    call uart_tx_char
    mvi a, 'c'
    call uart_tx_char
    mvi a, 'o'
    call uart_tx_char
    mvi a, 'm'
    call uart_tx_char
    mvi a, 'm'
    call uart_tx_char
    mvi a, 'a'
    call uart_tx_char
    mvi a, 'n'
    call uart_tx_char
    mvi a, 'd'
    call uart_tx_char
    call print_crlf
    ret

;==============================================================================
; Subroutine: print_reset_msg
; Purpose: Print "Resetting...\r\n"
; Modifies: A
;==============================================================================
print_reset_msg:
    mvi a, 'R'
    call uart_tx_char
    mvi a, 'e'
    call uart_tx_char
    mvi a, 's'
    call uart_tx_char
    mvi a, 'e'
    call uart_tx_char
    mvi a, 't'
    call uart_tx_char
    mvi a, 't'
    call uart_tx_char
    mvi a, 'i'
    call uart_tx_char
    mvi a, 'n'
    call uart_tx_char
    mvi a, 'g'
    call uart_tx_char
    mvi a, '.'
    call uart_tx_char
    mvi a, '.'
    call uart_tx_char
    mvi a, '.'
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
    mov c, a              ; Save original byte

    ; Print high nibble
    rrc                   ; Rotate right 4 times to get high nibble
    rrc
    rrc
    rrc
    ani 0x0F              ; Mask to get low 4 bits
    call print_hex_digit

    ; Print low nibble
    mov a, c              ; Restore original byte
    ani 0x0F              ; Mask to get low 4 bits
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

.end

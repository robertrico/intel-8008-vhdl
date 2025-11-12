; uart_rx.asm
; Intel 8008 UART Receiver Test Program
;
; Functionality:
; 1. Print "Hello, Terminal!\r\n" on startup
; 2. Enter main loop:
;    - Print prompt "> "
;    - Read input line until CR (Enter key)
;    - Echo each character as typed
;    - When Enter pressed, print "You said \"[input]\"\r\n"
;    - Repeat
;
; I/O Ports:
;   Port 0 (IN):  TX Status (bit 0 = tx_busy)
;   Port 3 (IN):  RX Data (read clears rx_ready)
;   Port 4 (IN):  RX Status (bit 0 = rx_ready)
;   Port 10 (OUT): TX Data
;   Note: Ports 1 and 2 are reserved for interrupt controller
;
; Memory Map:
;   ROM: 0x0000-0x07FF
;   RAM: 0x0800-0x0BFF
;   Input buffer: 0x0800-0x08FF (256 bytes max)

.8008
.org 0x0000

;==============================================================================
; Entry Point
;==============================================================================
main:
    ; Disable all interrupts (set mask to 0x00)
    mvi a, 0x00
    out 9                 ; Write to interrupt mask register (port 9)

    ; Print startup message: "Hello, Terminal!\r\n"
    call print_hello

;==============================================================================
; Main Loop
;==============================================================================
main_loop:
    ; Print prompt "> "
    mvi a, '>'
    call uart_tx_char
    mvi a, ' '
    call uart_tx_char

    ; Read input line into buffer at 0x0800
    call uart_rx_line

    ; Print response "You said \""
    call print_you_said

    ; Echo the buffer contents
    call print_buffer

    ; Print closing quote and newline
    mvi a, '"'
    call uart_tx_char
    call print_crlf

    ; Repeat
    jmp main_loop

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
; Subroutine: uart_rx_line
; Purpose: Read characters until CR (0x0D), store in buffer at 0x0800
;          Echo each character as typed
; Modifies: A, B, H, L
;==============================================================================
uart_rx_line:
    mvi h, 0x08           ; H = 0x08
    mvi l, 0x00           ; L = 0x00 (HL = 0x0800, start of RAM)

rx_loop:
    ; Wait for RX data ready
    in 4                  ; Read RX status (port 4)
    ani 0x01              ; Check rx_ready bit
    jz rx_loop            ; If no data, keep waiting

    ; Read character
    in 3                  ; Read RX data (port 3, clears rx_ready)
    mov b, a              ; Save character to B

    ; Check for CR (Enter key = 0x0D)
    sui 0x0D
    jz rx_done            ; If CR, we're done

    ; Not CR, store character in buffer
    mov a, b              ; Restore character
    mov m, a              ; Store at (HL)
    inr l                 ; Increment L (HL++)

    ; Echo character back to terminal
    mov a, b
    call uart_tx_char

    ; Continue reading
    jmp rx_loop

rx_done:
    ; Store null terminator
    mvi a, 0x00
    mov m, a

    ; Echo CR+LF to terminal
    call print_crlf
    ret

;==============================================================================
; Subroutine: print_buffer
; Purpose: Print null-terminated string from buffer at 0x0800
; Modifies: A, H, L
;==============================================================================
print_buffer:
    mvi h, 0x08           ; H = 0x08
    mvi l, 0x00           ; L = 0x00 (HL = 0x0800)

print_loop:
    mov a, m              ; Load character from (HL)
    ora a                 ; Check if null (sets flags)
    rz                    ; Return if null
    call uart_tx_char     ; Transmit character
    inr l                 ; HL++
    jmp print_loop

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
; Subroutine: print_hello
; Purpose: Print "Hello, Terminal!\r\n"
; Modifies: A
;==============================================================================
print_hello:
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
    mvi a, ','
    call uart_tx_char
    mvi a, ' '
    call uart_tx_char
    mvi a, 'T'
    call uart_tx_char
    mvi a, 'e'
    call uart_tx_char
    mvi a, 'r'
    call uart_tx_char
    mvi a, 'm'
    call uart_tx_char
    mvi a, 'i'
    call uart_tx_char
    mvi a, 'n'
    call uart_tx_char
    mvi a, 'a'
    call uart_tx_char
    mvi a, 'l'
    call uart_tx_char
    mvi a, '!'
    call uart_tx_char
    call print_crlf
    ret

;==============================================================================
; Subroutine: print_you_said
; Purpose: Print "You said \""
; Modifies: A
;==============================================================================
print_you_said:
    mvi a, 'Y'
    call uart_tx_char
    mvi a, 'o'
    call uart_tx_char
    mvi a, 'u'
    call uart_tx_char
    mvi a, ' '
    call uart_tx_char
    mvi a, 's'
    call uart_tx_char
    mvi a, 'a'
    call uart_tx_char
    mvi a, 'i'
    call uart_tx_char
    mvi a, 'd'
    call uart_tx_char
    mvi a, ' '
    call uart_tx_char
    mvi a, '"'
    call uart_tx_char
    ret

.end

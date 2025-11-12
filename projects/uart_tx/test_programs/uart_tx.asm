; ================================================================================
; UART_TX.ASM - UART Transmitter Test Program
; ================================================================================
; Demonstrates UART transmission using Intel 8008 CPU
; Transmits "Hello, Terminal!" followed by newline
;
; Memory Map:
;   ROM: 0x0000-0x07FF (2KB)
;   RAM: 0x0800-0x0BFF (1KB)
;   I/O Port 0 (IN 0): UART TX status register (bit 0 = tx_busy)
;   I/O Port 10 (OUT 10): UART TX data register
;
; UART Configuration:
;   Baud rate: 9600
;   Data bits: 8
;   Parity: None
;   Stop bits: 1
;
; Expected behavior:
;   - Program transmits "Hello, Terminal!" followed by CR+LF
;   - Then enters infinite loop
;   - Each character is transmitted via UART TX
;   - Program waits for tx_busy flag to clear before sending next character
;
; ================================================================================

.8008

; ================================================================================
; MAIN PROGRAM - Entry Point
; ================================================================================
.org 0x0000
main:
    ; ============================================================================
    ; TRANSMIT MESSAGE STRING
    ; ============================================================================
    ; We'll transmit each character one by one
    ; The Intel 8008 doesn't have sophisticated memory addressing,
    ; so we'll load each character explicitly

    ; "H"
    mvi a, 0x48
    call uart_tx_char

    ; "e"
    mvi a, 0x65
    call uart_tx_char

    ; "l"
    mvi a, 0x6C
    call uart_tx_char

    ; "l"
    mvi a, 0x6C
    call uart_tx_char

    ; "o"
    mvi a, 0x6F
    call uart_tx_char

    ; ","
    mvi a, 0x2C
    call uart_tx_char

    ; " " (space)
    mvi a, 0x20
    call uart_tx_char

    ; "T"
    mvi a, 0x54
    call uart_tx_char

    ; "e"
    mvi a, 0x65
    call uart_tx_char

    ; "r"
    mvi a, 0x72
    call uart_tx_char

    ; "m"
    mvi a, 0x6D
    call uart_tx_char

    ; "i"
    mvi a, 0x69
    call uart_tx_char

    ; "n"
    mvi a, 0x6E
    call uart_tx_char

    ; "a"
    mvi a, 0x61
    call uart_tx_char

    ; "l"
    mvi a, 0x6C
    call uart_tx_char

    ; "!"
    mvi a, 0x21
    call uart_tx_char

    ; Carriage return (CR)
    mvi a, 0x0D
    call uart_tx_char

    ; Line feed (LF)
    mvi a, 0x0A
    call uart_tx_char

    ; ============================================================================
    ; DONE - ENTER INFINITE LOOP
    ; ============================================================================
done:
    jmp done                    ; Loop forever

; ================================================================================
; UART_TX_CHAR - Transmit single character via UART
; ================================================================================
; Input: A = character to transmit
; Modifies: A
;
; This subroutine:
;   1. Waits for UART to be ready (tx_busy = 0)
;   2. Writes character to UART data register (OUT 10)
;
uart_tx_char:
    ; Save character in B register (since we'll use A for status check)
    mov b, a

wait_tx_ready:
    ; Read UART status register (IN 0)
    ; Bit 0 = tx_busy (1 = busy, 0 = ready)
    in 0

    ; Check if tx_busy is set (bit 0)
    ; If A & 0x01 != 0, UART is busy, keep waiting
    ani 0x01                    ; Mask bit 0
    jnz wait_tx_ready           ; If non-zero (busy), keep waiting

    ; UART is ready, transmit character
    mov a, b                    ; Restore character from B
    out 10                      ; Write to UART data register

    ; Return
    ret

.end

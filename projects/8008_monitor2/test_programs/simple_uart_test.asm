; simple_uart_test.asm
; Simple UART test program for testbench
; Transmits "OK\r\n" and then loops forever
;
; I/O Ports:
;   Port 0 (IN):  TX Status (bit 0 = tx_busy)
;   Port 10 (OUT): TX Data

.8008
.org 0x0000

main:
    ; Print "OK\r\n"
    mvi a, 'O'
    call uart_tx_char
    mvi a, 'K'
    call uart_tx_char
    mvi a, 0x0D           ; CR
    call uart_tx_char
    mvi a, 0x0A           ; LF
    call uart_tx_char

loop:
    jmp loop              ; Loop forever

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

.end

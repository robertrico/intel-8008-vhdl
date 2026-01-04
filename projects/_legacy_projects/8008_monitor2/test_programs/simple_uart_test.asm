; simple_uart_test.asm
; Test program for parse_four_hex subroutine
; Tests ASCII to hex conversion and hex parsing
;
; I/O Ports:
;   Port 0 (IN):  TX Status (bit 0 = tx_busy)
;   Port 10 (OUT): TX Data
;
; Memory Map:
;   RAM: 0x0800-0x0BFF
;   Test buffer: 0x0800 (will contain "A5F3")

            cpu 8008new
            org 0000H

main:
            mvi a,00H
            out 9
            ; Write test string "1234" to buffer at 0x0800
            ; This will test small values: 1, 2, 3, 4
            mvi h,08H
            mvi l,00H
            mvi a,'1'
            mov m,a
            inr l
            mvi a,'2'
            mov m,a
            inr l
            mvi a,'3'
            mov m,a
            inr l
            mvi a,'4'
            mov m,a

            ; Parse 4 hex digits from buffer
            call parse_four_hex
            ; Result: HL should be 0x1234 (hardware shows 0x0204!)

            ; Print the result using print_four_hex
            call print_four_hex

            ; Print newline
            mvi a,0DH
            call uart_tx_char
            mvi a,0AH
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
            mov b,a               ; Save character to B
wait_tx:
            in 0                  ; Read TX status (port 0)
            ani 01H               ; Check tx_busy bit
            jnz wait_tx           ; If busy, keep waiting
            mov a,b               ; Restore character
            out 10                ; Send to TX data port
            ret

;==============================================================================
; Subroutine: ascii2hex
; Purpose: Convert ASCII hex character ('0'-'9', 'A'-'F', 'a'-'f') to binary
; Input: A = ASCII character
; Output: A = hex value (0x00-0x0F), or 0xFF if invalid
; Modifies: A
;==============================================================================
ascii2hex:
            ; Check if '0'-'9' (ASCII 0x30-0x39)
            cpi '0'
            jc ascii2hex_invalid  ; Less than '0'
            cpi ':'               ; ':' is one past '9' (0x3A)
            jc ascii2hex_digit    ; It's '0'-'9'

            ; Check if 'A'-'F' (ASCII 0x41-0x46)
            cpi 'A'
            jc ascii2hex_invalid  ; Less than 'A'
            cpi 'G'               ; 'G' is one past 'F'
            jc ascii2hex_upper    ; It's 'A'-'F'

            ; Check if 'a'-'f' (ASCII 0x61-0x66)
            cpi 'a'
            jc ascii2hex_invalid  ; Less than 'a'
            cpi 'g'               ; 'g' is one past 'f'
            jc ascii2hex_lower    ; It's 'a'-'f'

            ; Invalid character
ascii2hex_invalid:
            mvi a,0FFH
            ret

ascii2hex_digit:
            ; '0'-'9': subtract 0x30
            sui '0'
            ret

ascii2hex_upper:
            ; 'A'-'F': subtract 0x37 (0x41 - 0x0A)
            sui 'A'-10
            ret

ascii2hex_lower:
            ; 'a'-'f': subtract 0x57 (0x61 - 0x0A)
            sui 'a'-10
            ret

;==============================================================================
; Subroutine: hex2ascii
; Purpose: Convert hex nibble (0x00-0x0F) to ASCII hex character
; Input: A = hex value (0x00-0x0F)
; Output: B = ASCII character ('0'-'9' or 'A'-'F')
; Modifies: A, B
;==============================================================================
hex2ascii:
            mov b,a               ; Save original value
            cpi 10                ; Check if < 10
            jc hex2ascii_digit    ; It's 0-9

            ; It's A-F (10-15)
            mov a,b
            adi 'A'-10            ; Convert to 'A'-'F'
            mov b,a
            ret

hex2ascii_digit:
            ; It's 0-9
            mov a,b
            adi '0'               ; Convert to '0'-'9'
            mov b,a
            ret

;==============================================================================
; Subroutine: parse_four_hex
; Purpose: Parse 4 hex digits from buffer at 0x0800
; Output: H = high byte, L = low byte (HL = 16-bit value)
; Modifies: A, B, C, D, E, H, L
;==============================================================================
parse_four_hex:
            ; Point to buffer
            mvi h,08H
            mvi l,00H

            ; Get first digit
            mov a,m
            call ascii2hex
            mov d,a               ; D = first nibble (SWAPPED: was E)

            ; Shift left 4 bits (multiply by 16)
            rlc
            rlc
            rlc
            rlc
            nop                   ; TEST: Add delay between RLC and MOV
            nop
            nop
            mov e,a               ; E = first nibble << 4 (SWAPPED: was D)
            ora a                 ; Clear carry flag - TEST IF THIS BREAKS IT

            ; Get second digit
            inr l
            mov a,m
            call ascii2hex
            ora e                 ; Combine with first nibble (SWAPPED: was D)
            mov e,a               ; E = high byte complete (SWAPPED: was D)

            ; Get third digit
            inr l
            mov a,m
            call ascii2hex
            mov d,a               ; D = third nibble (SWAPPED: was E)

            ; Shift left 4 bits
            rlc
            rlc
            rlc
            rlc
            nop                   ; TEST: Add delay between RLC and MOV
            nop
            nop
            mov b,a               ; B = third nibble << 4 (SWAPPED: was C)

            ; Get fourth digit
            inr l
            mov a,m
            call ascii2hex
            ora b                 ; Combine with third nibble (SWAPPED: was C)
            mov l,a               ; L = low byte complete

            ; Set H to high byte
            mov h,e               ; SWAPPED: was D
            ret

;==============================================================================
; Subroutine: print_four_hex
; Purpose: Print 4 hex digits from HL register
; Input: H = high byte, L = low byte
; Modifies: A, B, C, D
;==============================================================================
print_four_hex:
            ; Save HL
            mov d,h
            mov c,l

            ; Print high byte (H)
            mov a,h
            ; Get high nibble
            rlc
            rlc
            rlc
            rlc
            ani 0FH
            call hex2ascii
            mov a,b
            call uart_tx_char

            ; Get low nibble of high byte
            mov a,d
            ani 0FH
            call hex2ascii
            mov a,b
            call uart_tx_char

            ; Print low byte (L)
            mov a,c
            ; Get high nibble
            rlc
            rlc
            rlc
            rlc
            ani 0FH
            call hex2ascii
            mov a,b
            call uart_tx_char

            ; Get low nibble of low byte
            mov a,c
            ani 0FH
            call hex2ascii
            mov a,b
            call uart_tx_char

            ret

            end

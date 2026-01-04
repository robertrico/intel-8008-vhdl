; ================================================================================
; CYLON_SINGLE.ASM - Button-Driven Cylon/Knight Rider LED Effect
; ================================================================================
; Creates a bouncing LED pattern (Cylon eye effect) on 8 LEDs
; Advances one step per button press (button-driven, not auto-running)
;
; Memory Map:
;   ROM: 0x0000-0x07FF (2KB)
;   RAM: 0x0800-0x0BFF (1KB) - used for stack and variables
;   I/O Port 0 (IN 0): Button input (bit 0 = button pressed pulse)
;   I/O Port 8 (OUT 8): LED bank (8 bits, active low)
;
; Expected behavior:
;   - Button press advances Cylon pattern one step
;   - Pattern: LED0 -> LED1 -> LED2 -> ... -> LED7 -> LED6 -> ... -> LED0
;   - No auto-run: LEDs only change on button press
;
; Active-low LED encoding:
;   0xFE = 11111110 = LED0 on
;   0xFD = 11111101 = LED1 on
;   0xFB = 11111011 = LED2 on
;   0xF7 = 11110111 = LED3 on
;   0xEF = 11101111 = LED4 on
;   0xDF = 11011111 = LED5 on
;   0xBF = 10111111 = LED6 on
;   0x7F = 01111111 = LED7 on
;
; ================================================================================

.8008
.org 0x0000

; ================================================================================
; RST 0 VECTOR - Interrupt Entry Point
; ================================================================================
rst0_vector:
    jmp main                    ; Jump to main program (handles startup interrupt)
    ; Note: JMP is 3 bytes (44 LL HH), fills the RST 0 vector perfectly

; ================================================================================
; LOOKUP TABLE - LED Patterns for Each Position
; ================================================================================
; Position 0-13 maps to full Cylon cycle:
; Forward: 0->1->2->3->4->5->6->7 (positions 0-7)
; Reverse: 6->5->4->3->2->1       (positions 8-13)
; Total 14 positions for complete cycle

.org 0x0010
led_patterns:
    .db 0xFE    ; Position 0: LED0
    .db 0xFD    ; Position 1: LED1
    .db 0xFB    ; Position 2: LED2
    .db 0xF7    ; Position 3: LED3
    .db 0xEF    ; Position 4: LED4
    .db 0xDF    ; Position 5: LED5
    .db 0xBF    ; Position 6: LED6
    .db 0x7F    ; Position 7: LED7
    .db 0xBF    ; Position 8: LED6 (reverse)
    .db 0xDF    ; Position 9: LED5 (reverse)
    .db 0xEF    ; Position 10: LED4 (reverse)
    .db 0xF7    ; Position 11: LED3 (reverse)
    .db 0xFB    ; Position 12: LED2 (reverse)
    .db 0xFD    ; Position 13: LED1 (reverse)

; ================================================================================
; CONSTANTS
; ================================================================================
; BUTTON_BIT = 0x01 (Bit 0 of input port 0)
; NUM_POSITIONS = 14 (Total positions in Cylon cycle)

; ================================================================================
; MAIN PROGRAM
; ================================================================================
.org 0x0030
main:
    ; Initialize position to 0 (LED0 on)
    mvi a, 0
    mov b, a                    ; B = current position (0-13)

    ; Display initial LED pattern (position 0)
    call display_position

cylon_loop:
    ; ============================================================================
    ; WAIT FOR BUTTON PRESS
    ; ============================================================================
wait_for_button:
    in 0                        ; Read input port 0
    ani 0x01                    ; Mask bit 0 (button pressed pulse)
    jz wait_for_button          ; Loop until button pressed (bit 0 = 1)

    ; ============================================================================
    ; ADVANCE POSITION
    ; ============================================================================
advance_position:
    ; Increment position (B register)
    mov a, b
    adi 1                       ; A = position + 1

    ; Check if we've reached the end of cycle (position 14)
    cpi 14                      ; Compare A with 14
    jnz position_ok             ; If not equal, position is valid

    ; Wrap around to position 0
    mvi a, 0

position_ok:
    mov b, a                    ; Save new position in B

    ; ============================================================================
    ; DISPLAY NEW POSITION
    ; ============================================================================
    call display_position

    ; Loop back to wait for next button press
    jmp cylon_loop

; ================================================================================
; DISPLAY_POSITION - Output LED pattern for current position
; ================================================================================
; Input: B = position (0-13)
; Modifies: A, H, L
;
; This subroutine looks up the LED pattern from the table and outputs it
;
display_position:
    ; Calculate address of LED pattern: led_patterns + position
    ; led_patterns is at address 0x0010
    mvi h, 0x00                 ; H = high byte of address
    mvi l, 0x10                 ; L = low byte (0x0010 = led_patterns base)

    ; Add position (B) to address (HL)
    mov a, b                    ; A = position
    add l                       ; A = L + position
    mov l, a                    ; L = updated address
    ; (No carry possible since position < 14 and base = 0x10)

    ; Load LED pattern from table
    ; Note: 8008 doesn't have (HL) addressing, need to use memory reference
    ; We'll use a different approach: direct addressing based on position

    ; Alternative: Use indexed lookup via jump table
    ; For simplicity, use conditional branches
    mov a, b                    ; A = position
    cpi 0
    jz pos_0
    cpi 1
    jz pos_1
    cpi 2
    jz pos_2
    cpi 3
    jz pos_3
    cpi 4
    jz pos_4
    cpi 5
    jz pos_5
    cpi 6
    jz pos_6
    cpi 7
    jz pos_7
    cpi 8
    jz pos_8
    cpi 9
    jz pos_9
    cpi 10
    jz pos_10
    cpi 11
    jz pos_11
    cpi 12
    jz pos_12
    cpi 13
    jz pos_13
    ; Should never reach here
    ret

pos_0:
    mvi a, 0xFE
    jmp output_led
pos_1:
    mvi a, 0xFD
    jmp output_led
pos_2:
    mvi a, 0xFB
    jmp output_led
pos_3:
    mvi a, 0xF7
    jmp output_led
pos_4:
    mvi a, 0xEF
    jmp output_led
pos_5:
    mvi a, 0xDF
    jmp output_led
pos_6:
    mvi a, 0xBF
    jmp output_led
pos_7:
    mvi a, 0x7F
    jmp output_led
pos_8:
    mvi a, 0xBF
    jmp output_led
pos_9:
    mvi a, 0xDF
    jmp output_led
pos_10:
    mvi a, 0xEF
    jmp output_led
pos_11:
    mvi a, 0xF7
    jmp output_led
pos_12:
    mvi a, 0xFB
    jmp output_led
pos_13:
    mvi a, 0xFD
    ; Fall through to output_led

output_led:
    out 8                       ; Output to LED port
    ret

.end

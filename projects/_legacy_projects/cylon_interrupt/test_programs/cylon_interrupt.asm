; ================================================================================
; CYLON_INTERRUPT.ASM - Interrupt-Driven Cylon/Knight Rider LED Effect
; ================================================================================
; Demonstrates Intel 8008 generic interrupt controller with button interrupts
;
; Interrupt Architecture:
;   RST 0 (0x000): Startup interrupt - initializes system
;   RST 1 (0x008): Button interrupt - advances Cylon pattern
;
; Memory Map:
;   ROM: 0x0000-0x07FF (2KB)
;   RAM: 0x0800-0x0BFF (1KB) - used for stack and variables
;   I/O Port 8 (OUT 8): LED bank (8 bits, active low)
;   I/O Port 9 (OUT 9): Interrupt mask register
;   I/O Port 1 (INP 1): Interrupt status register (read-only)
;   I/O Port 2 (INP 2): Active interrupt source (read-only)
;
; Interrupt Controller:
;   Source 0: Startup interrupt (auto-generated on reset)
;   Source 1: Button interrupt (edge-triggered, debounced)
;   Mask register: OUT 9 (bit 0=source 0, bit 1=source 1, etc.)
;
; Expected behavior:
;   - System initializes on startup interrupt (RST 0)
;   - Button press triggers interrupt (RST 1)
;   - ISR advances Cylon pattern one step
;   - Pattern: LED0 -> LED1 -> ... -> LED7 -> LED6 -> ... -> LED0
;
; Active-low LED encoding:
;   0xFE = 11111110 = LED0 on
;   0xFD = 11111101 = LED1 on
;   ... etc ...
;
; ================================================================================

.8008

; ================================================================================
; RST VECTOR TABLE - Interrupt Entry Points
; ================================================================================
; Intel 8008 RST vectors are at fixed addresses:
; RST 0 = 0x000, RST 1 = 0x008, RST 2 = 0x010, etc.
;
.org 0x0000
rst0_vector:
    jmp startup_isr             ; RST 0: Startup interrupt
    ; JMP is 3 bytes (44 LL HH), .org handles padding to next vector

.org 0x0008
rst1_vector:
    jmp button_isr              ; RST 1: Button interrupt
    ; JMP is 3 bytes (44 LL HH)

; ================================================================================
; LOOKUP TABLE - LED Patterns for Each Position
; ================================================================================
; Position 0-13 maps to full Cylon cycle
;
.org 0x0020
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
; GLOBAL VARIABLES (in RAM)
; ================================================================================
; Position counter stored at RAM address 0x0800
.org 0x0800
position_var:
    .db 0       ; Current position (0-13)

; ================================================================================
; STARTUP INTERRUPT SERVICE ROUTINE (RST 0)
; ================================================================================
; Called once on system reset to initialize the system
;
.org 0x0050
startup_isr:
    ; ============================================================================
    ; INITIALIZE INTERRUPT CONTROLLER
    ; ============================================================================
    ; Enable both source 0 (startup) and source 1 (button)
    ; Mask register: bit 0=source 0, bit 1=source 1
    mvi a, 0x03                 ; Enable sources 0 and 1 (bits 0,1)
    out 9                       ; Write to interrupt mask register

    ; ============================================================================
    ; INITIALIZE POSITION
    ; ============================================================================
    mvi a, 0                    ; Position = 0
    ; Store in RAM (Intel 8008 doesn't have simple memory write)
    ; We'll keep position in register B instead
    mov b, a                    ; B = current position

    ; ============================================================================
    ; DISPLAY INITIAL POSITION
    ; ============================================================================
    call display_position

    ; ============================================================================
    ; ENABLE INTERRUPTS AND WAIT
    ; ============================================================================
    ; Intel 8008 doesn't have explicit EI/DI instructions
    ; Interrupts are automatically enabled when not in interrupt acknowledge
    ; Simply enter infinite loop, waiting for button interrupts

idle_loop:
    ; Could add HLT instruction here if 8008 supported it
    ; Instead, just loop forever
    jmp idle_loop

; ================================================================================
; BUTTON INTERRUPT SERVICE ROUTINE (RST 1)
; ================================================================================
; Called when button is pressed (interrupt source 1)
; Advances the Cylon pattern by one position
;
.org 0x0100
button_isr:
    ; ============================================================================
    ; DEBUG: Flash all LEDs to confirm ISR is being called
    ; ============================================================================
    mvi a, 0x00                 ; All LEDs ON (active-low: 0=on, 1=off)
    out 8                       ; Light all LEDs (immediate visual feedback)

    ; ============================================================================
    ; SAVE CONTEXT (if needed)
    ; ============================================================================
    ; For this simple application, we only modify A, B, and use stack
    ; In real ISR, would save all registers to stack

    ; ============================================================================
    ; ADVANCE POSITION
    ; ============================================================================
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

    ; ============================================================================
    ; RESTORE CONTEXT AND RETURN
    ; ============================================================================
    ; In real ISR, would restore saved registers here

    ret                         ; Return from interrupt (RTI equivalent)

; ================================================================================
; DISPLAY_POSITION - Output LED pattern for current position
; ================================================================================
; Input: B = position (0-13)
; Modifies: A
; Preserves: B
;
; This subroutine looks up the LED pattern and outputs it to port 8
;
display_position:
    ; Use conditional branches to select LED pattern
    ; (Intel 8008 doesn't have indirect addressing via HL)
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

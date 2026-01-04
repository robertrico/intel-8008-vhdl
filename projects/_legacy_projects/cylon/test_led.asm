; Simple LED test - turn all LEDs on immediately
.8008
.org 0x0000

rst0_vector:
    jmp main

main:
    ; Turn all LEDs ON (active low, so output 0x00)
    mvi a, 0x00
    out 8

    ; Infinite loop
loop:
    jmp loop

.end

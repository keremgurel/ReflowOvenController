; ISR_example_DE1SoC.asm:
; a) Increments/decrements a BCD variable every half second using
;    an ISR for timer 2.  Uses SW0 to decide.  Also 'blinks' LEDR0 every
;    half a second.
; b) Generates a 2kHz square wave at pin P1.0 using an ISR for timer 0.
; c) In the 'main' loop it displays the variable incremented/decremented
;    using the ISR for timer 2 on the LCD and the 7-segment displays.
;    Also resets it to zero if the KEY1 pushbutton  is pressed.
; d) Controls the LCD using general purpose pins P0.0 to P0.6.  Pins P0.0
;    to P0.6 are configured as outputs.


$NOLIST
$MODDE1SOC
$LIST


CLK           EQU 22118400 ; Microcontroller system crystal frequency in Hz
TIMER0_RATE   EQU 4096     ; 2048Hz squarewave (peak amplitude of CEM-1203 speaker)
TIMER0_RELOAD EQU ((65536-(CLK/(12*TIMER0_RATE)))) ; The prescaler in the CV-8052 is 12 unlike the AT89LP51RC2 where is ; 1.
TIMER2_RATE   EQU 1000     ; 1000Hz, for a timer tick of 1ms this also sets the frequency for the pulse function. if   ; this is changed (may need to be increased for smoother temp gradient, depending on how finicky the oven is, then ; values out of 10 used by pulse function will have to be adjusted proportionally.
TIMER2_RELOAD EQU ((65536-(CLK/(12*TIMER2_RATE))))


; Reset vector
org 0x0000
    ljmp main


; External interrupt 0 vector (not used in this code)
org 0x0003
        reti


; Timer/Counter 0 overflow interrupt vector
org 0x000B
;        ljmp Timer0_ISR


; External interrupt 1 vector (not used in this code)
org 0x0013
        reti


; Timer/Counter 1 overflow interrupt vector (not used in this code)
org 0x001B
        reti


; Serial port receive/transmit interrupt vector (not used in this code)
org 0x0023 
        reti
        
; Timer/Counter 2 overflow interrupt vector
org 0x002B
;        ljmp Timer2_ISR


; In the 8051 we can define direct access variables starting at location 0x30 up to location 0x7F
dseg at 0x30
Count1ms:     ds 2 ; Used to determine when one second has passed
BCD_counter:  ds 1 ; The BCD counter incremented in the ISR


;Oven Control Variables
    pulse_ratio:      ds 1
    pulse_counter:    ds 1


;Temperature and Voltage Variables
    temperature_cold: ds 2
    voltage_cold:     ds 8
    Result_cold:      ds 4
    temperature_hot:  ds 2
    voltage_hot:      ds 8
    Result_hot:       ds 4
    temp_result:      ds 2
;State Machine Variables
start_button:     ds 1
FSM_state:        ds 1
temp_soak:        ds 1 ;  keeping the temperature at same level
time_soak:        ds 1 ; keeping the time at same level
temp_refl:        ds 1 ; let reflow (temperature)
time_refl:        ds 1 ; let reflow time)
temp_cooldown:    ds 1 ; NOT REALLY SURE IF I NEED THIS OR NOT IS DEFINED AS 60 ALREADY BY JESUS
; In FSM these are the variables we will use to determine the state.
temp_counter:     ds 1 ; temperature value
time_counter:     ds 1 ; time counter (in seconds)
count:            ds 1 ; count starts when KEY3 is pressed.
pwm:              ds 1 ; power 
menu_vector:      ds 1


;for math32.asm
x:                ds 4
y:                ds 4
bcd:              ds 5


; In the 8051 we have variables that are 1-bit in size.  We can use the setb, clr, jb, and jnb
; instructions with these variables.  This is how you define a 1-bit variable:


bseg


seconds_flag: dbit 1 ; Set to one in the ISR every time 1000 ms had passed
; For each pushbutton we have a flag.  The corresponding FSM will set this
; flag to one when a valid press of the pushbutton is detected.
Key1_flag: dbit 1 ; allows UI to scroll down/up in the menu bar
Key2_flag: dbit 1 ; allows UI to select one of the options: temp_soak, time_soak, temp_refl, time_refl 
Key3_flag: dbit 1 ; means START, transition from stage 0 to stage 1 , IF PRESSED AGAIN, SHOULD STOP 
Key0_flag: dbit 1 ; means RESET
alarm:     dbit 1 ; for beeper feedback
mf:        dbit 1


; Bits used to access the LTC2308
LTC2308_MISO bit 0xF8 ; Read only bit
LTC2308_MOSI bit 0xF9 ; Write only bit
LTC2308_SCLK bit 0xFA ; Write only bit
LTC2308_ENN  bit 0xFB ; Write only bit


cseg
; These 'equ' must match the wiring between the DE1-SoC board and the LCD!
; P0 is in connector JP2.  Check "CV-8052 Soft Processor in the DE1-SoC Board: Getting
; Started Guide" for the details.


;ADC pin assignment
THERMO_IN    equ ADC_IN4
COLD_JUNC_IN equ ADC_IN0


;LCD ports   
ELCD_RS equ P0.1
ELCD_RW equ P0.2
ELCD_E  equ P0.3  
ELCD_D4 equ P0.4
ELCD_D5 equ P0.5
ELCD_D6 equ P0.6
ELCD_D7 equ P0.7






FT93C66_CE   EQU P2.0  ; WARNING: shared with MCP3008!
FT93C66_MOSI EQU P2.1 
FT93C66_MISO EQU P2.2
FT93C66_SCLK EQU P2.3 


BAUD EQU 115200
;Other Pins


SOUND_OUT     equ P0.0
UPDOWN        equ SWA.0[a]
COLD_CHANNEL  equ #00000000B
HOT_CHANNEL   equ #00000100B[b][c]


$NOLIST
$include(LCD_4bit_DE1SoC.inc) ; A library of LCD related functions and utility macros
$include(math32.inc) 
$include(FT93C66_DE1SoC.inc)
$LIST


;                      1234567890123456    <- This helps determine the location of the counter
Initial_Message1:  db 'Temp:xxx*C State', 0 ; Displays on LCD
Initial_Message2:  db 'Run Time:XXXs  x', 0

main:
;initialiszitionbleh
mainLoop:

jmp mainLoop
end


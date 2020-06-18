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

CLK           EQU 33333333 ; Microcontroller system crystal frequency in Hz 
TIMER0_RATE   EQU 4096     ; 2048Hz squarewave (peak amplitude of CEM-1203 speaker)
TIMER0_RELOAD EQU ((65536-(CLK/(12*TIMER0_RATE)))) ; The prescaler in the CV-8052 is 12 unlike the AT89LP51RC2 where is ; 1.
TIMER2_RATE   EQU 1000     ; 1000Hz, for a timer tick of 1ms this also sets the frequency for the pulse function. if   ; this is changed (may need to be increased for smoother temp gradient, depending on how finicky the oven is, then ; values out of 10 used by pulse function will have to be adjusted proportionally.
TIMER2_RELOAD EQU ((65536-(CLK/(12*TIMER2_RATE))))
TIMER1_RELOAD EQU (256-((2*CLK)/(12*32*BAUD)))
BAUD EQU 57600

; Reset vector
org 0x0000
    ljmp main

; External interrupt 0 vector (not used in this code)
org 0x0003
	ljmp KEY1_ISR

; Timer/Counter 0 overflow interrupt vector
org 0x000B
	ljmp Timer0_ISR

; External interrupt 1 vector (not used in this code)
org 0x0013
	ljmp KEY2_ISR

; Timer/Counter 1 overflow interrupt vector (not used in this code)
org 0x001B
	reti

; Serial port receive/transmit interrupt vector (not used in this code)
org 0x0023 
	reti
	
; Timer/Counter 2 overflow interrupt vector
org 0x002B
	ljmp Timer2_ISR

; In the 8051 we can define direct access variables starting at location 0x30 up to location 0x7F
dseg at 0x30
Count1ms:     ds 1
BCD_counter:  ds 1 ; The BCD counter incremented in the ISR, set to 100ms intervals

; Oven Control Variables
pulse_ratio:      ds 1
pulse_counter:    ds 1

; Temperature and Voltage Variables
temp_result:      ds 2

; State Machine Variables
FSM_state:        ds 1
temp_soak:        ds 1
time_soak:        ds 1
temp_refl:        ds 1
time_refl:        ds 1
temp_cooldown:    ds 1
beeper_counter:   ds 1
count:            ds 1
seconds_counter:  ds 1
minutes_counter:  ds 1
Menu_Vector:      ds 1
da_variable:      ds 1 ; temporary variable used to display the decimal adjusted version of binary variables

; for math32.asm
x:                ds 4
y:                ds 4
bcd:              ds 5

;temperature_func.inc variables
t_temp: ds 2
te0: ds 2
te1: ds 2
te2: ds 2
te3: ds 2
te4: ds 2
t_hot: ds 2
t_cold: ds 2
t_den: ds 4
t_1: ds 4
t_2: ds 4
t_3: ds 4
t_4: ds 4


; In the 8051 we have variables that are 1-bit in size.  We can use the setb, clr, jb, and jnb
; instructions with these variables.  This is how you define a 1-bit variable:

bseg

tenth_second_flag: dbit 1
seconds_flag:      dbit 1 ; Set to one in the ISR every time 1000 ms had passed
Key1_flag:         dbit 1 ; allows UI to select and increase/decrease the variables in the menu
mf:                dbit 1
test_flag:         dbit 1 ; to test the pulse_oven function

; Bits used to access the LTC2308
LTC2308_MISO bit 0xF8 ; Read only bit
LTC2308_MOSI bit 0xF9 ; Write only bit
LTC2308_SCLK bit 0xFA ; Write only bit
LTC2308_ENN  bit 0xFB ; Write only bit

cseg
; These 'equ' must match the wiring between the DE1-SoC board and the LCD!
; P0 is in connector JP2.  Check "CV-8052 Soft Processor in the DE1-SoC Board: Getting
; Started Guide" for the details.

; ADC pin assignment
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

;LED assignments
LED0	equ	LEDRA.0
LED1	equ	LEDRA.1
LED2	equ	LEDRA.2
LED3	equ	LEDRA.3
LED4	equ	LEDRA.4
LED5	equ	LEDRA.5
LED6	equ	LEDRA.6
LED7	equ	LEDRA.7
LED8	equ	LEDRA.8
LED9	equ	LEDRA.9

; DE1_SoC buttons
button1 equ KEY.1
button2 equ KEY.2
button3 equ KEY.3

FT93C66_CE   EQU P2.0 ; WARNING: shared with MCP3008!
FT93C66_MOSI EQU P2.1 
FT93C66_MISO EQU P2.2
FT93C66_SCLK EQU P2.3   

; BAUD EQU 115200

; Other Pins
SOUND_OUT    equ P0.0
SSR_box      equ P1.0
KEY_1        equ INT0
KEY_2        equ INT1
UP_DOWN      equ SWA.0
COLD_CHANNEL equ #00000000B
HOT_CHANNEL  equ #00000100B

; Look-up table for the 7-seg displays. (Segments are turn on with zero) 
T_7seg:
    DB 40H, 79H, 24H, 30H, 19H, 12H, 02H, 78H, 00H, 10H

$NOLIST
$include(LCD_4bit_DE1SoC.inc) ; A library of LCD related functions and utility macros
$include(math32.inc) 
$include(FT93C66_DE1SoC.inc)
$include(temperature_func.inc) ; temperature library
$LIST

		; 0123456789ABCDEF
Initial_Message1:  db '    *C State:   ', 0 ; Displays on LCD
Initial_Message2:  db 'Run Time:  :    ', 0
Menu_1_Message:    db 'Soak Temp:    *C', 0
Menu_2_Message:    db 'Soak Time:    s ', 0
Menu_3_Message:    db 'Refl Temp:    *C', 0
Menu_4_Message:    db 'Refl Time:    s ', 0
CLEAR_LCD_ROW:     db '                ', 0
State0_Message:    db '0  ', 0
State1_Message:    db 'STe', 0
State2_Message:    db 'STi', 0
State3_Message:    db 'RTe', 0
State4_Message:    db 'RTi', 0
State5_Message:    db 'CDN', 0

;------------------------------;
; Routine to initialize the ISR;
; for timer 0                  ;
;------------------------------;
Timer0_Init:
    mov a, TMOD
    anl a, #0xf0 ; Clear the bits for timer 0
    orl a, #0x01 ; Configure timer 0 as 16-timer
    mov TMOD, a
    mov TH0, #high(TIMER0_RELOAD)
    mov TL0, #low(TIMER0_RELOAD)
    ; Enable the timer and interrupts
    setb ET0  ; Enable timer 0 interrupt
    setb TR0  ; Start timer 0
    ret

;---------------------------------;
; ISR for timer 0.  Set to execute;
; every 1/4096Hz to generate a    ;
; 2048 Hz square wave at pin P3.7 ;
;---------------------------------;
Timer0_ISR:
    ;clr TF0  ; According to the data sheet this is done for us already.
    mov TH0, #high(TIMER0_RELOAD) ; Timer 0 doesn't have auto reload in the CV-8052
    mov TL0, #low(TIMER0_RELOAD)
    cpl SOUND_OUT ; Connect speaker to P0.0!
    reti

;------------------------------;
; Routine to initialize the ISR;
; for timer 2                  ;
;------------------------------;
Timer2_Init:
    mov T2CON, #0 ; Stop timer/counter.  Autoreload mode.
    mov TH2, #high(TIMER2_RELOAD)
    mov TL2, #low(TIMER2_RELOAD)
    ; Set the reload value
    mov RCAP2H, #high(TIMER2_RELOAD)
    mov RCAP2L, #low(TIMER2_RELOAD)
    ; Init One millisecond interrupt counter.
    clr a
    mov Count1ms, a
    ; Enable the timer and interrupts
    setb ET2  ; Enable timer 2 interrupt
    setb TR2  ; Enable timer 2
    ret

;----------------;
; ISR for timer 2;
;----------------;
Timer2_ISR:
    clr TF2  ; Timer 2 doesn't clear TF2 automatically. Do it in ISR

    ; The two registers used in the ISR must be saved in the stack
    push acc
    push psw
    inc Count1ms
    mov a, Count1ms
    cjne a, #100, Timer2_ISR_done ; Warning: this instruction changes the carry flag!

    ; 100 ms have passed
    setb tenth_second_flag
    mov a, pulse_counter
    add a, #0x01
    mov pulse_counter, a
    cjne a, #10, end_pulse_check
    mov pulse_counter, #0x00

end_pulse_check:
    clr a ; Reset to zero the milli-seconds counter
    mov Count1ms, a
    ; Modify the BCD counter
    mov a, BCD_counter
    add a, #0x01
    cjne a, #0x0A, Update_BCD_Counter
    setb seconds_flag
    mov a, #0x00
    mov BCD_counter, a
    mov a, seconds_counter
    add a, #0x01
    cjne a, #0x3C, Update_seconds_counter
    mov a, #0x00
    mov seconds_counter, a
    mov a, minutes_counter
    add a, #0x01
    mov minutes_counter, a
    sjmp Timer2_ISR_done

Update_BCD_Counter:	
    mov BCD_counter, a
    sjmp Timer2_ISR_done

Update_seconds_counter:
    mov seconds_counter, a

Timer2_ISR_done:
    pop psw
    pop acc
    reti

;------------------------------;
;Other initialization functions;
;------------------------------;
Initialize_Serial_Port:
	; Configure serial port and baud rate
	clr TR1 ; Disable timer 1
	anl TMOD, #0x0f ; Mask the bits for timer 1
	orl TMOD, #0x20 ; Set timer 1 in 8-bit auto reload mode
    orl PCON, #80H ; Set SMOD to 1
	mov TH1, #low(TIMER1_RELOAD)
	mov TL1, #low(TIMER1_RELOAD) 
	setb TR1 ; Enable timer 1
	mov SCON, #52H
	ret



Initialize_ADC:
    ; Initialize SPI pins connected to LTC2308
    clr LTC2308_MOSI
    clr LTC2308_SCLK
    setb LTC2308_ENN
    ret

Interrupt_init:
    setb EX0
    setb EX1
    clr IT0
    clr IT1
    ret

;----------;
;Other ISRs;
;----------;
KEY1_ISR: ; modify current variable
    push acc
    push psw
    Wait_Milli_Seconds(#50) ; Debounce delay.
    jnb KEY_1, KEY1_ISR_END
    setb Key1_flag
	
KEY1_ISR_END:
    pop psw
    pop acc
    reti

KEY2_ISR: ; select variable to modify
    push acc
    push psw
    Wait_Milli_Seconds(#50) ; Debo5tt5unce delay.
    jnb KEY_2, KEY2_ISR_END
    mov a, Menu_Vector
    add a, #0x01
    cjne a, #0x05, Update_MV ; we have 5 menus
    mov Menu_Vector, #0x00
    sjmp KEY2_ISR_END

Update_MV:
    mov Menu_Vector, a

KEY2_ISR_END:
    pop psw
    pop acc
    reti

;-----------;
;Menu States;
;-----------;
LONG_MENU2:
    ljmp MENU2

MENU1: ; soak temperature SHOULD BE CHOSEN BETWEEN 130 *C AND 170 *C!!!!!!!
    mov a, Menu_Vector ; checks menu_vector to see if we should stay or move to next state
    cjne a, #0x01, LONG_MENU2
    Set_Cursor(1, 1)
    Send_Constant_String(#menu_1_Message)
    lcall clear_math
    mov a, temp_soak
    mov x+0, a
    lcall hex2bcd
    mov a, bcd+0
    mov da_variable, a
    Set_Cursor(1, 13)
    Display_BCD(da_variable)
    mov a, bcd+1
    mov da_variable, a
    Set_Cursor(1, 11)
    Display_BCD(da_variable)
    Wait_Milli_Seconds(#50)
    jnb Key1_flag, MENU1 ;detects if the KEY1 is pressed (low signal) or not, if not just stay in menu1

    clr Key1_flag
    jnb UP_DOWN, M1_INC 
    mov a, temp_soak
    subb a, #0x01
    cjne a, #0x81, M1_END
    mov a, #0xAA
    sjmp M1_END

M1_INC:
    mov a, temp_soak
    add a, #0x01
    cjne a, #0xAB, M1_END
    mov a, #0x82

M1_END:
    mov temp_soak, a
    ljmp MENU1

LONG_MENU3:
    ljmp MENU3

MENU2: ; soak time SHOULD BE BETWEEN 60 AND 120
    mov a, Menu_Vector
    cjne a, #0x02, LONG_MENU3
    Set_Cursor(1, 1)
    Send_Constant_String(#menu_2_Message)
    lcall clear_math
    mov a, time_soak
    mov x+0, a
    lcall hex2bcd
    mov a, bcd+0
    mov da_variable, a
    Set_Cursor(1, 13)
    Display_BCD(da_variable)
    mov a, bcd+1
    mov da_variable, a
    Set_Cursor(1, 11)
    Display_BCD(da_variable)
    Wait_Milli_Seconds(#50)
    jnb Key1_flag, MENU2

    clr Key1_flag
    jnb UP_DOWN, M2_INC
    mov a, time_soak
    subb a, #0x01
    cjne a, #0x3B, M2_END
    mov a, #0x78
    ljmp M2_END

M2_INC:
    mov a, time_soak
    add a, #0x01
    cjne a, #0x79, M2_END
    mov a, #0x3C

M2_END:
    mov time_soak, a
    ljmp MENU2

LONG_MENU4:
    ljmp MENU4

MENU3: ; reflow temperature INITIALIZED WITH 217 IN MAIN SHOULD BE CHOSEN BETWEEN 217-223
    mov a, Menu_Vector
    cjne a, #0x03, LONG_MENU4
    Set_Cursor(1, 1)
    Send_Constant_String(#menu_3_Message)
    lcall clear_math
    mov a, temp_refl
    mov x+0, a
    lcall hex2bcd
    mov a, bcd+0
    mov da_variable, a
    Set_Cursor(1, 13)
    Display_BCD(da_variable)
    mov a, bcd+1
    mov da_variable, a
    Set_Cursor(1, 11)
    Display_BCD(da_variable)
    Wait_Milli_Seconds(#50)
    jnb Key1_flag, MENU3

    clr Key1_flag
    jnb UP_DOWN, M3_INC
    mov a, temp_refl
    subb a, #0x01
    cjne a, #0xD8, M3_END
    mov a, #0xDF
    sjmp M3_END

M3_INC:
    mov a, temp_refl
    add a, #0x01
    cjne a, #0xE0, M3_END
    mov a, #0xD9

M3_END:
    mov temp_refl, a
    ljmp MENU3

LONG_MENU0:
    lcall SAVE_VARIABLES
    ljmp MENU0

MENU4: ; reflow time INITIALIZED WITH 45 SECS IN MAIN SHOULD BE CHOSEN BETWEEN 45-75 SECS
    mov a, Menu_Vector
    cjne a, #0x04, LONG_MENU0
    Set_Cursor(1, 1)
    Send_Constant_String(#menu_4_Message)
    lcall clear_math
    mov a, time_refl
    mov x+0, a
    lcall hex2bcd
    mov a, bcd+0
    mov da_variable, a
    Set_Cursor(1, 13)
    Display_BCD(da_variable)
    mov a, bcd+1
    mov da_variable, a
    Set_Cursor(1, 11)
    Display_BCD(da_variable)
    Wait_Milli_Seconds(#50)
    jnb Key1_flag, MENU4

    clr Key1_flag
    jnb UP_DOWN, M4_INC
    mov a, time_refl
    subb a, #0x01
    cjne a, #0x2C, M4_END
    mov a, #0x4B
    sjmp M4_END

M4_INC:
    mov a, time_refl
    add a, #0x01
    cjne a, #0x4C, M4_END
    mov a, #0x2D

M4_END:
    mov time_refl, a
    ljmp MENU4

;------------------;
;Reflow Oven States;
;------------------;
SAFETY_CHECK:
    mov a, #50
    clr c
    subb a, temp_result
    jc state1_done
    mov a, #1
    lcall Beeper_Feedback
    ljmp MENU0

;--------------------------------------------------------;
;State 1: Initial ramp up to soak temperature (temp_soak);
;--------------------------------------------------------;
state1:
    mov a, FSM_state
    cjne a, #0x01, state2
    setb SSR_box
    jb Key1_flag, FSM_MENU0 ; check for reset button
    jnb seconds_flag, state1
    clr seconds_flag
    mov a, count
    add a, #0x01
    mov count, a
    cjne a, #60, SAFETY_DONE
    sjmp SAFETY_CHECK

SAFETY_DONE:
    mov a, temp_soak
    clr c ; 8051 doesn’t have a N flag, so I’m using the carry flag (it has helpful functions related to it)
    subb a, temp_result ; this sets the carry flag 1 if a borrow is required(temp>150) or 0 otherwise
    jnc state1_done ; if carry flag = 0, go to state1_done
    mov FSM_state, #2
    clr SSR_box
    mov count, #0x00
    mov a, #0
    lcall Beeper_Feedback

state1_done:
    lcall UPDATE_LCD
    sjmp state1

;----------------------------------------------;
;State2: stay at constant temp_soak temperature;
;----------------------------------------------;
state2:
    mov a, FSM_state
    cjne a, #0x02, state3
    lcall pulse_oven
    jb Key1_flag, FSM_MENU0
    jnb seconds_flag, state2
    clr seconds_flag
    mov a, count
    add a, #0x01
    mov count, a
    cjne a, time_soak, state2_done
    mov FSM_state, #3
    clr SSR_box
    mov count, #0x00
    mov a, #0
    lcall Beeper_Feedback

state2_done:
    lcall UPDATE_LCD
    sjmp state2

;--------------------------------------------------;
;State 3: Ramp up to reflow temperature (temp_refl);
;--------------------------------------------------;
state3:
    mov a, FSM_state
    cjne a, #0x03, state4
    setb SSR_box
    jb Key1_flag, FSM_MENU0
    jnb seconds_flag, state3
    clr seconds_flag
    mov a, temp_refl ; based on the reflow temperature chosen by UI
    clr c
    subb a, temp_result
    jnc state3_done
    mov FSM_state, #4
    clr SSR_box
    mov a, #0
    lcall Beeper_Feedback
	
state3_done:
    lcall UPDATE_LCD
    sjmp state3

FSM_MENU0:
    clr Key1_flag
    ljmp MENU0

;----------------------------------------------------------------------------------;
;state 4: maintain the reflow temperature for a certain time (temp_refl, time_refl);
;----------------------------------------------------------------------------------;
state4:
    mov a, FSM_state
    cjne a, #0x04, state5
    lcall pulse_oven
    jb Key1_flag, FSM_MENU0
    jnb seconds_flag, state4
    clr seconds_flag
    mov a, count
    add a, #0x01
    mov count, a
    cjne a, time_refl, state4_done
    mov FSM_state, #5
    clr SSR_box
    mov count, #0x00
    mov a, #1
    lcall Beeper_Feedback

state4_done:
    lcall UPDATE_LCD
    sjmp state4

;-----------------;
;state 5: cooldown;
;-----------------;
state5:
    mov a, FSM_state
    cjne a, #0x05, FSM_MENU0
    jb Key1_flag, FSM_MENU0
    jnb seconds_flag, state5
    clr seconds_flag
    clr c
    mov a, temp_result
    subb a, temp_cooldown
    jnc state5_done
    mov FSM_state, #0x00

end_loop:
    jnb seconds_flag, end_loop
    clr seconds_flag
    mov a, #0x00
    lcall Beeper_Feedback
    mov a, count
    add a, #0x01
    mov count, a
    cjne a, #6, end_loop
    mov count, #0x00

state5_done:
    lcall UPDATE_LCD
    sjmp state5

;---------------;
;other functions;
;---------------;

UPDATE_LCD:
    Set_Cursor(1, 1)
    Send_Constant_String(#Initial_Message1)
    Set_Cursor(2,1)
    Send_Constant_String(#Initial_Message2)
    lcall clear_math
    mov a, seconds_counter
    mov x+0, a
    lcall hex2bcd
    mov a, bcd+0
    mov da_variable, a
    Set_Cursor(2, 13)
    Display_BCD(da_variable)
    mov a, minutes_counter
    mov x+0, a
    lcall hex2bcd
    mov a, bcd+0
    mov da_variable, a
    Set_Cursor(2, 10)
    Display_BCD(da_variable)
    Set_Cursor(1, 14)
    mov a, FSM_state
    cjne a, #1, ST2
    Send_Constant_String(#State1_Message)
    sjmp UPDATE_LCD_END
ST2:
    cjne a, #2, ST3
    Send_Constant_String(#State2_Message)
    sjmp UPDATE_LCD_END
ST3:
    cjne a, #3, ST4
    Send_Constant_String(#State3_Message)
    sjmp UPDATE_LCD_END
ST4:
    cjne a, #4, ST5
    Send_Constant_String(#State4_Message)
    sjmp UPDATE_LCD_END
ST5:
    cjne a, #5, ST0
    Send_Constant_String(#State5_Message)
    sjmp UPDATE_LCD_END
ST0:
    Send_Constant_String(#State0_Message)

UPDATE_LCD_END:
    lcall display_temp
    ret

    ; PARAMETERS:
    ; pulse_ratio: out of 10, is the ratio of time that the oven should be on versus off
    ; pulse_counter: increments every time the time TR2 interrupt is called
pulse_oven:
    clr c
    mov a, pulse_ratio
    subb a, pulse_counter
    jc to_turn_off
    setb SSR_box
    ret

to_turn_off:
    clr SSR_box
    ret

SAVE_VARIABLES:
    lcall FT93C66_Write_Enable
    mov DPTR, #0x0000
    ; Save variables
    mov a, temp_soak
    lcall FT93C66_Write
    inc DPTR
    mov a, time_soak
    lcall FT93C66_Write
    inc DPTR
    mov a, temp_refl
    lcall FT93C66_Write
    inc DPTR
    mov a, time_refl
    lcall FT93C66_Write
    inc DPTR
    mov a, #0x55
    ; First key value
    lcall FT93C66_Write
    inc DPTR
    mov a, #0xAA
    ; Second key value
    lcall FT93C66_Write
    lcall FT93C66_Write_Disable
    ret

LOAD_VARIABLES:
    mov dptr, #0x0004
    ; First key value location.  Must be 0x55
    lcall FT93C66_Read
    cjne a, #0x55, Load_Defaults
    inc dptr
    ; Second key value location.  Must be 0xAA
    lcall FT93C66_Read
    cjne a, #0xAA, Load_Defaults
    ; Keys are good.  Load saved values.
    mov dptr, #0x0000
    lcall FT93C66_Read
    mov temp_soak, a
    inc dptr
    lcall FT93C66_Read
    mov time_soak, a
    inc dptr
    lcall FT93C66_Read
    mov temp_refl, a
    inc dptr
    lcall FT93C66_Read
    mov time_refl, a
    ret

Load_Defaults:
    mov temp_soak, #130 
    mov time_soak, #60
    mov temp_refl, #217 ; isn’t really given a space in the slides
    mov time_refl, #45
    ljmp MENU0

RESET_VARIABLES:
    mov BCD_counter, #0x00
    mov count, #0x00
    mov beeper_counter, #0x00
    mov seconds_counter, #0x00
    mov minutes_counter, #0x00
    mov pulse_counter, #0x00
    mov pulse_ratio, #0x02 ; 30% on, 70% off
    mov FSM_state, #0x00
    lcall UPDATE_LCD
    clr LEDRA.0
    clr LEDRA.1
    clr LEDRA.2
    clr LEDRA.3
    clr LEDRA.4
    clr LEDRA.5
    clr LEDRA.6
    clr LEDRA.7
   ;clr LEDRA.8
   ;clr LEDRA.9
    clr tenth_second_flag
    clr seconds_flag
    clr TR0
    clr SSR_box
    ret

BEEPER_MENU0:
    clr Key1_flag
    ljmp MENU0

Beeper_Feedback:
    setb TR0
    cjne a, #0, Long_Beep ; If a is not equal to 0, go to long beep. This a is coming from FSM
 
Short_Beep:
    lcall UPDATE_LCD
    Wait_Milli_Seconds(#100)
    mov a, beeper_counter
    add a, #0x01
    mov beeper_counter, a
    jb Key1_flag, BEEPER_MENU0
    cjne a, #10, Short_Beep
    mov beeper_counter, #0x00
    sjmp BEEPER_END

Long_Beep:
    lcall UPDATE_LCD
    jb Key1_flag, BEEPER_MENU0
    Wait_Milli_Seconds(#100)
    mov a, beeper_counter
    add a, #0x01
    mov beeper_counter, a
    cjne a, #50, Long_Beep
    mov beeper_counter, #0x00
    sjmp BEEPER_END

BEEPER_END:
    clr TR0
    clr seconds_flag
    ret

LONG_MENU1:
    Set_Cursor(2, 1)
    Send_Constant_String(#CLEAR_LCD_ROW)
    ljmp MENU1

;--------------------------------;
; Main program. Includes hardware;
; initialization and main menu.  ;
;--------------------------------;
main:
	; Initialization of hardware
    mov SP, #0x7F
   
    lcall Timer0_Init
    lcall Timer2_Init
    lcall Initialize_Serial_Port
    lcall Initialize_ADC
    lcall FT93C66_INIT_SPI
    lcall Interrupt_init

    ; We use the pins of P0 to control the LCD.  Configure as outputs.
    mov P0MOD, #11111111b ; P0.0 to P0.7 are outputs.  ('1' makes the pin output)
    ; We use pins P1.0 and P1.1 as outputs also.  Configure accordingly.
    mov P1MOD, #00000001b ; P1.0 is an output
    mov P2MOD, #00001011b ; P2.0, p2.1, p2.3 are outputs
    setb EA   ; Enable Global interrupts
    lcall ELCD_4BIT ; Configure LCD in four bit mode
    ; For convenience a few handy macros are included in 'LCD_4bit_DE1SoC.inc':
    mov Menu_Vector, #0x00
    mov temp_cooldown, #60
    lcall RESET_VARIABLES
    lcall LOAD_VARIABLES

MENU0:
    clr TR2 ; stop the clock for the duration of the rest state
    Wait_Milli_Seconds(#100)
    lcall RESET_VARIABLES
    mov a, Menu_Vector
    cjne a, #0x00, LONG_MENU1
    jnb Key1_flag, MENU0
	
    clr Key1_flag
    mov FSM_state, #0x01
    lcall UPDATE_LCD
    setb TR2 ; start run time clock and timer 2
    mov a, #0x00
    lcall Beeper_Feedback
    ljmp state1
END


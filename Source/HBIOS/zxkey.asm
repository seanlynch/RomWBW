; Etched Pixels's ZXKey driver from Fuzix adapted to HBIOS

;	Low level driver for the ZXKey Interface. We scan at 60Hz or so
;	thus we do this in asm to avoid extra interrupt overhead
;
;

		;; .module zxkeyasm


		.area ZXKEY_CODE1

		;; .globl _zxkey_scan
		;; .globl _zxkey_init

		;; .globl _keyrepeat
		;; .globl _keyboard_grab
		;; .globl _keyboard
		;; .globl _shiftkeyboard
		;; .globl _keybits

		;; .globl _zxkey_queue_key


ZXKEY_SYMCOL		.equ	7
ZXKEY_SYMROW		.equ	3
ZXKEY_CAPSCOL	.equ	5
ZXKEY_CAPSROW	.equ	4
ZXKEY_SYMBYTE	.equ	ZXKEY_SYMROW
ZXKEY_CAPSBYTE	.equ	ZXKEY_CAPSROW

;
;	Must match vt.h
;
ZXKEY_KRPT_FIRST	.equ	0
ZXKEY_KRPT_CONT	.equ	1

;
;	These two must match input.h
;
ZXKEY_KEYPRESS_SHIFT	.equ	2
ZXKEY_KEYBIT_SHIFT	.equ	1
ZXKEY_KEYPRESS_CTRL	.equ	4
ZXKEY_KEYBIT_CTRL	.equ	2

	;; HBIOS functions
ZXKEY_STAT:
	;; TODO
ZXKEY_FLUSH:
	;; TODO
ZXKEY_READ:
	;; TODO

;
;	On exit we return to C with HL indicating the key code and shift
;	type so that C can decide what to do. 0 is used to indicate
;	no work to be done
;

_zxkey_scan:
		; We scan EFFF F7FF FBFF FDFF FEFF
		; The ZX81 keyboard matrix doesn't use the other 3 extra
		; lines
		ld bc,#0xEFFF
		ld hl,#zxkey_keybuf
		ld de,#0	; E = Row 0  D = no changes
		xor a
		ld (zxkey_newkey),a	; No key found so far
		;
		; Scan each row looking for changes. An unchanged line is
		; uninteresting, the normal case and can be skipped for
		; speed
		;
zxkey_scannext:
		in a,(c)
		cp (hl)
		jr z, zxkey_nomods
		ld (hl),a
		inc d
zxkey_nomods:		inc hl		; keymap
		rrc b
		; If the 0 bit has hit C then we are done
		jr c,zxkey_scannext

		; Check if we have keys held down (repeat etc still matter)
		ld a,(zxkey_keysdown)
		or d
		ld hl,#0
		; No change, no keys down, nothing to do - exit
		ret z

		;
		; Changes happened. Walk the data to see what occurred
		; and update the old map as we go so that next time
		; we see only new changes
		;
		ld a,#0xFF
		out (0xFD),a

		push ix

		ld ix,#zxkey_keymap
		ld hl,#zxkey_keybuf
		ld b,#5
		ld e,#0
zxkey_keyscan:
		ld a,(hl)	; key buf - what is down now
		ld c,a
		xor (ix)	; existing key state as the OS sees it
		; A is now the changes
		; Save the new state
		ld (ix),c
		call nz, zxkey_eval
		inc hl
		inc ix
		inc e
		djnz zxkey_keyscan

		pop ix

		xor a
		out (0xFD),a

		;
		;	Final bits of work
		;

		ld hl,#0
		ld a,(zxkey_keysdown)
		or a
		ret z
		cp #3
		ret nc

		;
		;	Valid key down status
		;
		ld a,(zxkey_newkey)
		or a
		jr z, zxkey_checkrpt
		ld a,(zxkey_keyrepeat + ZXKEY_KRPT_FIRST)
		ld (zxkey_kbd_timer),a
		push af
		call zxkey_keydecode
		pop af
		ret
		;
		;	Our keycode is still down check if it is
		;	repeating yet
		;
zxkey_checkrpt:
		ld a,(zxkey_kbd_timer)
		dec a
		ld (zxkey_kbd_timer),a
		ret nz
		ld a,(zxkey_keyrepeat + ZXKEY_KRPT_CONT)
		ld (zxkey_kbd_timer),a
		push af
		call zxkey_keydecode
		pop af
		ret


		; Scan the bits and work out what changed for this
		; keyboard row
		;
		; (HL) = keymap entry
		; A = changed bits
		; E = row id, D free
		; B = used
		; C = zxkey_keybuf value
		; 
zxkey_eval:
		ld d,#0
zxkey_loop:
		; All changes done ?
		or a
		ret z
		add a
		jr nc, zxkey_next
		push af
		; This bit changed
		; E = row, D = bit num
		call zxkey_is_shift
		; Shift doesn't affect our counts and tables
		jr z, zxkey_pop_next

		bit 7,c		; key up or down ?
		jr z, zxkey_down
		ld a,(_keyboard_grab) ; TODO
		cp #3
		jr nz, zxkey_nonotify
		push bc
		push hl
		push de		; row and col
		push af		; banked
		call _zxkey_queue_key
		pop af
		pop de
		pop hl
		pop bc
zxkey_nonotify:
		ld a,(zxkey_keysdown)
		dec a
		ld (zxkey_keysdown),a
		jr zxkey_pop_next
zxkey_down:
		ld a,#1
		ld (zxkey_newkey),a
		ld (zxkey_keybits),de	; row and col
		ld a,(zxkey_keysdown)
		inc a
		ld (zxkey_keysdown),a
zxkey_pop_next:
		pop af
zxkey_next:
		inc d
		rlc c
		jr zxkey_loop



;
;	Turn key D,E into a keycode
;
zxkey_keylookup_shift:
		ld hl,#_shiftkeyboard
		jr zxkey_keylookup
zxkey_keylookup_main:
		ld hl,#_keyboard
zxkey_keylookup:
		ld a,e			; 0-4 so won't overflow
		add a
		add a
		add a
		add d
		ld e,a
		ld d,#0
		add hl,de
		ld a,(hl)
		ret


zxkey_keydecode:
		ld de,(zxkey_keybits)
		ld a,(zxkey_keybuf + ZXKEY_SYMBYTE)		; keymap for shift
		ld c,a
		ld a,(zxkey_keybuf + ZXKEY_CAPSBYTE)	; keymap for caps
		ld b,a
		bit ZXKEY_SYMCOL,c
		jr nz, zxkey_not_sym			; symbol shift not pressed
		bit ZXKEY_CAPSCOL,b
		jr z, zxkey_not_sym			; caps is pressed
		; Shift only - so look up the shifted symbol
		call zxkey_keylookup_shift
		ld e,#ZXKEY_KEYPRESS_SHIFT		; type shift
		jr zxkey_checkctrl
		;
		; Check for caps shift
		;
zxkey_not_sym:
		call zxkey_keylookup_main
		ld e,#0
		bit ZXKEY_CAPSCOL,b
		jr nz,zxkey_keyqueue			; caps is up - no changes
		ld e,#ZXKEY_KEYPRESS_SHIFT
		;
		; Capitalization and other caps shift oddities for the ZX
		; keyboard, notably caps-0 being backspace and to fit the
		; spectrum convention mapping caps-space as ^C
		;
		cp #'a'
		jr c, zxkey_notlc
		cp #'z'+1
		jr nc,zxkey_notlc
		sub #32
		jr zxkey_keyqueue
zxkey_notlc:		cp #'0'
		jr nz, zxkey_notkeybs
		ld a,#8
		jr zxkey_keyqueue
zxkey_notkeybs:	cp #' '
		jr nz,zxkey_notkeystop
		ld a,#3			; control-C
		jr zxkey_keyqueue
zxkey_notkeystop:	; TODO cursor keys
		cp #'1'
		jr c,zxkey_not_switch
		cp #'5'
		jr nc,zxkey_not_switch
		sub #'0'
		ld h,#0x40		; special code for console change
		ld l,a
		ret

zxkey_not_switch:
		;
		; There is no control key, so we map caps/sym together as
		; control. This is less than ideal as it has to be a sticky
		; toggle because of the rollover. At least it resembles
		; the way the Spectrum works 8)
		;
zxkey_checkctrl:
		bit ZXKEY_SYMCOL,b
		jr nz, zxkey_keyqueue
zxkey_checkctrl2:
		bit ZXKEY_CAPSCOL,c
		jr nz, zxkey_keyqueue

		; Toggle the control flag, and absorb the key
		ld a,(zxkey_ctrl)
		cpl
		ld (zxkey_ctrl),a
		ld hl,#0
		ret

		;
		;	Return the shift info and key symbol to
		;	the calling C code
		;
zxkey_keyqueue:
		ld h,e
		ld l,a
		; Finally check for the control toggle
		ld a,(zxkey_ctrl)
		or a
		ret z
		; Control was pressed
		set ZXKEY_KEYBIT_CTRL,e
		ld a,#0x1F
		and l
		ld l,a
		xor a
		ld (zxkey_ctrl),a
		ret


;
;	Helper to check if a key is a shift key
;
;	On entry D,E are the symbols to check
;	Returns Z if a shift key
;
zxkey_is_shift:
		ld a,#ZXKEY_SYMROW
		cp e
		jr nz, zxkey_notsymsh
		ld a,#7-ZXKEY_SYMCOL
		cp d
		ret
zxkey_notsymsh:
		ld a,#ZXKEY_CAPSROW
		cp e
		ret nz
		ld a,#7-ZXKEY_CAPSCOL
		cp d
		ret

		.area ZXKEY_DISCARD

ZXKEY_INIT:
		; Set up both arrays
		ld hl,#zxkey_keybuf
		ld a,#0xFF
		ld b,#10
zxkey_l1:
		ld (hl),a
		inc hl
		djnz zxkey_l1
		ret


		.area ZXKEY_CONST

;
;	5 x 8 key matrix. The eights go up and down the keyboard not
;	across it.
;
_zxkey_keyboard:
		; Decode 0: 0xFEFF
		.ascii 'bhvyg6t5'
		; Decode 1: 0xFDFF
		.ascii 'njcuf7r4'
		; Decode 2: 0xFBFF
		.ascii 'mkxid8e3'
		; Decode 3: 0xF7FF
		.byte 0		; symbol shift
		.ascii 'lzos9w2'
		; Decode 4: 0xEFFF
		.ascii ' '
		.byte 10
		.byte 0		; caps shift
		.ascii 'pa0q1'

_zxkey_shiftkeyboard:
		; Decode 0: 0xFEFF
		.ascii '*^/[}&>%'
		; Decode 1: 0xFDFF
		.ascii ",-?]{'<$"
		; Decode 2: 0xFBFF
		.ascii 'm+$i\(e#'	; FIXME pound not dollar
		; Decode 3: 0xF7FF
		.byte 0		; symbol shift
		.ascii '=:;[)w@'
		; Decode 4: 0xEFFF
		.byte ' ',10, 0	; space, enter, caps
		.ascii '"~_q!'

		.area ZXKEY_DATA
;
;	Working variables
;
zxkey_keysdown:	.ds 1		; Keys currently pressed (rollover protection)
zxkey_keybuf:		.ds 5		; Current matrix state
zxkey_keymap:		.ds 5		; Previous matrix state
zxkey_newkey:		.ds 1		; Have we seen a new key ?
zxkey_keybits:		.ds 2		; If so what was its position ?
zxkey_ctrl:		.ds 1		; Sticky control toggle
zxkey_kbd_timer:	.ds 1		; Timer for repeat

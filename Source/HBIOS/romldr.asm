;
;==================================================================================================
;   ROMWBW LOADER
;==================================================================================================
;
; THE LOADER CODE IS INVOKED IMMEDIATELY AFTER HBIOS COMPLETES SYSTEM INITIALIZATION.
; IT IS RESPONSIBLE FOR LOADING A RUNNABLE IMAGE (OPERATING SYSTEM, ETC.) INTO MEMORY
; AND TRANSFERRING CONTROL TO THAT IMAGE.  THE IMAGE MAY COME FROM ROM (ROMBOOT),
; RAM (APPBOOT/IMGBOOT) OR FROM DISK (DISK BOOT).
;
; IN THE CASE OF A ROM BOOT, THE SELECTED EXECUTABLE IMAGE IS COPIED FROM ROM
; INTO A THE DEFAULT RAM AND THEN CONTROL IS PASSED TO THE STARTING ADDRESS
; IN RAM.  IN THE CASE OF AN APPBOOT OR IMGBOOT STARTUP (SEE HBIOS.ASM)
; THE SOURCE OF THE IMAGE MAY BE RAM.
;
; IN THE CASE OF A DISK BOOT, SECTOR 2 (THE THIRD SECTOR) OF THE DISK DEVICE WILL
; BE READ -- THIS IS REFERRED TO AS THE BOOT INFO SECTOR AND IS EXPECTED TO HAVE
; THE FORMAT DEFINED AT BL_INFOSEC BELOW.  THE LAST THREE WORDS OF DATA IN THIS
; SECTOR DETERMINE THE FINAL DESTINATION STARTING AND ENDING ADDRESS FOR THE DISK
; LOAD OPERATION AS WELL AS THE ENTRY POINT TO TRANSFER CONTROL TO.  THE ACTUAL
; IMAGE TO BE LOADED *MUST* BE ON THE DISK IN THE SECTORS IMMEDIATELY FOLLOWING
; THE BOOT INFO SECTOR.  THIS MEANS THE IMAGE TO BE LOADED MUST BEGIN IN SECTOR
; 3 (THE FOURTH SECTOR) AND OCCUPY SECTORS CONTIGUOUSLY AFTER THAT.
;
; THE CODE BELOW RELOCATES ITSELF AT STARTUP TO THE START OF COMMON RAM
; AT $8000.  THIS MEANS THAT THE CODE, DATA, AND STACK WILL ALL STAY
; WITHIN $8000-$8FFF.  SINCE ALL CODE IMAGES LIKE TO BE LOADED EITHER
; HIGH OR LOW (NEVER IN THE MIDDLE), THE $8000-$8FFF LOCATION TENDS
; TO AVOID THE PROBLEM WHERE THE CODE IS OVERLAID DURING THE LOADING
; OF THE DESIRED EXECUTABLE IMAGE.
;
; INCLUDE GENERIC STUFF
;
#INCLUDE "std.asm"
;
INT_IM1	.EQU	$FF00
;
BID_CUR	.EQU	-1	; SPECIAL BANK ID VALUE INDICATES CURRENT BANK
;
	.ORG	0
;
;==================================================================================================
; NORMAL PAGE ZERO SETUP, RET/RETI/RETN AS APPROPRIATE
;==================================================================================================
;
	JP	$100			; RST 0: JUMP TO BOOT CODE
	.FILL	(008H - $),0FFH
#IF (BIOS == BIOS_UNA)
	JP	$FFFD			; RST 8: INVOKE UBIOS FUNCTION
#ELSE
	JP	HB_INVOKE		; RST 8: INVOKE HBIOS FUNCTION
#ENDIF
	.FILL	(010H - $),0FFH
	RET				; RST 10
	.FILL	(018H - $),0FFH
	RET				; RST 18
	.FILL	(020H - $),0FFH
	RET				; RST 20
	.FILL	(028H - $),0FFH
	RET				; RST 28
	.FILL	(030H - $),0FFH
	RET				; RST 30
	.FILL	(038H - $),0FFH
#IF (BIOS == BIOS_UNA)
	RETI				; RETURN W/ INTS DISABLED
#ELSE
  #IF (INTMODE == 1)
	JP	INT_IM1			; JP TO INTERRUPT HANDLER IN HI MEM		
  #ELSE
	RETI				; RETURN W/ INTS DISABLED
  #ENDIF
#ENDIF
	.FILL	(066H - $),0FFH
	RETN				; NMI
;
	.FILL	(100H - $),0FFH		; PAD REMAINDER OF PAGE ZERO
;
;==================================================================================================
;   STARTUP AND LOADER INITIALIZATION
;==================================================================================================
;
	DI			; NO INTERRUPTS FOR NOW
;
	; RELOCATE TO START OF COMMON RAM AT $8000
	LD	HL,0
	LD	DE,$8000
	LD	BC,LDR_SIZ
	LDIR
	JP	START
;
	.ORG	$8000 + $
;
START:	LD	SP,BL_STACK	; SETUP STACK
;
#IF (BIOS == BIOS_WBW)
	CALL	DELAY_INIT	; INIT DELAY FUNCTIONS
#ENDIF
;
#IF (BIOS == BIOS_UNA)
;	; COPY UNA BIOS PAGE ZERO TO USER BANK, LEAVE USER BANK ACTIVE
;	LD	BC,$01FB	; UNA FUNC = SET BANK
;	LD	DE,BID_BIOS	; UBIOS_PAGE (SEE PAGES.INC)
;	CALL	$FFFD		; DO IT (RST 08 NOT YET INSTALLED)
;	PUSH	DE		; SAVE PREVIOUS BANK
;;	                        
;	LD	HL,0		; FROM ADDRESS 0 (PAGE ZERO)
;	LD	DE,$9000	; USE $9000 AS BOUNCE BUFFER
;	LD	BC,256		; ONE PAGE IS 256 BYTES
;	LDIR			; DO IT
;;
;	LD	BC,$01FB	; UNA FUNC = SET BANK
;	;POP	DE		; RECOVER OPERATING BANK
;	LD	DE,BID_USR	; TO USER BANK
;	CALL	$FFFD		; DO IT (RST 08 NOT YET INSTALLED)
;;
;	LD	HL,$9000	; USE $9000 AS BOUNCE BUFFER
;	LD	DE,0		; TO PAGE ZERO OF OPERATING BANK
;	LD	BC,256		; ONE PAGE IS 256 BYTES
;	LDIR			; DO IT
;;
;;	; INSTALL UNA INVOCATION VECTOR FOR RST 08
;;	; *** IS THIS REDUNDANT? ***
;;	LD	A,$C3		; JP INSTRUCTION
;;	LD	(8),A		; STORE AT 0x0008
;;	LD	HL,($FFFE)	; UNA ENTRY VECTOR
;;	LD	(9),HL		; STORE AT 0x0009
;;
;	LD	BC,$01FB	; UNA FUNC = SET BANK
;	POP	DE		; RECOVER OPERATING BANK
;	CALL	$FFFD		; DO IT (RST 08 NOT YET INSTALLED)
#ELSE
	; PREP THE USER BANK (SETUP PAGE ZERO)
	LD	B,BF_SYSSETCPY	; HBIOS FUNC: SETUP BANK COPY
	LD	D,BID_USR	; D = DEST BANK = USER BANK
	LD	E,BID_BIOS	; E = SRC BANK = BIOS BANK
	LD	HL,256		; HL = COPY LEN = 1 PAGE = 256 BYTES
	RST	08		; DO IT
	LD	B,BF_SYSBNKCPY	; HBIOS FUNC: PERFORM BANK COPY
	LD	HL,0		; COPY FROM BIOS ADDRESS 0
	LD	DE,0		; TO USER ADDRESS 0
	RST	08		; DO IT
#ENDIF
	EI
;
;==================================================================================================
;   BOOT LOADER MENU DISPLAY
;==================================================================================================
;
	LD	DE,STR_BANNER	; DISPLAY BOOT BANNER
;
MENU:
	CALL	WRITESTR	; DISPLAY MESSAGE OR ERROR
	CALL	NEWLINE2		
;
#IF (DSKYENABLE)
	CALL	DSKY_RESET
	; DISPLAY DSKY BOOT MESSAGE
	LD	HL,MSG_SEL	; POINT TO BOOT MESSAGE	
	CALL 	DSKY_SHOWSEG	; DISPLAY MESSAGE
#ENDIF
;
#IF (BOOTTYPE == BT_AUTO)
	; INITIALIZE BOOT TIMEOUT DOWNCOUNTER
	LD	BC,100 * BOOT_TIMEOUT
	LD	(BL_TIMEOUT),BC
#ENDIF
;
	; DISPLAY ROM MENU ENTRIES
	PRTS("ROM: $")
	LD	B,MENU_N	; B IS LOOP COUNTER, # OF ENTRIES
	LD	HL,MENU_S	; HL POINTS TO START OF ENTRY
MENU1:
	; PROCESS A TABLE ENTRY
	PUSH	HL		; COPY HL TO
	POP	DE		; ... DE FOR USE AS CHAR PTR
MENU2:
	LD	A,(DE)		; GET NEXT CHAR
	INC	DE		; BUMP CHAR PTR FOR FUTURE
	CP	'$'		; TERMINATOR?
	JR	Z,MENU4		; IF YES, DONE WITH THIS ENTRY
	CP	'~'		; HOT KEY PREFIX?
	JR	NZ,MENU3	; IF NOT, JUST SKIP AHEAD
	CALL	PC_LPAREN	; L PAREN BEFORE HOT KEY
	LD	A,(DE)		; GET THE ACTUAL HOT KEY
	INC	DE		; BUMP CHAR PTR FOR FUTURE
	CALL	COUT		; OUTPUT HOT KEY
	LD	A,')'		; R PAREN WILL PRINT BELOW
MENU3:
	CALL	COUT		; OUTPUT CHAR
	JR	MENU2		; AND LOOP
MENU4:
	; END OF AN ENTRY
	CALL	PC_SPACE	; PRINT SEPARATOR
	LD	A,MENU_V	; LOAD ENTRY LENGTH
	CALL	ADDHLA		; BUMP HL TO NEXT ENTRY
	DJNZ	MENU1		; LOOP UNTIL COUNT EXPIRES
;
	; DISPLAY AVAILABLE DISK DRIVES
	PRTS("\r\nDisk: $")
	CALL	PRTALL		; PRINT DRIVE LIST
;
	LD	DE,STR_BOOTSEL
	CALL	WRITESTR
;
;==================================================================================================
;   BOOT SELECTION PROCESSING
;==================================================================================================
;
SEL:	; HANDLE SERIAL CONSOLE INPUT
	CALL	CST		; CHECK CONSOLE INPUT
	OR	A		; ZERO?
	JR	Z,SEL1		; IF NOT, CONTINUE
#IF (BIOS == BIOS_WBW)
  #IF (DIAGENABLE)
	XOR	A		; ZERO ACCUM
	OUT	(DIAGPORT),A	; CLEAR DIAG LEDS
  #ENDIF
  #IF (LEDENABLE)
	OR	$FF		; LED IS INVERTED
	OUT	(LEDPORT),A	; CLEAR LED
  #ENDIF
#ENDIF
	CALL	CINUC			; GET THE KEY
	CALL	COUT			; ECHO KEY
	CP	'R'			; CHECK FOR
	JP	Z,REBOOT		; REBOOT REQUEST
	LD	DE,MENU_S+10-MENU_V	; POINT TO SERIAL MENU COLUMN
	LD	C,2			; SET SERIAL FLAG
	JR	MATS			; GO CHECK MENU SELECTION
;
SEL1:
#IF (DSKYENABLE)
	; HANDLE DSKY KEY INPUT
	CALL	DSKY_STAT	; CHECK DSKY INPUT
	OR	A		; TEST FOR ZERO
	JR	Z,SEL2		; IF ZERO, NO KEY PRESSED
#IF (BIOS == BIOS_WBW)
  #IF (DIAGENABLE)
	XOR	A		; ZERO ACCUM
	OUT	(DIAGPORT),A	; CLEAR DIAG LEDS
  #ENDIF
  #IF (LEDENABLE)
	OR	$FF		; LED IS INVERTED
	OUT	(LEDPORT),A	; CLEAR LED
  #ENDIF
#ENDIF
	CALL	DSKY_GETKEY		; GET PENDING KEY PRESS		; NOTE DESKY_GETKEY
	CP	$FF			; CHECK FOR ERROR
	JR	Z,SEL2			; IF SO, IGNORE KEY, AND CONT LOOPING
	CP	KY_BO			; CHECK FOR REBOOT		; CAN RETURN AN INVALID
	JP	Z,REBOOT		; REBOOT REQUEST		; KEYSCAN AS FFH WHICH 
	LD	DE,MENU_S+11-MENU_V	; POINT TO DSKY MENU COLUMN	; MAY BE MATCHED WITH
	LD	C,1			; SET DSKY FLAG			; DUMMY MENU ENTRIES
	JR	MATS			; GO CHECK MENU SELECTION
#ENDIF
;
SEL2:
#IF (BOOTTYPE == BT_AUTO)
	; CHECK FOR AUTOBOOT TIMEOUT
	LD	DE,625		; DELAY FOR 10MS TO MAKE TIMEOUT CALC EASY
	CALL	VDELAY		; 16US * 625 = 10MS
	LD	BC,(BL_TIMEOUT)	; CHECK/INCREMENT TIMEOUT
	DEC	BC
	LD	(BL_TIMEOUT),BC
	LD	A,B
	OR	C
	JP	NZ,SEL3
;
#IF (BIOS == BIOS_WBW)
  #IF (DIAGENABLE)
	XOR	A		; ZERO ACCUM
	OUT	(DIAGPORT),A	; CLEAR DIAG LEDS
  #ENDIF
  #IF (LEDENABLE)
	OR	$FF		; LED IS INVERTED
	OUT	(LEDPORT),A	; CLEAR LED
  #ENDIF
#ENDIF
	LD	A,BOOT_DEFAULT		; TIMEOUT EXPIRED,
	LD	DE,MENU_S+10-MENU_V	; POINT TO SERIAL MENU COLUMN
	LD	C,2			; SET SERIAL FLAG
	JR	MATS			; PERFORM DEFAULT BOOT ACTION
#ENDIF
;
SEL3:
	; NO USER SELECTION YET
	JR	SEL		; LOOP
;
;==================================================================================================
;   ROM MENU TABLE MATCHING
;==================================================================================================
;
MATS:	LD	B,MENU_N	; LOOP THROUGH THE	; ON ENTRY DE POINTS TO
	LD	HL,MENU_V	; MENU TABLE AND	; THE MENU COLUMN WE ARE
MATS1:	EX	DE,HL		; CHECK IF THE		; CHECKING AND C CONTAINS
	ADD	HL,DE		; KEYPRESS MATCHES	; A FLAG TELLING US IF WE
	CP	(HL)            ; ANY OF 		; HAVE DSKY OR SERIAL INPUT
	EX	DE,HL           ; THE MENU ITEMS.
	JR	Z,MATS2
	DJNZ	MATS1		; IF WE REACH THE TABLE END AND DON'T HAVE
	JR	MATD		; A MATCH GO AND CHECK FOR A DISK SELECTION
;
MATS2:	LD	B,0		; WE GOT A MATCH FROM THE MENU TABLE. POINT
	EX	DE,HL		; TO THE ROM ADDRESS TO EXECUTE. ADJUST THE
	ADD	HL,BC		; POINTER TO THE ROM ENTRY BASED ON WHETHER WE
	EX	DE,HL		; GOT A MATCH IN THE DSKY OR SERIAL MENU COLUMN
	JP	GOROM		; JUMP TO THE ROM HANDLER.
;
MATD:	LD	B,A
	LD	A,C		; IF INPUT WAS SERIAL 
	LD	(BL_INPFLG),A	; SAVE INPUT FLAG
	DEC	C		; CONVERT TO FROM. 
	LD	A,B		; ASCII TO DECIMAL.
	JR	Z,MATD1		; DSKY NUMBERS ARE 
	SUB	'0'		; ALREADY DECIMAL
MATD1:	CP	10		; DO A RANGE CHECK
	JR	NC,MATX		; NOT VALID, HANDLE IT BELOW
;
	PUSH	BC
	PUSH	AF			; HOW MANY DISK
	LD	B,BF_SYSGET		; DEVICES DO WE
	LD	C,BF_SYSGET_DIOCNT	; HAVE IN THE 
	RST	08			; SYSTEM ?
	POP	AF
	POP	BC
;	JR	MATD2		; IF MORE THEN 9	; UNCOMMENT TO TEST DOUBLE CHAR ENTRY
	CP	10		; THEN WE NEED TO GET
	JR	NC,MATD2	; ANOTHER CHARACTER
;
	CP	E		; WE DON'T HAVE MORE THAN 10 DEVICES SO	; A = REQUESTED UNIT 
	JP	C,GOBOOTDISK	; CHECK IT IS IN RANGE. BOOT IF IT IS	; E = AVAILABLE UNITS
	JR	MATX		; IT IF NOT VALID, HANDLE IT BELOW

MATD2:	LD	B,A		; PROCESS FURTHER INPUT ; B = REQUESTED UNIT 
	LD	A,C		; CHECK WHERE TO GET    ; C = DSKY/SERIAL FLAG
	DEC	C		; THE INPUT FROM AND GO
	JR	NZ,MATD3	; GET ANOTHER CHARACTER
;
#IF (DSKYENABLE)		; INPUT DSKY
;
MATD4:	;CALL	DSKY_STAT	; WAIT FOR
	;OR	A		; ANOTHER
	;JR	Z,MATD4		; KEY FROM
	;CALL	DSKY_GETKEY	; DSKY
	CALL	DSKY_KEY

	CP	KY_EN		; IF NEXT KEY IS ENTER
	JR	Z,MATD6		; OR GO, PROCESS AS A 
	CP	KY_GO		; SINGLE DIGIT NUMBER
	JR	Z,MATD6		; OTHERWISE JOIN TWO
	JR	MATD5		; CHARCTERS IN ONE DECIMAL
#ENDIF
;
;				; INPUT SERIAL
;
MATD3:	;CALL	CST		; WAIT FOR
	;OR	A		; ANOTHER
	;JR	Z,MATD3		; KEY FROM
	CALL	CINUC		; SERIAL
	CALL	COUT		
;
	CP	CHR_CR		; IF NEXT KEY IS RETURN PROCESS
	JR	Z,MATD6		; AS A SINGLE DIGIT NUMBER
;
	SUB	'0'		; CONVERT THE SERIAL NUMBER TO DECIMAL
	CP	10		; DO A RANGE CHECK
	JR	NC,MATX		; NOT VALID, HANDLE IT BELOW

MATD5:	LD	C,A		; C CONTAINS SECOND CHARACTER INPUT 0..9
	LD	A,B		; A CONTAINS FIRST NUMBER INPUT 0..9
	ADD	A,A		
	LD	B,A		; MULTIPLY FIRST DIGIT BY 10					
	ADD	A,A		; AND ADD SECOND DIGIT	
	ADD	A,A		
	ADD	A,B		; CONVERT TWO INPUTTED
	ADD	A,C		; CHARACTERS TO DECIMAL.
	LD	B,A 
;
MATD6:	LD	A,B		; PUT THE DEVICE NUMBER TO BOOT 
	JP	GOBOOTDISK	; IN A AND GO BOOT DEVICE
;
MATX:	LD	DE,STR_INVALID	; SET ERROR STRING MESSAGE
	JP	MENU		; AND RESTART MENU LOOP
;
;==================================================================================================
;   ROM MENU TABLE
;==================================================================================================
;
#DEFINE MENU_L(M1,M2,M3,M4,M5,M6,M7,M8,M9,M10) \
#DEFCONT \ .DB M1
#DEFCONT \ .DB M2
#IF (DSKYENABLE)	
#DEFCONT \ .DB M3
#ELSE
#DEFCONT \ .DB $FF
#ENDIF
#DEFCONT \ .DW M4
#DEFCONT \ .DW M5
#DEFCONT \ .DW M6
#DEFCONT \ .DW M7
#DEFCONT \ .DB M8
#DEFCONT \ .DB M9
#DEFCONT \ .DB M10
;
; NOTE: THE FORMATTING OF THE FOLLOWING IS CRITICAL. TASM DOES NOT PASS MACRO ARGUMENTS WELL.
;       ENSURE STD.ASM HOLDS THE DEFINITIONS FOR *_LOC, *_SIZ *_END AND ANY CODE GENERATED WHICH DOES NOT 
;	INCLUDE STD.ASM IS SYNCED.
;
; NOTE: THE LOADABLE ROM IMAGES ARE PLACED IN ROM BANKS BID_IMG0 AND BID_IMG1.  HOWEVER, ROMWBW
;       SUPPORTS A MECHANISM TO LOAD A COMPLETE NEW SYSTEM DYNAMICALLY AS A RUNNABLE APPLICATION
;       (SEE APPBOOT AND IMGBOOT IN HBIOS.ASM).  IN THIS CASE, THE CONTENTS OF BID_IMG0 WILL
;       PRE-LOADED INTO THE CURRENTLY EXECUTING RAM BANK THEREBY ALLOWING THOSE IMAGES TO BE
;       DYNAMICALLY LOADED AS WELL.  TO SUPPORT THIS CONCEPT, A PSEUDO-BANK CALLED BID_CUR
;       IS USED TO SPECIFY THE IMAGES NORMALLY FOUND IN BID_IMG0.  IN GOROM, THIS SPECIAL
;       VALUE WILL CAUSE THE ASSOCIATED IMAGE TO BE LOADED FROM THE CURRENTLY EXECUTING BANK
;       WHICH WILL BE CORRECT REGARDLESS OF THE LOAD MODE.  IMAGES IN OTHER BANKS (BID_IMG1)
;	WILL ALWAYS BE LOADED DIRECTLY FROM ROM.
;
;              name          menu dsky   dest-exec    source  dest-addr  img-size  source-bank  dest     desc  
;              DB            DB   DB     DW           DW      DW         DW        DB           DB       DB
MENU_S:	MENU_L("~Monitor$ ", "M", KY_CL, MON_SERIAL,  1000h,  MON_LOC,   MON_SIZ,  BID_CUR,     BID_USR, "Monitor$     ")
MENU_1:	MENU_L("~CP/M$    ", "C", KY_BK, CPM_ENT,     2000h,  CPM_LOC,   CPM_SIZ,  BID_CUR,     BID_USR, "CP/M 80 v2.2$")
	MENU_L("~Z-System$", "Z", KY_FW, CPM_ENT,     5000h,  CPM_LOC,   CPM_SIZ,  BID_CUR,     BID_USR, "ZSDOS v1.1$  ")
#IF (BIOS == BIOS_WBW)
	MENU_L("~Forth$   ", "F", KY_EX, FTH_LOC,     0000h,  FTH_LOC,   FTH_SIZ,  BID_IMG1,    BID_USR, "Camel Forth$ ")
	MENU_L("~BASIC$   ", "B", KY_DE, BAS_LOC,     1700h,  BAS_LOC,   BAS_SIZ,  BID_IMG1,    BID_USR, "Nascom BASIC$")
	MENU_L("~T-BASIC$ ", "T", KY_EN, TBC_LOC,     3700h,  TBC_LOC,   TBC_SIZ,  BID_IMG1,    BID_USR, "Tasty BASIC$ ")
	MENU_L("~PLAY$    ", "P", $FF,   GAM_LOC,     4000h,  GAM_LOC,   GAM_SIZ,  BID_IMG1,    BID_USR, "Game$        ")
	MENU_L("~USER ROM$", "U", $FF,   USR_LOC,     7000h,  USR_LOC,   USR_SIZ,  BID_IMG1,    BID_USR, "User ROM$    ")
#ENDIF
#IF (DSKYENABLE)
	MENU_L("~DSKY$    ", "D", KY_GO, MON_DSKY,    1000h,  MON_LOC,   MON_SIZ,  BID_CUR,     BID_USR, "DSKY Monitor$")
#ENDIF
	MENU_L("$         ", "E", $FF,   EGG_LOC,     0E00h,  EGG_LOC,   EGG_SIZ,  BID_CUR,     BID_USR, "Easter Egg$  ")
;
MENU_E	.EQU	$				; END OF TABLE
MENU_V	.EQU	MENU_1 - MENU_S			; LENGTH OF EACH MENU RECORD
MENU_N	.EQU	((MENU_E - MENU_S) / MENU_V)	; NUMBER OF MENU ITEMS
;
;==================================================================================================
;   SYSTEM REBOOT HANDLER
;==================================================================================================
;
REBOOT: LD	DE,STR_REBOOT		; POINT TO MESSAGE
	CALL	WRITESTR		; PRINT IT
#IF (DSKYENABLE)
	LD	HL,MSG_BOOT		; POINT TO BOOT MESSAGE	
	CALL 	DSKY_SHOWSEG		; DISPLAY MESSAGE
#ENDIF
	LD	A,BID_BOOT		; BOOT BANK
	LD	HL,0			; ADDRESS ZERO
	CALL	HB_BNKCALL		; DOES NOT RETURN
;
;==================================================================================================
;   ROM IMAGE LOAD HANDLER
;==================================================================================================
;
; AT ENTRY, DE POINTS TO THE EXEC ADR FIELD OF THE ACTIVE ROM
; TABLE ENTRY
;
; ROM IMAGES MUST NOT OVERLAY THE SPACE OCCUPIED BY THE LOADER WHICH
; IS $8000-$8FFF.
;
GOROM:	PUSH	DE			; SAVE ROM TABLE ENTRY EXEC ADR PTR
	LD	DE,STR_BOOTROM		; ROM LOADING MSG PREFIX
	CALL	WRITESTR		; PRINT IT
#IF (DSKYENABLE)
	LD	HL,MSG_LOAD		; POINT TO LOAD MESSAGE	
	CALL 	DSKY_SHOWSEG		; DISPLAY MESSAGE
#ENDIF
	POP	HL			; EXEC ADR TO HL
	PUSH	HL			; AND RESAVE IT
	LD	A,10			; OFFSET TO IMAGE DESC
	CALL	ADDHLA			; APPLY IT
	EX	DE,HL			; MOVE TO DE, ORIG VALUE TO HL
	CALL	WRITESTR		; AND PRINT IT
	PRTS("...$")			; ADD SOME DOTS
	POP	HL			; RESTORE EXEC ADR TO HL
;
	LD	B,5			; PUT NEXT FIVE WORDS ON STACK
GOROM1:	LD	E,(HL)			; (1) EXEC ADR
	INC	HL			; (2) SOURCE ADR
	LD	D,(HL)			; (3) DEST ADR
	INC	HL			; (4) IMAGE SIZE
	PUSH	DE			; (5) SRC/DEST BANKS
	DJNZ	GOROM1			; LOOP TILL DONE
;
#IF (BIOS == BIOS_UNA)
;
; NOTE: UNA HAS NO INTERBANK MEMORY COPY, SO WE CAN ONLY LOAD
; IMAGES FROM THE CURRENT BANK.  A SIMPLE LDIR IS USED TO
; RELOCATE THE IMAGES.  AT SOME POINT AN UNA INTERBANK COPY
; SHOULD BE IMPLEMENTED HERE.
;
	; COPY IMAGE TO IT'S RUNNING LOCATION
	POP	HL			; POP AND DISCARD BANKS
	POP	BC			; GET IMAGE SIZE TO BC
	POP	DE			; GET DESTINATION ADR TO DE
	POP	HL			; GET SOURCE ADR TO HL
	LDIR				; MOVE IT
;
	; RECORD BOOT INFO
	LD	BC,$00FB		; GET LOWER PAGE ID
	RST	08			; DE := LOWER PAGE ID == BOOT ROM PAGE
	LD	L,1			; BOOT DISK UNIT IS ROM (UNIT ID = 1)
	LD	BC,$01FC		; UNA FUNC: SET BOOTSTRAP HISTORY
	RST	08			; CALL UNA
;
	; LAUNCH IMAGE W/ USER BANK ACTIVE
	; NOTE: UNA EXEC CHAIN CALL USES ADDRESS ON TOS
	CALL	NEWLINE2
	LD	DE,BID_USR		; TARGET BANK ID
	PUSH	DE			; ... ON STACK
	;DI				; ENTER WITH INTS DISABLED
	JP	$FFF7			; UNA INTER-PAGE EXEC CHAIN
#ELSE
;
; NOTE: CHECK FOR SPECIAL CASE WHERE SOURCE BANK IS BID_CUR.  IN THIS CASE
; WE COPY THE IMAGE FROM THE BANK THAT WE ARE CURRENTLY RUNNING IN.  THIS
; IS DONE TO SUPPORT THE APPBOOT AND IMGBOOT MODES AS DEFINED IN HBIOS.
; IN THE CASE OF THESE MODES IT IS INTENDED THAT THE IMAGES BE LOADED
; FROM THE CURRENT RAM BANK AND NOT FROM THEIR NORMAL ROM LOCATIONS.
;
	; COPY IMAGE TO IT'S RUNNING LOCATION
	POP	DE			; GET BANKS (E=SRC, D=DEST)
	POP	HL			; GET IMAGE SIZE
	LD	A,E			; SOURCE BANK TO A
	CP	BID_CUR			; SPECIAL CASE, BID_CUR?
	JR	NZ,GOROM2		; IF NOT, GO RIGHT TO COPY
	LD	A,(HB_CURBNK)		; GET CURRENT BANK
	LD	E,A			; AND SUBSTITUE THE VALUE
GOROM2:	LD	B,BF_SYSSETCPY		; HBIOS FUNC: SETUP BANK COPY
	RST	08			; DO IT
	POP	DE			; GET DEST ADR
	POP	HL			; GER SOURCE ADR
	LD	B,BF_SYSBNKCPY		; HBIOS FUNC: PERFORM BANK COPY
	RST	08			; DO IT
;
	; RECORD BOOT INFO
	LD	A,(HB_CURBNK)		; GET CURRENT BANK ID FROM PROXY DATA
	LD	B,BF_SYSSET		; HB FUNC: SET HBIOS PARAMETER
	LD	C,BF_SYSSET_BOOTINFO	; HB SUBFUNC: SET BOOT INFO
	LD	L,A			; ... AND SAVE AS BOOT BANK
	LD	DE,$0100		; BOOT VOLUME (UNIT, SLICE)
	RST	08
;
#IF (DSKYENABLE)
	LD	HL,MSG_GO		; POINT TO BOOT MESSAGE	
	CALL 	DSKY_SHOWSEG		; DISPLAY MESSAGE
#ENDIF
;
	; LAUNCH IMAGE W/ USER BANK ACTIVE
	CALL	NEWLINE2
	LD	A,BID_USR		; ACTIVATE USER BANK
	POP	HL			; RECOVER EXEC ADDRESS
	;DI				; ENTER WITH INTS DISABLED
	CALL	HB_BNKCALL		; AND GO
	HALT				; WE SHOULD NEVER RETURN!!!
#ENDIF
;
;==================================================================================================
;   DISK BOOT HANDLER
;==================================================================================================
;
GOBOOTDISK:
	LD	(BL_BOOTID),A		; SAVE INCOMING BOOTID
;
	; SET THE INITIAL BOOT UNIT AND SLICE
	;LD	A,(BL_BOOTID)		; GET BOOTID
	LD	(BL_DEVICE),A		; STORE IT
	XOR	A			; LU DEFAULTS TO 0
	LD	(BL_LU),A		; STORE IT
;
#IF (BIOS == BIOS_WBW)
;
	LD	A,(BL_INPFLG)		; GET INPUT FLAG
	CP	1			; DSKY?
	JR	Z,GOBOOTDISK1		; IF SO, SLICE 0 IS ASSUMED
;
	LD	A,(BL_DEVICE)		; GET BOOT DEVICE
	LD	C,A			; PUT IN C
	LD	B,BF_DIODEVICE		; HBIOS: DIO DEVICE FUNC
	RST	08
	LD	A,D			; DEVICE TYPE TO A
	CP	DIODEV_IDE		; HARD DISK DEVICE?
	JR	C,GOBOOTDISK1		; NOT SLICE WORTHY, SKIP AHEAD
;
	LD	DE,STR_SLICESEL		; SLICE SELECTION STRING
	CALL	WRITESTR		; DISPLAY IT
	CALL	CINUC			; GET THE KEY
	CALL	COUT			; ECHO KEY
;
	LD	DE,STR_INVALID		; SETUP IN CASE OF INVALID
	CP	13			; ENTER?
	JR	Z,GOBOOTDISK1		; IF SO, DONE
	CP	'0'			; START OF RANGE?
	JP	C,MENU			; BACK TO MENU IF TOO LOW
	CP	'9' + 1			; END OF RANGE
	JP	NC,MENU			; BACK TO MENU IF TOO HIGH
	SUB	'0'			; CONVERT TO BINARY
	LD	(BL_LU),A		; AND SAVE IT
GOBOOTDISK1:
;
#ENDIF
;
	LD	DE,STR_BOOTDISK
	CALL	WRITESTR
	LD	A,(BL_DEVICE)
	CALL	PRTDECB
	LD	DE,STR_BOOTDISK1
	CALL	WRITESTR
	LD	A,(BL_LU)
	CALL	PRTDECB
	PRTS("...$")
#IF (DSKYENABLE)
	LD	HL,MSG_LOAD		; POINT TO LOAD MESSAGE	
	CALL 	DSKY_SHOWSEG		; DISPLAY MESSAGE
#ENDIF
;
	LD	DE,STR_BOOTREAD	; DISK BOOT MESSAGE
	CALL	WRITESTR		; PRINT IT
;	
#IF (BIOS == BIOS_UNA)
	LD	A,(BL_BOOTID)		; GET BOOT DEVICE ID
	LD	B,A			; MOVE TO B
;
	; LOAD SECTOR 2 (BOOT INFO)
	LD	C,$41			; UNA FUNC: SET LBA
	LD	DE,0			; HI WORD OF LBA IS ALWAYS ZERO
	LD	HL,2			; LOAD STARTING INFO SECTOR 2
	RST	08			; SET LBA
	JP	NZ,DB_ERR		; HANDLE ERROR
;
	LD	C,$42			; UNA FUNC: READ SECTORS
	LD	DE,BL_INFOSEC		; DEST OF CPM IMAGE
	LD	L,1			; SECTORS TO READ
	RST	08			; DO READ
	JP	NZ,DB_ERR		; HANDLE ERROR
#ELSE
	; CHECK FOR VALID DRIVE LETTER
	LD	A,(BL_BOOTID)		; BOOT DEVICE TO A
	PUSH	AF			; SAVE BOOT DEVICE
	LD	B,BF_SYSGET
	LD	C,BF_SYSGET_DIOCNT
	RST	08			; E := DISK UNIT COUNT
	POP	AF			; RESTORE BOOT DEVICE
	CP	E			; CHECK MAX (INDEX - COUNT)
	JP	NC,DB_NODISK		; HANDLE INVALID SELECTION
;
	; SENSE MEDIA
	LD	A,(BL_DEVICE)		; GET DEVICE/UNIT
	LD	C,A			; STORE IN C
	LD	B,BF_DIOMEDIA		; DRIVER FUNCTION = DISK MEDIA
	LD	E,1			; ENABLE MEDIA CHECK/DISCOVERY
	RST	08			; CALL HBIOS
	JP	NZ,DB_ERR		; HANDLE ERROR
;	
	; SEEK TO SECTOR 2 OF LU
	LD	A,(BL_LU)		; GET LU SPECIFIED
	LD	E,A			; LU INDEX
	LD	H,65			; 65 TRACKS PER LU
	CALL	MULT8			; HL := H * E
	LD	DE,$02			; HEAD 0, SECTOR 2
	LD	B,BF_DIOSEEK	   	; SETUP FOR NEW SEEK CALL
	LD	A,(BL_DEVICE)		; GET BOOT DISK UNIT
	LD	C,A			; PUT IN C
	RST	08			; DO IT
	JP	NZ,DB_ERR		; HANDLE ERROR
;
	; READ
	LD	B,BF_DIOREAD		; FUNCTION IN B
	LD	A,(BL_DEVICE)		; GET BOOT DISK UNIT
	LD	C,A			; PUT IN C
	LD	HL,BL_INFOSEC     	; READ INTO INFO SEC BUFFER
	LD	D,BID_USR		; USER BANK		; 
	LD	E,1			; TRANSFER ONE SECTOR
	RST	08			; DO IT
	JP	NZ,DB_ERR		; HANDLE ERROR
;	
#ENDIF
;
	; CHECK SIGNATURE
	LD	DE,(BB_SIG)		; GET THE SIGNATURE
	LD	A,$A5			; FIRST BYTE SHOULD BE $A5
	CP	D			; COMPARE
	JP	NZ,DB_NOBOOT		; ERROR IF NOT EQUAL
	LD	A,$5A			; SECOND BYTE SHOULD BE $5A
	CP	E			; COMPARE
	JP	NZ,DB_NOBOOT		; ERROR IS NOT EQUAL
;
	; PRINT CPMLOC VALUE
	PRTS("\r\nLoc=$")
	LD	BC,(BB_CPMLOC)
	CALL	PRTHEXWORD
;
	; PRINT CPMEND VALUE
	PRTS(" End=$")
	LD	BC,(BB_CPMEND)
	CALL	PRTHEXWORD
;	
	; PRINT CPMENT VALUE
	PRTS(" Ent=$")
	LD	BC,(BB_CPMENT)
	CALL	PRTHEXWORD
;
	; PRINT DISK LABEL
	PRTS(" Label=$")
	LD	DE,BB_LABEL 		; if it is there, then a printable
	LD	A,(BB_TERM)		; Display Disk Label if Present
	CP	'$'			; (dwg 2/7/2012)
	CALL	Z,WRITESTR		; label is there as well even if spaces.
;
	LD	DE,STR_LOADING		; LOADING MESSAGE
	CALL	WRITESTR		; PRINT IT
;
	; COMPUTE NUMBER OF SECTORS TO LOAD
	LD	HL,(BB_CPMEND)		; HL := END
	LD	DE,(BB_CPMLOC)		; DE := START 
	OR	A			; CLEAR CARRY
	SBC	HL,DE			; HL := LENGTH TO LOAD
	LD	A,H			; DETERMINE 512 BYTE SECTOR COUNT
	RRA				; ... BY DIVIDING MSB BY TWO
	LD	(BL_COUNT),A		; ... AND SAVE IT
;
#IF (BIOS == BIOS_UNA)
;
	; READ OS IMAGE INTO MEMORY
	LD	C,$42			; UNA FUNC: READ SECTORS
	LD	A,(BL_BOOTID)		; GET BOOT DEVICE ID
	LD	B,A			; MOVE TO B
	LD	DE,(BB_CPMLOC)		; DEST OF CPM IMAGE
	LD	A,(BL_COUNT)		; GET SECTORS TO READ
	LD	L,A			; SECTORS TO READ
	RST	08			; DO READ
	JP	NZ,DB_ERR		; HANDLE ERROR
;
	; PASS BOOT DEVICE/UNIT/LU TO CBIOS COLD BOOT
	LD	DE,-1			; BOOT ROM PAGE, -1 FOR N/A
	LD	A,(BL_BOOTID)		; GET BOOT DISK UNIT ID
	LD	L,A			; PUT IN L
	LD	BC,$01FC		; UNA FUNC: SET BOOTSTRAP HISTORY
	RST	08			; CALL UNA
	JP	NZ,DB_ERR		; HANDLE ERROR
;
	; JUMP TO COLD BOOT ENTRY
	LD	HL,(BB_CPMENT)		; GET THE ENTRY POINT
	PUSH	HL			; PUT ON STACK FOR UNA CHAIN FUNC
	LD	DE,BID_USR		; TARGET BANK ID IS USER BANK
	PUSH	DE			; PUT ON STACK FOR UNA CHAIN FUNC
	;DI				; ENTER WITH INTS DISABLED
	JP	$FFF7			; UNA INTER-PAGE EXEC CHAIN
;
#ELSE
;
	; READ OS IMAGE INTO MEMORY
	LD	B,BF_DIOREAD		; FUNCTION IN B
	LD	A,(BL_DEVICE)		; GET BOOT DISK UNIT
	LD	C,A			; PUT IN C
	LD	HL,(BB_CPMLOC)     	; LOAD ADDRESS
	LD	D,BID_USR		; USER BANK
	LD	A,(BL_COUNT)		; GET SECTORS TO READ
	LD	E,A			; NUMBER OF SECTORS TO LOAD
	RST	08
	JP	NZ,DB_ERR		; HANDLE ERRORS
;	
	; PASS BOOT DEVICE/UNIT/LU TO CBIOS COLD BOOT
	LD	B,BF_SYSSET		; HB FUNC: SET HBIOS PARAMETER
	LD	C,BF_SYSSET_BOOTINFO	; HB SUBFUNC: SET BOOT INFO
	LD	A,(HB_CURBNK)		; GET CURRENT BANK ID FROM PROXY DATA
	LD	L,A			; ... AND SAVE AS BOOT BANK
	LD	A,(BL_DEVICE)		; LOAD BOOT DEVICE/UNIT
	LD	D,A			; SAVE IN D
	LD	A,(BL_LU)		; LOAD BOOT LU
	LD	E,A			; SAVE IN E
	RST	08
	JP	NZ,DB_ERR		; HANDLE ERRORS
;
#IF (DSKYENABLE)
	LD	HL,MSG_GO		; POINT TO BOOT MESSAGE	
	CALL 	DSKY_SHOWSEG		; DISPLAY MESSAGE
#ENDIF
;	
	; JUMP TO COLD BOOT ENTRY
	LD	A,BID_USR		; ACTIVATE USER BANK
	LD	HL,(BB_CPMENT)		; OS ENTRY ADDRESS
	;DI				; ENTER WITH INTS DISABLED
	CALL	HB_BNKCALL		; AND GO
	HALT				; WE SHOULD NEVER RETURN!!!
;
#ENDIF
;
DB_NODISK:
	; SELDSK DID NOT LIKE DRIVE SELECTION
	LD	DE,STR_NODISK
	JP	MENU
;
DB_NOBOOT:
	; DISK IS NOT BOOTABLE
	LD	DE,STR_NOBOOT
	JP	MENU
;
DB_ERR:
	; I/O ERROR DURING BOOT ATTEMPT
	LD	DE,STR_BOOTERR
	JP	MENU
;
#IF (BIOS == BIOS_UNA)
;
; PRINT LIST OF ALL DRIVES UNDER UNA
;
PRTALL:
	LD	B,0			; START WITH UNIT 0
;
PRTALL1:	; LOOP THRU ALL UNITS AVAILABLE
	LD	C,$48			; UNA FUNC: GET DISK TYPE
	LD	L,0			; PRESET UNIT COUNT TO ZERO
	RST	08			; CALL UNA, B IS ASSUMED TO BE UNTOUCHED!!!
	LD	A,L			; UNIT COUNT TO A
	OR	A			; PAST END?
	RET	Z			; WE ARE DONE
	PUSH	BC			; SAVE UNIT
	CALL	PRTDRV			; PROCESS THE UNIT
	POP	BC			; RESTORE UNIT
	INC	B			; NEXT UNIT
	JR	PRTALL1		; LOOP
;
; PRINT THE UNA UNIT INFO
; ON INPUT B HAS UNIT
;
PRTDRV:
	PUSH	BC			; SAVE UNIT
	PUSH	DE			; SAVE DISK TYPE
	LD	A,'('			; NEWLINE AND SPACING
	CALL	COUT			; PRINT IT
	LD	A,B			; DRIVE LETTER TO A
	CALL	PRTDECB
	LD	A,')'			; DRIVE LETTER COLON
	CALL	COUT			; PRINT IT
	POP	DE			; RECOVER DISK TYPE
	LD	A,D			; DISK TYPE TO A
	CP	$40			; RAM/ROM?
	JR	Z,PRTDRV1		; HANDLE RAM/ROM
	LD	DE,DEVIDE		; ASSUME IDE
	CP	$41			; IDE?
	JR	Z,PRTDRV2		; PRINT IT
	LD	DE,DEVPPIDE		; ASSUME PPIDE
	CP	$42			; PPIDE?
	JR	Z,PRTDRV2		; PRINT IT
	LD	DE,DEVSD		; ASSUME SD
	CP	$43			; SD?
	JR	Z,PRTDRV2		; PRINT IT
	LD	DE,DEVDSD		; ASSUME DSD
	CP	$44			; DSD?
	JR	Z,PRTDRV2		; PRINT IT
	LD	DE,DEVUNK		; OTHERWISE UNKNOWN
	JR	PRTDRV2
;
PRTDRV1:	; HANDLE RAM/ROM
	LD	C,$45			; UNA FUNC: GET DISK INFO
	LD	DE,BL_INFOSEC		; 512 BYTE BUFFER
	RST	08			; CALL UNA
	BIT	7,B			; TEST RAM DRIVE BIT
	LD	DE,DEVROM		; ASSUME ROM
	JR	Z,PRTDRV2		; IF SO, PRINT IT
	LD	DE,DEVRAM		; OTHERWISE RAM
	JR	PRTDRV2			; PRINT IT
;
PRTDRV2:	; PRINT DEVICE
	POP	BC			; RECOVER UNIT
	CALL	WRITESTR		; PRINT DEVICE NAME
	LD	A,B			; UNIT TO A
	ADD	A,'0'			; MAKE IT PRINTABLE NUMERIC			
	CALL	COUT			; PRINT IT
	LD	A,','			; DEVICE NAME SEPARATOR
	CALL	COUT			; PRINT IT
	RET				; DONE
;
DEVRAM		.DB	"RAM$"
DEVROM		.DB	"ROM$"
DEVIDE		.DB	"IDE$"
DEVPPIDE	.DB	"PPIDE$"
DEVSD		.DB	"SD$"
DEVDSD		.DB	"DSD$"
DEVUNK		.DB	"UNK$"
;
#ELSE
;
; PRINT LIST OF ALL DRIVES
;
PRTALL:
;
	LD	B,BF_SYSGET
	LD	C,BF_SYSGET_DIOCNT
	RST	08		; E := DISK UNIT COUNT
	LD	B,E		; COUNT TO B
	LD	A,B		; COUNT TO A
	OR	A		; SET FLAGS
	RET	Z		; BAIL OUT IF ZERO
	LD	C,0		; INIT DEVICE INDEX
;
PRTALL1:
	LD	A,'('		; FORMATTING
	CALL	COUT		; PRINT IT
	LD	A,C		; INDEX TO A
	CALL	PRTDECB
	LD	A,')'		; FORMATTING
	CALL	COUT		; PRINT IT
	PUSH	BC		; SAVE LOOP CONTROL
	LD	B,BF_DIODEVICE	; HBIOS FUNC: REPORT DEVICE INFO
	RST	08		; CALL HBIOS
	CALL 	PRTDRV		; PRINT IT
	POP	BC		; RESTORE LOOP CONTROL
	INC	C		; BUMP INDEX
	DJNZ	PRTALL1		; LOOP AS NEEDED
	RET			; DONE
;
; PRINT THE DRIVER DEVICE/UNIT INFO
; ON INPUT D HAS DRIVER ID, E HAS DRIVER MODE/UNIT
; DESTROY NO REGISTERS OTHER THAN A
;
PRTDRV:
	PUSH	DE		; PRESERVE DE
	PUSH	HL		; PRESERVE HL
	LD	A,D		; LOAD DEVICE/UNIT
	RRCA			; ROTATE DEVICE
	RRCA			; ... BITS
	RRCA			; ... INTO
	RRCA			; ... LOWEST 4 BITS
	AND	$0F		; ISOLATE DEVICE BITS
	ADD	A,A		; MULTIPLE BY TWO FOR WORD TABLE
	LD	HL,DEVTBL	; POINT TO START OF DEVICE NAME TABLE
	CALL	ADDHLA		; ADD A TO HL TO POINT TO TABLE ENTRY
	LD	A,(HL)		; DEREFERENCE HL TO LOC OF DEVICE NAME STRING
	INC	HL		; ...
	LD	D,(HL)		; ...
	LD	E,A		; ...
	CALL	WRITESTR	; PRINT THE DEVICE NMEMONIC
	POP	HL		; RECOVER HL
	POP	DE		; RECOVER DE
	LD	A,E		; LOAD DRIVER MODE/UNIT
	AND	$0F		; ISOLATE UNIT
	CALL	PRTDECB		; PRINT IT
	CALL	PC_SPACE	; FORMATTING
	;LD	A,E		; LOAD LU
	;CALL	PRTDECB		; PRINT IT
	RET
;
DEVTBL:	; DEVICE TABLE
	.DW	DEV00, DEV01, DEV02, DEV03
	.DW	DEV04, DEV05, DEV06, DEV07
	.DW	DEV08, DEV09, DEV10, DEV11
	.DW	DEV12, DEV13, DEV14, DEV15
;
DEVUNK	.DB	"???$"
DEV00	.DB	"MD$"
DEV01	.DB	"FD$"
DEV02	.DB	"RAMF$"
DEV03	.DB	"IDE$"
DEV04	.DB	"ATAPI$"
DEV05	.DB	"PPIDE$"
DEV06	.DB	"SD$"
DEV07	.DB	"PRPSD$"
DEV08	.DB	"PPPSD$"
DEV09	.DB	"HDSK$"
DEV10	.EQU	DEVUNK
DEV11	.EQU	DEVUNK
DEV12	.EQU	DEVUNK
DEV13	.EQU	DEVUNK
DEV14	.EQU	DEVUNK
DEV15	.EQU	DEVUNK
;
#ENDIF
;
;==================================================================================================
;   STRINGS
;==================================================================================================
;
STR_BANNER	.DB	"\r\n\r\n", PLATFORM_NAME, " Boot Loader$"
STR_BOOTSEL	.DB	"\r\n\r\nBoot Selection? $"
STR_SLICESEL	.DB	"    Slice(0-9)[0]? $"
STR_BOOTDISK	.DB	"\r\n\r\nBooting Disk Unit $"
STR_BOOTDISK1	.DB	", Slice $"
STR_BOOTROM	.DB	"\r\n\r\nLoading $"
STR_REBOOT	.DB	"\r\n\r\nRestarting System...$"
STR_INVALID	.DB	"\r\n\r\n*** Invalid Selection ***$"
STR_NODISK	.DB	"\r\n\r\nNo disk!$"
STR_NOBOOT	.DB	"\r\n\r\nDisk not bootable!$"
STR_BOOTERR	.DB	"\r\n\r\nBoot failure!$"
STR_BOOTREAD	.DB	"\r\n\r\nReading disk information...$"
STR_LOADING	.DB	"\r\n\r\nLoading...$"
;
#IF (DSKYENABLE)
MSG_SEL		.DB	$FF,$9D,$9D,$8F,$EC,$80,$80,$80	; "Boot?   "
MSG_BOOT	.DB	$FF,$9D,$9D,$8F,$00,$00,$00,$80	; "Boot... "
MSG_LOAD	.DB	$8B,$9D,$FD,$BD,$00,$00,$00,$80	; "Load... "
MSG_GO		.DB	$DB,$9D,$00,$00,$00,$80,$80,$80	; "Go...   "
#ENDIF


;
;==================================================================================================
;   INCLUDES
;==================================================================================================
;
#DEFINE USEDELAY
#INCLUDE "util.asm"
;
#IF (DSKYENABLE)
#DEFINE	DSKY_KBD
#INCLUDE "dsky.asm"
#ENDIF
;
;==================================================================================================
; CONSOLE CHARACTER I/O HELPER ROUTINES (REGISTERS PRESERVED)
;==================================================================================================
;
#IF (BIOS == BIOS_WBW)
;
; OUTPUT CHARACTER FROM A
;
COUT:
	; SAVE ALL INCOMING REGISTERS
	PUSH	AF
	PUSH	BC
	PUSH	DE
	PUSH	HL
;
	; OUTPUT CHARACTER TO CONSOLE VIA HBIOS
	LD	E,A			; OUTPUT CHAR TO E
	LD	C,CIODEV_CONSOLE	; CONSOLE UNIT TO C
	LD	B,BF_CIOOUT		; HBIOS FUNC: OUTPUT CHAR
	RST	08			; HBIOS OUTPUTS CHARACTDR
;
	; RESTORE ALL REGISTERS
	POP	HL
	POP	DE
	POP	BC
	POP	AF
	RET
;
; INPUT CHARACTER TO A
;
CIN:
	; SAVE INCOMING REGISTERS (AF IS OUTPUT)
	PUSH	BC
	PUSH	DE
	PUSH	HL
;
	; INPUT CHARACTER FROM CONSOLE VIA HBIOS
	LD	C,CIODEV_CONSOLE	; CONSOLE UNIT TO C
	LD	B,BF_CIOIN		; HBIOS FUNC: INPUT CHAR
	RST	08			; HBIOS READS CHARACTDR
	LD	A,E			; MOVE CHARACTER TO A FOR RETURN
;
	; RESTORE REGISTERS (AF IS OUTPUT)
	POP	HL
	POP	DE
	POP	BC
	RET
;
; RETURN INPUT STATUS IN A (0 = NO CHAR, !=0 CHAR WAITING)
;
CST:
	; SAVE INCOMING REGISTERS (AF IS OUTPUT)
	PUSH	BC
	PUSH	DE
	PUSH	HL
;
	; GET CONSOLE INPUT STATUS VIA HBIOS
	LD	C,CIODEV_CONSOLE	; CONSOLE UNIT TO C
	LD	B,BF_CIOIST		; HBIOS FUNC: INPUT STATUS
	RST	08			; HBIOS RETURNS STATUS IN A
;
	; RESTORE REGISTERS (AF IS OUTPUT)
	POP	HL
	POP	DE
	POP	BC
	RET
;
#ENDIF
;
#IF (BIOS == BIOS_UNA)
;
; OUTPUT CHARACTER FROM A
;
COUT:
	; SAVE ALL INCOMING REGISTERS
	PUSH	AF
	PUSH	BC
	PUSH	DE
	PUSH	HL
;
	; OUTPUT CHARACTER TO CONSOLE VIA UBIOS
	LD	E,A
	LD	BC,$12
	RST	08
;
	; RESTORE ALL REGISTERS
	POP	HL
	POP	DE
	POP	BC
	POP	AF
	RET
;
; INPUT CHARACTER TO A
;
CIN:
	; SAVE INCOMING REGISTERS (AF IS OUTPUT)
	PUSH	BC
	PUSH	DE
	PUSH	HL
;
	; INPUT CHARACTER FROM CONSOLE VIA UBIOS
	LD	BC,$11
	RST	08
	LD	A,E
;
	; RESTORE REGISTERS (AF IS OUTPUT)
	POP	HL
	POP	DE
	POP	BC
	RET
;
; RETURN INPUT STATUS IN A (0 = NO CHAR, !=0 CHAR WAITING)
;
CST:
	; SAVE INCOMING REGISTERS (AF IS OUTPUT)
	PUSH	BC
	PUSH	DE
	PUSH	HL
;
	; GET CONSOLE INPUT STATUS VIA UBIOS
	LD	BC,$13
	RST	08
	LD	A,E
;
	; RESTORE REGISTERS (AF IS OUTPUT)
	POP	HL
	POP	DE
	POP	BC
	RET
;
#ENDIF
;
; READ A CONSOLE CHARACTER AND CONVERT TO UPPER CASE
;
CINUC:
	CALL	CIN
	AND	7FH			; STRIP HI BIT
	CP	'A'			; KEEP NUMBERS, CONTROLS
	RET	C			; AND UPPER CASE
	CP	7BH			; SEE IF NOT LOWER CASE
	RET	NC
	AND	5FH			; MAKE UPPER CASE
	RET
;
;==================================================================================================
;   FILL REMAINDER OF BANK
;==================================================================================================
;
SLACK:		.EQU	($8000 + LDR_SIZ - $)
		.FILL	SLACK
;
		.ECHO	"LOADER space remaining: "
		.ECHO	SLACK
		.ECHO	" bytes.\n"
;
;==================================================================================================
;   WORKING DATA STORAGE
;==================================================================================================
		.ORG	$8000 + LDR_SIZ
;
		.DS	64		; 32 LEVEL STACK
BL_STACK	.EQU	$		; ... TOP IS HERE
;
BL_INPFLG	.DS	1		; INPUT FLAG, 1=DSKY, 2=SERIAL
BL_COUNT	.DS	1		; LOAD COUNTER
BL_TIMEOUT	.DS	2		; AUTOBOOT TIMEOUT COUNTDOWN COUNTER
BL_BOOTID	.DS	1		; BOOT DEVICE ID CHOSEN BY USER
BL_DEVICE	.DS	1		; DEVICE TO LOAD FROM
BL_LU		.DS	1		; LU TO LOAD FROM
;
; BOOT INFO SECTOR IS READ INTO AREA BELOW
; THE THIRD SECTOR OF A DISK DEVICE IS RESERVED FOR BOOT INFO
;
BL_INFOSEC	.EQU	$
		.DS	(512 - 128)
BB_METABUF	.EQU	$
BB_SIG		.DS	2	; SIGNATURE (WILL BE 0A55AH IF SET)
BB_PLATFORM	.DS	1	; FORMATTING PLATFORM
BB_DEVICE	.DS	1	; FORMATTING DEVICE
BB_FORMATTER	.DS	8	; FORMATTING PROGRAM
BB_DRIVE	.DS	1	; PHYSICAL DISK DRIVE #
BB_LU		.DS	1	; LOGICAL UNIT (LU)
		.DS	1	; MSB OF LU, NOW DEPRECATED
		.DS	(BB_METABUF + 128) - $ - 32
BB_PROTECT	.DS	1	; WRITE PROTECT BOOLEAN
BB_UPDATES	.DS	2	; UPDATE COUNTER
BB_RMJ		.DS	1	; RMJ MAJOR VERSION NUMBER
BB_RMN		.DS	1	; RMN MINOR VERSION NUMBER
BB_RUP		.DS	1	; RUP UPDATE NUMBER
BB_RTP		.DS	1	; RTP PATCH LEVEL
BB_LABEL	.DS	16	; 16 CHARACTER DRIVE LABEL
BB_TERM		.DS	1	; LABEL TERMINATOR ('$')
BB_BILOC	.DS	2	; LOC TO PATCH BOOT DRIVE INFO TO (IF NOT ZERO)
BB_CPMLOC	.DS	2	; FINAL RAM DESTINATION FOR CPM/CBIOS
BB_CPMEND	.DS	2	; END ADDRESS FOR LOAD
BB_CPMENT	.DS	2	; CP/M ENTRY POINT (CBIOS COLD BOOT)
;
	.END

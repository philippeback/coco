; =============================================================================
; BALLML.ASM - 6809 Machine Language 60 FPS Boing Ball Engine for Tandy CoCo 1
; Assemble with:
;   lwasm -9 -b -f raw -o ballml.raw --list=ballml.lst BALLML.ASM
; =============================================================================
; Memory Map (with PCLEAR 8 and CLEAR 200,&H5FFF):
;   $0600-$1DFF : Video Buffer A (Pages 1-4, PMODE 3) -> Base stored at $00BC!
;   $1E00-$35FF : Video Buffer B (Pages 5-8, PMODE 3) -> Base + $1800!
;   $6000-$623F : Circular AND Mask (12 bytes x 48 rows = 576 bytes)
;   $6240-$743F : 8 Rotation Frames (8 x 576 bytes = 4608 bytes)
;   $7440-$767F : Saved Background Patch G0 (Page 1, 576 bytes)
;   $7680-$78BF : Saved Background Patch G1 (Page 5, 576 bytes)
;   $7D00-$7FFF : 6809 Machine Language Engine & State Variables
; =============================================================================

        ORG     $7D00

;Fixed entry points for BASIC DEFUSR0 and DEFUSR1:
USR0_ENTRY      JMP     CAPTURE_PATCH   ; $7D00: Copy 48x48 from (8,8) to [$7FFE]
USR1_ENTRY      JMP     RUN_ENGINE      ; $7D03: Run 60 FPS page-flipped bounce loop

; -----------------------------------------------------------------------------
; State Variables
; -----------------------------------------------------------------------------
BX_SUB          FCB     16              ; X byte col * 4 (8..72 -> col 2..18)
VX_SUB          FCB     1               ; Horizontal speed (+1 or -1)
BY_FP           FDB     $0140           ; 12.4 fixed-point Y (20 * 16 = 320)
VY_FP           FDB     $0000           ; 12.4 fixed-point vertical velocity
FR_CNT          FCB     0               ; Rotation counter
DR_STEP         FCB     1               ; Rotation direction (+1 or -1)
OLD0_ADDR       FDB     $0884           ; Previous ball address on Page 1 ($0600)
OLD1_ADDR       FDB     $2084           ; Previous ball address on Page 5 ($1E00)

; -----------------------------------------------------------------------------
; USR0 ($7D00 -> CAPTURE_PATCH):
;   Copies 48x48 patch (12 bytes x 48 scanlines = 576 bytes) from (8,8) on
;   Page 1 ($0600 + 8*32 + 1 = $0701) to destination address in $7FFE:$7FFF.
; -----------------------------------------------------------------------------
CAPTURE_PATCH:
        PSHS    U,Y,X,D
        LDX     #$0701                  ; Source = (8,8) on Page 1 ($0600 + $0101)
        LDU     $7FFE                   ; Destination address poked by BASIC
        BSR     SAVE_BG
        PULS    D,X,Y,U,PC

; -----------------------------------------------------------------------------
; SAVE_BG: Copy 48 rows x 12 bytes from screen (X) to linear buffer (U)
; -----------------------------------------------------------------------------
SAVE_BG:
        LDB     #48
SAVE_ROW:
        PSHS    B
        LDD     ,X++
        STD     ,U++
        LDD     ,X++
        STD     ,U++
        LDD     ,X++
        STD     ,U++
        LDD     ,X++
        STD     ,U++
        LDD     ,X++
        STD     ,U++
        LDD     ,X++
        STD     ,U++
        LEAX    20,X                    ; Next scanline (32 - 12 = 20)
        PULS    B
        DECB
        BNE     SAVE_ROW
        RTS

; -----------------------------------------------------------------------------
; RESTORE_BG: Copy 48 rows x 12 bytes from linear buffer (X) to screen (U)
; -----------------------------------------------------------------------------
RESTORE_BG:
        LDB     #48
REST_ROW:
        PSHS    B
        LDD     ,X++
        STD     ,U++
        LDD     ,X++
        STD     ,U++
        LDD     ,X++
        STD     ,U++
        LDD     ,X++
        STD     ,U++
        LDD     ,X++
        STD     ,U++
        LDD     ,X++
        STD     ,U++
        LEAU    20,U                    ; Next scanline (32 - 12 = 20)
        PULS    B
        DECB
        BNE     REST_ROW
        RTS

; -----------------------------------------------------------------------------
; USR1 ($7D03 -> RUN_ENGINE):
;   Main 60 FPS VSYNC-locked hardware page-flipping animation loop
; -----------------------------------------------------------------------------
RUN_ENGINE:
        PSHS    CC,DP,U,Y,X,D
        ORCC    #$50                    ; Disable IRQ/FIRQ during high-speed blitting

        ; Initialize state variables
        LDD     #$1001                  ; BX_SUB = 16 (col 4), VX_SUB = +1
        STD     BX_SUB
        LDD     #$0140                  ; BY_FP = 20 * 16
        STD     BY_FP
        LDD     #$0000                  ; VY_FP = 0
        STD     VY_FP
        LDD     #$0001                  ; FR_CNT = 0, DR_STEP = +1
        STD     FR_CNT
        LDD     #$0884                  ; $0600 + 20*32 + 4 = $0884
        STD     OLD0_ADDR
        LDD     #$2084                  ; $1E00 + 20*32 + 4 = $2084
        STD     OLD1_ADDR

        ; Save initial background patches into G0 ($7440) and G1 ($7680)
        LDX     OLD0_ADDR
        LDU     #$7440
        JSR     SAVE_BG
        LDX     OLD1_ADDR
        LDU     #$7680
        JSR     SAVE_BG

MAIN_LOOP:
        ; --- 1) Render on hidden Page 5 ($1E00) while Page 1 ($0600) is shown ---
        LDU     OLD1_ADDR
        LDX     #$7680                  ; G1 background buffer
        JSR     RESTORE_BG

        JSR     STEP_PHYSICS            ; Returns D = Y*32 + X_col
        ADDD    #$1E00                  ; Add Page 5 base address ($1E00)
        STD     OLD1_ADDR
        TFR     D,X
        LDU     #$7680
        JSR     SAVE_BG

        LDU     OLD1_ADDR
        JSR     DRAW_BALL

        JSR     WAIT_VSYNC
        ; Flip SAM display address to Page 5 ($1E00 -> F = 15 = %0001111):
        ; Page 1 ($0600) is F = 3 (%0000011). Set F2 ($FFCB) and F3 ($FFCD)!
        STA     $FFCB                   ; Set SAM F2
        STA     $FFCD                   ; Set SAM F3 -> Page 5 ($1E00) now visible!

        ; --- 2) Render on hidden Page 1 ($0600) while Page 5 ($1E00) is shown ---
        LDU     OLD0_ADDR
        LDX     #$7440                  ; G0 background buffer
        JSR     RESTORE_BG

        JSR     STEP_PHYSICS            ; Returns D = Y*32 + X_col
        ADDD    #$0600                  ; Add Page 1 base address ($0600)
        STD     OLD0_ADDR
        TFR     D,X
        LDU     #$7440
        JSR     SAVE_BG

        LDU     OLD0_ADDR
        JSR     DRAW_BALL

        JSR     WAIT_VSYNC
        ; Flip SAM display address back to Page 1 ($0600 -> F = 3 = %0000011):
        ; Clear F2 ($FFCA) and Clear F3 ($FFCC)!
        STA     $FFCA                   ; Clear SAM F2
        STA     $FFCC                   ; Clear SAM F3 -> Page 1 ($0600) now visible!

        ; Check keyboard matrix for BREAK key to exit cleanly to BASIC
        LDA     #$FB                    ; Strobe column 2 (BREAK)
        STA     $FF02
        LDA     $FF00
        ANDA    #$40                    ; Row 6 = BREAK
        BEQ     EXIT_ENGINE
        JMP     MAIN_LOOP

EXIT_ENGINE:
        ; Ensure SAM display is pointing to Page 1 ($0600) before returning
        STA     $FFCA
        STA     $FFCC
        PULS    D,X,Y,U,DP,CC,PC

; -----------------------------------------------------------------------------
; DRAW_BALL: Masked 48x48 sprite blit onto screen at U
;   Mask:   $6000 (576 bytes)
;   Sprite: $6240 + ((FR_CNT / 2) & 7) * 576
; -----------------------------------------------------------------------------
DRAW_BALL:
        LDA     FR_CNT
        LSRA                            ; Advance rotation every 2nd 60Hz frame
        ANDA    #$07                    ; 8 rotation frames (0..7)
        LDB     #9                      ; 9 * 64 = 576 bytes per frame
        MUL                             ; D = frame * 9
        ASLB
        ROLA
        ASLB
        ROLA
        ASLB
        ROLA
        ASLB
        ROLA
        ASLB
        ROLA
        ASLB
        ROLA                            ; D = frame * 576 ($0240)
        ADDD    #$6240
        TFR     D,Y                     ; Y = current rotation frame pointer
        LDX     #$6000                  ; X = circular AND mask pointer
        LDB     #48                     ; 48 scanlines
DRAW_ROW:
        PSHS    B
        ; Unrolled 12-byte (48-pixel) scanline composite (6 x 16-bit words)
        LDD     ,U
        ANDA    ,X+
        ANDB    ,X+
        ORA     ,Y+
        ORB     ,Y+
        STD     ,U++

        LDD     ,U
        ANDA    ,X+
        ANDB    ,X+
        ORA     ,Y+
        ORB     ,Y+
        STD     ,U++

        LDD     ,U
        ANDA    ,X+
        ANDB    ,X+
        ORA     ,Y+
        ORB     ,Y+
        STD     ,U++

        LDD     ,U
        ANDA    ,X+
        ANDB    ,X+
        ORA     ,Y+
        ORB     ,Y+
        STD     ,U++

        LDD     ,U
        ANDA    ,X+
        ANDB    ,X+
        ORA     ,Y+
        ORB     ,Y+
        STD     ,U++

        LDD     ,U
        ANDA    ,X+
        ANDB    ,X+
        ORA     ,Y+
        ORB     ,Y+
        STD     ,U++

        LEAU    20,U                    ; Next scanline (32 - 12 = 20)
        PULS    B
        DECB
        LBNE    DRAW_ROW
        RTS

; -----------------------------------------------------------------------------
; STEP_PHYSICS: Updates X, Y, rotation, bounce audio, returns D = Y*32 + X_col
; -----------------------------------------------------------------------------
STEP_PHYSICS:
        ; 1) Horizontal position (BX_SUB = column * 4)
        LDA     BX_SUB
        ADDA    VX_SUB
        CMPA    #8                      ; Left wall = byte col 2 (pixel 8)
        BGE     CHK_RIGHT
        LDA     #8
        NEG     VX_SUB
        NEG     DR_STEP
        BSR     WALL_BEEP
        BRA     X_DONE
CHK_RIGHT:
        CMPA    #72                     ; Right wall = byte col 18 (pixel 72)
        BLE     X_DONE
        LDA     #72
        NEG     VX_SUB
        NEG     DR_STEP
        BSR     WALL_BEEP
X_DONE:
        STA     BX_SUB

        ; 2) Rotation step
        LDA     FR_CNT
        ADDA    DR_STEP
        STA     FR_CNT

        ; 3) Vertical 12.4 fixed-point gravity & floor bounce
        LDD     VY_FP
        ADDD    #6                      ; Gravity acceleration
        STD     VY_FP
        ADDD    BY_FP
        CMPD    #$0840                  ; Floor = Y 132 * 16 = $0840
        BLE     Y_DONE
        LDD     #-$00A8                 ; Rebound velocity (-168)
        STD     VY_FP
        BSR     FLOOR_BEEP
        LDD     #$0840                  ; Clamp to floor Y = 132
Y_DONE:
        STD     BY_FP

        ; 4) Compute screen offset D = Y*32 + X_col
        ANDB    #$F0                    ; Clear fractional 4 bits -> D = Y * 16
        ASLB
        ROLA                            ; D = Y * 32
        PSHS    D
        LDB     BX_SUB
        LSRB
        LSRB                            ; B = byte column (2..18)
        CLRA
        ADDD    ,S++                    ; D = Y * 32 + X_col
        RTS

; -----------------------------------------------------------------------------
; WAIT_VSYNC: Synchronize to 60 Hz MC6847 VDG Vertical Sync via PIA0
; -----------------------------------------------------------------------------
WAIT_VSYNC:
        LDA     $FF02                   ; Clear any stale VSYNC flag
VSYNC_LOOP:
        LDA     $FF03                   ; Bit 7 = VSYNC interrupt flag
        BPL     VSYNC_LOOP
        LDA     $FF02                   ; Acknowledge VSYNC flag
        RTS

; -----------------------------------------------------------------------------
; DAC Audio Clicks (WALL_BEEP and FLOOR_BEEP)
; -----------------------------------------------------------------------------
WALL_BEEP:
        LDB     #55                     ; Higher pitch delay
        BRA     DO_BEEP
FLOOR_BEEP:
        LDB     #135                    ; Deep thud delay
DO_BEEP:
        PSHS    D
        LDA     $FF23                   ; Enable 6-bit DAC sound multiplexer
        ORA     #$08
        STA     $FF23
        LDA     #10                     ; 10 square-wave cycles
BEEP_LOOP:
        PSHS    A
        LDA     #$FC                    ; DAC high
        STA     $FF20
        LDB     2,S                     ; Delay constant in B on stack
DLY_HI: DECB
        BNE     DLY_HI
        CLRA                            ; DAC low
        STA     $FF20
        LDB     2,S
DLY_LO: DECB
        BNE     DLY_LO
        PULS    A
        DECA
        BNE     BEEP_LOOP
        PULS    D,PC

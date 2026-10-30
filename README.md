# Amiga "Boing Ball" for Tandy CoCo 1 Extended BASIC (`BALL.BAS`)

A recreation of the classic 1984 Amiga "Boing Ball" demo written in **Tandy TRS-80 Color Computer 1 (CoCo 1) Extended Color BASIC**.

It uses **hardware page-flipping** (`PMODE 3,1` and `PMODE 3,5`), **pre-rendered 3D spherical projection**, and **masked `AND`/`OR` software sprites** so the checkered ball bounces smoothly and transparently over the perspective grid without flicker.

---

## Running the Program

If you have [XRoar](https://www.6809.org.uk/xroar/) installed, you can run [BALL.BAS](BALL.BAS) directly (or via the included VS Code build task in [.vscode/tasks.json](.vscode/tasks.json)):

```powershell
& 'C:\Program Files\6809.org.uk\XRoar 1.12\xroar.exe' -machine coco -load-text BALL.BAS
```

Then type `RUN` at the CoCo `OK` prompt.

> **Note:** At startup, the program pre-renders the mask and 4 rotation frames of the 3D sphere (~10–15 seconds with the high-speed hardware poke enabled) before switching to the animated bounce loop.

---

## Headless Verification (Docker)

For automated (AI-driven) verification, [toolchain/Dockerfile](toolchain/Dockerfile) builds a container with LWTOOLS, CMOC, ToolShed (`decb`), and headless **MAME**, exposing a one-shot `coco-verify` command (compile → disk image → boot → screen dump).

Note the deliberate emulator split: **XRoar** is used for interactive local runs, while the container uses **MAME** because its Lua API can dump the 6809 registers, GIME MMU registers, and the 80×25 text screen as plain text (`dump_vram.lua`) — XRoar has no Lua support.

---

## How the Code Works

### 1. Hardware Setup & High-Speed Mode (Lines `10–60`)
* **`POKE 65495,0` (`&HFFD7`)**: Activates the SAM (Synchronous Address Multiplexer) R1 high-speed mode, doubling the 6809E CPU clock from **0.895 MHz to 1.79 MHz** during ROM and internal operations.
* **`PCLEAR 8`**: Allocates all 8 graphics pages (12 KB of video RAM, since each page is 1.5 KB). Because `PMODE 3` requires **4 pages (6 KB)** per screen (`128×192` at 2 bits per pixel), 8 pages gives us two complete `PMODE 3` screen buffers:
  * **Buffer A**: Pages `1–4` (starts at page `1`)
  * **Buffer B**: Pages `5–8` (starts at page `5`)
* **`PMODE 3,1` & `SCREEN 1,1`**: Selects Color Set 1 on the Motorola MC6847 VDG:
  * `5` = **Buff** (White)
  * `6` = **Cyan**
  * `7` = **Magenta**
  * `8` = **Orange** (Reddish-Orange)
* **Sprite Arrays (`DIM`)**:
  * `B0(75)`–`B3(75)`: 4 rotation frames of the `48×48` ball sprite.
  * `MK(75)`: Circular `48×48` transparency bitmask.
  * `G0(75)`, `G1(75)`: Saved background patches for Buffer A (Page 1) and Buffer B (Page 5).

---

### 2. Circular Sprite Transparency via `PMODE 4` Bit Trick (Lines `70–320`)
In CoCo Extended BASIC `PMODE 3` (Color Set 1), the 2-bit pixel encodings in video RAM are:
| Color Number | Color Name | 2-Bit Pixel Value |
| :---: | :--- | :---: |
| `5` | Buff (White) | `00` |
| `6` | Cyan | `01` |
| `7` | Magenta | `10` |
| `8` | Orange | `11` |

Because **Buff is `00`** (all zeros) instead of `11`, drawing a sprite on a Buff background and using `PUT ..., OR` normally wouldn't work cleanly—and `PUT ..., PSET` would draw an ugly `48×48` rectangular box over the Magenta grid lines.

To get **true circular transparency** without slow byte-by-byte `PEEK`/`POKE` loops:
1. **Building the `AND` Mask (`MK`, Lines `70–130`)**:
   * The program temporarily switches to `PMODE 4,1` (2-color mode, where `1` = bit `1` and `0` = bit `0`).
   * `PCLS 1` fills the entire video memory with `11111111` bytes (`&HFF`).
   * A loop draws horizontal `PRESET` (`0`) scanlines inside the circle of radius `RA=22`, punching a circular hole of `00000000` bits in the middle while leaving `11111111` outside the circle.
   * Switching back to `PMODE 3,1`, `GET(8,8)-(56,56),MK,G` captures that exact bit pattern as our `AND` mask!
2. **Pre-Rendering the 4 Sphere Frames (`B0`–`B3`, Lines `140–320`)**:
   * Before rendering each frame (`F = 0 TO 3`), `PMODE 4,1:PCLS 0:PMODE 3,1` zeroes out video memory (`00` bits everywhere outside the sphere).
   * Inside the sphere, 3D spherical coordinates (`LA` = latitude band, `LO` = longitude band with a slight `DY*.012` axial tilt) are computed using `SQR` and `ATN`.
   * Alternating checks are plotted in **Buff (`5` = `00`)** and **Orange (`8` = `11`)**, finished with a `CIRCLE(32,32),RA,8` outline, and captured into `B0`–`B3`.

When compositing at runtime:
* `PUT ..., MK, AND` keeps the exterior background intact (`bg AND 11 = bg`) and clears the interior of the circle to `00` (**Buff**!).
* `PUT ..., B0, OR` overlays the **Orange (`11`)** checks into the cleared circle while leaving both the **Buff (`00`)** checks and the exterior **Magenta (`10`)** grid untouched!

---

### 3. Perspective Grid & Dual-Page Setup (Lines `330–490`)
* Draws the classic Amiga back-wall grid and perspective floor grid in **Magenta (`7`)** over **Buff (`5`)** on Page 1.
* **`PCOPY 1 TO 5:PCOPY 2 TO 6:PCOPY 3 TO 7:PCOPY 4 TO 8`**: Copies all 4 pages of the finished background into the second video buffer (Pages `5–8`).

---

### 4. Hardware Page-Flipping Animation Loop (Lines `500–790`)
A key feature of CoCo Extended BASIC is that **`PMODE 3,p` changes the active drawing page without changing the visible screen**—the VDG/SAM continues displaying the previous page until `SCREEN 1,1` is executed!

Each pair of frames alternates between Buffer B (`PMODE 3,5`) and Buffer A (`PMODE 3,1`):
1. **Select Hidden Page** (`PMODE 3,5` or `PMODE 3,1`).
2. **Restore Previous Background** (`PUT ..., G1, PSET` or `G0`) at the old ball coordinates on that page.
3. **Update Physics (`GOSUB 700`)**:
   * Advances position `(BX, BY)` and applies gravity `GY=3` to `VY`.
   * Bounces off the left/right walls (`BX<16` or `BX>190`), reversing horizontal velocity `VX`, reversing rotation direction `DR`, and playing a high pitch `SOUND 140,1`.
   * Bounces off the floor (`BY>132`), resetting upward velocity `VY=-24` and playing a deep thud `SOUND 60,1`.
   * Steps the rotation frame `FR = (FR + DR) AND 3`.
4. **Save New Background Patch** (`GET ..., G1, G` or `G0`) at the new `(BX, BY)`.
5. **Draw Masked Ball**:
   * `PUT(BX,BY)-(BX+48,BY+48),MK,AND` (punch circular hole)
   * `PUT(BX,BY)-(BX+48,BY+48),B0..B3,OR` (stamp rotated sphere)
6. **Flip Display Page (`SCREEN 1,1`)**: Instantly switches the video hardware to display the newly rendered page while the next iteration draws on the other page.

---

## CoCo Extended BASIC Quirks Handled
* **2-Character Variable Names**: All variable names (`RA`, `R2`, `P0`, `FP`, `DX`, `DY`, `X0`, `Y0`, `X1`, `Y1`, `Y2`, `LA`, `LO`, `BX`, `BY`, `VX`, `VY`, `GY`, `FR`, `DR`, `B0`–`B3`, `MK`, `G0`, `G1`) are unique in their first 2 characters.
* **Tokenizer Keyword Collisions**: Uses `RA` instead of `R` for radius so `FOR DY=-RA TO RA STEP 2` cannot tokenize `R` + `STEP` into the reserved word `OR` if spaces are stripped.
* **Floating-Point Boundary Guard**: Uses `SQR(ABS(R2-DX*DX-Y2))` in line `220` to prevent `?FC ERROR` from microscopic negative rounding errors at the circle's edge.

---

## 60 FPS 6809 Machine Language Hybrid (`BALLML.BAS` & `gen_ml.py`)

While `BALL.BAS` runs entirely in interpreted BASIC, **[BALLML.BAS](BALLML.BAS)** is a self-contained BASIC + **Motorola 6809E Machine Language** hybrid that runs the bounce loop at a **locked 60 FPS (synced to hardware VSYNC)** with **8 rotation frames** instead of 4.

The 504-byte 6809 machine language engine (lines `900–1100` in `BALLML.BAS`) is generated by **[gen_ml.py](gen_ml.py)**.

### Memory Map (`CLEAR 200,&H5FFF`)
`BALLML.BAS` reserves high RAM above `$5FFF` so BASIC variables and strings never collide with the sprite buffers or 6809 code:

| Address Range | Size | Purpose |
| :--- | :--- | :--- |
| `$0600–$1DFF` | 6,144 B | **Video Buffer A** (`PMODE 3` Pages `1–4`) |
| `$1E00–$35FF` | 6,144 B | **Video Buffer B** (`PMODE 3` Pages `5–8`) |
| `$6000–$623F` | 576 B | **Circular `AND` Mask** (`12` bytes × `48` scanlines) |
| `$6240–$743F` | 4,608 B | **8 Rotation Frames** (`8` × `576` bytes) |
| `$7440–$767F` | 576 B | **Saved Background Patch `G0`** (for Buffer A / Page 1) |
| `$7680–$78BF` | 576 B | **Saved Background Patch `G1`** (for Buffer B / Page 5) |
| `$7D00–$7F17` | 536 B | **6809 Machine Language Engine** (`USR0` & `USR1`, assembled from [BALLML.ASM](BALLML.ASM)) |
| `$7FFE–$7FFF` | 2 B | **`USR0` Destination Pointer Argument** |

### Building `BALLML.BAS` with `lwasm`
The 6809 assembly source is in [BALLML.ASM](BALLML.ASM) and is assembled using `lwasm` (`lwtools 4.9`) via [build.ps1](build.ps1) and [gen_ml.py](gen_ml.py):

```powershell
# Assemble BALLML.ASM -> ballml.raw / ballml.lst and update DATA lines in BALLML.BAS
.\build.ps1

# Or assemble and immediately launch BALLML.BAS in XRoar
.\build.ps1 -Run
```

### How the 6809 Engine Works

#### 1. Fast Block-Copy Capture (`USR0` at `$7D00`)
During startup, BASIC pre-renders the circular mask and the 8 sphere frames at `(8,8)` on Page 1 (video RAM address `$0600 + 8*32 + 1 = $0701`). Instead of using slow `PEEK`/`POKE` loops in BASIC, BASIC pokes the target buffer address into `$7FFE–$7FFF` and calls `Z=USR0(0)`.
* `USR0` loads `X = #$0701` and `U = [$7FFE]`, then copies `48` rows of `12` bytes using 6 unrolled 16-bit `LDD ,X++` / `STD ,U++` pairs per scanline (`LEAX 20,X` advances `32 - 12 = 20` bytes to the next scanline).

#### 2. Unrolled 16-Bit Masked Sprite Blitter (`DRAW_BALL`)
When `Z=USR1(0)` (`$7D03`) is called, the 6809 takes over completely:
* Uses the 6809's hardware **`MUL`** instruction (`frame * 9`, shifted left 6 times = `frame * 576`) to compute the base address of the current rotation frame in `Y`, with the circular mask pointer in `X = #$6000` and screen pointer in `U`.
* Each 12-byte (48-pixel) row is composited in a single pass using 6 unrolled 16-bit operations:
  ```nasm
  LDD  ,U      ; Read 2 background bytes (8 pixels) from video RAM
  ANDA ,X+     ; Mask left byte with circular AND mask
  ANDB ,X+     ; Mask right byte with circular AND mask
  ORA  ,Y+     ; Overlay left byte of rotated sphere frame
  ORB  ,Y+     ; Overlay right byte of rotated sphere frame
  STD  ,U++    ; Write 2 finished bytes (8 pixels) back to video RAM
  ```

#### 3. 60 Hz Hardware VSYNC & Direct SAM Page Flipping (`WAIT_VSYNC`)
* Waits for the MC6847 VDG Vertical Sync impulse by polling bit 7 of **PIA0 Control Register A (`$FF03`)** and clearing the interrupt flag by reading `$FF02`.
* Immediately during vertical blanking, it flips the displayed screen between **Page 1 (`$0600`, SAM offset `F = 3 = %0000011`)** and **Page 5 (`$1E00`, SAM offset `F = 15 = %0001111`)** by writing directly to the SAM display offset registers:
  * **Show Page 5 (`$1E00`)**: `STA $FFCB` (set SAM bit F2) + `STA $FFCD` (set SAM bit F3).
  * **Show Page 1 (`$0600`)**: `STA $FFCA` (clear SAM bit F2) + `STA $FFCC` (clear SAM bit F3).

#### 4. Fixed-Point Physics, DAC Audio, and `BREAK` Detection (`STEP_PHYSICS`)
* **16-Bit Fixed-Point Gravity**: Vertical position (`BY_FP`) and velocity (`VY_FP`) use 12.4 fixed-point math (`Y * 16`), adding `+6` gravity per 60 Hz frame for a smooth parabolic arc.
* **6-Bit DAC Bounce Audio**: Wall and floor bounces toggle the CoCo's 6-bit DAC (`$FF20`, after enabling the sound multiplexer on `$FF23` bit 3) with pitch constants `55` (high wall click) and `135` (deep floor thud).
* **Clean Exit to BASIC**: Every frame strobes column 2 of the keyboard matrix (`LDA #$FB` -> `STA $FF02`, `LDA $FF00`, `ANDA #$40`). Pressing **BREAK** restores SAM display Page 1 and returns cleanly via `PULS D,X,Y,U,DP,CC,PC` back to the BASIC `OK` prompt.

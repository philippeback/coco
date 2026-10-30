# How-To: The CoCo 3 Toolchain Docker Container

Everything in this repository that needs a Linux toolchain runs inside the Docker image
built from [../toolchain/Dockerfile](../toolchain/Dockerfile). This document explains,
step by step: how to **build** the image, how to **map folders** (`/workspace`, `/roms`),
how to **get inside** the container, and how to do the things the container exists to do.

---

## 1. What this container is (and is not)

| Aspect | Answer |
| :--- | :--- |
| **Purpose** | Headless, reproducible *compile → boot → verify* of CoCo 3 bare-metal code (C via CMOC, asm via LWTOOLS), driven by an AI or CI loop. |
| **Contents** | LWTOOLS 4.24 (`lwasm`/`lwlink`/`lwobjdump`), CMOC 0.1.100, ToolShed (`decb`, `os9`), MAME 0.264 (headless), plus the `coco-verify` one-shot command. |
| **Image name** | `coco3toolchain:latest` |
| **Not** | Not the interactive emulator workflow — for *playing* with BASIC locally you use **XRoar** on Windows (see `build.ps1 -Run` and `.vscode/tasks.json`). The container uses **MAME** because its Lua API can dump CPU registers, GIME MMU registers, and the 80×25 text screen as plain text (`/opt/coco-harness/dump_vram.lua`). XRoar has no Lua support. |

---

## 2. Build the image

From the repository root (PowerShell):

```powershell
docker build -t coco3toolchain toolchain
```

Or from inside `toolchain\`:

```powershell
Set-Location toolchain
docker build -t coco3toolchain .
```

**Facts to know:**
- First build takes ~10 minutes (it compiles LWTOOLS, CMOC, and ToolShed from source and pulls ~1 GB of apt packages, MAME included).
- Subsequent builds are near-instant thanks to layer caching. Comment-only edits to the Dockerfile do **not** invalidate any layer.
- Verify the image exists: `docker images coco3toolchain`

---

## 3. Folder mapping: `/workspace` and `/roms`

The container is stateless. Two bind mounts give it everything it needs:

| Container path | Mount this | Why |
| :--- | :--- | :--- |
| `/workspace` | Your repository (or any source dir) | Default `WORKDIR`. All inputs (`main.c`) and all outputs (`fenetre.bin`, `fenetre.dsk`, `screen_dump.txt`) live here, so results survive container exit. |
| `/roms` | A folder with your MAME ROMs | MAME needs the CoCo 3 BIOS ROMs. `coco-verify` uses `/roms` **if it exists**, otherwise falls back to `./roms` (i.e. `workspace\roms`). |

PowerShell syntax (Docker Desktop accepts Windows paths directly):

```powershell
docker run --rm -it `
  -v "C:\Dev\github\philippeback\coco:/workspace" `
  -v "C:\path\to\mame\roms:/roms" `
  coco3toolchain
```

**About the ROMs folder:** MAME 0.264's `coco3` driver requires the official MAME ROM set
(`coco3.rom` CRC `b4c88d6c`, plus FDC/DOS ROMs like `disk10.rom`, `ados3.rom`, …).
The simplest form is the official **`coco3.zip`** dropped into the mounted folder.
Check what your MAME expects with: `mame coco3 -listroms`.

> ⚠️ These are **MAME** ROMs. They are unrelated to XRoar's own ROM directory
> (`%LOCALAPPDATA%\xroar` on Windows).

---

## 4. Getting inside the container

The image's default command is `/bin/bash`, so a plain interactive run is:

```powershell
docker run --rm -it -v "C:\Dev\github\philippeback\coco:/workspace" -v "C:\path\to\mame\roms:/roms" coco3toolchain
```

You land in `/workspace` as root, with the whole toolchain on `PATH`:

| Tool | Location | What it does |
| :--- | :--- | :--- |
| `lwasm` / `lwlink` / `lwobjdump` | `/usr/local/bin` | 6809 assembler / linker / objdump (LWTOOLS 4.24) |
| `cmoc` | `/usr/local/bin` | C compiler for the 6809 |
| `decb` | `/usr/local/bin` | Disk-image tool: `decb dskini`, `decb copy`, `decb dir` for OS-9 `.dsk` files |
| `os9` | `/usr/local/bin` | OS-9 utility from ToolShed |
| `mame` | `/usr/local/bin` → `/usr/games/mame` | The emulator (apt installs to `/usr/games`; a symlink puts it on PATH) |
| `coco-verify` | `/usr/local/bin` | The one-shot verification pipeline (see §5) |
| `dump_vram.lua` | `/opt/coco-harness` | MAME Lua script that produces the text dump |

Useful one-liners once inside:

```bash
coco-verify main.c        # the whole pipeline, see §5
mame -version             # sanity check the emulator
decb dir fenetre.dsk      # inspect the generated disk
```

Exit with `exit` (`--rm` means the container disappears; `/workspace` content stays on your disk).

---

## 5. The intended job: `coco-verify`

`coco-verify [source.c]` (default `main.c`) runs the full loop in three steps:

1. **Compile** — `cmoc --coco -O2` on the source, producing `fenetre.bin` (plus a `-S` assembly listing for inspection).
2. **Package** — `decb dskini fenetre.dsk` if no disk exists yet, then `decb copy` the binary into the disk as **`FENETRE.BIN`**.
3. **Emulate** — headless MAME (`coco3`, 512 KB RAM, `-video none -sound none -nothrottle`, floppy `fenetre.dsk`), auto-typing `LOADM"FENETRE":EXEC` at boot, then the Lua inspector writes `screen_dump.txt` and it is printed to stdout.

One-shot from the host, no shell needed:

```powershell
docker run --rm -v "C:\Dev\github\philippeback\coco:/workspace" -v "C:\path\to\mame\roms:/roms" coco3toolchain coco-verify main.c
```

**The evidence it produces** (`screen_dump.txt`):
- `REG |` line — 6809 registers (PC, S, U, X, Y, D, DP, CC) at frame 295;
- `MMU |` line — GIME MMU Task 0 registers `$FFA0–$FFA7`;
- 25 lines of 80 characters — the hardware text screen as ASCII.

**Two gotchas, stated plainly:**
- The auto-boot command `LOADM"FENETRE":EXEC` is **OS-9 syntax**. MAME's `coco3` boots Color BASIC unless your `fenetre.dsk` is a *bootable OS-9 disk*. `decb dskini` creates an *empty* OS-9 disk — fine as a container format, but for a real OS-9 boot, place a prepared bootable `fenetre.dsk` in the workspace (step 2 only creates a disk when none exists, and always just injects `FENETRE.BIN` into it).
- If no ROMs are found, MAME exits with an error and `screen_dump.txt` stays stale — delete the old dump when a run fails, or trust timestamps, not content.

---

## 6. Doing the steps manually (inside the container)

If you want to pull the pipeline apart (debugging, custom flags):

```bash
cd /workspace

# 1. Compile C -> flat binary
cmoc --coco -O2 -o fenetre.bin main.c

# 2. Build the floppy image
decb dskini fenetre.dsk                      # only if it does not exist yet
decb copy -2 -b -r fenetre.bin "fenetre.dsk,FENETRE.BIN"
decb dir fenetre.dsk                         # verify the injection

# 3. Boot it headlessly
mame coco3 -rompath /roms -ramsize 512k -flop1 fenetre.dsk \
     -autoboot_delay 2 -autoboot_command 'LOADM"FENETRE":EXEC\n' \
     -autoboot_script /opt/coco-harness/dump_vram.lua \
     -str 5 -video none -sound none -nothrottle

cat screen_dump.txt                          # the verification evidence
```

And for pure assembly work (the BALLML style of this repo):

```bash
lwasm --6809 -f0 -oballml.raw BALLML.ASM     # assemble
lwobjdump ballml.raw                          # inspect
```

---

## 7. Troubleshooting quick table

| Symptom | Cause | Fix |
| :--- | :--- | :--- |
| `mame: command not found` | Image built before the PATH symlink fix | Rebuild the image (`docker build -t coco3toolchain toolchain`). |
| `Required ROM not found!` | `/roms` not mounted, or missing `coco3.zip` | Mount the ROMs folder; check `mame coco3 -listroms`. |
| Screen dump shows the Color BASIC prompt, not your program | Disk is not bootable OS-9, so `LOADM…` was typed into BASIC | Use a prepared bootable OS-9 `fenetre.dsk` in the workspace. |
| Outputs missing on the host | Forgot `-v …:/workspace` | Always mount the repo; the container itself is disposable. |
| `bash: ./coco-verify: … bad interpreter` on Windows-checked-out scripts | CRLF line endings | Run the pipeline inside the container (the image's own `/usr/local/bin/coco-verify` is clean). |

---

## 8. Cheat sheet

```powershell
# Build
docker build -t coco3toolchain toolchain

# Interactive shell (repo + ROMs mounted)
docker run --rm -it -v "C:\Dev\github\philippeback\coco:/workspace" -v "C:\path\to\mame\roms:/roms" coco3toolchain

# One-shot verification
docker run --rm -v "C:\Dev\github\philippeback\coco:/workspace" -v "C:\path\to\mame\roms:/roms" coco3toolchain coco-verify main.c
```
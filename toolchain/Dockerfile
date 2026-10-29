# ==============================================================================
# CoCo 3 Bare-Metal AI Verification Toolchain
# Includes: LWTOOLS (lwasm/lwlink), CMOC, ToolShed (decb), and Headless MAME
# ==============================================================================
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# 1. Install build dependencies, MAME, and utilities
RUN apt-get update && apt-get install -y \
    build-essential \
    bison \
    flex \
    wget \
    curl \
    git \
    mercurial \
    python3 \
    python3-pip \
    libfuse-dev \
    pkg-config \
    mame \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp/build

# 2. Build and install LWTOOLS (6809 Assembler & Linker required by CMOC)
ARG LWTOOLS_VERSION=4.24
RUN wget -q http://www.lwtools.ca/releases/lwtools/lwtools-${LWTOOLS_VERSION}.tar.gz && \
    tar xzf lwtools-${LWTOOLS_VERSION}.tar.gz && \
    cd lwtools-${LWTOOLS_VERSION} && \
    make -j$(nproc) && \
    make install && \
    ldconfig

# 3. Build and install CMOC (6809 C Compiler)
ARG CMOC_VERSION=0.1.88
RUN wget -q http://gvlsywt.cluster051.hosting.ovh.net/dev/cmoc-${CMOC_VERSION}.tar.gz && \
    tar xzf cmoc-${CMOC_VERSION}.tar.gz && \
    cd cmoc-${CMOC_VERSION} && \
    ./configure && \
    make -j$(nproc) && \
    make install

# 4. Build and install ToolShed ('decb' utility for .dsk floppy image manipulation)
RUN hg clone http://hg.code.sf.net/p/toolshed/code toolshed && \
    cd toolshed && \
    make -C build/unix -j$(nproc) && \
    cp build/unix/decb/decb /usr/local/bin/ && \
    cp build/unix/os9/os9 /usr/local/bin/

# Clean up build artifacts
WORKDIR /
RUN rm -rf /tmp/build

# 5. Pre-install the Headless MAME Lua VRAM & Register Inspector
RUN mkdir -p /opt/coco-harness
RUN cat << 'EOF' > /opt/coco-harness/dump_vram.lua
local frame = 0
emu.register_frame_done(function()
    frame = frame + 1
    if frame == 295 then
        local cpu = manager.machine.devices[":maincpu"]
        local mem = cpu.spaces["program"]
        local out = io.open("screen_dump.txt", "w")

        -- 1. 6809 CPU Registers
        out:write(string.format(
            "REG | PC:%04X S:%04X U:%04X X:%04X Y:%04X D:%04X DP:%02X CC:%02X\n",
            cpu.state["PC"].value, cpu.state["S"].value, cpu.state["U"].value,
            cpu.state["X"].value,  cpu.state["Y"].value, cpu.state["D"].value,
            cpu.state["DP"].value, cpu.state["CC"].value
        ))

        -- 2. GIME MMU Task 0 Registers ($FFA0 - $FFA7)
        local mmu = "MMU | "
        for i = 0, 7 do
            mmu = mmu .. string.format("$%X000:%02X ", i * 2, mem:read_u8(0xFFA0 + i))
        end
        out:write(mmu .. "\n" .. string.rep("=", 80) .. "\n")

        -- 3. 80x25 Hardware Text Screen (Mapped at logical $6000)
        local base = 0x6000
        for r = 0, 24 do
            local chars = {}
            for c = 0, 79 do
                local ch = mem:read_u8(base + (r * 160) + (c * 2))
                chars[#chars + 1] = (ch >= 32 and ch <= 126) and string.char(ch) or "."
            end
            out:write(table.concat(chars) .. "\n")
        end
        out:close()
    end
end)
EOF

# 6. Pre-install the one-shot compile + boot + verify command (`coco-verify`)
RUN cat << 'EOF' > /usr/local/bin/coco-verify
#!/usr/bin/env bash
set -e

SRC_FILE="${1:-main.c}"
BIN_NAME="FENETRE"

echo "[1/3] Compiling ${SRC_FILE} with CMOC..."
cmoc --coco -O2 -S "${SRC_FILE}"
cmoc --coco -O2 -o fenetre.bin "${SRC_FILE}"

echo "[2/3] Injecting ${BIN_NAME}.BIN into fenetre.dsk..."
if [ ! -f fenetre.dsk ]; then
    decb dskini fenetre.dsk
fi
decb copy -2 -b -r fenetre.bin "fenetre.dsk,${BIN_NAME}.BIN"

echo "[3/3] Running Headless MAME (120 frames post-boot)..."
if [ -d "/roms" ]; then
    ROM_FLAG="-rompath /roms"
else
    ROM_FLAG="-rompath ./roms"
fi

mame coco3 ${ROM_FLAG} \
    -ramsize 512k \
    -flop1 fenetre.dsk \
    -autoboot_delay 2 \
    -autoboot_command "LOADM\"${BIN_NAME}\":EXEC\n" \
    -autoboot_script /opt/coco-harness/dump_vram.lua \
    -str 5 -video none -sound none -nothrottle >/dev/null 2>&1

cat screen_dump.txt
EOF
RUN chmod +x /usr/local/bin/coco-verify

WORKDIR /workspace
CMD ["/bin/bash"]

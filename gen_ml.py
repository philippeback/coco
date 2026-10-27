"""
Assemble BALLML.ASM using lwasm (from tools/lwtools-4.9-win32) and update the
DATA statements in BALLML.BAS.
"""
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).parent
LWASM = ROOT / "tools" / "lwtools-4.9-win32" / "lwtools-mingw32" / "lwasm.exe"
ASM_FILE = ROOT / "BALLML.ASM"
RAW_FILE = ROOT / "ballml.raw"
LST_FILE = ROOT / "ballml.lst"
BAS_FILE = ROOT / "BALLML.BAS"

def main():
    cmd = [
        str(LWASM),
        "-9",
        "-f", "raw",
        f"-o{RAW_FILE}",
        f"--list={LST_FILE}",
        str(ASM_FILE),
    ]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        print("lwasm failed:")
        print(res.stdout)
        print(res.stderr)
        raise SystemExit(1)

    code = RAW_FILE.read_bytes()
    print(f"Assembled {ASM_FILE.name} -> {len(code)} bytes ($7D00..${0x7D00 + len(code) - 1:04X})")

    data_lines = []
    line_num = 900
    chunk_size = 24
    for i in range(0, len(code), chunk_size):
        chunk = code[i:i + chunk_size]
        hex_str = "".join(f"{b:02X}" for b in chunk)
        data_lines.append(f"{line_num} DATA {hex_str}")
        line_num += 10

    num_data_lines = len(data_lines)

    # Read BALLML.BAS and replace lines >= 900 and update line 70 count + DEFUSR1
    bas_lines = [
        line for line in BAS_FILE.read_text(encoding="ascii").splitlines()
        if line.strip() and int(line.split()[0]) < 900
    ]

    updated_bas = []
    for line in bas_lines:
        if line.startswith("70 "):
            updated_bas.append(f"70 FOR L=1 TO {num_data_lines}:READ H$")
        elif line.startswith("110 "):
            updated_bas.append("110 DEFUSR0=&H7D00:DEFUSR1=&H7D03")
        else:
            updated_bas.append(line)

    updated_bas.extend(data_lines)
    BAS_FILE.write_text("\n".join(updated_bas) + "\n", encoding="ascii")
    print(f"Updated {BAS_FILE.name} with {num_data_lines} DATA lines (900..{line_num - 10}).")

if __name__ == "__main__":
    main()

param(
    [switch]$Run
)

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
$Lwasm = Join-Path $Root "tools\lwtools-4.9-win32\lwtools-mingw32\lwasm.exe"
$XRoar = "C:\Program Files\6809.org.uk\XRoar 1.12\xroar.exe"

Write-Host "==> Assembling BALLML.ASM with lwasm and updating BALLML.BAS..." -ForegroundColor Cyan
python (Join-Path $Root "gen_ml.py")
if ($LASTEXITCODE -ne 0) {
    throw "Build failed!"
}

if ($Run) {
    Write-Host "==> Launching BALLML.BAS in XRoar..." -ForegroundColor Green
    & $XRoar -machine coco -load-text (Join-Path $Root "BALLML.BAS")
}

# Package the freshly-built Windows Flutter Release output into:
#   1. dist\awatv-windows.zip   — full Release dir zipped (the .exe + Flutter
#                                  engine DLLs + plugin DLLs + assets folder).
#                                  Users can unzip anywhere and run the .exe.
#   2. dist\awatv-setup.exe     — Inno Setup-generated installer.
#                                  Optional — only built when `iscc` is on PATH.
#
# Run AFTER `flutter build windows --release` from the repo root.
#
# Code-signing is intentionally OUT OF SCOPE. To sign the .exe + installer,
# obtain a code-signing certificate (Sectigo / DigiCert / SSL.com) and call
# signtool from a follow-up step:
#   signtool sign /tr http://timestamp.sectigo.com /td sha256 /fd sha256 \
#     /a awatv-setup.exe

$ErrorActionPreference = "Stop"

# Resolve repo root from this script's location ($PSScriptRoot is .../scripts).
$Root     = Split-Path -Parent $PSScriptRoot
$BuildDir = Join-Path $Root "apps\mobile\build\windows\x64\runner\Release"
$Dist     = Join-Path $Root "dist"

New-Item -ItemType Directory -Force -Path $Dist | Out-Null

if (!(Test-Path $BuildDir)) {
    throw "Build dir missing: $BuildDir`nRun 'flutter build windows --release' first."
}

Write-Host "Source build dir: $BuildDir"
Write-Host "Output dist dir:  $Dist"

# 1. ZIP the entire Release folder. The .exe by itself is useless — it needs
#    the Flutter engine DLLs and the `data\` folder next to it.
$ZipPath = Join-Path $Dist "awatv-windows.zip"
if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }
Write-Host "Creating ZIP: $ZipPath"
Compress-Archive -Path "$BuildDir\*" -DestinationPath $ZipPath -CompressionLevel Optimal

# 2. Optional: build an Inno Setup installer. We probe for `iscc` rather than
#    failing the whole job — ZIP-only is a perfectly valid release format.
$Iscc       = Get-Command "iscc" -ErrorAction SilentlyContinue
$IssScript  = Join-Path $Root "apps\mobile\windows\installer.iss"

if ($Iscc -and (Test-Path $IssScript)) {
    Write-Host "Inno Setup found at $($Iscc.Source) — building installer"
    & iscc.exe /Qp "$IssScript"
    if ($LASTEXITCODE -ne 0) {
        throw "Inno Setup compilation failed with exit code $LASTEXITCODE"
    }
    $Setup = Join-Path $Dist "awatv-setup.exe"
    if (Test-Path $Setup) {
        Write-Host "Installer built: $Setup"
    } else {
        Write-Warning "iscc returned 0 but installer not found at $Setup"
    }
} else {
    if (-not $Iscc) {
        Write-Host "Inno Setup (iscc) not on PATH — ZIP-only release"
    }
    if (-not (Test-Path $IssScript)) {
        Write-Host "installer.iss missing at $IssScript — ZIP-only release"
    }
}

Write-Host ""
Write-Host "Packaging complete:"
Get-ChildItem $Dist | Format-Table Name, Length, LastWriteTime

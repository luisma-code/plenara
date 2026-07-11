# Plenara - prep a Windows machine to RUN the packaged app.
#
# A Flutter release is self-contained as a FOLDER: plenara_app.exe plus all its DLLs
# (flutter_windows.dll, onnxruntime.dll, sherpa-onnx-c-api.dll, the data\ folder). Windows
# resolves those automatically because they sit next to the exe - so the one rule is: keep
# the Release folder intact, never move the exe out on its own.
#
# The ONE thing a fresh machine can lack is the Microsoft Visual C++ runtime that the build
# links against (vcruntime140.dll / msvcp140.dll). This script ensures it, then sanity-checks
# the package. Run once per novel machine:  powershell -ExecutionPolicy Bypass -File prep-machine.ps1
$ErrorActionPreference = "Stop"
$root = $PSScriptRoot

Write-Host "[prep] Plenara machine prep"

# 1) Visual C++ x64 runtime -------------------------------------------------
if (Test-Path "$env:WINDIR\System32\vcruntime140.dll") {
  Write-Host "[prep] Visual C++ runtime: present"
} else {
  Write-Host "[prep] Visual C++ runtime: MISSING - installing Microsoft.VCRedist.2015+.x64 via winget..."
  try {
    winget install --id Microsoft.VCRedist.2015+.x64 -e --accept-source-agreements --accept-package-agreements
    Write-Host "[prep] Visual C++ runtime installed"
  } catch {
    Write-Warning "[prep] winget install failed. Install the 'Visual C++ Redistributable (x64)' manually from https://aka.ms/vs/17/release/vc_redist.x64.exe"
  }
}

# 2) Verify the app package -------------------------------------------------
$rel = Join-Path $root "app\build\windows\x64\runner\Release"
$exe = Join-Path $rel "plenara_app.exe"
if (Test-Path $exe) {
  $need = "flutter_windows.dll","onnxruntime.dll","sherpa-onnx-c-api.dll"
  $missing = $need | Where-Object { -not (Test-Path (Join-Path $rel $_)) }
  if ($missing) {
    Write-Warning "[prep] package incomplete - missing: $($missing -join ', '). Rebuild with build.cmd, or re-extract the release zip so ALL files land together."
  } else {
    Write-Host "[prep] app package looks complete: $rel"
  }
} else {
  Write-Host "[prep] No local build found. Either:"
  Write-Host "         - build from source:   build.cmd   (needs the vendored .tools\flutter + Visual Studio C++ Build Tools)"
  Write-Host "         - or download a release .zip from GitHub and extract it, keeping every file together"
}

Write-Host "[prep] done. Launch with:  run.cmd"

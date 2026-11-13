# Builds bin\RE2DLSS-DX11.addon64 with MSVC (Visual Studio 2022+ with C++ tools).
# Usage: .\build.ps1 [-Install] [-GameDir <folder of re2.exe>]
#   -Install  copies the add-on into the game folder (game closed). The game must be on the
#             Steam beta branch dx11_non-rt.
param(
    [switch]$Install,
    [string]$GameDir = "E:\SteamLibrary\steamapps\common\RESIDENT EVIL 2  BIOHAZARD RE2"
)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$exe = "re2.exe"
$name = "RE2DLSS-DX11"

$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
# vcvars64.bat runs vswhere by name; PATH entries with parentheses in odd places (a Steam tool's
# folder) break cmd's parsing of vcvars, so only the Windows folders are kept for the build.
$env:PATH = "$(Split-Path $vswhere);$env:SystemRoot\System32;$env:SystemRoot;$env:SystemRoot\System32\WindowsPowerShell\v1.0"
$vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vs) { throw "Visual Studio with the C++ x64 tools not found." }
$vcvars = Join-Path $vs "VC\Auxiliary\Build\vcvars64.bat"

$obj = "$root\bin\obj"
New-Item -ItemType Directory -Force $obj | Out-Null
$addon = "$root\bin\$name.addon64"

# ReShade add-on headers in third_party\reshade match ReShade 6.8.0.
$cmd = @(
    "call `"$vcvars`" >nul",
    "fxc /nologo /T vs_5_0 /E VsMain /O3 /Vn kBlitVs /Fh `"$obj\blit_vs.h`" `"$root\src\blit.hlsl`" >nul",
    "fxc /nologo /T ps_5_0 /E PsMain /O3 /Vn kBlitPs /Fh `"$obj\blit_ps.h`" `"$root\src\blit.hlsl`" >nul",
    ("cl /nologo /std:c++17 /O2 /EHsc /MT /W3 /D_CRT_SECURE_NO_WARNINGS /DNOMINMAX " +
     "/I `"$obj`" /I `"$root\third_party\imgui`" /I `"$root\third_party\reshade\include`" /I `"$root\third_party\dlss\include`" " +
     "/Fo`"$obj\\`" `"$root\src\main.cpp`" `"$root\src\upscaler.cpp`" `"$root\src\dlss.cpp`" " +
     "user32.lib advapi32.lib ole32.lib d3d11.lib dxgi.lib `"$root\third_party\dlss\lib\nvsdk_ngx_s.lib`" " +
     "/link /DLL /OUT:`"$addon`" /PDB:`"$obj\$name.pdb`" /DEBUG")
) -join " && "
cmd /c $cmd
if ($LASTEXITCODE) { throw "build failed" }
Write-Host "Built $addon"

# NVIDIA's signed DLSS runtime (310.9.16; not in git).
$ngx = "$root\third_party\bin\nvngx_dlss.dll"
if ($Install) {
    if (-not (Test-Path $ngx)) { throw "nvngx_dlss.dll not found in third_party\bin" }
    if (-not (Test-Path "$GameDir\$exe")) { throw "$exe not found in $GameDir (pass -GameDir)" }
    if (Get-Process ([IO.Path]::GetFileNameWithoutExtension($exe)) -ErrorAction SilentlyContinue) { throw "Close the game first." }
    Copy-Item $addon, $ngx $GameDir -Force
    # REFramework companion script: sets the render scale for the render resolution dropdown.
    if (Test-Path "$GameDir\reframework") {
        New-Item -ItemType Directory -Force "$GameDir\reframework\autorun" | Out-Null
        Copy-Item "$root\reframework\$name.lua" "$GameDir\reframework\autorun" -Force
    } else { Write-Warning "REFramework not installed: the render resolution dropdown needs it" }
    Write-Host "Installed to $GameDir"
}

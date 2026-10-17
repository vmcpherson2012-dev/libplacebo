<#
.SYNOPSIS
  Windows wrapper for tools/build-windows.sh (VP FL35 libplacebo build).

.DESCRIPTION
  Runs the build script in an MSYS2 MINGW64 login shell. If Visual Studio is
  installed, the MSVC lib.exe is located with vswhere and handed to the script
  (LIB_EXE) so the bundle also contains the MSVC import library made from the
  .def. -ScriptArgs (one space-separated string) is passed to build-windows.sh.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\build-windows.ps1 -Jobs 4
  powershell -File tools\build-windows.ps1 -Msys2Root D:\msys64 -ScriptArgs "--strict --git-version"
#>
param(
    [string]$Msys2Root = "",
    [int]$Jobs = 4,
    [string]$OutDir = "",
    [string]$ScriptArgs = ""
)
$ErrorActionPreference = 'Stop'

if (-not $Msys2Root) {
    foreach ($c in @($env:MSYS2_ROOT, 'C:\msys64', 'D:\msys64')) {
        if ($c -and (Test-Path (Join-Path $c 'usr\bin\bash.exe'))) { $Msys2Root = $c; break }
    }
}
$bash = Join-Path $Msys2Root 'usr\bin\bash.exe'
if (-not (Test-Path $bash)) { throw "MSYS2 not found (pass -Msys2Root); install it from https://www.msys2.org/" }

$src = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function ConvertTo-MsysPath([string]$p) {
    $full = [System.IO.Path]::GetFullPath($p)
    return '/' + $full.Substring(0, 1).ToLower() + ($full.Substring(2) -replace '\\', '/')
}

$libExe = $null
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (Test-Path $vswhere) {
    $vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if ($vs) {
        $libExe = Get-ChildItem (Join-Path $vs 'VC\Tools\MSVC\*\bin\Hostx64\x64\lib.exe') -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
    }
}

$env:MSYSTEM = 'MINGW64'
$env:CHERE_INVOKING = '1'
if ($libExe) { $env:LIB_EXE = ConvertTo-MsysPath $libExe; Write-Host "MSVC lib.exe: $libExe" }
else { Write-Host 'MSVC lib.exe not found; the .lib must be generated from the .def separately.' }

$args2 = @('-j', "$Jobs")
if ($OutDir) { $args2 += @('-o', (ConvertTo-MsysPath $OutDir)) }
if ($ScriptArgs) { $args2 += ($ScriptArgs -split '\s+' | Where-Object { $_ }) }
$script = (ConvertTo-MsysPath (Join-Path $src 'tools\build-windows.sh'))
$quoted = ($args2 | ForEach-Object { "'" + ($_ -replace "'", "'\''") + "'" }) -join ' '

Push-Location $src
try {
    & $bash -lc "'$script' $quoted"
    if ($LASTEXITCODE -ne 0) { throw "build-windows.sh failed ($LASTEXITCODE)" }
} finally { Pop-Location }

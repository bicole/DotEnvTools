[CmdletBinding()]
param(
    [switch]$Check,
    [switch]$Diff,
    [bool]$Backup = $true,
    [switch]$Yes,
    [Alias('ha', 'help-agent')]
    [switch]$HelpAgent
)

$ErrorActionPreference = 'Stop'

if ($HelpAgent) {
    Write-Output "install.ps1 [-Check] [-Diff] [-Backup <bool>] [-Yes] [-ha] -- Installs DotEnvTools module to CurrentUser PowerShell Modules directory"
    exit 0
}

$RepoRoot = Split-Path -Parent $PSScriptRoot
$SrcDir = Join-Path $RepoRoot 'Source'
$Manifest = Import-PowerShellDataFile -Path (Join-Path $SrcDir 'DotEnvTools.psd1')
$Version = [string]$Manifest.ModuleVersion

$UserModulesRoot = if ($IsWindows -or $env:OS -eq 'Windows_NT') {
    Join-Path $HOME 'Documents/PowerShell/Modules'
} else {
    Join-Path $HOME '.local/share/powershell/Modules'
}

$DestDir = Join-Path $UserModulesRoot "DotEnvTools/$Version"

if ($Check) {
    $exists = Test-Path (Join-Path $DestDir 'DotEnvTools.psd1')
    Write-Host ("[CHECK] DotEnvTools v{0} at {1}: Exists={2}" -f $Version, $DestDir, $exists) -ForegroundColor Cyan
    exit 0
}

if ((Test-Path $DestDir) -and $Backup) {
    $ts = Get-Date -Format 'yyyyMMdd_HHmmss'
    Copy-Item -Path $DestDir -Destination "${DestDir}.bak.${ts}" -Recurse -Force
}

New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
Copy-Item -Path (Join-Path $SrcDir '*') -Destination $DestDir -Recurse -Force
Write-Host ("[OK] Installed DotEnvTools v{0} -> {1}" -f $Version, $DestDir) -ForegroundColor Green

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
    $docs = [Environment]::GetFolderPath('MyDocuments')
    if (-not $docs) { $docs = Join-Path $HOME 'Documents' }
    Join-Path $docs 'PowerShell/Modules'
} else {
    Join-Path $HOME '.local/share/powershell/Modules'
}

$DestDir = Join-Path $UserModulesRoot "DotEnvTools/$Version"

if ($Diff) {
    if (-not (Test-Path $DestDir)) {
        Write-Host ("[DIFF] Destination directory does not exist: {0} (all files will be newly installed)" -f $DestDir) -ForegroundColor Yellow
        Get-ChildItem -Path $SrcDir -Recurse -File | ForEach-Object {
            $rel = $_.FullName.Substring($SrcDir.Length).TrimStart('\', '/').Replace('\', '/')
            Write-Host ("  + {0}" -f $rel) -ForegroundColor Green
        }
    } else {
        Write-Host ("[DIFF] Comparing {0} with {1}:" -f $SrcDir, $DestDir) -ForegroundColor Cyan
        $diffCount = 0
        $srcFiles = Get-ChildItem -Path $SrcDir -Recurse -File
        foreach ($sf in $srcFiles) {
            $rel = $sf.FullName.Substring($SrcDir.Length).TrimStart('\', '/').Replace('\', '/')
            $dfPath = Join-Path $DestDir $rel
            if (-not (Test-Path $dfPath)) {
                Write-Host ("  + {0} (new in source)" -f $rel) -ForegroundColor Green
                $diffCount++
            } else {
                $srcHash = (Get-FileHash -Path $sf.FullName -Algorithm SHA256).Hash
                $dstHash = (Get-FileHash -Path $dfPath -Algorithm SHA256).Hash
                if ($srcHash -ne $dstHash) {
                    Write-Host ("  ~ {0} (content modified)" -f $rel) -ForegroundColor Yellow
                    $diffCount++
                }
            }
        }
        if ($diffCount -eq 0) {
            Write-Host "  No differences found; destination is up to date." -ForegroundColor Green
        }
    }
}

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

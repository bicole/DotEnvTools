<#!
.SYNOPSIS
Builds a deployable DotEnvTools module package.
.DESCRIPTION
Creates a versioned PowerShell module layout under .\dist from the Source folder, then creates a deployable ZIP package.
.PARAMETER NewVersion
Optional module version to stamp into the manifest before packaging.
.EXAMPLE
.\scripts\Build-DotEnvTools.ps1 -WhatIf
.EXAMPLE
.\scripts\Build-DotEnvTools.ps1 -NewVersion 0.5.2 -Verbose
.INPUTS
None
.OUTPUTS
System.IO.FileInfo
.NOTES
Windows PowerShell 5.1 compatible.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
[OutputType([System.IO.FileInfo])]
param(
    [Parameter(Mandatory = $false)]
    [string]$NewVersion
)

begin {
    $scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
    $repoRoot = Split-Path -Parent $scriptPath
    $moduleName = 'DotEnvTools'
    $sourceRoot = Join-Path $repoRoot 'Source'
    $manifestPath = Join-Path $sourceRoot "$moduleName.psd1"
    $modulePath = Join-Path $sourceRoot "$moduleName.psm1"
    $distRoot = Join-Path $repoRoot 'dist'
}

process {
    try {
        if (-not (Test-Path $manifestPath)) { Write-Error "Manifest not found: $manifestPath"; return }
        if (-not (Test-Path $modulePath)) { Write-Error "Module file not found: $modulePath"; return }

        if ($NewVersion) {
            $manifest = Import-PowerShellDataFile -Path $manifestPath
            $currentVersion = [string]$manifest.ModuleVersion
            
            if ($currentVersion -ne $NewVersion) {
                if ($PSCmdlet.ShouldProcess($manifestPath, "Update ModuleVersion from $currentVersion to $NewVersion")) {
                    $manifestText = Get-Content -Path $manifestPath -Raw -ErrorAction Stop
                    $updatedText = $manifestText -replace "ModuleVersion\s*=\s*'[^']+'", "ModuleVersion = '$NewVersion'"

                    if ($updatedText -ne $manifestText) {
                        [System.IO.File]::WriteAllText(
                            $manifestPath,
                            $updatedText,
                            [System.Text.UTF8Encoding]::new($false)
                        )
                    }
                }
            } else {
                Write-Verbose ("ModuleVersion is already {0}; manifest update skipped." -f $NewVersion)
            }
        }

        $manifest = Import-PowerShellDataFile -Path $manifestPath
        $version = [string]$manifest.ModuleVersion
        $stagingRoot = Join-Path $distRoot $moduleName
        $versionRoot = Join-Path $stagingRoot $version
        $zipPath = Join-Path $distRoot "$moduleName-$version.zip"

        if (Test-Path $stagingRoot) {
            if ($PSCmdlet.ShouldProcess($stagingRoot, 'Remove previous staging folder')) {
                Remove-Item -Path $stagingRoot -Recurse -Force
            }
        }
        if ($PSCmdlet.ShouldProcess($versionRoot, 'Create module staging folder')) {
            New-Item -Path $versionRoot -ItemType Directory -Force | Out-Null
        }
        if ($PSCmdlet.ShouldProcess($versionRoot, 'Copy Source files')) {
            Copy-Item -Path (Join-Path $sourceRoot '*') -Destination $versionRoot -Recurse -Force
        }
        foreach ($file in @('README.md','CHANGELOG.md','LICENSE')) {
            $sourceFile = Join-Path $repoRoot $file
            if (Test-Path $sourceFile) {
                if ($PSCmdlet.ShouldProcess($versionRoot, "Copy $file")) {
                    Copy-Item -Path $sourceFile -Destination $versionRoot -Force
                }
            }
        }
        if (Test-Path $zipPath) {
            if ($PSCmdlet.ShouldProcess($zipPath, 'Remove previous ZIP')) { Remove-Item -Path $zipPath -Force }
        }
        if ($PSCmdlet.ShouldProcess($zipPath, 'Create deployment ZIP')) {
            Compress-Archive -Path $stagingRoot -DestinationPath $zipPath -Force
            Get-Item -Path $zipPath
        }
    }
    catch { Write-Error "Build failed: $($_.Exception.Message)" }
}
end { }

# SIG # Begin signature block
# MIIHXQYJKoZIhvcNAQcCoIIHTjCCB0oCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDzA5+v7yt7ofnv
# k0ekuzGWJNXazOt4SjaIygq7swDuYaCCBDowggQ2MIICnqADAgECAhBDcn1KArYx
# pE0iSvuWuGW3MA0GCSqGSIb3DQEBCwUAMDMxMTAvBgNVBAMMKEJyeWFuIENvbGUg
# TG9jYWwgUG93ZXJTaGVsbCBDb2RlIFNpZ25pbmcwHhcNMjYwOTE2MTUxNzUxWhcN
# MjkwOTE2MTUyNzUxWjAzMTEwLwYDVQQDDChCcnlhbiBDb2xlIExvY2FsIFBvd2Vy
# U2hlbGwgQ29kZSBTaWduaW5nMIIBojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKC
# AYEA4rdAeFZ2eh7B+Ppoa8mqxfstL0sl4Zd1Y9FNKTOJn4gOIQXNVQ1dJyEfrJf5
# 4/mORMwsky0qBMA1F3ZmeaZSVtw9MTtfwKTJThw6Rom0dzLNqzDfatSoUJOuQi6e
# nRiRpswvGEfHd2pIPmW+vufOoaThuLlS8w84X036EzGIigaqq1FN/VPPD6PVMCMY
# oNA1QwFwdvqO6iScR7WZfW3sCm1oApAbhjtZnYvUqg9jxkjp49cIg0aYmXfdEpQC
# FRBacOUNetAwBti0jJ3w1K9gd4rg+7IAA/z5C/aC/HzVrJAS/LgbawmbIjW322Mg
# VpF703ArPhQ5OHkqWgv9qWLvkeHIzKeBjRuPzLGR+ybt8AnqwJT7PnCnWPBU17/v
# PO0+r9Y8z7ZgO3SduagEOa+GBw6qKqWb1vl+Z8vZCURBewE/hghY/LCPm6vIO0MB
# LXzPPnNQfOOGGdDQltld+TL8ZlKe08TK1m6ZdwyT1VfHY5NH5tgFfJHCe4OXfqDF
# 64TNAgMBAAGjRjBEMA4GA1UdDwEB/wQEAwIHgDATBgNVHSUEDDAKBggrBgEFBQcD
# AzAdBgNVHQ4EFgQUsQolemGuBXWQmQUtrq5wL1K8SnEwDQYJKoZIhvcNAQELBQAD
# ggGBAHXMAoTlUx5JzYEWMdqVfUgv1+ek6hdtaq45/twGhrXYj6aU4QT1ZhwwVuau
# xfLnchAaDJk4LW2C37ol1sKcqR5NsKaYRUr9nCqnHAi2rN6NTOsmOF4RZSKwP/ka
# bS7H5FcOBIkmeiyw+ZbOoDyYkjGEYIgaEmwP6rRm3zXRNWJCDWaalWjNY3lyjN1w
# NMznd3K8e6S8lBvDZUXIBAtXqV3JNB8vjHBvvvyaNLwOSVHb17OQEhNjgYoCknbT
# oCcuoXCV2F0v4o/4vPn/Qdtfor2TsQTQBeqIZGL0wc9Lin30A2MSF6M1DQaDI2LS
# XK4WweHeEwDxI+UheGR/EeEFPJdLEqZ47U+vE7+P3Kr9vtAd6p9HqI5lUHMFAiH0
# sbb/MpDsMTrbaWyFGbFo6bCTFFAMq6qq4DOgSl0nLJmNmlE/rVZ8A50XT028/7MD
# TRjnmDw6ZJSwU182OSlcj42OmyU+xsjP2J1ap4prg/acE18tWF99fRmkS7DWjQes
# XBuAijGCAnkwggJ1AgEBMEcwMzExMC8GA1UEAwwoQnJ5YW4gQ29sZSBMb2NhbCBQ
# b3dlclNoZWxsIENvZGUgU2lnbmluZwIQQ3J9SgK2MaRNIkr7lrhltzANBglghkgB
# ZQMEAgEFAKCBhDAYBgorBgEEAYI3AgEMMQowCKACgAChAoAAMBkGCSqGSIb3DQEJ
# AzEMBgorBgEEAYI3AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMC8G
# CSqGSIb3DQEJBDEiBCCOge7hJ3zf9H1sHSxSzk6AizZhoIkyrKxZQ0gKv5LGWTAN
# BgkqhkiG9w0BAQEFAASCAYBjKYchVymPlnMm4q0S0ExdmabI6yjJ1l2EjQmwqzTM
# gFY+sYxX3yOxWODpdAUCmxT0a/+Up0WqBD6urh7ZB3voQ9VigfgBm7yCf/yO4qdD
# 2YTalOp7ZwifadlkuSrpTuZREFBnP13XXLHKtjTRodqlS5lxOgcu1DWT0iDVF42J
# ZH3XfJVXHLTWlGv8J/cDTR7Rzeezcn2PtgbYcDGXHek0H1NoulBWmDdQgoDVufqh
# /QCiufVZlEdw/2EcFmltPSoI78kJ3MAiGjJFoYDZW8wKyDNA/t9bxJ9CFsrSrfBB
# LObwVhXuQ5KJI37CvAmACQp9I1DGQbbmEidSxfu1WfhDnYiXPQolWX56/kopX13q
# yoOAMcM5BDPydznpvSqBjDDg8p/4PbpbGGyHJLVFtQLhzxOrx/no5Tv63nmTGuYO
# sgXJ35eaVe2OZgjykwdG7m3yjtQ101Ne4Ka3cb2/M+fcd/Hthc/rpUcsCGddz8fS
# oazp/KlQZ2W3Lswxrj36/CQ=
# SIG # End signature block

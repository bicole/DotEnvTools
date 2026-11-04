<#!
.SYNOPSIS
Generates DotEnvTools Markdown and external MAML help.
.DESCRIPTION
Uses PlatyPS to recreate command Markdown help under docs/reference from inline
comment-based help, then generates Source/<Locale>/DotEnvTools-help.xml for
Get-Help.
.PARAMETER ModuleRoot
Repository root.
.PARAMETER Locale
Help locale folder name.
.PARAMETER Force
Overwrites generated Markdown and external help.
.EXAMPLE
.\scripts\Update-DotEnvToolsHelp.ps1 -ModuleRoot . -Force
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
    [ValidateNotNullOrEmpty()]
    [string]$ModuleRoot = '.',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$Locale = 'en-US',

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

begin {
    function Import-DotEnvToolsPlatyPS {
        [CmdletBinding()]
        param()

        $module = Get-Module -ListAvailable -Name platyPS |
            Sort-Object Version -Descending |
            Select-Object -First 1

        if ($module) {
            Import-Module $module.Path -Force -ErrorAction Stop
            return
        }

        $installedModule = $null
        if (Get-Command -Name Get-InstalledModule -ErrorAction SilentlyContinue) {
            $installedModule = Get-InstalledModule -Name platyPS -ErrorAction SilentlyContinue
        }

        if ($installedModule -and $installedModule.InstalledLocation) {
            $manifestPath = Join-Path $installedModule.InstalledLocation 'platyPS.psd1'
            Import-Module $manifestPath -Force -ErrorAction Stop
            return
        }

        throw 'platyPS is required. Install it with: Install-Module platyPS -Scope CurrentUser'
    }
}

process {
    try {
        $root = (Resolve-Path -Path $ModuleRoot -ErrorAction Stop).Path
        $moduleName = 'DotEnvTools'
        $manifestPath = Join-Path $root "Source\$moduleName.psd1"
        $markdownRoot = Join-Path $root 'docs\reference'
        $externalHelpRoot = Join-Path $root "Source\$Locale"

        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            Write-Error "Manifest not found: $manifestPath"
            return
        }

        Import-DotEnvToolsPlatyPS

        Remove-Module $moduleName -Force -ErrorAction SilentlyContinue
        Import-Module $manifestPath -Force -ErrorAction Stop

        if (Test-Path -LiteralPath $markdownRoot -PathType Container) {
            if ($PSCmdlet.ShouldProcess($markdownRoot, 'Remove existing Markdown help folder')) {
                Remove-Item -LiteralPath $markdownRoot -Recurse -Force
            }
        }

        if ($PSCmdlet.ShouldProcess($markdownRoot, 'Create Markdown help folder')) {
            New-Item -Path $markdownRoot -ItemType Directory -Force | Out-Null
        }

        if (-not (Test-Path -LiteralPath $externalHelpRoot -PathType Container)) {
            if ($PSCmdlet.ShouldProcess($externalHelpRoot, 'Create external help folder')) {
                New-Item -Path $externalHelpRoot -ItemType Directory -Force | Out-Null
            }
        }

        if ($PSCmdlet.ShouldProcess($markdownRoot, 'Recreate Markdown help from module')) {
            New-MarkdownHelp `
                -Module $moduleName `
                -OutputFolder $markdownRoot `
                -AlphabeticParamsOrder `
                -Force:$Force `
                -ErrorAction Stop | Out-Null
        }

        if ($PSCmdlet.ShouldProcess($externalHelpRoot, 'Generate external MAML help')) {
            New-ExternalHelp `
                -Path $markdownRoot `
                -OutputPath $externalHelpRoot `
                -Force `
                -ErrorAction Stop
        }
    }
    catch {
        Write-Error "Help generation failed: $($_.Exception.Message)"
    }
}

end {}

# SIG # Begin signature block
# MIIHXQYJKoZIhvcNAQcCoIIHTjCCB0oCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDwQ/pHi1Kc8nsL
# 85gZqOMMxRdJK7Ld68rTF2cCNTyOb6CCBDowggQ2MIICnqADAgECAhBDcn1KArYx
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
# CSqGSIb3DQEJBDEiBCCJDYbGVrfCW8RVzNZFpld4w+5n9+Bq2V0aeX/ETN4KOjAN
# BgkqhkiG9w0BAQEFAASCAYDMKm6CWNkl81PXzI103PJ7tC1MACB1CTdRwMkDI7zy
# TgL4jxazPyqzEQlpekg9QorQEh2YWr71Yccp41VjhF2NQO5ikE3xGvVUPLWsb1OY
# agT3zwBeFUngncjh8E4qjin4V2noJL3SSxjGP1xt7DIJ45RfbR8TrscQzTS6N0RJ
# RBzreZJPV/KI+/x8rF2f9sS0c0qbs7rCySt2qX0XV4x4WM6pht/joouEFRV0PZg2
# af4ZxCMc/doWbNAT6T0yANP7NEsrLNzYWOL5EIERzO5cs/X9F4hbeCraN/xugZgj
# cedj5YPB2Wv/1YXTxYcgEihb1Ej/SmEzKzbCmfKm0n7Nh3WV8OYeELiecRfBvQr0
# cEChCENb6cg2pTN4IltNqGMowZNk2bdJlz7IFhYzRds+h5JqN6DFGdsMzOwJnfRH
# LHojMomjXfST6+/IBGj6ow0DG6NlAU8EKsovslzrHfz0oJIWQV9gjQ5pxfBtsMI3
# 4K5d1UTSjB8PLGXma+TicKw=
# SIG # End signature block

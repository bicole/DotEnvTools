<#
.SYNOPSIS
Publishes a stable DotEnvTools release to PowerShell Gallery.

.DESCRIPTION
Builds the requested DotEnvTools version if needed, validates the module manifest,
and publishes the versioned module package to PowerShell Gallery.

Use this script only when the module is ready for public publishing. Pre-1.0 ZIP
artifacts should be distributed through GitHub Releases instead.

The PowerShell Gallery API key must be supplied through the current process
environment variable PSGALLERY_API_KEY.

.PARAMETER NewVersion
The module version to build and publish.

.EXAMPLE
$env:PSGALLERY_API_KEY = '<api-key>'
.\scripts\Publish-DotEnvTools.ps1 -NewVersion 1.0.0 -WhatIf

.EXAMPLE
$env:PSGALLERY_API_KEY = '<api-key>'
.\scripts\Publish-DotEnvTools.ps1 -NewVersion 1.0.0 -Verbose

.INPUTS
None.

.OUTPUTS
System.IO.FileInfo

.NOTES
Windows PowerShell 5.1 compatible.
Do not store PSGALLERY_API_KEY in source control, profile scripts, or committed files.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$NewVersion
)

begin {
    $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
    $repoRoot = Split-Path -Parent $scriptRoot

    $moduleName = 'DotEnvTools'
    $buildScript = Join-Path $scriptRoot 'Build-DotEnvTools.ps1'
    $distRoot = Join-Path $repoRoot 'dist'
    $moduleVersionPath = Join-Path (Join-Path $distRoot $moduleName) $NewVersion
    $manifestPath = Join-Path $moduleVersionPath "$moduleName.psd1"

    $apiKey = $env:PSGALLERY_API_KEY
}

process {
    try {
        if ([string]::IsNullOrWhiteSpace($apiKey)) {
            Write-Error 'Set PSGALLERY_API_KEY for this session before publishing.'
            return
        }

        if (-not (Test-Path -Path $buildScript -PathType Leaf)) {
            Write-Error ("Build script not found: {0}" -f $buildScript)
            return
        }

        if (-not (Test-Path -Path $moduleVersionPath -PathType Container)) {
            if ($PSCmdlet.ShouldProcess($moduleVersionPath, "Build DotEnvTools $NewVersion")) {
                & $buildScript -NewVersion $NewVersion -Verbose:$VerbosePreference
            }
        }

        if (-not (Test-Path -Path $manifestPath -PathType Leaf)) {
            Write-Error ("Manifest not found after build: {0}" -f $manifestPath)
            return
        }

        Write-Verbose ("Validating manifest: {0}" -f $manifestPath)
        Test-ModuleManifest -Path $manifestPath -ErrorAction Stop | Out-Null

        if ($PSCmdlet.ShouldProcess($moduleVersionPath, 'Publish module to PowerShell Gallery')) {
            Publish-Module `
                -Path $moduleVersionPath `
                -NuGetApiKey $apiKey `
                -Verbose:$VerbosePreference
        }

        Get-Item -Path $moduleVersionPath
    }
    catch {
        Write-Error ("Publish failed. {0}" -f $_.Exception.Message)
    }
}

end {}

# SIG # Begin signature block
# MIIHXQYJKoZIhvcNAQcCoIIHTjCCB0oCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCC40j7EadH1yQmZ
# 2tKBLzoYJSdMMegd7HavV1CKsgUvRaCCBDowggQ2MIICnqADAgECAhBDcn1KArYx
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
# CSqGSIb3DQEJBDEiBCAnKY0u5SiA85xLNKnZJL13YUVyYc85ke/Om/Ppev6hZzAN
# BgkqhkiG9w0BAQEFAASCAYAREQYdJJWJyaD3D/UI8p56fdMdaAgF/dAm6OUeDLpx
# /1elS/NnBLRACFc8ZFAKHTwGfe3tVTlVOE6bb4S4XWbJXsFSkMrGOPywNJP5tK4K
# B3JP3nyLutWKITTrxlSnSar3XKJ8vZO6UBnaQLVoPUpjke7su44TsU3GqdSD5TnI
# BB8PDbO/WtSGoDqKmjSYcq5TARC4a4hhYVej40jjpEe7v+Q08xUd0Urv4dSqncq3
# QFc7JTa6WQsYTYq9uG37SzEPfkDO0sC7OFuHDVhDU5ca+aHQJqU8RLRgBCM7vWDd
# /HoN0cl1yCBoHOh1UDBlN73Y40Y9uWQV0VZ4PYX9rpXeQEIIK2THnWR5uTTK2Wra
# LBzZWhlPFeM7hGTOzL+WzfqHMyN5R2kxEJbks9JCDVTf/kxNtlDWDIwnt4Zga5wD
# /T6RmK3rOzBiUp2SoabVDEzUfItkQcsHpKG8i7xBagvG0rGEsmY5ik8i5tYxW1Qr
# FzglO0MsgE5p0db2IOHt7co=
# SIG # End signature block

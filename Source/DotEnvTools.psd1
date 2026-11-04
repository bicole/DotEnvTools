@{
    RootModule = 'DotEnvTools.psm1'
    ModuleVersion = '0.8.18'
    GUID = '4d69b4ea-9d83-4e24-8d6f-6b74c3a6d052'
    Author = 'DotEnvTools Contributors'
    CompanyName = 'Community'
    Copyright = '(c) DotEnvTools Contributors. All rights reserved.'
    Description = 'Windows PowerShell 5.1 compatible .env file loader with opt-in auto-load support.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Add-DotEnvAutoLoadProfile',
        'ConvertFrom-DotEnv',
        'Disable-DotEnvAutoLoad',
        'Enable-DotEnvAutoLoad',
        'Export-DotEnvFile',
        'Find-DotEnvFile',
        'Get-DotEnvAutoLoadState',
        'Get-DotEnvConfiguration',
        'Get-DotEnvFilePath',
        'Get-DotEnvValue',
        'Import-DotEnvFile',
        'Initialize-DotEnvProject',
        'Invoke-DotEnvCommand',
        'Invoke-DotEnvAutoLoadNow',
        'Read-DotEnvFile',
        'Remove-DotEnvAutoLoadProfile',
        'Remove-DotEnvValue',
        'Remove-DotEnvVariable',
        'Set-DotEnvValue',
        'Test-DotEnvGitIgnore',
        'Test-DotEnvFile'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('dotenv', 'env', 'PowerShell', 'WindowsPowerShell')
            LicenseUri = 'https://github.com/nandub/DotEnvTools/blob/main/LICENSE'
            ProjectUri = 'https://github.com/nandub/DotEnvTools'
            ReleaseNotes = '0.8.17 fixes Dev Container Feature project initialization and lifecycle smoke coverage.'
        }
    }
}













# SIG # Begin signature block
# MIIHXQYJKoZIhvcNAQcCoIIHTjCCB0oCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBq0Y+tnomzZ39p
# ptuIvLfSGg2mktIoFYPYx2NPI/Hzv6CCBDowggQ2MIICnqADAgECAhBDcn1KArYx
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
# CSqGSIb3DQEJBDEiBCA8eYqqpfMTqGYA669Z6GdB2LbejQULBeLA33TqBY1UkzAN
# BgkqhkiG9w0BAQEFAASCAYBzUii6bUZs9ecE1aZeJq1Fv/ZveLYs4yBqxk5+M/+/
# qCQ3dwwwemsjig+UWZiqgW629d17ugkwwDWsqns1dvJFYH1OI3kGrqLQZpMpOiol
# +R3P6cE/07Vsy2YfLVu6XY+XE8tCgS1CDgnVLaqJ9x7BxfN+m5T/sO4vZdZvcD55
# NtgLNosbWZrD3s62vVlpY9AwK1zJkgEOgD0UrAfECtN372o9Cw9N5vxd5x0vD1UU
# ruQE3aDKpNBm8ly39qEWZdr/MiqILeNs/xkzDyc6Vq11ldIWb5OcVVaqEsV1isRr
# LdoQnldfoxeO3Cqv9mEk8A4UCiW7FkIDzQBrYXE1jz1LrKIedO3CIs0g2zeME8BK
# Q7VSn2YrjUjK7SiSjqpVS3i70zHd36KUHw5PdaCG/OLMCWqvRrmgSBI28nf2l5oy
# K78SgXqojUMfZg42ncka+MFhkLN2qdqlRQXy1JCinVbBDxnAHmZ0lErTlUDhAU/X
# zch+5QIFxhLTvdjkA2R+2cc=
# SIG # End signature block

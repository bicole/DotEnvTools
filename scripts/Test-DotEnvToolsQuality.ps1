<#!
.SYNOPSIS
Runs quality checks for DotEnvTools.
.DESCRIPTION
Validates source layout, manifest import, optional PSScriptAnalyzer, and optional Pester tests.
.PARAMETER ModuleRoot
Repository root.
.PARAMETER RunAnalyzer
Run PSScriptAnalyzer if available.
.PARAMETER RunTests
Run Pester tests if available.
.EXAMPLE
.\scripts\Test-DotEnvToolsQuality.ps1 -ModuleRoot .\ -Verbose
.EXAMPLE
.\scripts\Test-DotEnvToolsQuality.ps1 -ModuleRoot .\ -RunTests -Verbose
.INPUTS
None
.OUTPUTS
System.Management.Automation.PSCustomObject
.NOTES
Windows PowerShell 5.1 compatible.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
[OutputType([pscustomobject])]
param(
    [Parameter(Mandatory = $false)]
    [string]$ModuleRoot = '.',
    [Parameter(Mandatory = $false)]
    [switch]$RunAnalyzer,
    [Parameter(Mandatory = $false)]
    [switch]$RunTests
)

begin {
    $errors = New-Object System.Collections.ArrayList
    $warnings = New-Object System.Collections.ArrayList
}
process {
    $root = (Resolve-Path -Path $ModuleRoot).Path
    Write-Verbose "Using root path: $root"
    $manifestPath = Join-Path $root 'Source\DotEnvTools.psd1'
    if (-not (Test-Path $manifestPath)) { [void]$errors.Add("Manifest not found: $manifestPath") }
    else {
        try {
            Import-PowerShellDataFile -Path $manifestPath -ErrorAction Stop | Out-Null
            if ($PSCmdlet.ShouldProcess($manifestPath, 'Import module for validation')) {
                Remove-Module DotEnvTools -Force -ErrorAction SilentlyContinue
                Import-Module $manifestPath -Force -ErrorAction Stop
            }
        } catch { [void]$errors.Add("Module import failed: $($_.Exception.Message)") }
    }
    if ($RunAnalyzer) {
        $pssa = Get-Module -ListAvailable PSScriptAnalyzer | Sort-Object Version -Descending | Select-Object -First 1
        if ($pssa) {
            try {
                Import-Module $pssa.Path -Force -ErrorAction Stop
                $settings = Join-Path $root 'PSScriptAnalyzerSettings.psd1'
                if (Test-Path $settings) { $findings = Invoke-ScriptAnalyzer -Path (Join-Path $root 'Source') -Recurse -Settings $settings }
                else { $findings = Invoke-ScriptAnalyzer -Path (Join-Path $root 'Source') -Recurse }
                foreach ($finding in @($findings)) { [void]$warnings.Add("$($finding.RuleName): $($finding.Message)") }
            } catch { [void]$errors.Add("PSScriptAnalyzer failed: $($_.Exception.Message)") }
        } else { [void]$warnings.Add('PSScriptAnalyzer not installed.') }
    }
    if ($RunTests) {
        $testsPath = Join-Path $root 'Tests'
        $testFiles = @(Get-ChildItem -Path $testsPath -Filter '*.Tests.ps1' -Recurse -ErrorAction SilentlyContinue)
        if ($testFiles.Count -eq 0) { [void]$warnings.Add('No Pester test files found.') }
        else {
            $pester = Get-Module -ListAvailable Pester | Sort-Object Version -Descending | Select-Object -First 1
            if ($pester) {
                try {
                    Import-Module $pester.Path -Force -ErrorAction Stop
                    if ($PSCmdlet.ShouldProcess($testsPath, 'Execute Pester tests')) {
                        if ([version]$pester.Version -ge [version]'5.0.0') {
                            $config = New-PesterConfiguration
                            $config.Run.Path = $testsPath
                            $config.Run.PassThru = $true
                            $config.Output.Verbosity = 'Detailed'
                            $result = Invoke-Pester -Configuration $config
                        } else { $result = Invoke-Pester -Path $testsPath -PassThru }
                        if ($result.FailedCount -gt 0) { [void]$errors.Add("Pester failed tests: $($result.FailedCount)") }
                    }
                } catch { [void]$errors.Add("Pester failed: $($_.Exception.Message)") }
            } else { [void]$warnings.Add('Pester not installed.') }
        }
    }
}
end {
    foreach ($w in $warnings) { Write-Warning $w }
    foreach ($e in $errors) { Write-Error $e }
    [pscustomobject]@{ ModuleName='DotEnvTools'; Passed=(@($errors).Count -eq 0); ErrorCount=@($errors).Count; WarningCount=@($warnings).Count; RootPath=$ModuleRoot }
}

# SIG # Begin signature block
# MIIHXQYJKoZIhvcNAQcCoIIHTjCCB0oCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCC1xx9ogHo1dYoJ
# ORvJ58D5NlKU9NtjjtejkFG7CdQZKKCCBDowggQ2MIICnqADAgECAhBDcn1KArYx
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
# CSqGSIb3DQEJBDEiBCD3TOsRP1BIR3hY8wCpW2PCWoGdK4DKS62voxMnxjDuFTAN
# BgkqhkiG9w0BAQEFAASCAYBdNtVCvgC2HFRhyENLa1UifPSmz54L7R1RiHpKYqAn
# glX9w7IQsnUJytPSSXDg9Qq8Lseuqo811m2+F03/ngdWmLeYIWUfrN4EPSxsoB4f
# Rk7o4vsNhIwCzjAT6BiDsNHBaLgTmQqYhBhk1akKyhSsDuwL/CO+TkhJfjYYHhVP
# 6029wH47J3guDfsW8JjfL0pOrHz06Xx6D0eU95PY0jfAxWBVraFmGwLmOuI6wZ1y
# a76Qclr5DdqJnCbnlOdAKQLUB0VF7qf4bVZ46F+wuI8fTHJIt5JR8xiHD9Z8wy7N
# zktZm31Ilos6/9q808xrrPenNMNmfR79QUimhhoLfVSGo4iugZveFuKlTqZHXLiU
# 10AzlqciSu0QK6oAPnDT6vWA7qlcQ/k/1g16Jvi1zFlhoOV2CBaY+MRyHnk2gSyG
# k/mXqkDWSKoiDg4YIePLcrDOxMvI1RvTbZW37fN7EtR3kg6WsvAGCT85uV12N8XO
# FxjQ+t7dG7f+Vqey2vT0zNM=
# SIG # End signature block

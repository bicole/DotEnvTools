<#
.SYNOPSIS
Pester tests for DotEnvTools.

.DESCRIPTION
Validates parsing, import/remove behavior, and the auto-load regression where
an unchanged .env file must reload when tracked variables are missing.

.NOTES
Requires Pester 5.x.
Windows PowerShell 5.1 compatible.
#>

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\Source\DotEnvTools.psd1'

    Remove-Module DotEnvTools -Force -ErrorAction SilentlyContinue
    Import-Module $modulePath -Force -ErrorAction Stop
}

Describe 'DotEnvTools basic behavior' {

    BeforeEach {
        $script:TestRoot = Join-Path $TestDrive 'DotEnvToolsCase'
        New-Item -Path $script:TestRoot -ItemType Directory -Force | Out-Null

        $script:EnvPath = Join-Path $script:TestRoot '.env'

@'
API_URL=https://localhost:8443
DB_NAME=DotEnvDemo
QUOTED_VALUE="hello world"
EMPTY_VALUE=
'@ | Set-Content -Path $script:EnvPath -Encoding UTF8

        Remove-Item Env:\API_URL -ErrorAction SilentlyContinue
        Remove-Item Env:\DB_NAME -ErrorAction SilentlyContinue
        Remove-Item Env:\QUOTED_VALUE -ErrorAction SilentlyContinue
        Remove-Item Env:\EMPTY_VALUE -ErrorAction SilentlyContinue
    }

    AfterEach {
        Disable-DotEnvAutoLoad -ErrorAction SilentlyContinue | Out-Null

        if (Test-Path -Path $script:EnvPath) {
            Remove-DotEnvVariable -Path $script:EnvPath -ErrorAction SilentlyContinue | Out-Null
        }

        Remove-Item Env:\API_URL -ErrorAction SilentlyContinue
        Remove-Item Env:\DB_NAME -ErrorAction SilentlyContinue
        Remove-Item Env:\QUOTED_VALUE -ErrorAction SilentlyContinue
        Remove-Item Env:\EMPTY_VALUE -ErrorAction SilentlyContinue
    }

    It 'Parses simple dotenv content' {
        $content = @'
API_URL=https://localhost:8443
DB_NAME=DotEnvDemo
QUOTED_VALUE="hello world"
EMPTY_VALUE=
'@

        $result = ConvertFrom-DotEnv -Content $content

        $result.API_URL | Should -Be 'https://localhost:8443'
        $result.DB_NAME | Should -Be 'DotEnvDemo'
        $result.QUOTED_VALUE | Should -Be 'hello world'
        $result.EMPTY_VALUE | Should -Be ''
    }

    It 'Unescapes quotes inside double quoted values' {
        $content = 'QUOTED_VALUE="hello \"world\" there"'

        $result = ConvertFrom-DotEnv -Content $content

        $result.QUOTED_VALUE | Should -Be 'hello "world" there'
    }

    It 'Parses export prefixes, inline comments, escapes, and multiline quoted values' {
        $content = @'
export API_URL=https://localhost # local endpoint
QUOTED_VALUE="hello\tworld"
MULTILINE_VALUE="first
second"
'@

        $result = ConvertFrom-DotEnv -Content $content

        $result.API_URL | Should -Be 'https://localhost'
        $result.QUOTED_VALUE | Should -Be "hello`tworld"
        $result.MULTILINE_VALUE | Should -Be ("first{0}second" -f [Environment]::NewLine)
    }

    It 'Preserves hash characters inside quotes and ignores comments after quoted values' {
        $content = @'
QUOTED_VALUE="hello # world" # outside comment
SINGLE_VALUE='literal # value' # outside comment
'@

        $result = ConvertFrom-DotEnv -Content $content -Strict

        $result.QUOTED_VALUE | Should -Be 'hello # world'
        $result.SINGLE_VALUE | Should -Be 'literal # value'
    }

    It 'Reports unterminated quoted values in strict mode' {
        $content = 'BROKEN_VALUE="hello'

        $errors = $null
        $result = ConvertFrom-DotEnv -Content $content -Strict -ErrorVariable errors -ErrorAction SilentlyContinue

        $result.PSObject.Properties.Name | Should -Not -Contain 'BROKEN_VALUE'
        ($errors.Exception.Message -join "`n") | Should -Match 'Unterminated quoted value'
    }

    It 'Uses the last value when a key is repeated' {
        $content = @'
API_URL=https://first.example
API_URL=https://second.example
'@

        $result = ConvertFrom-DotEnv -Content $content

        $result.API_URL | Should -Be 'https://second.example'
    }

    It 'Reads EMPTY_VALUE as an empty string record' {
        $record = Read-DotEnvFile -Path $script:EnvPath |
            Where-Object { $_.Name -eq 'EMPTY_VALUE' }

        $record | Should -Not -BeNullOrEmpty
        $record.Value | Should -Be ''
    }

    It 'Imports and removes environment variables' {
        Import-DotEnvFile -Path $script:EnvPath -Override | Out-Null

        $env:API_URL | Should -Be 'https://localhost:8443'
        $env:DB_NAME | Should -Be 'DotEnvDemo'
        $env:QUOTED_VALUE | Should -Be 'hello world'

        Remove-DotEnvVariable -Path $script:EnvPath | Out-Null

        Test-Path Env:\API_URL | Should -BeFalse
        Test-Path Env:\DB_NAME | Should -BeFalse
        Test-Path Env:\QUOTED_VALUE | Should -BeFalse
        Test-Path Env:\EMPTY_VALUE | Should -BeFalse
    }

    It 'Does not remove existing variables skipped by NoClobber' {
        $env:API_URL = 'pre-existing'

        Import-DotEnvFile -Path $script:EnvPath | Out-Null

        $env:API_URL | Should -Be 'pre-existing'

        Remove-DotEnvVariable -Path $script:EnvPath | Out-Null

        $env:API_URL | Should -Be 'pre-existing'
    }

    It 'Reports malformed dotenv files as invalid' {
        Set-Content -Path $script:EnvPath -Value @(
            'API_URL=https://localhost:8443'
            'BADLINE'
        ) -Encoding UTF8

        $result = Test-DotEnvFile -Path $script:EnvPath

        $result.IsValid | Should -BeFalse
        $result.ErrorCount | Should -BeGreaterThan 0
        ($result.Errors -join "`n") | Should -Match "Missing '=' delimiter"
    }

    It 'Reports missing required and extra example keys' {
        $examplePath = Join-Path $script:TestRoot '.env.example'
        Set-Content -Path $examplePath -Value @(
            'API_URL='
            'REQUIRED_ONLY='
        ) -Encoding UTF8

        $result = Test-DotEnvFile `
            -Path $script:EnvPath `
            -ExamplePath $examplePath `
            -Required API_URL,REQUIRED_ONLY `
            -RequireNoExtraKeys

        $result.IsValid | Should -BeTrue
        $result.WarningCount | Should -BeGreaterThan 0
        ($result.Warnings -join "`n") | Should -Match 'Missing required key: REQUIRED_ONLY'
        ($result.Warnings -join "`n") | Should -Match 'Extra key not present in example: DB_NAME'
    }

    It 'Does not report required key errors when Required is omitted' {
        $examplePath = Join-Path $script:TestRoot '.env.example'
        Set-Content -Path $examplePath -Value @(
            'API_URL='
            'DB_NAME='
            'QUOTED_VALUE='
            'EMPTY_VALUE='
        ) -Encoding UTF8

        $result = Test-DotEnvFile -Path $script:EnvPath -ExamplePath $examplePath

        $result.IsValid | Should -BeTrue
        $result.ErrorCount | Should -Be 0
        ($result.Errors -join "`n") | Should -Not -Match 'Invalid required key name'
    }

    It 'Round-trips exported values with embedded quotes' {
        $exportPath = Join-Path $script:TestRoot '.env.export'
        $env:QUOTED_VALUE = 'hello "world" there'

        Export-DotEnvFile -Path $exportPath -Name QUOTED_VALUE -Force | Out-Null

        $result = ConvertFrom-DotEnv -Path $exportPath

        $result.QUOTED_VALUE | Should -Be 'hello "world" there'
    }

    It 'Reads dotenv configuration and single values without changing the environment' {
        $result = Get-DotEnvConfiguration -Path $script:EnvPath
        $value = Get-DotEnvValue -Path $script:EnvPath -Name API_URL

        $result.API_URL | Should -Be 'https://localhost:8443'
        $value | Should -Be 'https://localhost:8443'
        Test-Path Env:\API_URL | Should -BeFalse
    }

    It 'Sets and removes values in dotenv files' {
        Set-DotEnvValue -Path $script:EnvPath -Name NEW_VALUE -Value 'hello "world"' | Out-Null

        (Get-DotEnvValue -Path $script:EnvPath -Name NEW_VALUE) | Should -Be 'hello "world"'

        Remove-DotEnvValue -Path $script:EnvPath -Name NEW_VALUE | Out-Null

        Get-DotEnvValue -Path $script:EnvPath -Name NEW_VALUE | Should -BeNullOrEmpty
    }

    It 'Creates starter dotenv and example files' {
        $projectRoot = Join-Path $script:TestRoot 'NewProject'

        $files = @(Initialize-DotEnvProject -Path $projectRoot -Name API_URL,DB_NAME)

        @($files).Count | Should -Be 2
        Test-Path (Join-Path $projectRoot '.env') | Should -BeTrue
        Test-Path (Join-Path $projectRoot '.env.example') | Should -BeTrue
        Get-DotEnvValue -Path (Join-Path $projectRoot '.env.example') -Name API_URL | Should -Be ''
    }

    It 'Creates starter dotenv files in the current directory when Path is dot' {
        $projectRoot = Join-Path $script:TestRoot 'DotProject'
        New-Item -Path $projectRoot -ItemType Directory -Force | Out-Null

        Push-Location -LiteralPath $projectRoot
        try {
            $files = @(Initialize-DotEnvProject -Path . -Template WebApp -IncludeVariants -EnvironmentName development)
        }
        finally {
            Pop-Location
        }

        @($files).Count | Should -Be 5
        Test-Path (Join-Path $projectRoot '.env.example') | Should -BeTrue
        Test-Path (Join-Path $projectRoot '.env.local') | Should -BeTrue
        Test-Path (Join-Path $projectRoot '.env.development') | Should -BeTrue
        Test-Path (Join-Path $projectRoot '.env.development.local') | Should -BeTrue
        Test-Path (Join-Path $projectRoot 'DotProject') | Should -BeFalse
    }

    It 'Creates layered starter dotenv files' {
        $projectRoot = Join-Path $script:TestRoot 'LayeredNewProject'

        $files = @(Initialize-DotEnvProject -Path $projectRoot -Name API_URL -IncludeVariants -EnvironmentName development)

        @($files).Count | Should -Be 5
        Test-Path (Join-Path $projectRoot '.env.local') | Should -BeTrue
        Test-Path (Join-Path $projectRoot '.env.development') | Should -BeTrue
        Test-Path (Join-Path $projectRoot '.env.development.local') | Should -BeTrue
    }

    It 'Creates web app starter dotenv files' {
        $projectRoot = Join-Path $script:TestRoot 'WebAppProject'

        $files = @(Initialize-DotEnvProject -Path $projectRoot -Template WebApp -IncludeVariants -EnvironmentName development)

        @($files).Count | Should -Be 5

        $examplePath = Join-Path $projectRoot '.env.example'
        $envPath = Join-Path $projectRoot '.env'
        $localPath = Join-Path $projectRoot '.env.local'

        Get-DotEnvValue -Path $examplePath -Name APP_NAME | Should -Be 'MyApp'
        Get-DotEnvValue -Path $examplePath -Name DATABASE_URL | Should -Be 'postgresql://app_user:change_me@localhost:5432/app_db'
        Get-DotEnvValue -Path $examplePath -Name RATE_LIMIT_ENABLED | Should -Be 'true'
        Get-DotEnvValue -Path $envPath -Name PORT | Should -Be '3000'

        Get-Content -Path $localPath -Raw | Should -Match '# JWT_SECRET=change_me'
    }

    It 'Runs commands with temporary dotenv variables' {
        $powerShellPath = (Get-Process -Id $PID).Path
        $output = Invoke-DotEnvCommand `
            -Path $script:EnvPath `
            -Command $powerShellPath `
            -ArgumentList @('-NoProfile', '-Command', '[Console]::Write($env:API_URL)') `
            -Override

        $output | Should -Be 'https://localhost:8443'
        Test-Path Env:\API_URL | Should -BeFalse
    }

    It 'Restores previous values after command failures' {
        $powerShellPath = (Get-Process -Id $PID).Path
        $env:API_URL = 'pre-existing'

        Invoke-DotEnvCommand `
            -Path $script:EnvPath `
            -Command $powerShellPath `
            -ArgumentList @('-NoProfile', '-Command', 'exit 42') `
            -Override `
            -ErrorAction SilentlyContinue | Out-Null

        $env:API_URL | Should -Be 'pre-existing'
    }

    It 'Checks dotenv gitignore hygiene' {
        Set-Content -Path (Join-Path $script:TestRoot '.gitignore') -Value @(
            '.env'
            '.env.*'
            '.env.keys'
        ) -Encoding UTF8

        $result = Test-DotEnvGitIgnore -Path $script:TestRoot

        $result.IsProtected | Should -BeTrue
        @($result.MissingPatterns).Count | Should -Be 0
    }

    It 'Does not expose WhatIf on read-only commands' {
        $readOnlyCommands = @(
            'Get-DotEnvAutoLoadState'
            'Get-DotEnvConfiguration'
            'Get-DotEnvFilePath'
            'Get-DotEnvValue'
            'Read-DotEnvFile'
            'Test-DotEnvFile'
            'Test-DotEnvGitIgnore'
        )

        foreach ($commandName in $readOnlyCommands) {
            (Get-Command -Name $commandName -Module DotEnvTools).Parameters.ContainsKey('WhatIf') |
                Should -BeFalse -Because "$commandName does not mutate state"
        }
    }

    It 'Reloads unchanged dotenv file when tracked variables are missing' {
        Push-Location $script:TestRoot

        try {
            Enable-DotEnvAutoLoad -TrustedPath $script:TestRoot | Out-Null

            Invoke-DotEnvAutoLoadNow | Out-Null

            $env:API_URL | Should -Be 'https://localhost:8443'

            Remove-DotEnvVariable -Path $script:EnvPath | Out-Null

            Test-Path Env:\API_URL | Should -BeFalse

            Invoke-DotEnvAutoLoadNow | Out-Null

            $env:API_URL | Should -Be 'https://localhost:8443'
            $env:DB_NAME | Should -Be 'DotEnvDemo'
            $env:QUOTED_VALUE | Should -Be 'hello world'
        }
        finally {
            Pop-Location
        }
    }
}

Describe 'DotEnvTools layered dotenv loading' {

    BeforeEach {
        $script:LayerRoot = Join-Path $TestDrive 'DotEnvToolsLayerCase'
        New-Item -Path $script:LayerRoot -ItemType Directory -Force | Out-Null

@'
BASE_ONLY=base
SHARED_VALUE=base
'@ | Set-Content -Path (Join-Path $script:LayerRoot '.env') -Encoding UTF8

@'
LOCAL_ONLY=local
SHARED_VALUE=local
'@ | Set-Content -Path (Join-Path $script:LayerRoot '.env.local') -Encoding UTF8

@'
DEV_ONLY=development
SHARED_VALUE=development
'@ | Set-Content -Path (Join-Path $script:LayerRoot '.env.development') -Encoding UTF8

@'
DEV_LOCAL_ONLY=development-local
SHARED_VALUE=development-local
'@ | Set-Content -Path (Join-Path $script:LayerRoot '.env.development.local') -Encoding UTF8

        Remove-Item Env:\BASE_ONLY -ErrorAction SilentlyContinue
        Remove-Item Env:\LOCAL_ONLY -ErrorAction SilentlyContinue
        Remove-Item Env:\DEV_ONLY -ErrorAction SilentlyContinue
        Remove-Item Env:\DEV_LOCAL_ONLY -ErrorAction SilentlyContinue
        Remove-Item Env:\SHARED_VALUE -ErrorAction SilentlyContinue
    }

    AfterEach {
        Disable-DotEnvAutoLoad -ErrorAction SilentlyContinue | Out-Null

        Remove-Item Env:\BASE_ONLY -ErrorAction SilentlyContinue
        Remove-Item Env:\LOCAL_ONLY -ErrorAction SilentlyContinue
        Remove-Item Env:\DEV_ONLY -ErrorAction SilentlyContinue
        Remove-Item Env:\DEV_LOCAL_ONLY -ErrorAction SilentlyContinue
        Remove-Item Env:\SHARED_VALUE -ErrorAction SilentlyContinue
    }

    It 'Resolves layered dotenv files in deterministic order' {
        $files = @(
            Get-DotEnvFilePath -Path $script:LayerRoot -IncludeVariants -EnvironmentName development
        )

        @($files).Count | Should -Be 4
        [System.IO.Path]::GetFileName($files[0]) | Should -Be '.env'
        [System.IO.Path]::GetFileName($files[1]) | Should -Be '.env.local'
        [System.IO.Path]::GetFileName($files[2]) | Should -Be '.env.development'
        [System.IO.Path]::GetFileName($files[3]) | Should -Be '.env.development.local'
    }

    It 'Loads only .env when variants are not included' {
        Import-DotEnvFile -Path $script:LayerRoot -Override | Out-Null

        $env:BASE_ONLY | Should -Be 'base'
        $env:LOCAL_ONLY | Should -BeNullOrEmpty
        $env:DEV_ONLY | Should -BeNullOrEmpty
        $env:DEV_LOCAL_ONLY | Should -BeNullOrEmpty
        $env:SHARED_VALUE | Should -Be 'base'
    }

    It 'Loads layered dotenv files with override precedence' {
        Import-DotEnvFile -Path $script:LayerRoot -IncludeVariants -EnvironmentName development -Override | Out-Null

        $env:BASE_ONLY | Should -Be 'base'
        $env:LOCAL_ONLY | Should -Be 'local'
        $env:DEV_ONLY | Should -Be 'development'
        $env:DEV_LOCAL_ONLY | Should -Be 'development-local'
        $env:SHARED_VALUE | Should -Be 'development-local'
    }

    It 'Preserves first value when NoClobber is active' {
        Import-DotEnvFile -Path $script:LayerRoot -IncludeVariants -EnvironmentName development -NoClobber | Out-Null

        $env:BASE_ONLY | Should -Be 'base'
        $env:LOCAL_ONLY | Should -Be 'local'
        $env:DEV_ONLY | Should -Be 'development'
        $env:DEV_LOCAL_ONLY | Should -Be 'development-local'
        $env:SHARED_VALUE | Should -Be 'base'
    }

    It 'Finds dotenv files by searching parent directories' {
        $child = Join-Path $script:LayerRoot 'nested\child'
        New-Item -Path $child -ItemType Directory -Force | Out-Null

        $files = @(Find-DotEnvFile -Path $child -IncludeVariants -EnvironmentName development)

        @($files).Count | Should -Be 4
        [System.IO.Path]::GetFileName($files[0]) | Should -Be '.env'
    }
}

Describe 'DotEnvTools variable expansion' {

    BeforeEach {
        $script:ExpandRoot = Join-Path $TestDrive 'DotEnvToolsExpandCase'
        New-Item -Path $script:ExpandRoot -ItemType Directory -Force | Out-Null

@'
HOST=localhost
PORT=8080
API_URL=http://${HOST}:${PORT}
LITERAL_VALUE=${MISSING_VALUE}
'@ | Set-Content -Path (Join-Path $script:ExpandRoot '.env') -Encoding UTF8

        Remove-Item Env:\HOST -ErrorAction SilentlyContinue
        Remove-Item Env:\PORT -ErrorAction SilentlyContinue
        Remove-Item Env:\API_URL -ErrorAction SilentlyContinue
        Remove-Item Env:\LITERAL_VALUE -ErrorAction SilentlyContinue
        Remove-Item Env:\MISSING_VALUE -ErrorAction SilentlyContinue
    }

    AfterEach {
        Remove-Item Env:\HOST -ErrorAction SilentlyContinue
        Remove-Item Env:\PORT -ErrorAction SilentlyContinue
        Remove-Item Env:\API_URL -ErrorAction SilentlyContinue
        Remove-Item Env:\LITERAL_VALUE -ErrorAction SilentlyContinue
        Remove-Item Env:\MISSING_VALUE -ErrorAction SilentlyContinue
    }

    It 'Does not expand variables by default' {
        Import-DotEnvFile -Path $script:ExpandRoot -Override | Out-Null

        $env:API_URL | Should -Be 'http://${HOST}:${PORT}'
    }

    It 'Expands variables when ExpandVariables is used' {
        Import-DotEnvFile -Path $script:ExpandRoot -Override -ExpandVariables | Out-Null

        $env:API_URL | Should -Be 'http://localhost:8080'
    }

    It 'Expands unbraced variables when ExpandVariables is used' {
        Set-Content -Path (Join-Path $script:ExpandRoot '.env') -Value @(
            'HOST=localhost'
            'PORT=8080'
            'API_URL=http://$HOST:$PORT'
        ) -Encoding UTF8

        Import-DotEnvFile -Path $script:ExpandRoot -Override -ExpandVariables | Out-Null

        $env:API_URL | Should -Be 'http://localhost:8080'
    }

    It 'Preserves missing variable references' {
        Import-DotEnvFile -Path $script:ExpandRoot -Override -ExpandVariables | Out-Null

        $env:LITERAL_VALUE | Should -Be '${MISSING_VALUE}'
    }
}

Describe 'DotEnvTools Dev Container Feature metadata' {

    It 'Uses the current module version as the default Feature install version' {
        $manifest = Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot '..\Source\DotEnvTools.psd1')
        $featurePath = Join-Path $PSScriptRoot '..\src\dotenvtools\devcontainer-feature.json'
        $installPath = Join-Path $PSScriptRoot '..\src\dotenvtools\install.sh'

        $feature = Get-Content -Path $featurePath -Raw | ConvertFrom-Json
        $installScript = Get-Content -Path $installPath -Raw

        $feature.id | Should -Be 'dotenvtools'
        $feature.options.version.default | Should -Be ([string]$manifest.ModuleVersion)
        $feature.options.archivePath.default | Should -Be ''
        $feature.options.template.enum | Should -Contain 'Basic'
        $feature.options.template.enum | Should -Contain 'WebApp'
        $feature.postCreateCommand | Should -Match ([regex]::Escape('/usr/local/share/dotenvtools/devcontainer-post-create.sh ''${containerWorkspaceFolder}'''))
        $feature.postStartCommand | Should -Match ([regex]::Escape('/usr/local/share/dotenvtools/devcontainer-post-create.sh ''${containerWorkspaceFolder}'''))
        $installScript | Should -Match ([regex]::Escape(('DOTENVTOOLS_VERSION="${{VERSION:-{0}}}"' -f [string]$manifest.ModuleVersion)))
        $installScript | Should -Match ([regex]::Escape('$ErrorActionPreference = ''Stop'''))
        $installScript | Should -Match ([regex]::Escape('initialize-project.ps1'))
        $installScript | Should -Match ([regex]::Escape('Import-Module $env:module_path -Force'))
        $installScript | Should -Match ([regex]::Escape('DotEnvTools did not create expected file'))
        $installScript | Should -Match ([regex]::Escape('DOTENVTOOLS_WORKSPACE'))
        $installScript | Should -Match ([regex]::Escape('initializeProject is false'))
        $installScript | Should -Match ([regex]::Escape('.env.example already exists'))
        $installScript | Should -Match ([regex]::Escape('Initializing DotEnvTools project in'))
        $installScript | Should -Match ([regex]::Escape('export module_path='))
        $installScript | Should -Match ([regex]::Escape('export workspace='))
    }
}

# SIG # Begin signature block
# MIIHXQYJKoZIhvcNAQcCoIIHTjCCB0oCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCD6kltMd59qMUos
# HrlAZwyfA/5gveoxPBwaHhdPcYa/MaCCBDowggQ2MIICnqADAgECAhBDcn1KArYx
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
# CSqGSIb3DQEJBDEiBCAwG7TXMw5MCNj/yNcC6892wI2fg1VtH3Y3aVwRyKvV5jAN
# BgkqhkiG9w0BAQEFAASCAYCvsy5lbq9ccHEAHPY/xDurB5X478nNbMKDRZelHpS9
# PDroff5Kdc1+QYF8sYDxGNqSsNDAOQ2to/DrcE5L+Tdses37hIlY6QirNgXoCxEK
# FEN2OVLc6XEfs0SBVikyQf6UFNYMX6UttIeu/3upy3649P0CyJ1nOYWVXxX/+bA+
# SDSy1Lzwl0gQL9zRFFEtX5XDXODFVIyTUJQdd5+RjAjnMboz27u+8TgVQbM0obYk
# 4h0xQA9Jv7NjE/89OCaGdB1u42/4i4/y03SH91CDbqWGGwR5gp9jNK/rl4p69/W0
# /jM4AM0JBnvRvN1AZDK+G2y0guCjV9CTKYQsTBBuEmFkSSeFy3LAbtg4gKv5vUm3
# s8SfO/Zw+jmM/D7CsD/k9Fj3NgbVjNhb5kFNuR6Wa+PpXRUDtspC+JPpJiWI+xIz
# 7gd/VXvVS9PWQKOdmpL8LG3Q5PofKfflWYbJY49VnMo15yzWuPvlUBKlQFNjL1re
# NZdCHaJxkrwWwMv7P18F7Xs=
# SIG # End signature block

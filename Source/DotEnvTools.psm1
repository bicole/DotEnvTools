# DotEnvTools.psm1
# Windows PowerShell 5.1 compatible .env loader.

Set-StrictMode -Version 2.0

$dotEnvStateVariable = Get-Variable -Name DotEnvState -Scope Script -ErrorAction SilentlyContinue
if ($null -eq $dotEnvStateVariable) {
    $script:DotEnvState = @{
        AutoLoadEnabled = $false
        LastPath = $null
        LastLoadedFiles = @()
        LoadedFiles = @{}
        LoadedVariables = @{}
        OriginalValues = @{}
        FileHashes = @{}
        TrustedPaths = @()
        TrustAll = $false
        RemoveOnExit = $false
        IncludeVariants = $false
        EnvironmentName = $null
        Override = $false
        NoClobber = $false
        RevealValues = $false
    }
}

function Resolve-DotEnvValue {
<#
.SYNOPSIS
Resolves ${NAME} references inside a dotenv value.

.DESCRIPTION
Expands variable references in the form ${NAME} using a provided value map first,
then the current process environment. Missing variables are preserved unchanged.

.PARAMETER Value
The raw value to resolve.

.PARAMETER ValueMap
Hashtable of already-known dotenv values.

.PARAMETER MaxDepth
Maximum recursive expansion depth.

.EXAMPLE
Resolve-DotEnvValue -Value 'http://${HOST}:${PORT}' -ValueMap @{ HOST = 'localhost'; PORT = '8080' }

.INPUTS
System.String

.OUTPUTS
System.String

.NOTES
Windows PowerShell 5.1 compatible.
This function does not execute commands.
#>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$Value,

        [Parameter(Mandatory = $false)]
        [hashtable]$ValueMap,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 50)]
        [int]$MaxDepth = 10
    )

    if ($null -eq $Value) {
        return ''
    }

    $resolved = [string]$Value
    $pattern = '\$\{([A-Za-z_][A-Za-z0-9_]*)\}|\$([A-Za-z_][A-Za-z0-9_]*)'

    for ($depth = 0; $depth -lt $MaxDepth; $depth++) {
        $regexMatches = [regex]::Matches($resolved, $pattern)

        if ($regexMatches.Count -eq 0) {
            break
        }

        $builder = New-Object System.Text.StringBuilder
        $lastIndex = 0
        $changed = $false

        foreach ($match in $regexMatches) {
            [void]$builder.Append($resolved.Substring($lastIndex, $match.Index - $lastIndex))

            $name = $match.Groups[1].Value
            if ([string]::IsNullOrEmpty($name)) {
                $name = $match.Groups[2].Value
            }
            $replacement = $null
            $found = $false

            if ($null -ne $ValueMap -and $ValueMap.ContainsKey($name)) {
                $replacement = $ValueMap[$name]
                $found = $true
            }
            else {
                $envPath = "Env:\{0}" -f $name

                if (Test-Path -Path $envPath) {
                    $replacement = (Get-Item -Path $envPath).Value
                    $found = $true
                }
            }

            if ($found) {
                if ($null -eq $replacement) {
                    $replacement = ''
                }

                [void]$builder.Append([string]$replacement)
                $changed = $true
            }
            else {
                [void]$builder.Append($match.Value)
            }

            $lastIndex = $match.Index + $match.Length
        }

        if ($lastIndex -lt $resolved.Length) {
            [void]$builder.Append($resolved.Substring($lastIndex))
        }

        $newResolved = $builder.ToString()

        if (-not $changed -or $newResolved -eq $resolved) {
            $resolved = $newResolved
            break
        }

        $resolved = $newResolved
    }

    return $resolved
}

function Get-DotEnvQuotedValueEndIndex {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Value,

        [Parameter(Mandatory = $true)]
        [ValidateSet('"', "'")]
        [string]$Quote
    )

    $escaped = $false

    for ($index = 1; $index -lt $Value.Length; $index++) {
        $character = $Value.Substring($index, 1)

        if ($Quote -eq '"' -and $escaped) {
            $escaped = $false
            continue
        }

        if ($Quote -eq '"' -and $character -eq '\') {
            $escaped = $true
            continue
        }

        if ($character -eq $Quote) {
            return $index
        }
    }

    return -1
}

function Resolve-DotEnvTargetPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    if ($Path -in @('.', '.\', './')) {
        return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    }

    $parentPath = Split-Path -Path $Path -Parent
    $leafName = Split-Path -Path $Path -Leaf

    if ([string]::IsNullOrWhiteSpace($leafName)) {
        return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    }

    if ([string]::IsNullOrWhiteSpace($parentPath)) {
        $resolvedParent = (Get-Location).ProviderPath
    }
    else {
        $resolvedParent = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($parentPath)
    }

    Join-Path -Path $resolvedParent -ChildPath $leafName
}

function Get-DotEnvFilePath {
<#
.SYNOPSIS
Resolves .env file paths in deterministic load order.

.DESCRIPTION
Returns existing .env files from either a direct .env file path or a directory path.
When -IncludeVariants is used, variant files are returned in precedence order:

`.env`, `.env.local`, `.env.<EnvironmentName>`, and `.env.<EnvironmentName>.local`.

Only existing files are returned.

.PARAMETER Path
A .env file path or directory path.

.PARAMETER IncludeVariants
Includes supported .env variant files.

.PARAMETER EnvironmentName
Optional environment name, such as development, test, staging, or production.

.PARAMETER SearchUp
Searches parent directories for dotenv files and returns parent files before child files.

.EXAMPLE
Get-DotEnvFilePath -Path .\

.EXAMPLE
Get-DotEnvFilePath -Path .\ -IncludeVariants -EnvironmentName development

.EXAMPLE
Get-DotEnvFilePath -Path .\src -SearchUp

.INPUTS
System.String

.OUTPUTS
System.String

.NOTES
Windows PowerShell 5.1 compatible.
#>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeVariants,

        [Parameter(Mandatory = $false)]
        [string]$EnvironmentName,

        [Parameter(Mandatory = $false)]
        [switch]$SearchUp
    )

    begin {}

    process {
        try {
            $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)

            if (Test-Path -LiteralPath $resolvedPath -PathType Leaf) {
                $resolvedPath
                return
            }

            if (-not (Test-Path -LiteralPath $resolvedPath -PathType Container)) {
                Write-Error -Message ("Path not found: {0}" -f $Path) -Category ObjectNotFound
                return
            }

            $searchRoots = New-Object System.Collections.ArrayList
            if ($SearchUp) {
                $currentDirectory = [System.IO.DirectoryInfo]$resolvedPath
                $stack = New-Object System.Collections.Stack

                while ($null -ne $currentDirectory) {
                    $stack.Push($currentDirectory.FullName)
                    $currentDirectory = $currentDirectory.Parent
                }

                while ($stack.Count -gt 0) {
                    [void]$searchRoots.Add($stack.Pop())
                }
            }
            else {
                [void]$searchRoots.Add($resolvedPath)
            }

            $candidateNames = New-Object System.Collections.ArrayList
            [void]$candidateNames.Add('.env')

            if ($IncludeVariants) {
                [void]$candidateNames.Add('.env.local')

                if (-not [string]::IsNullOrWhiteSpace($EnvironmentName)) {
                    [void]$candidateNames.Add(('.env.{0}' -f $EnvironmentName))
                    [void]$candidateNames.Add(('.env.{0}.local' -f $EnvironmentName))
                }
            }

            foreach ($root in $searchRoots) {
                foreach ($candidateName in $candidateNames) {
                    $candidatePath = Join-Path $root $candidateName

                    if (Test-Path -LiteralPath $candidatePath -PathType Leaf) {
                        $candidatePath
                    }
                }
            }
        }
        catch {
            Write-Error -Message ("Failed to resolve .env file path from '{0}'. {1}" -f $Path, $_.Exception.Message) -Category InvalidOperation
        }
    }

    end {}
}

function Test-DotEnvTrustedPath {
<#
.SYNOPSIS
Tests whether a path is trusted for auto-loading.
.DESCRIPTION
Returns true when TrustAll is enabled or the target path is equal to or below a trusted path.
.PARAMETER Path
Path to test.
.PARAMETER TrustedPath
Trusted directory roots.
.PARAMETER TrustAll
Trust every path.
.EXAMPLE
Test-DotEnvTrustedPath -Path C:\Dev\App -TrustedPath C:\Dev
.INPUTS
None
.OUTPUTS
System.Boolean
.NOTES
Internal helper. Windows PowerShell 5.1 compatible.
#>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter()]
        [string[]]$TrustedPath,

        [Parameter()]
        [switch]$TrustAll
    )

    process {
        if ($TrustAll) {
            return $true
        }

        if ($null -eq $TrustedPath -or @($TrustedPath).Count -eq 0) {
            return $false
        }

        try {
            $resolvedPath = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')

            foreach ($trusted in $TrustedPath) {
                if ([string]::IsNullOrWhiteSpace($trusted)) {
                    continue
                }

                $resolvedTrusted = [System.IO.Path]::GetFullPath($trusted).TrimEnd('\')

                if ($resolvedPath.Equals($resolvedTrusted, [System.StringComparison]::OrdinalIgnoreCase)) {
                    return $true
                }

                $trustedWithSlash = $resolvedTrusted + '\'
                if ($resolvedPath.StartsWith($trustedWithSlash, [System.StringComparison]::OrdinalIgnoreCase)) {
                    return $true
                }
            }
        }
        catch {
            Write-Verbose ("Trusted path check failed. {0}" -f $_.Exception.Message)
        }

        return $false
    }
}

function ConvertFrom-DotEnv {
<#
.SYNOPSIS
Parses .env content into a PowerShell object.

.DESCRIPTION
Parses .env content from a file path or raw content string and returns a PSCustomObject
where each .env key becomes a property.

.PARAMETER Path
Path to a .env file.

.PARAMETER Content
Raw .env content.

.PARAMETER Strict
Reports invalid .env lines as errors instead of silently skipping them.

.EXAMPLE
ConvertFrom-DotEnv -Path .\.env

.EXAMPLE
ConvertFrom-DotEnv -Content "KEY=value"

.INPUTS
System.String

.OUTPUTS
System.Management.Automation.PSCustomObject

.NOTES
Windows PowerShell 5.1 compatible.
#>
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $true, ParameterSetName = 'Content', ValueFromPipeline = $true)]
        [ValidateNotNull()]
        [string]$Content,

        [Parameter(Mandatory = $false)]
        [switch]$Strict
    )

    begin {
        $contentBuffer = New-Object System.Collections.ArrayList
    }

    process {
        try {
            if ($PSCmdlet.ParameterSetName -eq 'Content') {
                [void]$contentBuffer.Add($Content)
            }
        }
        catch {
            Write-Error -Message ("Failed to buffer .env content. {0}" -f $_.Exception.Message) -Category InvalidOperation
        }
    }

    end {
        try {
            if ($PSCmdlet.ParameterSetName -eq 'Path') {
                if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
                    Write-Error -Message ("File not found: {0}" -f $Path) -Category ObjectNotFound
                    return
                }

                $rawContent = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
            }
            else {
                $rawContent = ($contentBuffer -join [Environment]::NewLine)
            }

            $result = [ordered]@{}

            $physicalLines = $rawContent -split "`r?`n"
            $lines = New-Object System.Collections.ArrayList

            for ($index = 0; $index -lt $physicalLines.Count; $index++) {
                $logicalLine = [string]$physicalLines[$index]
                $trimmedLogicalLine = $logicalLine.Trim()

                if ($trimmedLogicalLine -match '^[A-Za-z_][A-Za-z0-9_]*\s*=\s*["'']' -or $trimmedLogicalLine -match '^export\s+[A-Za-z_][A-Za-z0-9_]*\s*=\s*["'']') {
                    $separatorIndex = $logicalLine.IndexOf('=')
                    $valueStart = $logicalLine.Substring($separatorIndex + 1).TrimStart()

                    if ($valueStart.Length -gt 0) {
                        $quote = $valueStart.Substring(0, 1)
                        $quotedValueEndIndex = Get-DotEnvQuotedValueEndIndex -Value $valueStart -Quote $quote

                        while (
                            $index -lt ($physicalLines.Count - 1) -and
                            $quotedValueEndIndex -lt 0
                        ) {
                            $index++
                            $logicalLine = $logicalLine + [Environment]::NewLine + [string]$physicalLines[$index]
                            $valueStart = $logicalLine.Substring($separatorIndex + 1).TrimStart()
                            $quotedValueEndIndex = Get-DotEnvQuotedValueEndIndex -Value $valueStart -Quote $quote
                        }
                    }
                }

                [void]$lines.Add($logicalLine)
            }

            foreach ($line in $lines) {
                $trimmed = $line.Trim()

                if ([string]::IsNullOrWhiteSpace($trimmed)) {
                    continue
                }

                if ($trimmed.StartsWith('#')) {
                    continue
                }

                if ($trimmed.StartsWith('export ')) {
                    $trimmed = $trimmed.Substring(7).TrimStart()
                }

                if ($trimmed -notmatch '=') {
                    if ($Strict) {
                        Write-Error -Message ("Invalid .env line. Missing '=' delimiter: {0}" -f $line) -Category InvalidData
                    }

                    continue
                }

                $pair = $trimmed -split '=', 2
                $name = $pair[0].Trim()

                if ([string]::IsNullOrWhiteSpace($name)) {
                    if ($Strict) {
                        Write-Error -Message ("Invalid .env line. Empty variable name: {0}" -f $line) -Category InvalidData
                    }

                    continue
                }

                if ($name -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
                    if ($Strict) {
                        Write-Error -Message ("Invalid .env line. Invalid variable name: {0}" -f $line) -Category InvalidData
                    }

                    continue
                }

                $value = ''

                if ($pair.Count -ge 2) {
                    $value = $pair[1]
                }

                if ($null -eq $value) {
                    $value = ''
                }
                else {
                    $value = [string]$value
                }

                $value = $value.Trim()
                $wasQuoted = $false

                if ($value.Length -gt 0) {
                    if ($value.StartsWith('"') -or $value.StartsWith("'")) {
                        $quote = $value.Substring(0, 1)
                        $quotedValueEndIndex = Get-DotEnvQuotedValueEndIndex -Value $value -Quote $quote

                        if ($quotedValueEndIndex -lt 0) {
                            if ($Strict) {
                                Write-Error -Message ("Invalid .env line. Unterminated quoted value: {0}" -f $line) -Category InvalidData
                            }

                            continue
                        }

                        $remainder = $value.Substring($quotedValueEndIndex + 1).Trim()
                        if ($Strict -and -not [string]::IsNullOrWhiteSpace($remainder) -and -not $remainder.StartsWith('#')) {
                            Write-Error -Message ("Invalid .env line. Unexpected content after quoted value: {0}" -f $line) -Category InvalidData
                            continue
                        }

                        $wasQuoted = $true
                        $wasDoubleQuoted = $quote -eq '"'
                        $value = $value.Substring(1, $quotedValueEndIndex - 1)

                        if ($wasDoubleQuoted) {
                            $value = $value -replace '\\n', "`n"
                            $value = $value -replace '\\t', "`t"
                            $value = $value -replace '\\"', '"'
                            $value = $value -replace '\\\\', '\'
                        }
                    }
                }

                if (-not $wasQuoted) {
                    $value = $value -replace '\s+#.*$', ''
                    $value = $value.TrimEnd()
                }

                if ($null -eq $value) {
                    $value = ''
                }

                $result[$name] = [string]$value
            }

            [pscustomobject]$result
        }
        catch {
            Write-Error -Message ("Failed to parse .env content. {0}" -f $_.Exception.Message) -Category InvalidOperation
        }
    }
}

function Read-DotEnvFile {
<#
.SYNOPSIS
Reads a .env file and returns normalized key/value records.

.DESCRIPTION
Reads a single .env file, parses it with ConvertFrom-DotEnv, and returns one object
per environment variable with Name, Value, and SourcePath properties.

This function normalizes null values to empty strings so EMPTY_VALUE= remains an
empty environment variable rather than being treated as a missing value.

.PARAMETER Path
Path to a .env file.

.PARAMETER Strict
Reports invalid .env lines as errors.

.PARAMETER IncludeVariants
Compatibility parameter. Variant resolution should occur before calling this function.

.EXAMPLE
Read-DotEnvFile -Path .\.env

.EXAMPLE
Read-DotEnvFile -Path .\.env -Strict

.INPUTS
System.String

.OUTPUTS
System.Management.Automation.PSCustomObject

.NOTES
Windows PowerShell 5.1 compatible.
#>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [switch]$Strict
    )

    begin {}

    process {
        try {
            if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
                Write-Error -Message ("File not found: {0}" -f $Path) -Category ObjectNotFound
                return
            }

            $content = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
            $parsed = ConvertFrom-DotEnv -Content $content -Strict:$Strict

            foreach ($property in $parsed.PSObject.Properties) {
                $value = $property.Value

                if ($null -eq $value) {
                    $value = ''
                }
                else {
                    $value = [string]$value
                }

                [pscustomobject]@{
                    Name       = $property.Name
                    Value      = $value
                    SourcePath = $Path
                }
            }
        }
        catch {
            Write-Error -Message ("Failed to read .env file '{0}'. {1}" -f $Path, $_.Exception.Message) -Category ReadError
        }
    }

    end {}
}

function Get-DotEnvConfiguration {
<#
.SYNOPSIS
Gets dotenv configuration without modifying the process environment.
.DESCRIPTION
Resolves one or more dotenv files and returns a PSCustomObject by default, or an
ordered hashtable when -AsHashtable is used.
.PARAMETER Path
Path to a .env file or directory.
.PARAMETER IncludeVariants
Includes supported variant files.
.PARAMETER EnvironmentName
Optional environment suffix used with variant files.
.PARAMETER SearchUp
Searches parent directories for dotenv files, loading parents before children.
.PARAMETER Strict
Enables strict parsing.
.PARAMETER ExpandVariables
Expands variable references using values already read, then process variables.
.PARAMETER AsHashtable
Returns an ordered hashtable instead of a PSCustomObject.
.EXAMPLE
Get-DotEnvConfiguration -Path .\.env
.EXAMPLE
Get-DotEnvConfiguration -Path . -IncludeVariants -EnvironmentName development -AsHashtable
.NOTES
Windows PowerShell 5.1 compatible.
#>
    [CmdletBinding()]
    [OutputType([pscustomobject], [System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter()]
        [switch]$IncludeVariants,

        [Parameter()]
        [string]$EnvironmentName,

        [Parameter()]
        [switch]$SearchUp,

        [Parameter()]
        [switch]$Strict,

        [Parameter()]
        [switch]$ExpandVariables,

        [Parameter()]
        [switch]$AsHashtable
    )

    process {
        try {
            $map = [ordered]@{}
            $files = @(
                Get-DotEnvFilePath `
                    -Path $Path `
                    -IncludeVariants:$IncludeVariants `
                    -EnvironmentName $EnvironmentName `
                    -SearchUp:$SearchUp
            )

            foreach ($file in $files) {
                foreach ($entry in Read-DotEnvFile -Path $file -Strict:$Strict) {
                    if ($null -eq $entry) {
                        continue
                    }

                    $value = if ($null -eq $entry.Value) { '' } else { [string]$entry.Value }

                    if ($ExpandVariables) {
                        $value = Resolve-DotEnvValue -Value $value -ValueMap $map
                    }

                    $map[$entry.Name] = $value
                }
            }

            if ($AsHashtable) {
                return $map
            }

            [pscustomobject]$map
        }
        catch {
            Write-Error -Message ("Failed to get dotenv configuration from path '{0}'. {1}" -f $Path, $_.Exception.Message) -Category ReadError
        }
    }
}

function Get-DotEnvValue {
<#
.SYNOPSIS
Gets one dotenv value without modifying the process environment.
.DESCRIPTION
Reads resolved dotenv files and returns the value for a single key. This command
does not write to the process environment.
.PARAMETER Path
Path to a .env file or directory.
.PARAMETER Name
Variable name to return.
.PARAMETER IncludeVariants
Includes supported variant files.
.PARAMETER EnvironmentName
Optional environment suffix used with variant files.
.PARAMETER SearchUp
Searches parent directories for dotenv files.
.PARAMETER Strict
Enables strict parsing.
.PARAMETER ExpandVariables
Expands variable references before returning the value.
.EXAMPLE
Get-DotEnvValue -Path .\.env -Name API_URL
.EXAMPLE
Get-DotEnvValue -Path . -Name API_URL -IncludeVariants -EnvironmentName development -ExpandVariables
.OUTPUTS
System.String
.NOTES
Windows PowerShell 5.1 compatible.
#>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[A-Za-z_][A-Za-z0-9_]*$')]
        [string]$Name,

        [Parameter()]
        [switch]$IncludeVariants,

        [Parameter()]
        [string]$EnvironmentName,

        [Parameter()]
        [switch]$SearchUp,

        [Parameter()]
        [switch]$Strict,

        [Parameter()]
        [switch]$ExpandVariables
    )

    process {
        $map = Get-DotEnvConfiguration `
            -Path $Path `
            -IncludeVariants:$IncludeVariants `
            -EnvironmentName $EnvironmentName `
            -SearchUp:$SearchUp `
            -Strict:$Strict `
            -ExpandVariables:$ExpandVariables `
            -AsHashtable

        if ($map.Contains($Name)) {
            [string]$map[$Name]
        }
    }
}

function Find-DotEnvFile {
<#
.SYNOPSIS
Finds dotenv files in the current or parent directories.
.DESCRIPTION
Searches upward from a directory and returns matching dotenv files in deterministic
load order.
.PARAMETER Path
Starting directory for the search.
.PARAMETER IncludeVariants
Includes supported variant files.
.PARAMETER EnvironmentName
Optional environment suffix used with variant files.
.EXAMPLE
Find-DotEnvFile -Path . -IncludeVariants -EnvironmentName development
.OUTPUTS
System.String
.NOTES
Windows PowerShell 5.1 compatible.
#>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$Path = '.',

        [Parameter()]
        [switch]$IncludeVariants,

        [Parameter()]
        [string]$EnvironmentName
    )

    process {
        Get-DotEnvFilePath -Path $Path -IncludeVariants:$IncludeVariants -EnvironmentName $EnvironmentName -SearchUp
    }
}

function Format-DotEnvValue {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [string]$Value
    )

    if ($null -eq $Value) {
        $Value = ''
    }

    $escaped = [string]$Value
    if ($escaped -match '\s|#|=|"') {
        $escaped = $escaped -replace '\\', '\\'
        $escaped = $escaped -replace '"', '\"'
        return '"' + $escaped + '"'
    }

    $escaped
}

function Set-DotEnvValue {
<#
.SYNOPSIS
Adds or updates a key in a dotenv file.
.DESCRIPTION
Writes a key/value pair to a dotenv file. Existing matching keys are replaced;
unrelated lines and comments are preserved.
.PARAMETER Path
Path to the dotenv file.
.PARAMETER Name
Variable name to add or update.
.PARAMETER Value
Value to write.
.PARAMETER Force
Creates the file if missing.
.EXAMPLE
Set-DotEnvValue -Path .\.env -Name API_URL -Value https://localhost:8443
.EXAMPLE
Set-DotEnvValue -Path .\.env -Name API_URL -Value https://localhost:8443 -Force
.OUTPUTS
System.IO.FileInfo
.NOTES
Windows PowerShell 5.1 compatible.
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[A-Za-z_][A-Za-z0-9_]*$')]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Value,

        [Parameter()]
        [switch]$Force
    )

    process {
        try {
            $targetPath = Resolve-DotEnvTargetPath -Path $Path
            if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
                if (-not $Force) {
                    Write-Error -Message ("File not found: {0}. Use -Force to create it." -f $targetPath) -Category ObjectNotFound
                    return
                }

                $parent = Split-Path -Parent $targetPath
                if ($parent -and -not (Test-Path -LiteralPath $parent)) {
                    New-Item -Path $parent -ItemType Directory -Force | Out-Null
                }
            }

            $lines = @()
            if (Test-Path -LiteralPath $targetPath -PathType Leaf) {
                $lines = @(Get-Content -LiteralPath $targetPath -ErrorAction Stop)
            }

            $updated = $false
            $formatted = '{0}={1}' -f $Name, (Format-DotEnvValue -Value $Value)
            $newLines = foreach ($line in $lines) {
                if (-not $updated -and $line -match ('^\s*(?:export\s+)?{0}\s*=' -f [regex]::Escape($Name))) {
                    $updated = $true
                    $formatted
                }
                else {
                    $line
                }
            }

            if (-not $updated) {
                $newLines = @($newLines) + $formatted
            }

            if ($PSCmdlet.ShouldProcess($targetPath, ("Set dotenv value {0}" -f $Name))) {
                Set-Content -LiteralPath $targetPath -Value $newLines -Encoding UTF8
                Get-Item -LiteralPath $targetPath -Force
            }
        }
        catch {
            Write-Error -Message ("Failed to set dotenv value '{0}'. {1}" -f $Name, $_.Exception.Message) -Category WriteError
        }
    }
}

function Remove-DotEnvValue {
<#
.SYNOPSIS
Removes a key from a dotenv file.
.DESCRIPTION
Removes matching key assignments from a dotenv file. Other lines are preserved.
.PARAMETER Path
Path to the dotenv file.
.PARAMETER Name
Variable name to remove.
.EXAMPLE
Remove-DotEnvValue -Path .\.env -Name API_URL
.OUTPUTS
System.IO.FileInfo
.NOTES
Windows PowerShell 5.1 compatible.
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[A-Za-z_][A-Za-z0-9_]*$')]
        [string]$Name
    )

    process {
        try {
            $targetPath = Resolve-DotEnvTargetPath -Path $Path
            if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
                Write-Error -Message ("File not found: {0}" -f $targetPath) -Category ObjectNotFound
                return
            }

            $lines = @(Get-Content -LiteralPath $targetPath -ErrorAction Stop)
            $newLines = @($lines | Where-Object { $_ -notmatch ('^\s*(?:export\s+)?{0}\s*=' -f [regex]::Escape($Name)) })

            if ($PSCmdlet.ShouldProcess($targetPath, ("Remove dotenv value {0}" -f $Name))) {
                Set-Content -LiteralPath $targetPath -Value $newLines -Encoding UTF8
                Get-Item -LiteralPath $targetPath -Force
            }
        }
        catch {
            Write-Error -Message ("Failed to remove dotenv value '{0}'. {1}" -f $Name, $_.Exception.Message) -Category WriteError
        }
    }
}

function Initialize-DotEnvProject {
<#
.SYNOPSIS
Creates starter dotenv files for a project.
.DESCRIPTION
Creates `.env`, `.env.example`, and optionally layered dotenv files in a target
directory. Existing files are preserved unless -Force is used.
.PARAMETER Path
Target project directory.
.PARAMETER Name
Variable names to include in generated files.
.PARAMETER Template
Starter template to use. Basic uses -Name values. WebApp creates common web
application placeholders.
.PARAMETER EnvironmentName
Optional environment suffix used for generated layer names.
.PARAMETER IncludeVariants
Creates `.env.local`, `.env.<EnvironmentName>`, and `.env.<EnvironmentName>.local`.
.PARAMETER ExampleOnly
Creates only `.env.example`.
.PARAMETER Force
Overwrites existing target files.
.EXAMPLE
Initialize-DotEnvProject -Path . -Name API_URL,DB_NAME
.EXAMPLE
Initialize-DotEnvProject -Path . -Template WebApp -IncludeVariants
.EXAMPLE
Initialize-DotEnvProject -Path . -Name API_URL,DB_NAME -IncludeVariants -EnvironmentName development
.NOTES
Windows PowerShell 5.1 compatible.
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$Path = '.',

        [Parameter(Mandatory = $false)]
        [ValidatePattern('^[A-Za-z_][A-Za-z0-9_]*$')]
        [string[]]$Name = @('API_URL', 'DB_NAME'),

        [Parameter(Mandatory = $false)]
        [ValidateSet('Basic', 'WebApp')]
        [string]$Template = 'Basic',

        [Parameter(Mandatory = $false)]
        [string]$EnvironmentName = 'development',

        [Parameter(Mandatory = $false)]
        [switch]$IncludeVariants,

        [Parameter(Mandatory = $false)]
        [switch]$ExampleOnly,

        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    process {
        try {
            $targetRoot = Resolve-DotEnvTargetPath -Path $Path

            if (-not (Test-Path -LiteralPath $targetRoot -PathType Container)) {
                if ($PSCmdlet.ShouldProcess($targetRoot, 'Create project directory')) {
                    New-Item -Path $targetRoot -ItemType Directory -Force | Out-Null
                }
            }

            $uniqueNames = @($Name | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
            if (@($uniqueNames).Count -eq 0) {
                $uniqueNames = @('API_URL', 'DB_NAME')
            }

            $exampleLines = New-Object System.Collections.ArrayList
            $projectLines = New-Object System.Collections.ArrayList
            $localOverrideLines = New-Object System.Collections.ArrayList
            $environmentLines = New-Object System.Collections.ArrayList

            if ($Template -eq 'WebApp') {
                foreach ($line in @(
                    '# Commit this template with safe placeholder values.'
                    ''
                    '# --- APP CONFIGURATION ---'
                    'APP_NAME=MyApp'
                    'APP_ENV=development'
                    'NODE_ENV=development'
                    'PORT=3000'
                    'APP_URL=http://localhost:3000'
                    'CORS_ORIGIN=http://localhost:3000'
                    ''
                    '# --- DATABASE ---'
                    '# Choose DATABASE_URL or individual DB_* variables for your application.'
                    'DATABASE_URL=postgresql://app_user:change_me@localhost:5432/app_db'
                    'DB_HOST=localhost'
                    'DB_PORT=5432'
                    'DB_NAME=app_db'
                    'DB_USER=app_user'
                    'DB_PASS='
                    ''
                    '# --- AUTHENTICATION ---'
                    '# Generate secrets with a secure random generator before using outside local development.'
                    'JWT_SECRET=change_me'
                    'SESSION_SECRET=change_me'
                    ''
                    '# --- CACHE / QUEUE ---'
                    'REDIS_URL=redis://localhost:6379'
                    ''
                    '# --- THIRD-PARTY SERVICES ---'
                    'STRIPE_API_KEY='
                    'MAIL_HOST=smtp.example.test'
                    'MAIL_PORT=2525'
                    'MAIL_USER='
                    'MAIL_PASS='
                    'MAIL_FROM=no-reply@example.test'
                    'SENTRY_DSN='
                    ''
                    '# --- FEATURE FLAGS & LOGGING ---'
                    'ENABLE_NEW_DASHBOARD=false'
                    'RATE_LIMIT_ENABLED=true'
                    'LOG_LEVEL=debug'
                    'CACHE_TTL_SECONDS=300'
                )) {
                    [void]$exampleLines.Add($line)
                }

                foreach ($line in @(
                    '# Project defaults. Do not commit real secrets.'
                    'APP_NAME=MyApp'
                    'APP_ENV=development'
                    'NODE_ENV=development'
                    'PORT=3000'
                    'APP_URL=http://localhost:3000'
                    'LOG_LEVEL=debug'
                    'ENABLE_NEW_DASHBOARD=false'
                    'RATE_LIMIT_ENABLED=true'
                )) {
                    [void]$projectLines.Add($line)
                }

                foreach ($line in @(
                    '# Local machine overrides. Do not commit real secrets.'
                    '# DATABASE_URL=postgresql://app_user:change_me@localhost:5432/app_db'
                    '# JWT_SECRET=change_me'
                    '# SESSION_SECRET=change_me'
                    '# STRIPE_API_KEY='
                    '# SENTRY_DSN='
                )) {
                    [void]$localOverrideLines.Add($line)
                }

                foreach ($line in @(
                    ("# {0} environment values." -f $EnvironmentName)
                    'APP_ENV=development'
                    'NODE_ENV=development'
                    'LOG_LEVEL=debug'
                )) {
                    [void]$environmentLines.Add($line)
                }
            }
            else {
                [void]$exampleLines.Add('# Commit this template with safe placeholder values.')
                [void]$projectLines.Add('# Project defaults. Do not commit real secrets.')
                [void]$localOverrideLines.Add('# Local machine overrides. Do not commit real secrets.')
                [void]$environmentLines.Add(("# {0} environment values." -f $EnvironmentName))

                foreach ($variableName in $uniqueNames) {
                    [void]$exampleLines.Add(('{0}=' -f $variableName))
                    [void]$projectLines.Add(('{0}=' -f $variableName))
                    [void]$localOverrideLines.Add(('# {0}=' -f $variableName))
                    [void]$environmentLines.Add(('{0}=' -f $variableName))
                }
            }

            $files = New-Object System.Collections.ArrayList
            [void]$files.Add('.env.example')

            if (-not $ExampleOnly) {
                [void]$files.Add('.env')

                if ($IncludeVariants) {
                    [void]$files.Add('.env.local')

                    if (-not [string]::IsNullOrWhiteSpace($EnvironmentName)) {
                        [void]$files.Add(('.env.{0}' -f $EnvironmentName))
                        [void]$files.Add(('.env.{0}.local' -f $EnvironmentName))
                    }
                }
            }

            foreach ($fileName in $files) {
                $targetPath = Join-Path $targetRoot $fileName

                if ((Test-Path -LiteralPath $targetPath -PathType Leaf) -and -not $Force) {
                    Write-Error -Message ("File already exists: {0}. Use -Force to overwrite." -f $targetPath) -Category ResourceExists
                    continue
                }

                $lines = New-Object System.Collections.ArrayList
                [void]$lines.Add(("# {0}" -f $fileName))

                if ($fileName -eq '.env.example') {
                    [void]$lines.AddRange($exampleLines)
                }
                elseif ($fileName -like '*.local') {
                    [void]$lines.AddRange($localOverrideLines)
                }
                elseif ($fileName -ne '.env') {
                    [void]$lines.AddRange($environmentLines)
                }
                else {
                    [void]$lines.AddRange($projectLines)
                }

                if ($PSCmdlet.ShouldProcess($targetPath, 'Create dotenv file')) {
                    Set-Content -LiteralPath $targetPath -Value $lines -Encoding UTF8
                    Get-Item -LiteralPath $targetPath -Force
                }
            }
        }
        catch {
            Write-Error -Message ("Failed to initialize dotenv project. {0}" -f $_.Exception.Message) -Category WriteError
        }
    }
}

function Import-DotEnvFile {
<#
.SYNOPSIS
Imports variables from one or more .env files into the current PowerShell process.

.DESCRIPTION
Reads .env-formatted files and loads variables into the current process environment
through the PowerShell Env: provider.

The function resolves dotenv files using Get-DotEnvFilePath, then reads each file
with Read-DotEnvFile.

By default, values are imported exactly as written. When -ExpandVariables is used,
references in the form ${NAME} are expanded using previously loaded dotenv values
first, then current process environment variables. Missing references are preserved
unchanged.

.PARAMETER Path
Path to a .env file or directory containing .env files.

.PARAMETER Scope
Environment scope. Currently only Process is supported.

.PARAMETER Override
Overwrite existing environment variables.

.PARAMETER NoClobber
Do not overwrite existing environment variables. This is the default behavior.

.PARAMETER IncludeVariants
Includes supported variant files such as .env.local and .env.<EnvironmentName>
when resolving files.

.PARAMETER EnvironmentName
Optional environment suffix used with variant files, such as development, test,
staging, production, or prod.

.PARAMETER Strict
Enables strict parsing behavior in the reader/parser.

.PARAMETER ExpandVariables
Expands ${NAME} references in values using already-loaded dotenv values first,
then current process environment variables. Missing references are preserved.

.PARAMETER PassThru
Returns import result records.

.PARAMETER RevealValues
Shows actual values in PassThru output. By default, non-empty values are masked.

.EXAMPLE
Import-DotEnvFile -Path .\.env -WhatIf

.EXAMPLE
Import-DotEnvFile -Path .\.env -Verbose -PassThru

.EXAMPLE
Import-DotEnvFile -Path . -IncludeVariants -EnvironmentName development -Override -Verbose

.EXAMPLE
Import-DotEnvFile -Path .\.env -ExpandVariables -Override -Verbose

.INPUTS
System.String

.OUTPUTS
System.Management.Automation.PSCustomObject

.NOTES
Windows PowerShell 5.1 compatible.
This command only writes to the current process environment.
Variable expansion is text-only and does not execute commands.
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Process')]
        [string]$Scope = 'Process',

        [Parameter(Mandatory = $false)]
        [switch]$Override,

        [Parameter(Mandatory = $false)]
        [switch]$NoClobber,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeVariants,

        [Parameter(Mandatory = $false)]
        [string]$EnvironmentName,

        [Parameter(Mandatory = $false)]
        [switch]$SearchUp,

        [Parameter(Mandatory = $false)]
        [switch]$Strict,

        [Parameter(Mandatory = $false)]
        [switch]$ExpandVariables,

        [Parameter(Mandatory = $false)]
        [switch]$PassThru,

        [Parameter(Mandatory = $false)]
        [switch]$RevealValues
    )

    begin {
        $valueMap = @{}
    }

    process {
        try {
            if ($Override -and $NoClobber) {
                Write-Error -Message 'Specify either -Override or -NoClobber, not both.' -Category InvalidArgument
                return
            }

            if (-not $Override -and -not $NoClobber) {
                $NoClobber = $true
            }

            $files = @(
                Get-DotEnvFilePath `
                    -Path $Path `
                    -IncludeVariants:$IncludeVariants `
                    -EnvironmentName $EnvironmentName `
                    -SearchUp:$SearchUp
            )

            foreach ($file in $files) {
                foreach ($entry in Read-DotEnvFile -Path $file -Strict:$Strict) {
                    if ($null -eq $entry) {
                        continue
                    }

                    $name = $entry.Name
                    $value = $entry.Value

                    if ([string]::IsNullOrWhiteSpace($name)) {
                        Write-Error -Message ("Skipping .env entry with empty variable name from file: {0}" -f $file) -Category InvalidData
                        continue
                    }

                    if ($null -eq $value) {
                        $value = ''
                    }
                    else {
                        $value = [string]$value
                    }

                    if ($ExpandVariables) {
                        $value = Resolve-DotEnvValue -Value $value -ValueMap $valueMap
                    }

                    $envPath = "Env:\{0}" -f $name
                    $hadPreviousValue = Test-Path -Path $envPath
                    $previousValue = $null

                    if ($hadPreviousValue) {
                        $previousItem = Get-Item -Path $envPath -ErrorAction SilentlyContinue

                        if ($null -ne $previousItem) {
                            $previousValue = $previousItem.Value
                        }
                    }

                    $action = 'Set'
                    $changed = $false

                    if ($hadPreviousValue -and $NoClobber -and -not $Override) {
                        $action = 'SkippedExisting'
                    }
                    else {
                        if ($hadPreviousValue) {
                            $action = 'Updated'
                        }

                        if ($PSCmdlet.ShouldProcess(
                                ("{0}:{1}" -f $Scope, $name),
                                ("Set from {0}" -f (Split-Path -Path $file -Leaf))
                            )) {
                            Set-Item -Path $envPath -Value $value -ErrorAction Stop
                            $changed = $true

                            if (-not $script:DotEnvState.OriginalValues.ContainsKey($name)) {
                                $script:DotEnvState.OriginalValues[$name] = if ($hadPreviousValue) { $previousValue } else { $null }
                            }

                            $script:DotEnvState.LoadedVariables[$name] = @{
                                SourcePath       = $file
                                Scope            = $Scope
                                HadPreviousValue = $hadPreviousValue
                            }
                        }
                    }

                    # Keep the current resolved value available for later variables and later layers.
                    # This is intentional even when NoClobber skips an existing environment variable:
                    # the dotenv file's own value remains available for expansion in subsequent keys.
                    $valueMap[$name] = $value

                    if ($PassThru) {
                        $displayValue = $value

                        if (-not $RevealValues -and -not [string]::IsNullOrEmpty($value)) {
                            $displayValue = '********'
                        }

                        [pscustomobject]@{
                            Name             = $name
                            Value            = $displayValue
                            Scope            = $Scope
                            SourcePath       = $file
                            Action           = $action
                            Changed          = $changed
                            HadPreviousValue = $hadPreviousValue
                        }
                    }
                }
            }
        }
        catch {
            Write-Error -Message ("Failed to import .env file from path '{0}'. {1}" -f $Path, $_.Exception.Message) -Category InvalidOperation
        }
    }

    end {}
}

function Invoke-DotEnvCommand {
<#
.SYNOPSIS
Runs a command with dotenv variables applied temporarily.
.DESCRIPTION
Loads dotenv values into the current process, invokes a command, then restores the
previous process environment values. This is intended for child process workflows
where dotenv values should not remain in the interactive session.
.PARAMETER Path
Path to a .env file or directory.
.PARAMETER Command
Command to invoke.
.PARAMETER ArgumentList
Arguments passed to the command.
.PARAMETER Override
Temporarily overwrites existing process variables while the command runs.
.PARAMETER NoClobber
Preserves existing process variables while the command runs. This is the default.
.PARAMETER IncludeVariants
Includes supported variant files.
.PARAMETER EnvironmentName
Optional environment suffix used with variant files.
.PARAMETER SearchUp
Searches parent directories for dotenv files.
.PARAMETER Strict
Enables strict parsing.
.PARAMETER ExpandVariables
Expands variable references before running the command.
.PARAMETER PassThru
Returns command metadata after invocation.
.EXAMPLE
Invoke-DotEnvCommand -Path .\.env -Command npm -ArgumentList @('test')
.EXAMPLE
Invoke-DotEnvCommand -Path . -Command npm -ArgumentList @('test') -IncludeVariants -EnvironmentName development -Override
.OUTPUTS
System.Management.Automation.PSCustomObject
.NOTES
Windows PowerShell 5.1 compatible.
#>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Command,

        [Parameter()]
        [string[]]$ArgumentList = @(),

        [Parameter()]
        [switch]$Override,

        [Parameter()]
        [switch]$NoClobber,

        [Parameter()]
        [switch]$IncludeVariants,

        [Parameter()]
        [string]$EnvironmentName,

        [Parameter()]
        [switch]$SearchUp,

        [Parameter()]
        [switch]$Strict,

        [Parameter()]
        [switch]$ExpandVariables,

        [Parameter()]
        [switch]$PassThru
    )

    process {
        if ($Override -and $NoClobber) {
            Write-Error -Message 'Specify either -Override or -NoClobber, not both.' -Category InvalidArgument
            return
        }

        if (-not $Override -and -not $NoClobber) {
            $NoClobber = $true
        }

        $previousValues = @{}
        $loadedNames = New-Object System.Collections.ArrayList

        try {
            $map = Get-DotEnvConfiguration `
                -Path $Path `
                -IncludeVariants:$IncludeVariants `
                -EnvironmentName $EnvironmentName `
                -SearchUp:$SearchUp `
                -Strict:$Strict `
                -ExpandVariables:$ExpandVariables `
                -AsHashtable

            foreach ($name in $map.Keys) {
                $envPath = "Env:\{0}" -f $name
                $hadPreviousValue = Test-Path -Path $envPath
                $previousValue = $null

                if ($hadPreviousValue) {
                    $previousItem = Get-Item -Path $envPath -ErrorAction SilentlyContinue
                    if ($null -ne $previousItem) {
                        $previousValue = $previousItem.Value
                    }
                }

                $previousValues[$name] = @{
                    HadPreviousValue = $hadPreviousValue
                    Value = $previousValue
                }

                if ($hadPreviousValue -and $NoClobber -and -not $Override) {
                    continue
                }

                Set-Item -Path $envPath -Value ([string]$map[$name]) -ErrorAction Stop
                [void]$loadedNames.Add($name)
            }

            & $Command @ArgumentList
            $exitCode = if ($null -ne $global:LASTEXITCODE) { [int]$global:LASTEXITCODE } else { 0 }

            if ($PassThru) {
                [pscustomobject]@{
                    Command = $Command
                    ArgumentList = @($ArgumentList)
                    ExitCode = $exitCode
                    LoadedVariables = @($loadedNames)
                }
            }
        }
        catch {
            Write-Error -Message ("Failed to invoke command with dotenv values. {0}" -f $_.Exception.Message) -Category InvalidOperation
        }
        finally {
            foreach ($name in $previousValues.Keys) {
                $envPath = "Env:\{0}" -f $name
                $state = $previousValues[$name]

                if ($state.HadPreviousValue) {
                    Set-Item -Path $envPath -Value ([string]$state.Value) -ErrorAction SilentlyContinue
                }
                else {
                    Remove-Item -Path $envPath -ErrorAction SilentlyContinue
                }
            }
        }
    }
}

function Remove-DotEnvVariable {
<#
.SYNOPSIS
Removes environment variables defined in a .env file.

.DESCRIPTION
Reads one or more .env files, determines the variable names, and removes those
variables from the current process environment.

If the module recorded an original value for a variable, the original value is
restored instead of removing the variable.

.PARAMETER Path
Path to a .env file or directory.

.PARAMETER IncludeVariants
Includes supported .env variants when resolving files.

.PARAMETER EnvironmentName
Optional environment name used when resolving variant files.

.PARAMETER Strict
Enables strict parsing.

.PARAMETER PassThru
Returns result records.

.EXAMPLE
Remove-DotEnvVariable -Path .\.env -WhatIf

.EXAMPLE
Remove-DotEnvVariable -Path .\.env -Verbose -PassThru

.INPUTS
System.String

.OUTPUTS
System.Management.Automation.PSCustomObject

.NOTES
Windows PowerShell 5.1 compatible.
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeVariants,

        [Parameter(Mandatory = $false)]
        [string]$EnvironmentName,

        [Parameter(Mandatory = $false)]
        [switch]$SearchUp,

        [Parameter(Mandatory = $false)]
        [switch]$Strict,

        [Parameter(Mandatory = $false)]
        [switch]$PassThru
    )

    begin {}

    process {
        try {
            $files = @(
                Get-DotEnvFilePath `
                    -Path $Path `
                    -IncludeVariants:$IncludeVariants `
                    -EnvironmentName $EnvironmentName `
                    -SearchUp:$SearchUp
            )

            foreach ($file in $files) {
                foreach ($entry in Read-DotEnvFile -Path $file -Strict:$Strict) {
                    if ($null -eq $entry) {
                        continue
                    }

                    $name = $entry.Name

                    if ([string]::IsNullOrWhiteSpace($name)) {
                        continue
                    }

                    $envPath = "Env:\{0}" -f $name
                    $existsBefore = Test-Path -Path $envPath
                    $action = 'Remove'
                    $changed = $false
                    $wasLoaded = $script:DotEnvState.LoadedVariables.ContainsKey($name)

                    $hasOriginalValue = $false
                    $originalValue = $null

                    if ($script:DotEnvState.OriginalValues.ContainsKey($name)) {
                        $hasOriginalValue = $true
                        $originalValue = $script:DotEnvState.OriginalValues[$name]
                    }

                    if (-not $wasLoaded) {
                        $action = 'SkippedUntracked'
                    }
                    elseif ($PSCmdlet.ShouldProcess(("Process:{0}" -f $name), $action)) {
                        if ($hasOriginalValue -and $null -ne $originalValue) {
                            Set-Item -Path $envPath -Value ([string]$originalValue) -ErrorAction Stop
                            $action = 'Restored'
                            $changed = $true
                        }
                        else {
                            if (Test-Path -Path $envPath) {
                                Remove-Item -Path $envPath -ErrorAction Stop
                                $changed = $true
                            }
                        }

                        if ($script:DotEnvState.LoadedVariables.ContainsKey($name)) {
                            $script:DotEnvState.LoadedVariables.Remove($name)
                        }

                        if ($script:DotEnvState.OriginalValues.ContainsKey($name)) {
                            $script:DotEnvState.OriginalValues.Remove($name)
                        }
                    }

                    if ($PassThru) {
                        [pscustomobject]@{
                            Name         = $name
                            Scope        = 'Process'
                            SourcePath   = $file
                            Action       = $action
                            Changed      = $changed
                            ExistedBefore = $existsBefore
                        }
                    }
                }
            }
        }
        catch {
            Write-Error -Message ("Failed to remove .env variables from path '{0}'. {1}" -f $Path, $_.Exception.Message) -Category InvalidOperation
        }
    }

    end {}
}

function Test-DotEnvFile {
<#
.SYNOPSIS
Validates .env file syntax and optional .env.example coverage.
.DESCRIPTION
Parses a .env file in strict mode and optionally verifies that keys from an example file exist.
.PARAMETER Path
Path to .env file.
.PARAMETER ExamplePath
Optional .env.example path.
.PARAMETER Required
Specific variable names expected in the dotenv file.
.PARAMETER RequireNoExtraKeys
Warns when the dotenv file contains keys that are not present in the example file.
.EXAMPLE
Test-DotEnvFile -Path .\.env -ExamplePath .\.env.example
.EXAMPLE
Test-DotEnvFile -Path .\.env -ExamplePath .\.env.example -Required API_URL,DB_NAME -RequireNoExtraKeys
.INPUTS
System.String
.OUTPUTS
System.Management.Automation.PSCustomObject
.NOTES
Windows PowerShell 5.1 compatible.
#>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter()]
        [string]$ExamplePath,

        [Parameter()]
        [string[]]$Required,

        [Parameter()]
        [switch]$RequireNoExtraKeys
    )

    process {
        $errors = New-Object System.Collections.ArrayList
        $warnings = New-Object System.Collections.ArrayList
        $keys = @()

        try {
            $strictErrors = $null
            $records = @(Read-DotEnvFile -Path $Path -Strict -ErrorVariable strictErrors -ErrorAction SilentlyContinue)
            foreach ($strictError in @($strictErrors)) {
                [void]$errors.Add($strictError.Exception.Message)
            }

            $keys = @($records | Select-Object -ExpandProperty Name -Unique)

            if ($ExamplePath) {
                $exampleStrictErrors = $null
                $exampleRecords = @(Read-DotEnvFile -Path $ExamplePath -Strict -ErrorVariable exampleStrictErrors -ErrorAction SilentlyContinue)
                foreach ($exampleStrictError in @($exampleStrictErrors)) {
                    [void]$errors.Add($exampleStrictError.Exception.Message)
                }

                $exampleKeys = @($exampleRecords | Select-Object -ExpandProperty Name -Unique)
                foreach ($exampleName in $exampleKeys) {
                    if ($keys -notcontains $exampleName) {
                        [void]$warnings.Add("Missing key from example: $exampleName")
                    }
                }

                if ($RequireNoExtraKeys) {
                    foreach ($key in $keys) {
                        if ($exampleKeys -notcontains $key) {
                            [void]$warnings.Add("Extra key not present in example: $key")
                        }
                    }
                }
            }

            if ($Required -and @($Required).Count -gt 0) {
                foreach ($requiredName in @($Required)) {
                    if ($requiredName -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
                        [void]$errors.Add("Invalid required key name: $requiredName")
                    }
                    elseif ($keys -notcontains $requiredName) {
                        [void]$warnings.Add("Missing required key: $requiredName")
                    }
                }
            }
        }
        catch {
            [void]$errors.Add($_.Exception.Message)
        }

        [pscustomobject]@{
            Path = $Path
            IsValid = (@($errors).Count -eq 0)
            KeyCount = @($keys).Count
            Keys = $keys
            ErrorCount = @($errors).Count
            WarningCount = @($warnings).Count
            Errors = @($errors)
            Warnings = @($warnings)
        }
    }
}

function Test-DotEnvGitIgnore {
<#
.SYNOPSIS
Checks whether common dotenv secret files are ignored by git.
.DESCRIPTION
Reads a repository .gitignore file and reports whether common dotenv patterns are present.
.PARAMETER Path
Repository path. Defaults to current directory.
.PARAMETER Patterns
Patterns to require. Defaults to .env, .env.*, and .env.keys.
.EXAMPLE
Test-DotEnvGitIgnore -Path .
.NOTES
Windows PowerShell 5.1 compatible.
#>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Path = '.',

        [Parameter()]
        [string[]]$Patterns = @('.env', '.env.*', '.env.keys')
    )

    process {
        try {
            $root = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
            $gitIgnorePath = Join-Path $root '.gitignore'
            $lines = @()

            if (Test-Path -LiteralPath $gitIgnorePath -PathType Leaf) {
                $lines = @(Get-Content -LiteralPath $gitIgnorePath -ErrorAction Stop | ForEach-Object { $_.Trim() })
            }

            $missing = @($Patterns | Where-Object { $lines -notcontains $_ })

            [pscustomobject]@{
                Path = $gitIgnorePath
                Exists = Test-Path -LiteralPath $gitIgnorePath -PathType Leaf
                IsProtected = (@($missing).Count -eq 0)
                RequiredPatterns = @($Patterns)
                MissingPatterns = @($missing)
            }
        }
        catch {
            Write-Error -Message ("Failed to test dotenv gitignore hygiene. {0}" -f $_.Exception.Message) -Category InvalidOperation
        }
    }
}

function Export-DotEnvFile {
<#
.SYNOPSIS
Exports selected process environment variables to a .env file.
.DESCRIPTION
Writes environment variables to .env format.
.PARAMETER Path
Destination .env path.
.PARAMETER Name
Optional variable names. If omitted, all process environment variables are exported.
.PARAMETER Force
Overwrite an existing file.
.EXAMPLE
Export-DotEnvFile -Path .\.env.export -Name API_URL,DB_NAME -WhatIf
.EXAMPLE
Export-DotEnvFile -Path .\.env.export -Force
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
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter()]
        [string[]]$Name,

        [Parameter()]
        [switch]$Force
    )

    process {
        try {
            $targetPath = Resolve-DotEnvTargetPath -Path $Path

            if ((Test-Path -LiteralPath $targetPath) -and -not $Force) {
                Write-Error -Message ("File already exists: {0}. Use -Force to overwrite." -f $targetPath) -Category ResourceExists
                return
            }

            $items = Get-ChildItem Env:
            if ($Name -and @($Name).Count -gt 0) {
                $items = foreach ($n in $Name) {
                    Get-Item -Path ('Env:\{0}' -f $n) -ErrorAction SilentlyContinue
                }
            }

            $lines = foreach ($item in $items) {
                if ($null -ne $item) {
                    '{0}={1}' -f $item.Name, (Format-DotEnvValue -Value ([string]$item.Value))
                }
            }

            if ($PSCmdlet.ShouldProcess($targetPath, 'Export .env file')) {
                $parent = Split-Path -Parent $targetPath
                if ($parent -and -not (Test-Path -LiteralPath $parent)) {
                    New-Item -Path $parent -ItemType Directory -Force | Out-Null
                }

                Set-Content -LiteralPath $targetPath -Value $lines -Encoding UTF8
                Get-Item -LiteralPath $targetPath -Force
            }
        }
        catch {
            Write-Error -Message ("Failed to export .env file. {0}" -f $_.Exception.Message) -Category WriteError
        }
    }
}

function Get-DotEnvAutoLoadState {
<#
.SYNOPSIS
Gets DotEnvTools auto-load state.
.DESCRIPTION
Returns current auto-load settings and tracked file information.
.EXAMPLE
Get-DotEnvAutoLoadState
.INPUTS
None
.OUTPUTS
System.Management.Automation.PSCustomObject
.NOTES
Windows PowerShell 5.1 compatible.
#>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    process {
        [pscustomobject]@{
            AutoLoadEnabled = [bool]$script:DotEnvState.AutoLoadEnabled
            LastPath = $script:DotEnvState.LastPath
            TrustedPath = @($script:DotEnvState.TrustedPaths)
            TrustAll = [bool]$script:DotEnvState.TrustAll
            RemoveOnExit = [bool]$script:DotEnvState.RemoveOnExit
            NoClobber = [bool]$script:DotEnvState.NoClobber
            IncludeVariants = [bool]$script:DotEnvState.IncludeVariants
            EnvironmentName = $script:DotEnvState.EnvironmentName
            LastLoadedFiles = @($script:DotEnvState.LastLoadedFiles)
            TrackedFileCount = @($script:DotEnvState.FileHashes.Keys).Count
        }
    }
}

function Invoke-DotEnvAutoLoadNow {
<#
.SYNOPSIS
Runs the DotEnvTools auto-load check for the current directory immediately.
.DESCRIPTION
Loads .env files for the current directory when auto-load is enabled and the directory is trusted.
.PARAMETER PassThru
Returns auto-load state after execution.
.EXAMPLE
Invoke-DotEnvAutoLoadNow -WhatIf
.EXAMPLE
Invoke-DotEnvAutoLoadNow -Verbose -PassThru
.INPUTS
None
.OUTPUTS
System.Management.Automation.PSCustomObject
.NOTES
Reloads unchanged files when tracked variables are missing.
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [switch]$PassThru
    )

    process {
        if (-not $script:DotEnvState.AutoLoadEnabled) {
            Write-Verbose 'DotEnvTools auto-load is not enabled.'
            if ($PassThru) { Get-DotEnvAutoLoadState }
            return
        }

        try {
            $currentPath = (Get-Location).Path

            $isTrusted = Test-DotEnvTrustedPath `
                -Path $currentPath `
                -TrustedPath $script:DotEnvState.TrustedPaths `
                -TrustAll:$script:DotEnvState.TrustAll

            if (-not $isTrusted) {
                Write-Verbose ("Current path is not trusted for .env auto-load: {0}" -f $currentPath)

                if ($script:DotEnvState.RemoveOnExit) {
                    $loadedFiles = @($script:DotEnvState.LastLoadedFiles)

                    foreach ($loadedFile in $loadedFiles) {
                        if (-not [string]::IsNullOrWhiteSpace($loadedFile)) {
                            if (Test-Path -LiteralPath $loadedFile -PathType Leaf) {
                                Write-Verbose ("Removing variables because current path is outside trusted path: {0}" -f $loadedFile)
                                Remove-DotEnvVariable -Path $loadedFile -ErrorAction SilentlyContinue | Out-Null
                            }
                        }
                    }

                    $script:DotEnvState.LastLoadedFiles = @()
                    $script:DotEnvState.FileHashes.Clear()
                }

                $script:DotEnvState.LastPath = $currentPath

                if ($PassThru) {
                    Get-DotEnvAutoLoadState
                }

                return
            }

            if ($script:DotEnvState.RemoveOnExit -and $script:DotEnvState.LastPath -and ($script:DotEnvState.LastPath -ne $currentPath)) {
                foreach ($oldFile in @($script:DotEnvState.LastLoadedFiles)) {
                    if (Test-Path -LiteralPath $oldFile) {
                        Remove-DotEnvVariable -Path $oldFile -ErrorAction SilentlyContinue | Out-Null
                    }
                }
            }

            $files = @(Get-DotEnvFilePath -Path $currentPath -IncludeVariants:$script:DotEnvState.IncludeVariants -EnvironmentName $script:DotEnvState.EnvironmentName)
            $script:DotEnvState.LastLoadedFiles = $files

            foreach ($file in $files) {
                $hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
                $oldHash = $null

                if ($script:DotEnvState.FileHashes.ContainsKey($file)) {
                    $oldHash = $script:DotEnvState.FileHashes[$file]
                }

                $shouldLoad = $true
                if ($oldHash -eq $hash) {
                    $trackedVariables = @()
                    if ($script:DotEnvState.LoadedFiles.ContainsKey($file)) {
                        $trackedVariables = @($script:DotEnvState.LoadedFiles[$file])
                    }

                    if (@($trackedVariables).Count -gt 0) {
                        $allStillPresent = $true
                        foreach ($name in $trackedVariables) {
                            if (-not (Test-Path -Path ('Env:\{0}' -f $name))) {
                                $allStillPresent = $false
                                break
                            }
                        }

                        if ($allStillPresent) {
                            $shouldLoad = $false
                            Write-Verbose ("Skipping unchanged .env file because tracked variables are still present: {0}" -f $file)
                        }
                        else {
                            Write-Verbose ("Reloading unchanged .env file because one or more tracked variables are missing: {0}" -f $file)
                        }
                    }
                    else {
                        Write-Verbose ("Reloading unchanged .env file because no tracked variable list exists: {0}" -f $file)
                    }
                }

                if (-not $shouldLoad) {
                    continue
                }

                if ($PSCmdlet.ShouldProcess($file, 'Auto-load .env file')) {
                    if ($script:DotEnvState.NoClobber) {
                        $records = @(Import-DotEnvFile -Path $file -NoClobber -PassThru -RevealValues -ErrorAction Stop)
                    }
                    else {
                        $records = @(Import-DotEnvFile -Path $file -Override -PassThru -RevealValues -ErrorAction Stop)
                    }

                    $loadedNames = @(
                        $records |
                            Where-Object { $_.Changed -eq $true -or $_.Action -eq 'Set' -or $_.Action -eq 'Updated' -or $_.Action -eq 'SkippedExisting' } |
                            Select-Object -ExpandProperty Name -Unique
                    )

                    $script:DotEnvState.FileHashes[$file] = $hash
                    $script:DotEnvState.LoadedFiles[$file] = $loadedNames
                }
            }

            $script:DotEnvState.LastPath = $currentPath
        }
        catch {
            Write-Error -Message ("DotEnvTools immediate auto-load failed. {0}" -f $_.Exception.Message) -Category InvalidOperation
        }

        if ($PassThru) { Get-DotEnvAutoLoadState }
    }
}

function Enable-DotEnvAutoLoad {
<#
.SYNOPSIS
Enables automatic .env loading for trusted directories.
.DESCRIPTION
Overrides the prompt function to check for .env files when the prompt renders.
.PARAMETER TrustedPath
Trusted paths allowed to auto-load .env files.
.PARAMETER TrustAll
Trust all paths.
.PARAMETER RemoveOnExit
Remove/restore variables when leaving a directory.
.PARAMETER IncludeVariants
Include .env variants.
.PARAMETER EnvironmentName
Optional environment name.
.PARAMETER Override
Overwrite existing variables.
.PARAMETER NoClobber
Do not overwrite existing variables.
.EXAMPLE
Enable-DotEnvAutoLoad -TrustedPath C:\Dev -WhatIf
.EXAMPLE
Enable-DotEnvAutoLoad -TrustedPath C:\Dev -RemoveOnExit -Verbose
.INPUTS
None
.OUTPUTS
System.Management.Automation.PSCustomObject
.NOTES
Auto-load is opt-in. Windows PowerShell 5.1 compatible.
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [string[]]$TrustedPath,

        [Parameter()]
        [switch]$TrustAll,

        [Parameter()]
        [switch]$RemoveOnExit,

        [Parameter()]
        [switch]$IncludeVariants,

        [Parameter()]
        [string]$EnvironmentName,

        [Parameter()]
        [switch]$Override,

        [Parameter()]
        [switch]$NoClobber
    )

    process {
        if ($PSCmdlet.ShouldProcess('PowerShell prompt', 'Enable .env auto-load')) {
            $originalPromptVariable = Get-Variable -Name OriginalPrompt -Scope Script -ErrorAction SilentlyContinue
            if ($null -eq $originalPromptVariable) {
                $promptCommand = Get-Command prompt -ErrorAction SilentlyContinue
                if ($promptCommand -and ($promptCommand.PSObject.Properties.Name -contains 'ScriptBlock') -and $promptCommand.ScriptBlock) {
                    $script:OriginalPrompt = $promptCommand.ScriptBlock
                }
                else {
                    $script:OriginalPrompt = { "PS $($executionContext.SessionState.Path.CurrentLocation)> " }
                }
            }

            if ($TrustedPath -and @($TrustedPath).Count -gt 0) {
                $script:DotEnvState.TrustedPaths = @($TrustedPath | ForEach-Object { [System.IO.Path]::GetFullPath($_).TrimEnd('\') })
            }
            elseif (-not $TrustAll -and @($script:DotEnvState.TrustedPaths).Count -eq 0) {
                $script:DotEnvState.TrustedPaths = @((Get-Location).Path)
            }

            $script:DotEnvState.AutoLoadEnabled = $true
            $script:DotEnvState.TrustAll = [bool]$TrustAll
            $script:DotEnvState.RemoveOnExit = [bool]$RemoveOnExit
            $script:DotEnvState.IncludeVariants = [bool]$IncludeVariants
            $script:DotEnvState.EnvironmentName = $EnvironmentName
            $script:DotEnvState.Override = [bool]$Override
            $script:DotEnvState.NoClobber = -not [bool]$Override
            if ($NoClobber) { $script:DotEnvState.NoClobber = $true }

            $dotEnvPromptScriptBlock = {
                try {
                    Invoke-DotEnvAutoLoadNow -ErrorAction SilentlyContinue | Out-Null
                }
                catch {
                    Write-Verbose ("DotEnvTools prompt auto-load failed. {0}" -f $_.Exception.Message)
                }

                if ($script:OriginalPrompt) {
                    & $script:OriginalPrompt
                }
                else {
                    "PS $($executionContext.SessionState.Path.CurrentLocation)> "
                }
            }

            Set-Item -Path Function:\global:prompt -Value $dotEnvPromptScriptBlock -Force

            [pscustomobject]@{
                Enabled = $true
                TrustedPath = @($script:DotEnvState.TrustedPaths)
                TrustAll = [bool]$script:DotEnvState.TrustAll
                RemoveOnExit = [bool]$script:DotEnvState.RemoveOnExit
                IncludeVariants = [bool]$script:DotEnvState.IncludeVariants
                EnvironmentName = $script:DotEnvState.EnvironmentName
            }
        }
    }
}

function Disable-DotEnvAutoLoad {
<#
.SYNOPSIS
Disables DotEnvTools automatic .env loading.
.DESCRIPTION
Restores the original prompt function when known and disables auto-load state.
.PARAMETER RemoveCurrent
Removes variables from the last loaded files.
.EXAMPLE
Disable-DotEnvAutoLoad -WhatIf
.EXAMPLE
Disable-DotEnvAutoLoad -RemoveCurrent -Verbose
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
        [Parameter()]
        [switch]$RemoveCurrent
    )

    process {
        if ($PSCmdlet.ShouldProcess('PowerShell prompt', 'Disable .env auto-load')) {
            $removedCurrent = $false

            if ($RemoveCurrent) {
                $loadedFiles = @($script:DotEnvState.LastLoadedFiles)

                foreach ($loadedFile in $loadedFiles) {
                    if (-not [string]::IsNullOrWhiteSpace($loadedFile)) {
                        if (Test-Path -LiteralPath $loadedFile -PathType Leaf) {
                            Write-Verbose ("Removing variables from loaded file: {0}" -f $loadedFile)
                            Remove-DotEnvVariable -Path $loadedFile -ErrorAction SilentlyContinue | Out-Null
                            $removedCurrent = $true
                        }
                    }
                }

                $script:DotEnvState.LastLoadedFiles = @()
                $script:DotEnvState.FileHashes.Clear()
            }

            $script:DotEnvState.AutoLoadEnabled = $false

            $originalPromptVariable = Get-Variable -Name OriginalPrompt -Scope Script -ErrorAction SilentlyContinue
            if ($null -ne $originalPromptVariable -and $script:OriginalPrompt) {
                Set-Item -Path Function:\global:prompt -Value $script:OriginalPrompt -ErrorAction SilentlyContinue
            }

            [pscustomobject]@{
                Enabled = $false
                RemovedCurrent = $removedCurrent
            }
        }
    }
}

function Add-DotEnvAutoLoadProfile {
<#
.SYNOPSIS
Adds DotEnvTools auto-load initialization to the current user's profile.
.DESCRIPTION
Appends import and Enable-DotEnvAutoLoad lines to the current user's PowerShell profile.
.PARAMETER TrustedPath
Trusted paths for auto-load.
.PARAMETER TrustAll
Trust all paths.
.EXAMPLE
Add-DotEnvAutoLoadProfile -TrustedPath C:\Dev -WhatIf
.EXAMPLE
Add-DotEnvAutoLoadProfile -TrustedPath C:\Dev -Verbose
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
        [Parameter()]
        [string[]]$TrustedPath,

        [Parameter()]
        [switch]$TrustAll
    )

    process {
        $profilePath = $PROFILE.CurrentUserCurrentHost
        $lines = New-Object System.Collections.ArrayList
        [void]$lines.Add('# DotEnvTools auto-load')
        [void]$lines.Add('Import-Module DotEnvTools -ErrorAction SilentlyContinue')

        if ($TrustAll) {
            [void]$lines.Add('Enable-DotEnvAutoLoad -TrustAll | Out-Null')
        }
        elseif ($TrustedPath -and @($TrustedPath).Count -gt 0) {
            $quoted = @($TrustedPath | ForEach-Object { "'{0}'" -f ($_ -replace "'", "''") }) -join ', '
            [void]$lines.Add(('Enable-DotEnvAutoLoad -TrustedPath @({0}) | Out-Null' -f $quoted))
        }
        else {
            [void]$lines.Add('Enable-DotEnvAutoLoad | Out-Null')
        }

        if ($PSCmdlet.ShouldProcess($profilePath, 'Add DotEnvTools auto-load profile block')) {
            $parent = Split-Path -Parent $profilePath
            if (-not (Test-Path -LiteralPath $parent)) {
                New-Item -Path $parent -ItemType Directory -Force | Out-Null
            }

            Add-Content -LiteralPath $profilePath -Value '' -Encoding UTF8
            Add-Content -LiteralPath $profilePath -Value $lines -Encoding UTF8
            Get-Item -LiteralPath $profilePath
        }
    }
}

function Remove-DotEnvAutoLoadProfile {
<#
.SYNOPSIS
Removes DotEnvTools auto-load lines from the current user's profile.
.DESCRIPTION
Removes lines containing DotEnvTools auto-load profile markers.
.EXAMPLE
Remove-DotEnvAutoLoadProfile -WhatIf
.EXAMPLE
Remove-DotEnvAutoLoadProfile -Verbose
.INPUTS
None
.OUTPUTS
System.IO.FileInfo
.NOTES
Windows PowerShell 5.1 compatible.
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([System.IO.FileInfo])]
    param()

    process {
        $profilePath = $PROFILE.CurrentUserCurrentHost
        if (-not (Test-Path -LiteralPath $profilePath)) {
            Write-Error -Message ("Profile not found: {0}" -f $profilePath) -Category ObjectNotFound
            return
        }

        if ($PSCmdlet.ShouldProcess($profilePath, 'Remove DotEnvTools auto-load profile lines')) {
            $content = Get-Content -LiteralPath $profilePath -ErrorAction Stop
            $filtered = $content | Where-Object {
                ($_ -notmatch 'DotEnvTools auto-load') -and
                ($_ -notmatch 'Import-Module DotEnvTools') -and
                ($_ -notmatch 'Enable-DotEnvAutoLoad')
            }
            Set-Content -LiteralPath $profilePath -Value $filtered -Encoding UTF8
            Get-Item -LiteralPath $profilePath
        }
    }
}

# SIG # Begin signature block
# MIIHXQYJKoZIhvcNAQcCoIIHTjCCB0oCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCRTVMcJqwwICc9
# Le/ym3oTC8zCnnYgx9+/YNdKslqvp6CCBDowggQ2MIICnqADAgECAhBDcn1KArYx
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
# CSqGSIb3DQEJBDEiBCAqjsaEYXqTXwV324ouctfPPmL4xkog7xRA8InNf5GfdzAN
# BgkqhkiG9w0BAQEFAASCAYAjsWUXbxnqcVYs2XXHDbbwyiWZ5IlKzpY+/RY4FW2d
# T0Ca+J/cE+CsfZvJhz+a+eONONOcgP+JD7rLxYhIuKg+OXtLKjZYWDfThLxaERu+
# etD29j/llCj85y597U9/QQPFDykrxTZ+fT8ZxivhnCtPM9pxE2VnrEN8GK+QVG2K
# jxR6RHO5tpiqK+g52UdTpycXB4UeRldmcvwMj+lAmm/Lvi4vD/uIZ5XPJ34YZNYx
# S+w25SgF/QfKYe+3oWRIJ9aEg0oVBg65r83SkiF6E8IrXpMlRMatme2Jc74qh10d
# TVh4rDz0A+UmCX2bYrrHu0PW37dCcLrD8vBJSiC4lcK7OBjtw1zNCzKEV+MjDphD
# +w7XRhaX6LUhF1jEJL2FoF5ELTEaRkJwxzl81Wxp7n/G89p+4TxTOsw0z/WeYUDy
# XaBvskXGwSw22hH1jpjZIFxU9o1hgtWeg37/b0MLRaQYjo0ZmGIzTUPN5Z4ZRNIc
# +RLt/HF56ADp1YqG7rg+5b8=
# SIG # End signature block

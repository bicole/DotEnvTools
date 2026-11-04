#!/usr/bin/env bash
set -euo pipefail

DOTENVTOOLS_VERSION="${VERSION:-0.8.18}"
ARCHIVE_PATH_OPTION="${ARCHIVEPATH:-}"
INITIALIZE_PROJECT="${INITIALIZEPROJECT:-false}"
TEMPLATE="${TEMPLATE:-Basic}"
INCLUDE_VARIANTS="${INCLUDEVARIANTS:-false}"
ENVIRONMENT_NAME="${ENVIRONMENTNAME:-development}"

INSTALL_ROOT="/usr/local/share/powershell/Modules/DotEnvTools"
FEATURE_ROOT="/usr/local/share/dotenvtools"
ARCHIVE_URL="https://github.com/nandub/DotEnvTools/releases/download/v${DOTENVTOOLS_VERSION}/DotEnvTools-${DOTENVTOOLS_VERSION}.zip"
ARCHIVE_PATH="/tmp/dotenvtools-${DOTENVTOOLS_VERSION}.zip"
EXTRACT_ROOT="/tmp/dotenvtools-${DOTENVTOOLS_VERSION}"
FEATURE_SOURCE_ROOT="$(pwd)"

echo "Installing DotEnvTools ${DOTENVTOOLS_VERSION}..."

if ! command -v pwsh >/dev/null 2>&1; then
    echo "DotEnvTools requires PowerShell. Add ghcr.io/devcontainers/features/powershell:2 before this Feature." >&2
    exit 1
fi

if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-install-recommends ca-certificates curl unzip
    rm -rf /var/lib/apt/lists/*
elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache ca-certificates curl unzip
elif command -v dnf >/dev/null 2>&1; then
    dnf install -y ca-certificates curl unzip
    dnf clean all
else
    echo "No supported package manager found. Install ca-certificates, curl, and unzip in the base image." >&2
    exit 1
fi

rm -rf "${EXTRACT_ROOT}" "${ARCHIVE_PATH}"
mkdir -p "${EXTRACT_ROOT}" "${INSTALL_ROOT}" "${FEATURE_ROOT}"

if [ -n "${ARCHIVE_PATH_OPTION}" ]; then
    if [[ "${ARCHIVE_PATH_OPTION}" = /* ]]; then
        LOCAL_ARCHIVE_PATH="${ARCHIVE_PATH_OPTION}"
    else
        LOCAL_ARCHIVE_PATH="${FEATURE_SOURCE_ROOT}/${ARCHIVE_PATH_OPTION}"
    fi

    if [ ! -f "${LOCAL_ARCHIVE_PATH}" ]; then
        echo "Local DotEnvTools archive not found: ${LOCAL_ARCHIVE_PATH}" >&2
        exit 1
    fi

    cp "${LOCAL_ARCHIVE_PATH}" "${ARCHIVE_PATH}"
else
    curl -fsSL "${ARCHIVE_URL}" -o "${ARCHIVE_PATH}"
fi

unzip -q "${ARCHIVE_PATH}" -d "${EXTRACT_ROOT}"

MODULE_SOURCE="$(find "${EXTRACT_ROOT}" -type f -name 'DotEnvTools.psd1' -print -quit)"
if [ -z "${MODULE_SOURCE}" ]; then
    echo "Downloaded archive did not contain DotEnvTools.psd1." >&2
    exit 1
fi

MODULE_SOURCE_DIR="$(dirname "${MODULE_SOURCE}")"
rm -rf "${INSTALL_ROOT:?}/${DOTENVTOOLS_VERSION}"
mkdir -p "${INSTALL_ROOT}/${DOTENVTOOLS_VERSION}"
cp -R "${MODULE_SOURCE_DIR}/." "${INSTALL_ROOT}/${DOTENVTOOLS_VERSION}/"

cat > "${FEATURE_ROOT}/initialize-project.ps1" << 'POWERSHELL'
$ErrorActionPreference = 'Stop'

Import-Module $env:module_path -Force

if (-not (Test-Path -LiteralPath $env:workspace -PathType Container)) {
    New-Item -Path $env:workspace -ItemType Directory -Force | Out-Null
}

$params = @{
    Path = $env:workspace
    Template = $env:template
    EnvironmentName = $env:environment_name
}
if ($env:include_variants -eq 'true') {
    $params.IncludeVariants = $true
}

$files = @(Initialize-DotEnvProject @params)
$expectedFiles = @('.env.example', '.env')
if ($env:include_variants -eq 'true') {
    $expectedFiles += '.env.local'

    if (-not [string]::IsNullOrWhiteSpace($env:environment_name)) {
        $expectedFiles += ".env.$($env:environment_name)"
        $expectedFiles += ".env.$($env:environment_name).local"
    }
}

foreach ($fileName in $expectedFiles) {
    $filePath = Join-Path -Path $env:workspace -ChildPath $fileName
    if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
        $createdFiles = @($files | ForEach-Object { $_.FullName }) -join ', '
        throw "DotEnvTools did not create expected file '$filePath'. Returned files: $createdFiles"
    }
}

Write-Host ("DotEnvTools initialized files: {0}" -f ($expectedFiles -join ', '))
POWERSHELL

cat > "${FEATURE_ROOT}/devcontainer-post-create.sh" << EOF
#!/usr/bin/env bash
set -euo pipefail

if [ "${INITIALIZE_PROJECT}" != "true" ]; then
    echo "DotEnvTools project initialization skipped because initializeProject is false."
    exit 0
fi

export workspace="\${1:-\${DOTENVTOOLS_WORKSPACE:-\${containerWorkspaceFolder:-\${PWD}}}}"
if [ -z "\${workspace}" ] || [ "\${workspace}" = '\${containerWorkspaceFolder}' ]; then
    export workspace="\${PWD}"
fi
export module_path="${INSTALL_ROOT}/${DOTENVTOOLS_VERSION}/DotEnvTools.psd1"
export template="${TEMPLATE}"
export environment_name="${ENVIRONMENT_NAME}"
export include_variants="${INCLUDE_VARIANTS}"

if [ -f "\${workspace}/.env.example" ]; then
    echo "DotEnvTools project initialization skipped because \${workspace}/.env.example already exists."
    exit 0
fi

echo "Initializing DotEnvTools project in \${workspace}..."
pwsh -NoLogo -NoProfile -NonInteractive -File "${FEATURE_ROOT}/initialize-project.ps1"
EOF

chmod +x "${FEATURE_ROOT}/devcontainer-post-create.sh"

pwsh -NoLogo -NoProfile -Command "Import-Module '${INSTALL_ROOT}/${DOTENVTOOLS_VERSION}/DotEnvTools.psd1' -Force; (Get-Module DotEnvTools).Version.ToString()"

rm -rf "${EXTRACT_ROOT}" "${ARCHIVE_PATH}"

echo "DotEnvTools ${DOTENVTOOLS_VERSION} installed."

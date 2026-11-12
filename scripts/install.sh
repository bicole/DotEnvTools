#!/usr/bin/env bash
set -euo pipefail

CHECK=0
DIFF=0
BACKUP=1
YES=0

for arg in "$@"; do
    case "$arg" in
        -ha|--help-agent)
            echo "install.sh [--check] [--diff] [--backup|--no-backup] [--yes] [-ha] -- Installs DotEnvTools into ~/.local/share/powershell/Modules"
            exit 0
            ;;
        --check) CHECK=1 ;;
        --diff) DIFF=1 ;;
        --backup) BACKUP=1 ;;
        --no-backup) BACKUP=0 ;;
        --yes|-y) YES=1 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if command -v pwsh >/dev/null 2>&1; then
    PWSH_ARGS=("-NoProfile" "-File" "$SCRIPT_DIR/install.ps1")
    [ "$CHECK" -eq 1 ] && PWSH_ARGS+=("-Check")
    [ "$DIFF" -eq 1 ] && PWSH_ARGS+=("-Diff")
    [ "$BACKUP" -eq 0 ] && PWSH_ARGS+=("-Backup:\$false")
    [ "$YES" -eq 1 ] && PWSH_ARGS+=("-Yes")
    pwsh "${PWSH_ARGS[@]}"
else
    VERSION="$(grep -E "ModuleVersion[[:space:]]*=" "$REPO_ROOT/Source/DotEnvTools.psd1" | sed -E "s/.*=[[:space:]]*['\"]([^'\"]+)['\"].*/\1/")"
    [ -z "$VERSION" ] && VERSION="0.1.0"
    DEST="$HOME/.local/share/powershell/Modules/DotEnvTools/$VERSION"
    if [ "$DIFF" -eq 1 ] && [ -d "$DEST" ]; then
        diff -u -r "$REPO_ROOT/Source" "$DEST" || true
    fi
    if [ "$CHECK" -eq 1 ]; then
        echo "[CHECK] DotEnvTools target: $DEST"
        exit 0
    fi
    mkdir -p "$DEST"
    cp -R "$REPO_ROOT/Source/"* "$DEST/"
    echo "[OK] Installed DotEnvTools -> $DEST"
fi

# Agent Instructions (`DotEnvTools`)

## Overview
Cross-platform PowerShell 7+ module and Dev Container Feature for parsing, validating, layering, and expanding `.env` files.

## Installation & Verification
- **Windows / PowerShell (`pwsh`)**: `pwsh -NoProfile -File scripts/install.ps1 [-Check] [-Diff] [-Backup] [-Yes] [-ha]`
- **POSIX (`bash`)**: `./scripts/install.sh [--check] [--diff] [--backup] [--yes] [-ha]`
- **Tests**: `pwsh -NoProfile -File scripts/Test-DotEnvToolsQuality.ps1`

## OSS Prior Art & Community Standards
Before authoring a plan or designing a new subsystem/service/CLI, survey existing OSS standards, RFCs, and reference implementations (e.g. Nomad/Kubelet/runners, OpenMetrics/OTLP, rustup/K3s installers). Plans MUST include an `## OSS Prior Art & Community Standards` section covering: what OSS can be adopted or wrapped, which community patterns a custom design inherits, and why re-invention was avoided. Security-sensitive designs (installers, token exchange, supervisors) must follow OWASP/NIST guidance (checksums, least privilege, no plaintext tokens). Full rule: `~/.gemini/config/rules/oss-prior-art.md`; enforced by `scripts/audit_standards.py` (WARN by default, FAIL in agent-infrastructure; configurable via `.agents/standards.json`).
# Skill: New Machine Build

## Purpose

This repository automates the setup of a new development machine on macOS, Linux, and Windows. It installs common development tools using platform-native package managers (Homebrew on macOS/Linux, Chocolatey on Windows) and follows a regulated-friendly IQ/OQ/PQ qualification lifecycle.

## Repository Structure

| File / Directory | Description |
|---|---|
| `NewMachineSetup.sh` | Bash setup script for macOS and Linux |
| `NewMachineSetup.ps1` | PowerShell setup script for Windows |
| `Brewfile` | Homebrew package list |
| `chocolatey.config` | Chocolatey package list |
| `requirements.txt` | Python package list |
| `Gemfile` | Ruby gem list |
| `unbrew.sh` | Homebrew teardown / uninstall helper |
| `Dockerfile` | Container image for isolated testing |
| `.github/workflows/cicd.yml` | CI/CD pipeline (lint → qualification → full install) |
| `.github/actions/setup-homebrew-linux/` | Composite action to install Homebrew on Linux runners |

## Lifecycle Architecture

Both setup scripts follow the same qualification lifecycle:

```
preflight-validation → IQ → bootstrap → package-installation → OQ → language-dependencies → PQ → post-checks
```

- **IQ** – Validates prerequisites, package manager presence, PATH visibility, and checksum accessibility.
- **OQ** – Validates operational behaviour: dependency-manager health, conflict detection, rollback safety.
- **PQ** – Validates performance: response time, disk I/O, network responsiveness, resource thresholds.

Qualification stages are non-mutating when run with `--validate-only` (or any single `--iq-only` / `--oq-only` / `--pq-only` flag).

## CI/CD Pipeline

The pipeline runs on `push` and `pull_request` to `master`, on a daily schedule, and on `workflow_dispatch`. It skips runs for Markdown and config-only changes.

### Jobs (in dependency order)

1. **shell-lint** – `shellcheck` on `NewMachineSetup.sh` and `unbrew.sh`.
2. **powershell-static** – PowerShell AST parse check on `NewMachineSetup.ps1`.
3. **bash-qualification** – Runs `--iq-only`, `--oq-only`, and `--pq-only` on `macos-latest` and `ubuntu-latest`. Needs `shell-lint`.
4. **powershell-qualification** – Runs `--iq-only`, `--oq-only`, and `--pq-only` on `windows-latest`. Needs `powershell-static`.
5. **bash-validate-only** – Full `--validate-only` benchmark on `macos-latest` and `ubuntu-latest`. Gates on `bash-qualification`. Runs on schedule, manual dispatch, and pull_request.
6. **powershell-validate-only** – Full `--validate-only` benchmark on `windows-latest`. Gates on `powershell-qualification`. Runs on schedule, manual dispatch, and pull_request.
7. **tag** – Bumps and pushes a version tag. Gates on `shell-lint`, `powershell-static`, `bash-qualification`, and `powershell-qualification`.

### CI-specific Behaviour

- Cask and MAS lines are filtered from the Brewfile before `brew bundle` on Linux CI.
- Chocolatey bulk installs and edition packages are skipped when `CI=true` or `GITHUB_ACTIONS=true`.
- `brew doctor` warnings and PQ load spikes are non-fatal when `CI=true` or `GITHUB_ACTIONS=true`.
- `pip install` conditionally adds `--break-system-packages` when pip detects an externally managed environment.
- `--ignore-installed` is added on macOS CI to avoid conflicts with Homebrew-managed Python packages.
- `typing-extensions` is excluded from `requirements.txt` to avoid macOS CI pip conflicts.

## Coding Conventions

- **Bash**: POSIX-compatible where possible; uses `set -euo pipefail`. CI-only guards use `is_ci_environment()` which checks `CI=true` OR `GITHUB_ACTIONS=true`.
- **PowerShell**: Uses `$ErrorActionPreference = 'Stop'`. `Clear-Host` is wrapped as best-effort for non-interactive CI hosts. `Test-IsCIEnvironment` checks `$env:CI -eq "true"` OR `$env:GITHUB_ACTIONS -eq "true"`.
- **Commits**: Pin action references to a commit SHA where feasible; do not introduce new unpinned action references.
- **Dependencies**: Managed via Renovate (`renovate.json`). Do not manually bump versions.

## Agent Guidance

When working in this repository:

1. **Run existing checks** – Use `shellcheck NewMachineSetup.sh unbrew.sh` for Bash changes and PowerShell AST parsing for `.ps1` changes. Do not add new linting tools.
2. **Qualification flags** – Use `--validate-only` to smoke-test script changes without making system changes.
3. **Brewfile changes** – Avoid adding taps or casks that break Linux CI; ensure `brew bundle` works without `--no-cask`.
4. **requirements.txt** – Do not add `typing-extensions`; it conflicts with Homebrew-managed Python on macOS CI.
5. **Workflow changes** – Pin new action references to a commit SHA, not a tag.
6. **CI guards** – Wrap any step that is unsafe in a non-interactive or read-only environment behind `is_ci_environment()` / `Test-IsCIEnvironment` checks (both `CI` and `GITHUB_ACTIONS` are checked).
7. **Full install jobs** – Only the `bash-qualification` and `powershell-qualification` jobs perform real installs; `validate-only` jobs and lint jobs must remain non-mutating.

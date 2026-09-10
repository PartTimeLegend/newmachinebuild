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
3. **bash-qualification** – Runs `--iq-only`, `--oq-only`, `--pq-only`, then a full install verification on `macos-latest` and `ubuntu-latest`. Needs `shell-lint`.
4. **powershell-qualification** – Runs `-IQOnly`, `-OQOnly`, `-PQOnly`, then a full install verification on `windows-latest`. Needs `powershell-static`.
5. **bash-validate-only** / **powershell-validate-only** – Combined `--validate-only` / `-ValidateOnly` benchmarks (workflow_dispatch/schedule/pull_request). Need their respective qualification job.
6. **tag** – Tags a release on `push` to `master` after qualification jobs.
### CI-specific Behaviour

- Cask and MAS lines are filtered from the Brewfile before `brew bundle` on Linux CI.
- Chocolatey bulk installs and edition packages are skipped when `GITHUB_ACTIONS=true`.
- `brew doctor` warnings and PQ load spikes are non-fatal when `CI=true`.
- `pip install` conditionally adds `--break-system-packages` when pip detects an externally managed environment.
- `--ignore-installed` is added on macOS CI to avoid conflicts with Homebrew-managed Python packages.
- `typing-extensions` is excluded from `requirements.txt` to avoid macOS CI pip conflicts.

## Coding Conventions

- **Bash**: POSIX-compatible where possible; uses `set -euo pipefail`. CI-only guards use `[[ -n "${CI:-}" ]]` or `[[ -n "${GITHUB_ACTIONS:-}" ]]`.
- **PowerShell**: Uses `$ErrorActionPreference = 'Stop'`. `Clear-Host` is wrapped as best-effort for non-interactive CI hosts.
- **Commits**: Prefer pinned action SHAs (e.g. `actions/checkout@<sha>`) in workflow files; avoid introducing new tag/branch-based action references.
- **Dependencies**: Managed via Renovate (`renovate.json`). Do not manually bump versions.

## Agent Guidance

When working in this repository:

1. **Run existing checks** – Use `shellcheck NewMachineSetup.sh unbrew.sh` for Bash changes and PowerShell AST parsing for `.ps1` changes. Do not add new linting tools.
2. **Qualification flags** – Use `--validate-only` to smoke-test script changes without making system changes.
3. **Brewfile changes** – Avoid adding taps or casks that break Linux CI; ensure `brew bundle` works without `--no-cask`.
4. **requirements.txt** – Do not add `typing-extensions`; it conflicts with Homebrew-managed Python on macOS CI.
5. **Workflow changes** – Pin all action references to a commit SHA, not a tag.
6. **CI guards** – Wrap any step that is unsafe in a non-interactive or read-only environment behind `CI`/`GITHUB_ACTIONS` checks.
7. **Full install jobs** – Only the `bash-cicd` and `powershell-cicd` jobs perform real installs; all other jobs must remain non-mutating.

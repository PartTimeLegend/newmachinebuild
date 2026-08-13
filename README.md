# New Machine Build

[![CICD](https://github.com/PartTimeLegend/newmachinebuild/actions/workflows/cicd.yml/badge.svg)](https://github.com/PartTimeLegend/newmachinebuild/actions/workflows/cicd.yml)

A new machine is a PITA. This makes it less, at least for me it does.

## Overview

This repository contains scripts to automate the setup of a new development machine. It handles the installation of common development tools and applications using package managers:

- For macOS: [Homebrew](https://brew.sh/)
- For Windows: [Chocolatey](https://chocolatey.org)

## Lifecycle architecture

Both setup scripts now follow the same regulated-friendly lifecycle:

```mermaid
flowchart LR
  A[preflight-validation] --> B[IQ]
  B --> C[bootstrap]
  C --> D[package-installation]
  D --> E[OQ]
  E --> F[language-dependencies]
  F --> G[PQ]
  G --> H[post-checks]
```

The qualification stages are intended to be non-mutating when run through validation flags:

- **IQ** validates prerequisites, package manager presence, PATH visibility, and checksum accessibility.
- **OQ** validates operational behavior, dependency-manager health, conflict detection, and rollback safety checks.
- **PQ** validates response-time, disk I/O, network responsiveness, and baseline resource thresholds.

## Usage

### macOS

```bash
./NewMachineSetup.sh
```

Qualification-only troubleshooting flags:

```bash
./NewMachineSetup.sh --iq-only
./NewMachineSetup.sh --oq-only
./NewMachineSetup.sh --pq-only
./NewMachineSetup.sh --validate-only
```

### Windows

```powershell
.\NewMachineSetup.ps1
```

Qualification-only troubleshooting flags:

```powershell
.\NewMachineSetup.ps1 -IQOnly -SkipElevation
.\NewMachineSetup.ps1 -OQOnly -SkipElevation
.\NewMachineSetup.ps1 -PQOnly -SkipElevation
.\NewMachineSetup.ps1 -ValidateOnly -SkipElevation
```

Optional Windows Update stage:

```powershell
.\NewMachineSetup.ps1 -WindowsUpdate
```

## Qualification thresholds

Default PQ thresholds can be tuned with environment variables:

- `NMB_MIN_RAM_MB` (default `4096`)
- `NMB_MIN_DISK_MB` (default `10240`)
- `NMB_MIN_AVAILABLE_MEMORY_MB` (PowerShell PQ default `512`)
- `NMB_PACKAGE_MANAGER_THRESHOLD_SECONDS` (default `5`)
- `NMB_NETWORK_THRESHOLD_SECONDS` (default `5`)
- `NMB_DISK_WRITE_MBPS_MIN` (default `5`)
- `NMB_LOAD_THRESHOLD_MULTIPLIER` (Bash PQ default `2`)

Increase these thresholds for slower CI runners, or tighten them for production-like qualification hosts.

## Customization

To customize the installations:

- Edit `Brewfile` for macOS Homebrew packages and applications
- Edit `chocolatey.config` for Windows applications
- Edit `features.txt` for Windows features
- Edit `requirements.txt` for Python packages
- Edit `Gemfile` for Ruby gems

## Script architecture and extension model

Design goals in this repository:

- **SOLID**: each stage is orchestrated independently and low-level install logic is isolated behind dedicated functions.
- **DRY**: shared behavior (retry, failure tracking, operation-state tracking, summary output) is centralized in reusable helpers.
- **ACID-like consistency**: prerequisite validation runs first, install operations track explicit state transitions (`planned`, `running`, `succeeded`, `failed`), and retries are applied in a controlled way.

When adding a new installer:

1. Add a dedicated install function (single responsibility).
2. Reuse the shared retry/failure/state helpers.
3. Hook the function into the appropriate stage.
4. Keep qualification and preflight checks in validation stages when new inputs or dependencies are required.

## Regulated environment best practices

- Run `--iq-only` or `-IQOnly` before mutating a host.
- Use `--oq-only` or `-OQOnly` after package changes to confirm dependency managers still behave correctly.
- Reserve `--validate-only` for CI/CD or formal qualification evidence when a full non-mutating pass is required.
- Treat PQ thresholds as release criteria and document any local overrides used during validation.

## Brewfile

The `Brewfile` uses Homebrew Bundle, a feature that allows you to specify all your desired packages, casks, and even Mac App Store applications in a single file.

To manually install from the Brewfile:

```bash
brew bundle
```

## Chocolatey Config

The `chocolatey.config` is an XML file that defines all the Windows packages to install. It follows the Chocolatey package configuration format.

To manually install from the Chocolatey config:

```powershell
choco install chocolatey.config
```

## Contributing

As this is my personal set up I will not be accepting package PR's. I'm sorry, but I'm not installing things I don't need. You can fork it though.

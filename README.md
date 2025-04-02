# New Machine Build

[![CICD](https://github.com/PartTimeLegend/newmachinebuild/actions/workflows/cicd.yml/badge.svg)](https://github.com/PartTimeLegend/newmachinebuild/actions/workflows/cicd.yml)

A new machine is a PITA. This makes it less, at least for me it does.

## Overview

This repository contains scripts to automate the setup of a new development machine. It handles the installation of common development tools and applications using package managers:

- For macOS: [Homebrew](https://brew.sh/)
- For Windows: [Chocolatey](https://chocolatey.org)

## Usage

### macOS

```bash
./NewMachineSetup.sh
```

This will:

1. Install Homebrew if not already installed
2. Install packages listed in `brews.txt`
3. Install applications listed in `casks.txt`
4. Install Python packages from `requirements.txt`
5. Install Ruby gems from `Gemfile`

### Windows

```powershell
.\NewMachineSetup.ps1
```

This will:

1. Install Chocolatey if not already installed
2. Create a workspace directory
3. Install Windows features listed in `features.txt`
4. Install applications listed in `chocolatey.txt`
5. Install Python packages from `requirements.txt`
6. Install Ruby gems from `Gemfile`

## Customisation

To customise the installations:

- Edit `brews.txt` for macOS Homebrew packages
- Edit `casks.txt` for macOS applications
- Edit `chocolatey.txt` for Windows applications
- Edit `features.txt` for Windows features
- Edit `requirements.txt` for Python packages
- Edit `Gemfile` for Ruby gems

## Contributing

As this is my personal set up I will not be accepting package PR's. I'm sorry, but I'm not installing things I don't need. You can fork it though.

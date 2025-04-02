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
2. Install all packages and applications from `Brewfile`
3. Install Python packages from `requirements.txt`
4. Install Ruby gems from `Gemfile`

### Windows

```powershell
.\NewMachineSetup.ps1
```

This will:

1. Install Chocolatey if not already installed
2. Create a workspace directory
3. Install Windows features listed in `features.txt`
4. Install applications listed in `chocolatey.config`
5. Install Python packages from `requirements.txt`
6. Install Ruby gems from `Gemfile`

## Customization

To customize the installations:

- Edit `Brewfile` for macOS Homebrew packages and applications
- Edit `chocolatey.config` for Windows applications
- Edit `features.txt` for Windows features
- Edit `requirements.txt` for Python packages
- Edit `Gemfile` for Ruby gems

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

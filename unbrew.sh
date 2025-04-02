#!/usr/bin/env bash

set -e

echo "Starting Homebrew uninstallation process..."
echo "This will remove all packages installed via Homebrew."

# Check if Homebrew is installed
if ! command -v brew &> /dev/null; then
    echo "Homebrew is not installed. Nothing to do."
    exit 0
fi

# Confirm before proceeding
read -p "Are you sure you want to remove all Homebrew packages? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Operation canceled."
    exit 1
fi

echo "Uninstalling all Homebrew packages..."

# If the Brewfile exists, try to uninstall everything from it first
if [ -f "Brewfile" ]; then
    echo "Attempting to uninstall packages from Brewfile..."
    brew bundle cleanup --force || echo "Failed to cleanup via Brewfile, continuing with manual uninstall..."
fi

# Loop until no packages remain
while [[ $(brew list | wc -l) -ne 0 ]]; do
  for package in $(brew list); do
    echo "Uninstalling $package..."
    brew uninstall --force --ignore-dependencies "$package" || echo "Failed to uninstall $package, continuing anyway..."
  done
done

echo "All packages removed. Now uninstalling Homebrew itself..."

# Uninstall Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)"

echo "Homebrew uninstallation completed."

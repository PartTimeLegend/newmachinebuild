#!/usr/bin/env bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)"
while [[ `brew list | wc -l` -ne 0 ]]; do
    for package in `brew list`; do
        brew uninstall --force --ignore-dependencies $package
    done
done

#!/usr/bin/env bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew update
packages=("git"
  "git-lfs"
  "meld"
  "ruby"
  "go"
  "python"
  "dotnet"
  "dotnet-sdk"
  "node"
  "visual-studio-code"
  "postman"
  "visual-studio"
  "010-editor"
  "electrum"
  "google-chrome"
  "firefox"
  "terraform"
  "packer"
  "tflint"
  "p7zip"
  "powershell"
  "cmake"
  "burp-suite"
  "autopsy"
  "balenaetcher"
  "yarn"
  "pgadmin4"
  "azure-data-studio"
  "nosql-workbench"
  "openssh"
  "openssl"
  "slack"
  "teamviewer"
  "curl"
  "wireshark"
  "nmap"
  "wireguard-go"
  "awscli"
  "azure-cli"
  "docker"
  "helm"
  "kubernetes-cli"
  "minikube"
  "zoom"
  "microsoft-teams"
  "k9s")

install () {
  brew install $1
  return $?
}

uninstall () {
  brew uninstall $1
  brew $?
}

force_link () {
  brew link --overwrite $1
}

heroic_efforts () {
  # As we cannot get meaniful exit codes from homebrew we have to assume all failures to be the same.
  # So we are going to brute force a fix or die trying
  force_link $1
  retVal=$?
  if [ $retVal -ne 0 ]; then
    uninstall $1
    if [ $retVal -eq 0 ]; then
    # We managed to uninstall so now try to reinstall
      install $1
    fi
  fi
    exit $retVal
}

for package in ${packages[@]}; do
  install $package
  [ $? -eq 0 ] && echo "$package was installed successfully" || heroic_efforts $package
  [ $? -eq 0 ] && echo "$package was heroically installed" || "$package was not installed for some reason and we could not correct this."
done

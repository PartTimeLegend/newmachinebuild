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
  "k9s"
  "act")

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

for package in ${packages[@]}; do
  install $package
  [ $? -eq 0 ] && echo "$package was installed successfully" || "$package was not installed for some reason and we could not correct this."
done

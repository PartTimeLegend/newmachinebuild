#!/usr/bin/env bash

set -e  # Exit immediately if a command exits with a non-zero status

# Install Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Configure Homebrew for Linux environment
if [ "$(expr substr $(uname -s) 1 5)" == "Linux" ]; then
  echo '# Set PATH, MANPATH, etc., for Homebrew.' >> /home/runner/.bash_profile
  echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> /home/runner/.bash_profile
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

# Update Homebrew
brew update

# Read packages from file
packages=()
while IFS= read -r line; do
   [[ -n "$line" ]] && packages+=("$line")
done < brews.txt

# Read casks from file
casks=()
while IFS= read -r line; do
   [[ -n "$line" ]] && casks+=("$line")
done < casks.txt

# Function to install a brew package
install () {
  echo "Installing package: $1"
  brew install "$1"
  return $?
}

# Function to install a cask
install-cask () {
  echo "Installing cask: $1"
  brew install --cask "$1"
  return $?
}

# Function to uninstall a brew package
uninstall () {
  echo "Uninstalling package: $1"
  brew uninstall "$1"
  return $?
}

# Function to force link a brew package
force_link () {
  echo "Force linking: $1"
  brew link --overwrite "$1"
}

# Install brew packages
for package in "${packages[@]}"; do
  install "$package"
  [ $? -eq 0 ] && echo "$package was installed successfully" || echo "$package was not installed for some reason and we could not correct this."
done

# Install casks
for cask in "${casks[@]}"; do
  install-cask "$cask"
  [ $? -eq 0 ] && echo "$cask was installed successfully" || echo "$cask was not installed for some reason and we could not correct this."
done

# Install Python packages
install-pip () {
  echo "Installing Python packages from requirements.txt"
  pip install -r requirements.txt
  return $?
}

# Install Ruby gems
install-gems () {
  echo "Installing Ruby gems from Gemfile"
  bundle install
  return $?
}

# Run installations
install-pip
install-gems

echo "Setup completed successfully!"

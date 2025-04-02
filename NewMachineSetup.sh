#!/usr/bin/env bash

set -e  # Exit immediately if a command exits with a non-zero status

echo "Starting new machine setup..."

# Install Homebrew
if ! command -v brew &> /dev/null; then
  echo "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
  echo "Homebrew is already installed."
fi

# Configure Homebrew for Linux environment
if [ "$(expr substr $(uname -s) 1 5)" == "Linux" ]; then
  echo "Configuring Homebrew for Linux..."
  echo '# Set PATH, MANPATH, etc., for Homebrew.' >> /home/runner/.bash_profile
  echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> /home/runner/.bash_profile
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

# Update Homebrew
echo "Updating Homebrew..."
brew update

# Install from Brewfile
echo "Installing packages and applications from Brewfile..."
brew bundle --verbose

# Function to check if command exists
command_exists() {
  command -v "$1" &> /dev/null
}

# Install Python packages
install_pip() {
  echo "Installing Python packages from requirements.txt..."
  if [ -f "requirements.txt" ] && command_exists pip; then
    pip install -r requirements.txt
    return $?
  else
    echo "requirements.txt not found or pip not installed, skipping Python packages."
    return 0
  fi
}

# Install Ruby gems
install_gems() {
  echo "Installing Ruby gems from Gemfile..."
  if [ -f "Gemfile" ] && command_exists bundle; then
    bundle install
    return $?
  else
    echo "Gemfile not found or bundle not installed, skipping Ruby gems."
    return 0
  fi
}

# Run installations
install_pip
install_gems

echo "Setup completed successfully!"

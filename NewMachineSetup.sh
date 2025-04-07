#!/usr/bin/env bash

set -e  # Exit immediately if a command exits with a non-zero status

echo "Starting new machine setup..."

# Array to track failed installations
failed_installations=()

# Install Homebrew
if ! command -v brew &> /dev/null; then
  echo "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
    failed_installations+=("Homebrew:Installation_failed")
    echo "Failed to install Homebrew, but continuing..."
  }
else
  echo "Homebrew is already installed."
fi

# Configure Homebrew for Linux environment
if [ "$(expr substr $(uname -s) 1 5)" == "Linux" ]; then
  echo "Configuring Homebrew for Linux..."
  echo '# Set PATH, MANPATH, etc., for Homebrew.' >> /home/runner/.bash_profile
  echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> /home/runner/.bash_profile
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" || {
    failed_installations+=("Homebrew:Linux_configuration_failed")
    echo "Failed to configure Homebrew for Linux, but continuing..."
  }
fi

# Update Homebrew
echo "Updating Homebrew..."
brew update || {
  failed_installations+=("Homebrew:Update_failed")
  echo "Failed to update Homebrew, but continuing..."
}

# Install from Brewfile
echo "Installing packages and applications from Brewfile..."
brew_log=$(mktemp)
brew bundle --verbose 2>&1 | tee "$brew_log" || {
  # Parse the log to find failed installations
  grep -i "failed to install" "$brew_log" | while read -r line; do
    pkg=$(echo "$line" | grep -oP '(?<=failed to install )[^ ]+' || echo "unknown")
    reason=$(echo "$line" | sed 's/.*failed to install [^:]*: \(.*\)/\1/' || echo "Unknown reason")
    failed_installations+=("$pkg:$reason")
  done
  echo "Some Brewfile installations failed, but continuing..."
}
rm -f "$brew_log"

# Function to check if command exists
command_exists() {
  command -v "$1" &> /dev/null
}

# Install Python packages
install_pip() {
  echo "Installing Python packages from requirements.txt..."
  if [ -f "requirements.txt" ] && command_exists pip; then
    pip install -r requirements.txt || {
      failed_installations+=("Python_packages:pip_install_failed")
      return 1
    }
    return $?
  else
    echo "requirements.txt not found or pip not installed, skipping Python packages."
    [ ! -f "requirements.txt" ] && failed_installations+=("Python_packages:requirements.txt_not_found")
    ! command_exists pip && failed_installations+=("Python_packages:pip_not_installed")
    return 0
  fi
}

# Install Ruby gems
install_gems() {
  echo "Installing Ruby gems from Gemfile..."
  if [ -f "Gemfile" ] && command_exists bundle; then
    bundle install || {
      failed_installations+=("Ruby_gems:bundle_install_failed")
      return 1
    }
    return $?
  else
    echo "Gemfile not found or bundle not installed, skipping Ruby gems."
    [ ! -f "Gemfile" ] && failed_installations+=("Ruby_gems:Gemfile_not_found")
    ! command_exists bundle && failed_installations+=("Ruby_gems:bundle_not_installed")
    return 0
  fi
}

# Run installations
install_pip || echo "Python package installation had some issues, but continuing..."
install_gems || echo "Ruby gems installation had some issues, but continuing..."

# Display failed installations if any
if [ ${#failed_installations[@]} -gt 0 ]; then
  echo -e "\n\033[31mFAILED INSTALLATIONS SUMMARY:\033[0m"
  for failure in "${failed_installations[@]}"; do
    IFS=':' read -r package reason <<< "$failure"
    echo -e "\033[33m$package\033[0m: \033[31m${reason//_/ }\033[0m"
  done
  echo -e "\nSetup completed with some failures. Please check the errors above."
else
  echo -e "\n\033[32mSetup completed successfully with no failures!\033[0m"
fi

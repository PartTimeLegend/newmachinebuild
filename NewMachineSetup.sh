#!/usr/bin/env bash

set -euo pipefail

VALIDATE_ONLY=false
DRY_RUN="${NEW_MACHINE_DRY_RUN:-false}"
MAX_RETRIES="${NEW_MACHINE_MAX_RETRIES:-2}"

for arg in "$@"; do
  case "$arg" in
    --validate-only)
      VALIDATE_ONLY=true
      ;;
    --dry-run)
      DRY_RUN=true
      ;;
    *)
      echo "Unknown argument: $arg"
      exit 1
      ;;
  esac
done

echo "Starting new machine setup..."

failed_installations=()
operation_states=()

record_failure() {
  local package="$1"
  local reason="$2"
  failed_installations+=("${package}:${reason}")
}

record_operation_state() {
  local operation="$1"
  local state="$2"
  local message="${3:-}"
  operation_states+=("${operation}|${state}|${message}")
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

invoke_with_retry() {
  local description="$1"
  shift

  if [ "$DRY_RUN" = true ]; then
    echo "[dry-run] $description"
    return 0
  fi

  local attempt=1
  while [ "$attempt" -le "$MAX_RETRIES" ]; do
    if "$@"; then
      return 0
    fi

    if [ "$attempt" -lt "$MAX_RETRIES" ]; then
      echo "Retrying '$description' (attempt $((attempt + 1))/$MAX_RETRIES)..."
      sleep 2
    fi

    attempt=$((attempt + 1))
  done

  return 1
}

run_stage() {
  local stage_name="$1"
  shift

  record_operation_state "$stage_name" "planned"
  record_operation_state "$stage_name" "running"

  if "$@"; then
    record_operation_state "$stage_name" "succeeded"
    return 0
  fi

  record_operation_state "$stage_name" "failed"
  return 1
}

validate_inputs() {
  local valid=true

  if [ ! -f "Brewfile" ]; then
    echo "Brewfile not found"
    record_failure "Brewfile" "not_found"
    valid=false
  fi

  if [ -f "requirements.txt" ] && ! command_exists pip; then
    echo "pip command not found; Python dependency stage may fail"
  fi

  if [ -f "Gemfile" ] && ! command_exists bundle; then
    echo "bundle command not found; Ruby dependency stage may fail"
  fi

  if [ "$valid" = false ]; then
    return 1
  fi

  return 0
}

install_homebrew() {
  if command_exists brew; then
    echo "Homebrew is already installed."
    return 0
  fi

  echo "Installing Homebrew..."
  if ! invoke_with_retry "Install Homebrew" /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
    record_failure "Homebrew" "installation_failed"
    return 1
  fi

  return 0
}

configure_homebrew_linux() {
  if [ "$(uname -s)" != "Linux" ]; then
    return 0
  fi

  if [ ! -x "/home/linuxbrew/.linuxbrew/bin/brew" ]; then
    record_failure "Homebrew" "linux_binary_not_found"
    return 1
  fi

  echo "Configuring Homebrew for Linux..."
  if ! grep -q 'brew shellenv' /home/runner/.bash_profile 2>/dev/null; then
    {
      echo '# Set PATH, MANPATH, etc., for Homebrew.'
      echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"'
    } >> /home/runner/.bash_profile
  fi

  if ! eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"; then
    record_failure "Homebrew" "linux_configuration_failed"
    return 1
  fi

  return 0
}

update_homebrew() {
  echo "Updating Homebrew..."
  if ! invoke_with_retry "Update Homebrew" brew update; then
    record_failure "Homebrew" "update_failed"
    return 1
  fi

  return 0
}

install_brewfile() {
  echo "Installing packages and applications from Brewfile..."
  if ! invoke_with_retry "Install Brewfile dependencies" brew bundle --verbose; then
    record_failure "Brewfile" "bundle_install_failed"
    return 1
  fi

  return 0
}

install_pip() {
  echo "Installing Python packages from requirements.txt..."
  if [ ! -f "requirements.txt" ]; then
    return 0
  fi

  if ! command_exists pip; then
    record_failure "Python_packages" "pip_not_installed"
    return 1
  fi

  if ! invoke_with_retry "Install Python requirements" pip install -r requirements.txt; then
    record_failure "Python_packages" "pip_install_failed"
    return 1
  fi

  return 0
}

install_gems() {
  echo "Installing Ruby gems from Gemfile..."
  if [ ! -f "Gemfile" ]; then
    return 0
  fi

  if ! command_exists bundle; then
    record_failure "Ruby_gems" "bundle_not_installed"
    return 1
  fi

  if ! invoke_with_retry "Install Ruby gems" bundle install; then
    record_failure "Ruby_gems" "bundle_install_failed"
    return 1
  fi

  return 0
}

run_post_checks() {
  if ! command_exists brew; then
    record_failure "Post_checks" "brew_not_available"
    return 1
  fi

  if ! invoke_with_retry "Run brew doctor" brew doctor; then
    record_failure "Post_checks" "brew_doctor_failed"
    return 1
  fi

  return 0
}

print_summary() {
  echo -e "\nOPERATION STATE SUMMARY:"
  for entry in "${operation_states[@]}"; do
    IFS='|' read -r operation state message <<< "$entry"
    if [ -n "$message" ]; then
      echo "- $operation [$state]: $message"
    else
      echo "- $operation [$state]"
    fi
  done

  if [ ${#failed_installations[@]} -gt 0 ]; then
    echo -e "\n\033[31mFAILED INSTALLATIONS SUMMARY:\033[0m"
    for failure in "${failed_installations[@]}"; do
      IFS=':' read -r package reason <<< "$failure"
      echo -e "\033[33m$package\033[0m: \033[31m${reason//_/ }\033[0m"
    done
    echo -e "\nSetup completed with some failures."
  else
    echo -e "\n\033[32mSetup completed successfully with no failures!\033[0m"
  fi
}

bootstrap_stage() {
  install_homebrew || return 1
  configure_homebrew_linux || return 1
  update_homebrew || return 1
}

package_stage() {
  install_brewfile
}

language_stage() {
  local ok=true
  install_pip || ok=false
  install_gems || ok=false
  [ "$ok" = true ]
}

main() {
  run_stage "preflight-validation" validate_inputs || true

  if [ "$VALIDATE_ONLY" = true ]; then
    print_summary
    [ ${#failed_installations[@]} -eq 0 ]
    return
  fi

  run_stage "bootstrap" bootstrap_stage || true
  run_stage "package-installation" package_stage || true
  run_stage "language-dependencies" language_stage || true
  run_stage "post-checks" run_post_checks || true

  print_summary

  if [ ${#failed_installations[@]} -gt 0 ]; then
    return 1
  fi
}

main "$@"

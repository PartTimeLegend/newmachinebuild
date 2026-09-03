#!/usr/bin/env bash

set -euo pipefail

VALIDATE_ONLY=false
IQ_ONLY=false
OQ_ONLY=false
PQ_ONLY=false
DRY_RUN="${NEW_MACHINE_DRY_RUN:-false}"
MAX_RETRIES="${NEW_MACHINE_MAX_RETRIES:-2}"
MIN_RAM_MB="${NMB_MIN_RAM_MB:-4096}"
MIN_DISK_MB="${NMB_MIN_DISK_MB:-10240}"
PACKAGE_MANAGER_THRESHOLD_SECONDS="${NMB_PACKAGE_MANAGER_THRESHOLD_SECONDS:-5}"
NETWORK_THRESHOLD_SECONDS="${NMB_NETWORK_THRESHOLD_SECONDS:-5}"
DISK_WRITE_MBPS_MIN="${NMB_DISK_WRITE_MBPS_MIN:-5}"
LOAD_THRESHOLD_MULTIPLIER="${NMB_LOAD_THRESHOLD_MULTIPLIER:-2}"

for arg in "$@"; do
  case "$arg" in
    --validate-only)
      VALIDATE_ONLY=true
      ;;
    --iq-only)
      IQ_ONLY=true
      ;;
    --oq-only)
      OQ_ONLY=true
      ;;
    --pq-only)
      PQ_ONLY=true
      ;;
    --dry-run)
      DRY_RUN=true
      ;;
    --help|-h)
      cat <<'USAGE'
Usage: ./NewMachineSetup.sh [--validate-only] [--iq-only] [--oq-only] [--pq-only] [--dry-run]

  --validate-only  Run IQ, OQ, and PQ validation stages without mutating the system.
  --iq-only        Run only the preflight and IQ validation path.
  --oq-only        Run only the preflight and OQ validation path.
  --pq-only        Run only the preflight and PQ validation path.
  --dry-run        Print mutating commands instead of executing them.
USAGE
      exit 0
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

find_first_command() {
  local candidate
  for candidate in "$@"; do
    if command_exists "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

qualification_only_mode() {
  [ "$VALIDATE_ONLY" = true ] || [ "$IQ_ONLY" = true ] || [ "$OQ_ONLY" = true ] || [ "$PQ_ONLY" = true ]
}

is_ci_environment() {
  [ "${CI:-}" = "true" ] || [ "${GITHUB_ACTIONS:-}" = "true" ]
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

float_gt() {
  awk -v left="$1" -v right="$2" 'BEGIN { exit !(left > right) }'
}

float_lt() {
  awk -v left="$1" -v right="$2" 'BEGIN { exit !(left < right) }'
}

now_seconds() {
  if command_exists python3; then
    python3 -c 'import time; print(time.time())'
  elif command_exists python; then
    python -c 'import time; print(time.time())'
  elif command_exists perl; then
    perl -MTime::HiRes=time -e 'print time'
  else
    date +%s
  fi
}

measure_command_seconds() {
  local output_file start end
  output_file=$(mktemp)
  start=$(now_seconds)

  if "$@" >"$output_file" 2>&1; then
    end=$(now_seconds)
    rm -f "$output_file"
    awk -v start="$start" -v end="$end" 'BEGIN { printf "%.2f", end - start }'
    return 0
  fi

  cat "$output_file"
  rm -f "$output_file"
  return 1
}

measure_url_seconds() {
  curl -fsSI -o /dev/null -w '%{time_total}' --max-time "$NETWORK_THRESHOLD_SECONDS" "$1" 2>/dev/null
}

check_url_connectivity() {
  curl -fsSI --max-time "$NETWORK_THRESHOLD_SECONDS" "$1" >/dev/null 2>&1
}

verify_checksum() {
  local tool_name="$1"
  local tool_path
  tool_path=$(command -v "$tool_name")

  if command_exists shasum; then
    shasum -a 256 "$tool_path" >/dev/null 2>&1
  else
    cksum "$tool_path" >/dev/null 2>&1
  fi
}

get_total_ram_mb() {
  local ram_bytes=""
  if command_exists sysctl; then
    ram_bytes=$(sysctl -n hw.memsize 2>/dev/null || true)
  fi

  if [ -z "$ram_bytes" ] && command_exists getconf; then
    local pages page_size
    pages=$(getconf _PHYS_PAGES 2>/dev/null || true)
    page_size=$(getconf PAGE_SIZE 2>/dev/null || true)
    if [ -n "$pages" ] && [ -n "$page_size" ]; then
      ram_bytes=$((pages * page_size))
    fi
  fi

  if [ -n "$ram_bytes" ]; then
    echo $((ram_bytes / 1024 / 1024))
  else
    echo 0
  fi
}

get_free_disk_mb() {
  df -Pm . | awk 'NR == 2 { print $4 }'
}

get_cpu_cores() {
  if command_exists sysctl; then
    sysctl -n hw.ncpu 2>/dev/null || true
  elif command_exists getconf; then
    getconf _NPROCESSORS_ONLN 2>/dev/null || true
  else
    echo 1
  fi
}

get_load_average() {
  if command_exists sysctl; then
    sysctl -n vm.loadavg 2>/dev/null | tr -d '{}' | awk '{ print $1 }'
  elif [ -f /proc/loadavg ]; then
    awk '{ print $1 }' /proc/loadavg
  else
    echo 0
  fi
}

validate_inputs() {
  local valid=true
  local os_name total_ram_mb free_disk_mb endpoint

  os_name=$(uname -s)
  case "$os_name" in
    Darwin|Linux)
      ;;
    *)
      echo "Unsupported operating system: $os_name"
      record_failure "preflight-validation" "unsupported_os_${os_name}"
      valid=false
      ;;
  esac

  if [ ! -f "Brewfile" ]; then
    echo "Brewfile not found"
    record_failure "Brewfile" "not_found"
    valid=false
  fi

  total_ram_mb=$(get_total_ram_mb)
  if [ "$total_ram_mb" -lt "$MIN_RAM_MB" ]; then
    record_failure "preflight-validation" "insufficient_ram_${total_ram_mb}MB"
    valid=false
  fi

  free_disk_mb=$(get_free_disk_mb)
  if [ "$free_disk_mb" -lt "$MIN_DISK_MB" ]; then
    record_failure "preflight-validation" "insufficient_disk_${free_disk_mb}MB"
    valid=false
  fi

  for endpoint in "https://brew.sh" "https://pypi.org/simple/" "https://rubygems.org"; do
    if ! check_url_connectivity "$endpoint"; then
      record_failure "preflight-validation" "network_unreachable_$(echo "$endpoint" | sed 's#https\?://##; s#[^A-Za-z0-9]#_#g')"
      valid=false
    fi
  done

  if [ -f "requirements.txt" ] && [ -z "$(find_first_command pip3 pip || true)" ]; then
    echo "pip command not found; Python dependency stage may fail"
  fi

  if [ -f "Gemfile" ] && ! command_exists bundle; then
    echo "bundle command not found; Ruby dependency stage may fail"
  fi

  [ "$valid" = true ]
}

run_iq_stage() {
  local success=true
  local python_cmd pip_cmd bundle_cmd
  local core_tools tool_name command_name

  python_cmd=$(find_first_command python3 python || true)
  pip_cmd=$(find_first_command pip3 pip || true)
  bundle_cmd=$(find_first_command bundle || true)

  if command_exists brew; then
    verify_checksum brew || {
      record_failure "IQ" "brew_checksum_failed"
      success=false
    }
  elif qualification_only_mode; then
    record_failure "IQ" "brew_not_installed"
    success=false
  else
    echo "Homebrew is not installed yet; bootstrap will install it."
  fi

  core_tools="git python pip"
  for tool_name in $core_tools; do
    case "$tool_name" in
      python)
        command_name="$python_cmd"
        ;;
      pip)
        command_name="$pip_cmd"
        ;;
      *)
        command_name="$tool_name"
        ;;
    esac

    if [ -n "$command_name" ] && command_exists "$command_name"; then
      verify_checksum "$command_name" || {
        record_failure "IQ" "${tool_name}_checksum_failed"
        success=false
      }
    elif qualification_only_mode; then
      record_failure "IQ" "${tool_name}_not_installed"
      success=false
    else
      echo "$tool_name is not installed yet; later stages may provision it."
    fi
  done

  if [ -n "$bundle_cmd" ] && command_exists "$bundle_cmd"; then
    verify_checksum "$bundle_cmd" || {
      record_failure "IQ" "bundle_checksum_failed"
      success=false
    }
  else
    echo "bundle is not installed yet; Ruby gem stage will provision it."
  fi

  [ "$success" = true ]
}

run_homebrew_installer() {
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
}

install_homebrew() {
  if command_exists brew; then
    echo "Homebrew is already installed."
    return 0
  fi

  echo "Installing Homebrew..."
  if ! invoke_with_retry "Install Homebrew" run_homebrew_installer; then
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
      echo "eval \"\$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)\""
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
  local brew_bundle_args=(--verbose)
  local -a brew_bundle_cmd=(brew bundle "${brew_bundle_args[@]}")

  if [ -f "Brewfile" ] && command_exists brew; then
    while IFS= read -r line; do
      local tap_name
      tap_name=$(echo "$line" | sed -n 's/^tap[[:space:]]*"\([^"]*\)".*/\1/p')
      if [ -n "$tap_name" ]; then
        brew tap "$tap_name" 2>/dev/null || true
        brew trust "$tap_name" 2>/dev/null || true
      fi
    done < Brewfile
  fi

  if is_ci_environment && [ "$(uname -s)" = "Darwin" ]; then
    echo "Skipping Homebrew casks and Mac App Store apps in CI."
    if ! invoke_with_retry \
      "Install Brewfile dependencies" \
      env HOMEBREW_BUNDLE_NO_INSTALL_CASK=1 HOMEBREW_BUNDLE_NO_INSTALL_MAS=1 "${brew_bundle_cmd[@]}"; then
      record_failure "Brewfile" "bundle_install_failed"
      return 1
    fi
    return 0
  fi

  if ! invoke_with_retry "Install Brewfile dependencies" "${brew_bundle_cmd[@]}"; then
    record_failure "Brewfile" "bundle_install_failed"
    return 1
  fi

  return 0
}

run_oq_stage() {
  local success=true
  local python_cmd pip_cmd bundle_cmd package_duration
  local -a pip_resolution_args

  python_cmd=$(find_first_command python3 python || true)
  pip_cmd=$(find_first_command pip3 pip || true)
  bundle_cmd=$(find_first_command bundle || true)

  if command_exists brew; then
    brew --version >/dev/null 2>&1 || {
      record_failure "OQ" "brew_not_operational"
      success=false
    }
    brew bundle list --all --file=Brewfile >/dev/null 2>&1 || {
      record_failure "OQ" "brew_bundle_manifest_validation_failed"
      success=false
    }
    brew uninstall --help >/dev/null 2>&1 || {
      record_failure "OQ" "brew_rollback_unavailable"
      success=false
    }
  else
    record_failure "OQ" "brew_not_available"
    success=false
  fi

  if [ -n "$python_cmd" ]; then
    "$python_cmd" --version >/dev/null 2>&1 || {
      record_failure "OQ" "python_not_operational"
      success=false
    }
  else
    record_failure "OQ" "python_not_available"
    success=false
  fi

  if [ -n "$pip_cmd" ]; then
    "$pip_cmd" --version >/dev/null 2>&1 || {
      record_failure "OQ" "pip_not_operational"
      success=false
    }
    "$pip_cmd" uninstall --help >/dev/null 2>&1 || {
      record_failure "OQ" "pip_rollback_unavailable"
      success=false
    }
    if [ -f "requirements.txt" ]; then
      pip_resolution_args=(install --dry-run --ignore-installed)
      if "$pip_cmd" install --help 2>/dev/null | grep -q -- '--break-system-packages'; then
        pip_resolution_args+=(--break-system-packages)
      fi
      "$pip_cmd" "${pip_resolution_args[@]}" -r requirements.txt >/dev/null 2>&1 || {
        record_failure "OQ" "pip_dependency_resolution_failed"
        success=false
      }
    fi
  else
    record_failure "OQ" "pip_not_available"
    success=false
  fi

  if [ -n "$bundle_cmd" ]; then
    "$bundle_cmd" --version >/dev/null 2>&1 || {
      record_failure "OQ" "bundle_not_operational"
      success=false
    }
    "$bundle_cmd" check >/dev/null 2>&1 || {
      record_failure "OQ" "bundle_dependency_check_failed"
      success=false
    }
    if command_exists gem; then
      gem uninstall --help >/dev/null 2>&1 || {
        record_failure "OQ" "gem_rollback_unavailable"
        success=false
      }
    fi
  elif [ -f "Gemfile" ]; then
    record_failure "OQ" "bundle_not_available"
    success=false
  fi

  if ! check_url_connectivity "https://formulae.brew.sh"; then
    record_failure "OQ" "homebrew_repository_unreachable"
    success=false
  fi

  [ "$success" = true ]
}

install_pip() {
  local pip_cmd
  local -a pip_install_args
  pip_cmd=$(find_first_command pip3 pip || true)

  echo "Installing Python packages from requirements.txt..."
  if [ ! -f "requirements.txt" ]; then
    return 0
  fi

  if [ -z "$pip_cmd" ]; then
    record_failure "Python_packages" "pip_not_installed"
    return 1
  fi

  pip_install_args=(install)
  if "$pip_cmd" install --help 2>/dev/null | grep -q -- '--break-system-packages'; then
    pip_install_args+=(--break-system-packages)
  fi

  if ! invoke_with_retry "Install Python requirements" "$pip_cmd" "${pip_install_args[@]}" -r requirements.txt; then
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

run_pq_stage() {
  local success=true
  local package_duration network_duration disk_start disk_end disk_seconds disk_mbps load_average core_limit
  local temp_file

  if command_exists brew; then
    if package_duration=$(measure_command_seconds brew --version); then
      if float_gt "$package_duration" "$PACKAGE_MANAGER_THRESHOLD_SECONDS"; then
        record_failure "PQ" "brew_response_too_slow_${package_duration}s"
        success=false
      fi
    else
      record_failure "PQ" "brew_response_measurement_failed"
      success=false
    fi
  else
    record_failure "PQ" "brew_not_available"
    success=false
  fi

  local pip_cmd
  pip_cmd=$(find_first_command pip3 pip || true)
  if [ -n "$pip_cmd" ]; then
    if package_duration=$(measure_command_seconds "$pip_cmd" --version); then
      if float_gt "$package_duration" "$PACKAGE_MANAGER_THRESHOLD_SECONDS"; then
        record_failure "PQ" "pip_response_too_slow_${package_duration}s"
        success=false
      fi
    else
      record_failure "PQ" "pip_response_measurement_failed"
      success=false
    fi
  fi

  temp_file=$(mktemp)
  disk_start=$(now_seconds)
  if dd if=/dev/zero of="$temp_file" bs=1048576 count=8 conv=fsync >/dev/null 2>&1; then
    disk_end=$(now_seconds)
    disk_seconds=$(awk -v start="$disk_start" -v end="$disk_end" 'BEGIN { printf "%.2f", end - start }')
    if float_gt "$disk_seconds" 0; then
      disk_mbps=$(awk -v size_mb="8" -v duration="$disk_seconds" 'BEGIN { printf "%.2f", size_mb / duration }')
      if float_lt "$disk_mbps" "$DISK_WRITE_MBPS_MIN"; then
        record_failure "PQ" "disk_write_below_threshold_${disk_mbps}MBps"
        success=false
      fi
    fi
  else
    record_failure "PQ" "disk_io_test_failed"
    success=false
  fi
  rm -f "$temp_file"

  if network_duration=$(measure_url_seconds "https://formulae.brew.sh"); then
    if float_gt "$network_duration" "$NETWORK_THRESHOLD_SECONDS"; then
      record_failure "PQ" "network_response_too_slow_${network_duration}s"
      success=false
    fi
  else
    record_failure "PQ" "network_measurement_failed"
    success=false
  fi

  load_average=$(get_load_average)
  core_limit=$(awk -v cores="$(get_cpu_cores)" -v multiplier="$LOAD_THRESHOLD_MULTIPLIER" 'BEGIN { printf "%.2f", cores * multiplier }')
  if [ -n "$load_average" ] && float_gt "$load_average" "$core_limit"; then
    if is_ci_environment; then
      echo "Skipping strict load average gate in CI (observed=${load_average}, threshold=${core_limit})."
    else
      record_failure "PQ" "resource_utilization_high_${load_average}"
      success=false
    fi
  fi

  [ "$success" = true ]
}

run_post_checks() {
  local success=true

  if ! command_exists brew; then
    record_failure "Post_checks" "brew_not_available"
    return 1
  fi

  if ! invoke_with_retry "Run brew doctor" brew doctor; then
    if is_ci_environment; then
      echo "Ignoring brew doctor failure in CI due to hosted-runner Homebrew warnings."
    else
      record_failure "Post_checks" "brew_doctor_failed"
      success=false
    fi
  fi

  [ "$success" = true ]
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

finish_validation_run() {
  print_summary

  if [ ${#failed_installations[@]} -gt 0 ]; then
    return 1
  fi

  return 0
}

main() {
  if qualification_only_mode; then
    run_stage "preflight-validation" validate_inputs || true
  else
    if ! run_stage "preflight-validation" validate_inputs; then
      print_summary
      return 1
    fi
  fi

  if [ "$IQ_ONLY" = true ]; then
    run_stage "IQ" run_iq_stage || true
    finish_validation_run
    return
  fi

  if [ "$OQ_ONLY" = true ]; then
    run_stage "OQ" run_oq_stage || true
    finish_validation_run
    return
  fi

  if [ "$PQ_ONLY" = true ]; then
    run_stage "PQ" run_pq_stage || true
    finish_validation_run
    return
  fi

  if [ "$VALIDATE_ONLY" = true ]; then
    run_stage "IQ" run_iq_stage || true
    run_stage "OQ" run_oq_stage || true
    run_stage "PQ" run_pq_stage || true
    run_stage "post-checks" run_post_checks || true
    finish_validation_run
    return
  fi

  run_stage "IQ" run_iq_stage || true
  run_stage "bootstrap" bootstrap_stage || true
  run_stage "package-installation" package_stage || true
  run_stage "OQ" run_oq_stage || true
  run_stage "language-dependencies" language_stage || true
  run_stage "PQ" run_pq_stage || true
  run_stage "post-checks" run_post_checks || true

  print_summary

  if [ ${#failed_installations[@]} -gt 0 ]; then
    return 1
  fi
}

main "$@"

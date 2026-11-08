#!/usr/bin/env bash
#
# Droidspaces kernel support helpers. Sourced, not executed.
#
# SYSVIPC adds sysvsem/sysvshm to task_struct, which would shift the kABI and
# bootloop the device (stock vendor modules refuse to load). The Droidspaces
# kABI patch moves them into the ANDROID_KABI_RESERVE(6..8) padding instead.
#

DROIDSPACES_KABI_PATCH="droidspaces-sysvipc-kabi-6-7-8.patch"

apply_droidspaces_kabi_patch() {
  local patch_dir="$1"
  local patch_file="${patch_dir}/${DROIDSPACES_KABI_PATCH}"
  local slot

  [[ -f "$patch_file" ]] || {
    echo "::error::Droidspaces kABI patch is missing: ${patch_file}"
    exit 1
  }
  for slot in 6 7 8; do
    grep -qE "^[[:space:]]*ANDROID_KABI_RESERVE\(${slot}\);" include/linux/sched.h || {
      echo "::error::task_struct ANDROID_KABI_RESERVE(${slot}) is not free in include/linux/sched.h; the Droidspaces kABI patch cannot be used on this tree."
      exit 1
    }
  done
  grep -qE '^[[:space:]]*struct sysv_sem[[:space:]]+sysvsem;' include/linux/sched.h || {
    echo "::error::task_struct has no plain sysvsem field; the Droidspaces kABI patch does not match this tree."
    exit 1
  }

  patch -p1 --forward --no-backup-if-mismatch < "$patch_file" || {
    echo "::error::Droidspaces kABI patch did not apply to this kernel source."
    exit 1
  }

  grep -Fq 'ANDROID_KABI_USE(6, struct sysv_sem sysvsem)' include/linux/sched.h || {
    echo "::error::sysvsem was not moved into ANDROID_KABI slot 6 after patching."
    exit 1
  }
  grep -Fq 'struct sysv_shm sysvshm' include/linux/sched.h || {
    echo "::error::sysvshm was not moved into the ANDROID_KABI padding after patching."
    exit 1
  }
  {
    echo "droidspaces_kabi_patch=${DROIDSPACES_KABI_PATCH}"
    grep -n 'ANDROID_KABI_USE(6, struct sysv_sem sysvsem)\|struct sysv_shm sysvshm' include/linux/sched.h
  } | tee droidspaces-source-proof.txt
}

droidspaces_config_keys() {
  local fragment="${DROIDSPACES_CONFIG_DIR:?}/droidspaces.config"
  [[ -f "$fragment" ]] || {
    echo "::error::Missing Droidspaces config fragment: ${fragment}" >&2
    return 1
  }
  sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' -e 's/=y[[:space:]]*$//' "$fragment"
}

apply_droidspaces_config() {
  local config_file="$1"
  local key

  [[ "${DROIDSPACES:-0}" == 1 ]] || return 0
  while IFS= read -r key; do
    enable_config_values "$config_file" "$key"
  done < <(droidspaces_config_keys)
}

verify_droidspaces_config() {
  local config_file="$1"
  local proof_file="$2"
  local key
  local required="CONFIG_SYSVIPC CONFIG_POSIX_MQUEUE CONFIG_IPC_NS CONFIG_PID_NS CONFIG_DEVTMPFS"

  [[ "${DROIDSPACES:-0}" == 1 ]] || return 0

  echo "Droidspaces kernel options in the final .config" > "$proof_file"
  for key in $required; do
    require_config_enabled "$config_file" "$key"
    echo "kept ${key}" >> "$proof_file"
  done
  while IFS= read -r key; do
    case " $required " in *" $key "*) continue ;; esac
    if grep -q "^${key}=y$" "$config_file"; then
      echo "kept ${key}" >> "$proof_file"
    else
      echo "dropped ${key}" >> "$proof_file"
      echo "::warning::Droidspaces option dropped by Kconfig: ${key}"
    fi
  done < <(droidspaces_config_keys)

  # These resize scheduler/cgroup structures; no padding trick covers them.
  for key in CONFIG_CFS_BANDWIDTH CONFIG_CGROUP_PIDS; do
    if grep -q "^${key}=y$" "$config_file"; then
      echo "::error::${key} is enabled; it changes the kABI and bootloops devices that keep stock vendor modules."
      exit 1
    fi
    echo "kabi-guard ${key} is off" >> "$proof_file"
  done
}

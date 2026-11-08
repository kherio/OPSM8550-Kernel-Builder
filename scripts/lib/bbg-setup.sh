#!/usr/bin/env bash
#
# Baseband-guard (BBG) integration helpers. Sourced, not executed.
# Depends on lib/git-helpers.sh, lib/kernel-helpers.sh and lib/nomount-setup.sh
# (insert_line_before_last_match).
#
# BBG is a stackable LSM (DEFINE_LSM on 5.15) that denies writes to critical
# partitions. It allocates no fields in core kernel structs, so the exported
# kABI is unchanged.
#

BBG_REPO_URL="https://github.com/vc-teahouse/Baseband-guard"
BBG_PINNED_COMMIT="028ff7fd509e2104596da7cc1ef8e6ce2a0c9082"
BBG_DEFAULT_LSM="landlock,lockdown,yama,loadpin,safesetid,integrity,selinux,smack,tomoyo,apparmor,bpf"

install_baseband_guard() {
  local repo="${1:-$BBG_REPO_URL}"
  local commit="${2:-$BBG_PINNED_COMMIT}"
  local security_dir
  local scratch="Baseband-guard.src"
  local kconfig_source='source "security/baseband-guard/Kconfig"'

  if [[ -d security ]]; then
    security_dir="security"
  elif [[ -d common/security ]]; then
    security_dir="common/security"
  else
    echo "::error::Baseband-guard requires a security/ or common/security/ directory."
    exit 1
  fi

  rm -rf "$scratch" Baseband-guard
  git init -q "$scratch"
  git -C "$scratch" remote add origin "$repo"
  git_fetch_retry "$scratch" --depth=1 --no-tags origin "$commit"
  git -C "$scratch" checkout -q --detach FETCH_HEAD
  test "$(git -C "$scratch" rev-parse HEAD)" = "$commit" || {
    echo "::error::Baseband-guard checkout does not match pinned commit $commit."
    exit 1
  }

  # Export without .git: the BBG Makefile runs `git fetch --unshallow` when it
  # sees .git/shallow, which would hit the network during the kernel build.
  mkdir Baseband-guard
  git -C "$scratch" archive HEAD | tar -x -C Baseband-guard
  rm -rf "$scratch"

  test -f Baseband-guard/baseband_guard.c
  test -f Baseband-guard/Kconfig
  test -f Baseband-guard/Makefile

  rm -rf "${security_dir}/baseband-guard"
  ln -s "$(realpath --relative-to="$security_dir" Baseband-guard)" "${security_dir}/baseband-guard"
  ensure_line_in_file "${security_dir}/Makefile" 'obj-$(CONFIG_BBG) += baseband-guard/'
  insert_line_before_last_match "${security_dir}/Kconfig" "endmenu" "$kconfig_source" || {
    echo "::error::Could not add Baseband-guard Kconfig to ${security_dir}/Kconfig."
    exit 1
  }

  grep -Fq '#define DEFINE_LSM(lsm)' include/linux/lsm_hooks.h || {
    echo "::error::This kernel lacks DEFINE_LSM; the non-GKI Baseband-guard SELinux patch path is not supported."
    exit 1
  }

  BBG_SECURITY_DIR="$security_dir"
  export BBG_SECURITY_DIR
  {
    echo "bbg_repo=$repo"
    echo "bbg_commit=$commit"
    echo "bbg_security_dir=$security_dir"
    grep -Fn 'baseband-guard' "${security_dir}/Makefile" "${security_dir}/Kconfig"
  } | tee bbg-source-proof.txt
  echo "[+] Integrated Baseband-guard from $commit."
}

apply_bbg_config() {
  local config_file="$1"
  local lsm_line
  local lsm_value

  [[ "${BASEBAND_GUARD:-0}" == 1 ]] || return 0

  enable_config_values "$config_file" CONFIG_SECURITY CONFIG_BBG
  # Boot/recovery stay writable so the kernel can still be flashed from Android.
  disable_config_values "$config_file" CONFIG_BBG_BLOCK_BOOT CONFIG_BBG_BLOCK_RECOVERY

  lsm_line="$(grep -E '^CONFIG_LSM=' "$config_file" || true)"
  if [[ -z "$lsm_line" ]]; then
    lsm_value="$BBG_DEFAULT_LSM"
  else
    lsm_value="${lsm_line#CONFIG_LSM=}"
    lsm_value="${lsm_value#\"}"
    lsm_value="${lsm_value%\"}"
  fi
  case ",${lsm_value}," in
    *,baseband_guard,*) ;;
    *) lsm_value="${lsm_value},baseband_guard" ;;
  esac
  set_config_value "$config_file" CONFIG_LSM "\"${lsm_value}\""
}

verify_bbg_config() {
  local config_file="$1"
  local proof_file="$2"

  [[ "${BASEBAND_GUARD:-0}" == 1 ]] || return 0

  require_config_enabled "$config_file" CONFIG_BBG
  require_config_disabled "$config_file" CONFIG_BBG_BLOCK_BOOT
  require_config_disabled "$config_file" CONFIG_BBG_BLOCK_RECOVERY
  grep -E '^CONFIG_LSM=.*baseband_guard' "$config_file" > /dev/null || {
    echo "::error::baseband_guard is missing from CONFIG_LSM in the final .config."
    grep -E '^CONFIG_LSM=' "$config_file" || true
    exit 1
  }
  {
    echo "Baseband-guard options in the final .config"
    grep -E '^(CONFIG_BBG|CONFIG_LSM=|# CONFIG_BBG)' "$config_file"
    echo "pinned_commit=${BBG_PINNED_COMMIT}"
  } > "$proof_file"
}

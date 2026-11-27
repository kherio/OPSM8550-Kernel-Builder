#!/usr/bin/env bash
#
# Out-of-tree Wi-Fi USB driver build helpers. Sourced, not executed.
# Depends on lib/git-helpers.sh and lib/kernel-helpers.sh.
#
# The driver is built as an external module against the exact tree and
# config that produced the Image, and signed with the key embedded in that
# Image, so vermagic, modversions CRCs and the module signature all match.
# Nothing is linked into the Image: the kernel stays ABI-identical.
#

# morrownr/88x2bu-20210702 is explicitly a frozen 2021 snapshot: its own
# README says it gets no further API-related updates, and it predates the
# cfg80211 multi-link (MLO-era) callback signatures this kernel's wireless
# stack already uses (extra link_id arguments, wireless_dev.links[] instead
# of a bare current_bss, etc.) -- confirmed by a real build failing on
# exactly those mismatches. ShorterKing/RTL88x2BU-Android-Drivers_rtl8812au
# vendors a newer Realtek driver tree (same GPL-2.0 licence, genuine Realtek
# 2007-2019 copyright headers) that already handles both the old and new
# cfg80211 shapes via LINUX_VERSION_CODE guards. The actual driver lives in
# that repo's RTL88x2BU-Linux-Driver/ subdirectory.
RTL88X2BU_REPO="https://github.com/ShorterKing/RTL88x2BU-Android-Drivers_rtl8812au.git"
RTL88X2BU_COMMIT="578690da28a7a6bfc458d7e5ee44c51f19263e45"
RTL88X2BU_REPO_SUBDIR="RTL88x2BU-Linux-Driver"
RTL88X2BU_MODULE_NAME="88x2bu"
WIFI_STAGE_DIR="wifi-module-stage"

export_exact_commit() {
  local repo="$1"
  local commit="$2"
  local dest="$3"
  local subdir="${4:-}"
  local scratch="${dest}.git-src"

  rm -rf "$dest" "$scratch"
  git init -q "$scratch"
  git -C "$scratch" remote add origin "$repo"
  git_fetch_retry "$scratch" --depth=1 --no-tags origin "$commit"
  git -C "$scratch" checkout -q --detach FETCH_HEAD
  test "$(git -C "$scratch" rev-parse HEAD)" = "$commit" || {
    echo "::error::Checkout of $repo does not match pinned commit $commit."
    return 1
  }
  mkdir -p "$dest"
  if [[ -n "$subdir" ]]; then
    # Archive only the subdirectory the real driver lives in, then strip its
    # leading path component so $dest's contents match a plain driver repo.
    git -C "$scratch" archive HEAD -- "$subdir" | tar -x -C "$dest" --strip-components=1
  else
    git -C "$scratch" archive HEAD | tar -x -C "$dest"
  fi
  rm -rf "$scratch"
}

wifi_find_sign_file() {
  local candidate
  for candidate in out/scripts/sign-file scripts/sign-file; do
    [[ -x "$candidate" ]] && { echo "$candidate"; return 0; }
  done
  return 1
}

sign_module_with_kernel_key() {
  local module="$1"
  local sign_file
  local hash
  local key="out/certs/signing_key.pem"
  local cert="out/certs/signing_key.x509"

  sign_file="$(wifi_find_sign_file)" || {
    echo "::warning::sign-file not found; leaving ${module} unsigned."
    return 1
  }
  [[ -f "$key" && -f "$cert" ]] || {
    echo "::warning::Kernel signing key not found in out/certs; leaving ${module} unsigned."
    return 1
  }
  hash="$(sed -n 's/^CONFIG_MODULE_SIG_HASH="\(.*\)"$/\1/p' out/.config)"
  hash="${hash:-sha512}"
  "$sign_file" "$hash" "$key" "$cert" "$module"
}

build_rtl88x2bu_module() {
  local kernel_release="$1"
  local proof="wifi-driver-proof.txt"
  local src="wifi-driver-src"
  local ko
  local vermagic
  local signed=no

  grep -q '^CONFIG_MODULES=y$' out/.config || { echo "::error::CONFIG_MODULES is off."; return 1; }
  grep -q '^CONFIG_CFG80211=m$' out/.config || {
    echo "::error::CONFIG_CFG80211 is not a module in this kernel; the external Wi-Fi driver cannot bind to the ROM's cfg80211.ko."
    return 1
  }

  export_exact_commit "$RTL88X2BU_REPO" "$RTL88X2BU_COMMIT" "$src" "$RTL88X2BU_REPO_SUBDIR" || return 1
  test -f "$src/Makefile" || return 1

  # Full module pass first: it creates the Module.symvers entries (cfg80211
  # and friends) the external module is linked against.
  make -j"$(nproc)" "${MAKE_ARGS[@]}" modules 2>&1 | tee wifi-modules-build.log
  [[ "${PIPESTATUS[0]}" -eq 0 ]] || { echo "::error::make modules failed."; return 1; }

  # morrownr/88x2bu's own Makefile only sets obj-$(CONFIG_RTL8822BU) when it is
  # invoked the "normal" way -- `make` inside the driver's own directory, with
  # no $(KERNELRELEASE) set -- because that path is what exports
  # CONFIG_RTL8822BU=m before recursing into the kernel's build system. Driving
  # it the standard out-of-tree-module way instead, directly via the kernel's
  # own `make O=out M=<dir> modules` (as below), skips straight to the
  # kbuild-include branch of that Makefile, where CONFIG_RTL8822BU is still
  # unset: obj-$(CONFIG_RTL8822BU) then expands to the empty "obj-" variable,
  # so nothing is ever added to obj-m and the module silently builds nothing.
  # Passing CONFIG_RTL8822BU=m on the command line here reproduces what that
  # normal invocation path would have exported, without needing to go through it.
  # This driver predates both Clang-under-Werror builds and this kernel's
  # stricter diagnostics: it hardcodes GCC-13-only flags Clang's driver
  # doesn't recognize at all (-Wno-stringop-overread and friends), and its
  # own source trips several genuine but harmless Clang-only warnings
  # (uninitialized-on-some-paths locals, redundant parens) that GCC never
  # flagged. This kernel's GKI defconfig builds with CONFIG_WERROR=y, which
  # promotes every one of those to a hard build error -- and Clang treats an
  # unrecognized -W name as a special driver-level diagnostic that a plain,
  # later -Wno-error does NOT retroactively downgrade (unlike an ordinary
  # per-translation-unit warning): it needs its own explicit
  # -Wno-unknown-warning-option alongside -Wno-error. Both together turn
  # -Werror back off for this one out-of-tree, third-party module only; the
  # kernel's own first-party code still builds with CONFIG_WERROR=y
  # untouched.
  make -j"$(nproc)" "${MAKE_ARGS[@]}" CONFIG_RTL8822BU=m KCFLAGS="-Wno-unknown-warning-option -Wno-error" -C "$PWD" M="$PWD/$src" modules 2>&1 | tee -a wifi-modules-build.log
  [[ "${PIPESTATUS[0]}" -eq 0 ]] || { echo "::error::RTL88x2BU external module build failed."; return 1; }

  ko="$src/${RTL88X2BU_MODULE_NAME}.ko"
  test -f "$ko" || { echo "::error::${ko} was not produced."; return 1; }
  llvm-strip --strip-debug "$ko"
  sign_module_with_kernel_key "$ko" && signed=yes

  vermagic="$(modinfo -F vermagic "$ko")"
  case "$vermagic" in
    "${kernel_release} "*) ;;
    *)
      echo "::error::Module vermagic '${vermagic}' does not match kernel release '${kernel_release}'."
      return 1
      ;;
  esac

  rm -rf "$WIFI_STAGE_DIR"
  mkdir -p "$WIFI_STAGE_DIR"
  cp "$ko" "$WIFI_STAGE_DIR/"
  {
    echo "RTL8812BU / RTL8822BU external module (TP-Link Archer T3U Plus, USB 2357:0138)"
    echo "source=${RTL88X2BU_REPO}"
    echo "commit=${RTL88X2BU_COMMIT}"
    echo "kernel_release=${kernel_release}"
    echo "signed=${signed}"
    modinfo "$ko" | grep -E '^(filename|vermagic|depends|srcversion|signer|sig_hashalgo):' || true
    echo "has_T3U_Plus_id=$(modinfo -F alias "$ko" | grep -ci 'v2357p0138')"
    echo "size=$(stat -c %s "$ko")"
  } | tee "$proof"
  grep -q 'has_T3U_Plus_id=[1-9]' "$proof" || {
    echo "::error::USB ID 2357:0138 is missing from the module aliases."
    return 1
  }
  echo "$kernel_release" > "$WIFI_STAGE_DIR/kernel_release"
}

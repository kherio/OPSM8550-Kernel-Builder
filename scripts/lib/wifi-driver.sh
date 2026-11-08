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

RTL88X2BU_REPO="https://github.com/morrownr/88x2bu-20210702.git"
RTL88X2BU_COMMIT="418d71cc00cd18b4a671f8c49ecce9b19cbfd3c9"
RTL88X2BU_MODULE_NAME="88x2bu"
WIFI_STAGE_DIR="wifi-module-stage"

export_exact_commit() {
  local repo="$1"
  local commit="$2"
  local dest="$3"
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
  git -C "$scratch" archive HEAD | tar -x -C "$dest"
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
  local wifi_errors

  grep -q '^CONFIG_MODULES=y$' out/.config || { echo "::error::CONFIG_MODULES is off."; return 1; }
  grep -q '^CONFIG_CFG80211=m$' out/.config || {
    echo "::error::CONFIG_CFG80211 is not a module in this kernel; the external Wi-Fi driver cannot bind to the ROM's cfg80211.ko."
    return 1
  }

  export_exact_commit "$RTL88X2BU_REPO" "$RTL88X2BU_COMMIT" "$src" || return 1
  test -f "$src/Makefile" || return 1

  # Full module pass first: it creates the Module.symvers entries (cfg80211
  # and friends) the external module is linked against.
  make -j"$(nproc)" "${MAKE_ARGS[@]}" modules 2>&1 | tee wifi-modules-build.log
  [[ "${PIPESTATUS[0]}" -eq 0 ]] || { echo "::error::make modules failed."; return 1; }

  make -j"$(nproc)" "${MAKE_ARGS[@]}" -C "$PWD" M="$PWD/$src" CONFIG_RTL8822BU=m modules 2>&1 | tee -a wifi-modules-build.log
  if [[ "${PIPESTATUS[0]}" -ne 0 ]]; then
    wifi_errors="$(grep -E ' error:|undefined|No rule to make target|fatal error:|\*\*\* ' wifi-modules-build.log | grep -v 'make modules' | tail -n 10 | cut -c1-320 || true)"
    [[ -n "$wifi_errors" ]] || wifi_errors="$(tail -n 10 wifi-modules-build.log | cut -c1-320)"
    wifi_errors="${wifi_errors//'%'/'%25'}"
    wifi_errors="${wifi_errors//$'\r'/'%0D'}"
    wifi_errors="${wifi_errors//$'\n'/'%0A'}"
    echo "::error title=RTL88x2BU module errors::${wifi_errors}"
    return 1
  fi

  # The driver Makefile only exports CONFIG_RTL8822BU=m in its standalone branch,
  # so it is passed explicitly above; without it kbuild builds nothing.
  ko="$src/${RTL88X2BU_MODULE_NAME}.ko"
  if [[ ! -f "$ko" ]]; then
    echo "::error::${ko} was not produced. Built: $(find "$src" -name '*.ko' | head -n 3 | tr '\n' ' ')"
    return 1
  fi
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

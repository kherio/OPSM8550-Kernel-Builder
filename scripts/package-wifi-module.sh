#!/usr/bin/env bash
#
# Package the staged external Wi-Fi driver as a KernelSU module ZIP and add it
# to the release assets. Does nothing when no driver was staged.
#
set -euo pipefail

: "${SOC:?}"
: "${GITHUB_WORKSPACE:?}"
: "${BUILD_TIMESTAMP:?}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE="${GITHUB_WORKSPACE}/${SOC}/wifi-module-stage"
ASSET_DIR="${GITHUB_WORKSPACE}/release-assets"

if [[ "${WIFI_RTL88X2BU:-0}" != 1 ]]; then
  exit 0
fi
if [[ ! -f "$STAGE/88x2bu.ko" ]]; then
  echo "::warning::Wi-Fi driver was requested but no module was staged; skipping the module ZIP."
  exit 0
fi

KERNEL_RELEASE="$(cat "$STAGE/kernel_release")"
MODULE_ID="nethunter-wifi-rtl88x2bu"
ZIP_NAME="NetHunter-WiFi-RTL88x2BU_${KERNEL_RELEASE}_${BUILD_TIMESTAMP}.zip"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/lib" "$WORK/META-INF/com/google/android"
cp "$STAGE/88x2bu.ko" "$WORK/lib/"
cp "${SCRIPT_DIR}/wifi-module/nh-wifi.sh" "$WORK/nh-wifi.sh"
cp "${SCRIPT_DIR}/wifi-module/README.txt" "$WORK/README.txt"
touch "$WORK/skip_mount"

cat > "$WORK/module.prop" <<EOF_PROP
id=${MODULE_ID}
name=NetHunter Wi-Fi: RTL8812BU (TP-Link Archer T3U Plus)
version=${KERNEL_RELEASE}
versionCode=$(date -u +%Y%m%d)
author=kherio
description=Wi-Fi USB driver (88x2bu) built against kernel ${KERNEL_RELEASE}. Not loaded automatically: run nh-wifi.sh load.
EOF_PROP

# Standard module installer stubs (KernelSU/Magisk read META-INF).
cp "${SCRIPT_DIR}/wifi-module/update-binary" "$WORK/META-INF/com/google/android/update-binary"
echo '#MAGISK' > "$WORK/META-INF/com/google/android/updater-script"
cat > "$WORK/customize.sh" <<'EOF_CUST'
SKIPUNZIP=0
chmod 0755 "$MODPATH/nh-wifi.sh"
ui_print "- Driver 88x2bu installed. Load it with:"
ui_print "  su -c sh /data/adb/modules/nethunter-wifi-rtl88x2bu/nh-wifi.sh load"
EOF_CUST

mkdir -p "$ASSET_DIR"
(cd "$WORK" && zip -r9 "${ASSET_DIR}/${ZIP_NAME}" . -x '.git/*')
zip -T "${ASSET_DIR}/${ZIP_NAME}" > /dev/null
(
  cd "$ASSET_DIR"
  sha256sum "$ZIP_NAME" >> SHA256SUMS
)
echo "[+] Packaged ${ZIP_NAME}"

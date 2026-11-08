#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/kernel-helpers.sh
. "$SCRIPT_DIR/../lib/kernel-helpers.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
export NETHUNTER_CONFIG_DIR="$SCRIPT_DIR/../configs"

for fragment in nethunter-core nethunter-optional; do
  [[ -s "$NETHUNTER_CONFIG_DIR/$fragment.config" ]] || fail "missing fragment $fragment"
  while IFS= read -r line; do
    [[ "$line" =~ ^CONFIG_[A-Z0-9_]+=y$ ]] || fail "$fragment has an invalid line: $line"
  done < <(sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' "$NETHUNTER_CONFIG_DIR/$fragment.config")
done
dupes="$(cat "$NETHUNTER_CONFIG_DIR"/nethunter-*.config | sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' | sort | uniq -d)"
[[ -z "$dupes" ]] || fail "duplicate options across fragments: $dupes"

# Never touch options that change core struct layouts or the ROM's cfg80211.
if grep -Eq 'CONFIG_(SYSVIPC|CFG80211|MAC80211|NETFILTER|NF_)' "$NETHUNTER_CONFIG_DIR"/nethunter-*.config; then
  fail "fragments must not enable SYSVIPC, cfg80211, mac80211 or netfilter options"
fi

# Disabled by default: nothing changes.
printf 'CONFIG_USB_SERIAL=m\n# CONFIG_BT_HCIBTUSB is not set\n' > "$work/off.config"
cp "$work/off.config" "$work/off.expected"
NETHUNTER=0 apply_nethunter_config "$work/off.config"
cmp -s "$work/off.config" "$work/off.expected" || fail "NETHUNTER=0 modified the config"

# Enabled: every key lands as =y, existing values are replaced.
printf 'CONFIG_USB_SERIAL=m\n# CONFIG_BT_HCIBTUSB is not set\nCONFIG_CFG80211=m\n' > "$work/on.config"
NETHUNTER=1 apply_nethunter_config "$work/on.config"
grep -qx 'CONFIG_USB_SERIAL=y' "$work/on.config" || fail "USB_SERIAL not enabled"
grep -qx 'CONFIG_BT_HCIBTUSB=y' "$work/on.config" || fail "BT_HCIBTUSB not enabled"
grep -qx 'CONFIG_USB_CONFIGFS_RNDIS=y' "$work/on.config" || fail "RNDIS not enabled"
grep -qx 'CONFIG_CFG80211=m' "$work/on.config" || fail "cfg80211 was modified"

# Verification: dropped optional options only warn and are recorded.
cp "$work/on.config" "$work/final.config"
sed -i '/^CONFIG_DVB_USB_RTL28XXU=y$/d' "$work/final.config"
NETHUNTER=1 verify_nethunter_config "$work/final.config" "$work/proof.txt" > "$work/out.txt"
grep -qx 'dropped CONFIG_DVB_USB_RTL28XXU' "$work/proof.txt" || fail "dropped option not recorded"
grep -q '::warning::NetHunter optional options dropped' "$work/out.txt" || fail "missing warning for dropped option"

# Verification: a dropped core option fails the build.
sed -i '/^CONFIG_USB_CONFIGFS_RNDIS=y$/d' "$work/final.config"
if (NETHUNTER=1 verify_nethunter_config "$work/final.config" "$work/proof2.txt") > /dev/null 2>&1; then
  fail "dropped core option did not fail verification"
fi

echo "nethunter-config-test: ok"

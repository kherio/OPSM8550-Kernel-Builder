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
if grep -Eq 'CONFIG_(SYSVIPC|CFG80211|MAC80211|CFS_BANDWIDTH|CGROUP_PIDS)' "$NETHUNTER_CONFIG_DIR"/nethunter-*.config; then
  fail "fragments must not enable SYSVIPC, cfg80211, mac80211 or ABI-breaking cgroup options"
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
sed -i '/^CONFIG_USB_HACKRF=y$/d' "$work/final.config"
NETHUNTER=1 verify_nethunter_config "$work/final.config" "$work/proof.txt" > "$work/out.txt"
grep -qx 'dropped CONFIG_USB_HACKRF' "$work/proof.txt" || fail "dropped option not recorded"
grep -q '::warning::NetHunter optional options dropped' "$work/out.txt" || fail "missing warning for dropped option"

# Verification: a dropped core option fails the build.
sed -i '/^CONFIG_USB_CONFIGFS_RNDIS=y$/d' "$work/final.config"
if (NETHUNTER=1 verify_nethunter_config "$work/final.config" "$work/proof2.txt") > /dev/null 2>&1; then
  fail "dropped core option did not fail verification"
fi

# --- Droidspaces ---
export DROIDSPACES_CONFIG_DIR="$NETHUNTER_CONFIG_DIR"
. "$SCRIPT_DIR/../lib/droidspaces-setup.sh"
if sed -e 's/[[:space:]]*#.*$//' "$DROIDSPACES_CONFIG_DIR/droidspaces.config" | grep -Eq 'CONFIG_(CFS_BANDWIDTH|CGROUP_PIDS)'; then
  fail "droidspaces fragment must not enable CFS_BANDWIDTH or CGROUP_PIDS"
fi
printf '# CONFIG_PID_NS is not set\n' > "$work/ds.config"
DROIDSPACES=0 apply_droidspaces_config "$work/ds.config"
grep -qx '# CONFIG_PID_NS is not set' "$work/ds.config" || fail "DROIDSPACES=0 modified the config"
DROIDSPACES=1 apply_droidspaces_config "$work/ds.config"
grep -qx 'CONFIG_PID_NS=y' "$work/ds.config" || fail "PID_NS not enabled"
grep -qx 'CONFIG_SYSVIPC=y' "$work/ds.config" || fail "SYSVIPC not enabled"
DROIDSPACES=1 verify_droidspaces_config "$work/ds.config" "$work/ds-proof.txt" > /dev/null 2>&1 || fail "droidspaces verification failed on a good config"
echo 'CONFIG_CFS_BANDWIDTH=y' >> "$work/ds.config"
if (DROIDSPACES=1 verify_droidspaces_config "$work/ds.config" "$work/ds-proof2.txt") > /dev/null 2>&1; then
  fail "CFS_BANDWIDTH did not fail the kABI guard"
fi


# (patch applicability is checked in CI against the real kernel source)

# --- Baseband-guard ---
. "$SCRIPT_DIR/../lib/bbg-setup.sh"
printf 'CONFIG_LSM="landlock,selinux,bpf"\n' > "$work/bbg.config"
BASEBAND_GUARD=1 apply_bbg_config "$work/bbg.config"
grep -qx 'CONFIG_LSM="landlock,selinux,bpf,baseband_guard"' "$work/bbg.config" || fail "baseband_guard not appended to CONFIG_LSM"
BASEBAND_GUARD=1 apply_bbg_config "$work/bbg.config"
[[ "$(grep -o baseband_guard "$work/bbg.config" | wc -l)" == 1 ]] || fail "baseband_guard appended twice"
grep -qx 'CONFIG_BBG=y' "$work/bbg.config" || fail "BBG not enabled"
grep -qx '# CONFIG_BBG_BLOCK_BOOT is not set' "$work/bbg.config" || fail "BBG_BLOCK_BOOT not off"
printf 'CONFIG_SECURITY=y\n' > "$work/bbg2.config"
BASEBAND_GUARD=1 apply_bbg_config "$work/bbg2.config"
grep -q '^CONFIG_LSM=".*,baseband_guard"$' "$work/bbg2.config" || fail "default CONFIG_LSM not created"
BASEBAND_GUARD=0 apply_bbg_config "$work/bbg3.config" 2>/dev/null || true
[[ ! -e "$work/bbg3.config" ]] || fail "BASEBAND_GUARD=0 touched a config"

echo "nethunter-config-test: ok"

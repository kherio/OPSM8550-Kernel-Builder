#!/system/bin/sh
# Load/unload the RTL8812BU (88x2bu) driver. Run as root.
MODDIR="${0%/*}"
KO="$MODDIR/lib/88x2bu.ko"
NAME=88x2bu

case "$1" in
  load)
    shift
    if grep -q "^$NAME " /proc/modules; then
      echo "$NAME is already loaded."
      exit 0
    fi
    if ! grep -q '^cfg80211 ' /proc/modules; then
      modprobe cfg80211 2>/dev/null
    fi
    if ! grep -q '^cfg80211 ' /proc/modules; then
      echo "cfg80211 is not loaded and could not be loaded. Is the ROM's Wi-Fi stack present?"
      exit 1
    fi
    if [ "$#" -eq 0 ]; then
      set -- rtw_switch_usb_mode=0 rtw_led_ctrl=1
    fi
    insmod "$KO" "$@" || { echo "insmod failed; see: dmesg | tail -n 30"; exit 1; }
    echo "Loaded $NAME. Plug in the adapter, then check: ip link"
    ;;
  unload)
    rmmod "$NAME"
    ;;
  status)
    grep "^$NAME " /proc/modules || echo "$NAME is not loaded."
    ip link 2>/dev/null | grep -E 'wlan|wlx'
    dmesg | grep -iE '88x2bu|rtw_' | tail -n 15
    ;;
  *)
    echo "usage: sh nh-wifi.sh load [module options] | unload | status"
    exit 1
    ;;
esac

NetHunter Wi-Fi: RTL8812BU (TP-Link Archer T3U Plus)

Driver: morrownr/88x2bu-20210702 (cfg80211, monitor mode and injection).
Built against the exact kernel/config in module.prop and signed with its key.
It needs no change to the ROM's mac80211, and nothing loads at boot.

  su -c sh /data/adb/modules/nethunter-wifi-rtl88x2bu/nh-wifi.sh load
  (plug in the adapter)
  su -c sh /data/adb/modules/nethunter-wifi-rtl88x2bu/nh-wifi.sh status
  su -c sh /data/adb/modules/nethunter-wifi-rtl88x2bu/nh-wifi.sh unload

Monitor mode (from the Kali chroot or any shell with iw):
  ip link set wlan1 down
  iw dev wlan1 set type monitor
  ip link set wlan1 up

If insmod fails, send: dmesg | tail -n 30

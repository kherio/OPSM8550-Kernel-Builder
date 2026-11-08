# OnePlus Snapdragon Kernel Builder (with Kali NetHunter support)

GitHub Actions pipeline for building selected OnePlus Snapdragon 7 Gen 3(SM7550),
8 Gen 1(SM8450), 8 Gen 2(SM8550), and 8 Gen 3(SM8650) kernels. The repository contains the build
pipeline, validation, packaging, and release automation; kernel sources are
resolved from upstream repositories at build time.

> **Kali NetHunter kernel.** Set the `nethunter` input to build the kernel with
> everything Kali NetHunter needs from the kernel side (USB gadget, USB serial,
> Bluetooth, USB Ethernet, NFC, CAN, SDR, IP Set), optionally together with
> Baseband-guard, Droidspaces and an external USB Wi-Fi driver module. The
> ZIP and Image names get a `_nethunter` suffix. Validated on the OnePlus 11
> with crDroid, FinaSU + SUSFS + NoMount. See
> [Kali NetHunter kernel: technical reference](#kali-nethunter-kernel-technical-reference).

## Supported build profiles

The workflow exposes only device/source combinations that are intentionally
configured. This avoids late failures caused by selecting an incompatible SoC
and source independently.

| SoC | Target device | AnyKernel accepted device IDs | Source preset |
| --- | --- | --- | --- |
| `sm7550` | OnePlus Nord CE4 | `benz`, `OP5D3FL1`, `CPH2613` | Nord CE4 development |
| `sm7550` | OnePlus Nord CE4 | `benz`, `OP5D3FL1`, `CPH2613` | crDroid (recommended for crDroid) |
| `sm8450` | OnePlus 10 Pro | `negroni`, `OP516EL1`, `OP516FL1` | OnePlus official |
| `sm8450` | OnePlus 10T / Ace Pro | `ovaltine`, `OP5551L1`, `OP5552L1` | LineageOS community |
| `sm8550` | OnePlus 11 | `salami`, `OP591BL1`, `OP594DL1` | OnePlus official |
| `sm8550` | OnePlus 11 | `salami`, `OP591BL1`, `OP594DL1` | LunarisOS |
| `sm8550` | OnePlus 11 / 12R / Ace 3 | OnePlus 11 IDs plus `aston`, `OP5D35L1`, `astonc`, `OP5CF9L1` | LineageOS |
| `sm8550` | OnePlus 11 / 12R / Ace 3 | OnePlus 11 IDs plus `aston`, `OP5D35L1`, `astonc`, `OP5CF9L1` | crDroid |
| `sm8550` | OnePlus 12R / Ace 3 | `aston`, `OP5D35L1`, `astonc`, `OP5CF9L1` | OnePlus 12R development |
| `sm8650` | OnePlus 12 | `waffle`, `OP5929L1`, `OP595DL1` | OnePlus official |
| `sm8650` | OnePlus 12 | `waffle`, `OP5929L1`, `OP595DL1` | LineageOS |
| `sm8650` | OnePlus 12 | `waffle`, `OP5929L1`, `OP595DL1` | crDroid |

The OnePlus 10T community source is intentionally labeled `ovaltine`; it is
not presented as a OnePlus 10 Pro source.

The Nord CE4 source projects store their SM7550/crow device support in
`sm8550`-named kernel and modules repositories and build it with the Kalama
GKI fragments plus the benz-specific `CONFIG_OPLUS_DEVICE_DTBS=y` and
`CONFIG_BENZ_DTB=y` make flags. The profiles keep the real `sm7550` device
identity in release metadata while resolving that upstream naming explicitly.
Use the dedicated crDroid profile on crDroid: it resolves crDroid's own
kernel and modules instead of the unrelated development/Lineage branch, which
is not ABI-compatible with crDroid's first-stage vendor modules.

The OnePlus 12 LineageOS and crDroid profiles also reproduce both device-tree
make assignments, `CONFIG_OPLUS_DEVICE_DTBS=y` from the shared SM8650
BoardConfig and `CONFIG_WAFFLE_DTB=y` from the waffle BoardConfig, on every
make invocation and record them in build provenance. Command-line Kbuild
assignments are not expected to be written back to `.config`; keeping them on
the make command line matches how the ROM builds its kernel and external
modules.

The OnePlus 12 crDroid profile has an optional **ROM GKI module compatibility**
mode for a boot-only custom Image. A custom Image generates a new module signing
key, while the installed ROM keeps its `system_dlkm` GKI modules. On affected
builds, `rfkill.ko` is rejected with `exports protected symbol rfkill_alloc`,
which prevents the dependent `qca_cld3_kiwi_v2` Wi-Fi driver from loading.
Selecting `Use existing ROM system_dlkm modules (experimental)` disables
`CONFIG_MODULE_SIG_PROTECT` for that build while retaining module signature
parsing and module version checks. It allows modules whose signature cannot be
verified with this Image's newly generated key, so only use it with ROM modules
you trust. This can let the existing ROM modules load, but it reduces GKI
protected-symbol enforcement and does not guarantee
compatibility if module CRCs or firmware differ. The default remains strict.
The chosen mode is recorded in `build-info.json` and in the ZIP filename.
The OnePlus 12 crDroid flashable ZIP also replaces AnyKernel's 32-bit ARM
BusyBox and MagiskBoot with pinned arm64 versions from Magisk 30.7. The device
reports `arm64-v8a` and cannot execute the old 32-bit MagiskBoot; the package
verifies both binary checksums and ELF architecture before creating the ZIP.

The LunarisOS OnePlus 11 profile follows the kernel source published in the
LunarisOS OTA metadata. Its maintainer kernel uses `lineage-23.2`, while its
matching external modules use the `los` branch; the resolver pins both branches
independently and records both exact commits in the build provenance.

Every package accepts both its custom-ROM codename and the device-specific
stock board IDs published by the corresponding device tree. Generic SoC board
names such as `taro`, `kalama`, and `pineapple` are deliberately excluded so a
package cannot pass the check merely because another phone shares its chipset.
The check remains enabled, and a rejected flash prints all four device values
reported to AnyKernel so a genuinely missing regional alias can be diagnosed
safely.

## Build modes

`Build OnePlus Kernel` offers three modes:

- `Patch/config validation only` clones exact upstream revisions, applies the
  selected KernelSU/KPM/SUSFS/NoMount/ZeroMount integration, verifies the final
  config, and smoke-compiles the affected KPM, SUSFS, VFS, proc, reboot,
  NoMount, and ZeroMount objects without spending time on a full kernel compile.
- `Full build (artifact only)` builds and uploads a 14-day workflow artifact.
  This is the default and does not create a permanent GitHub Release.
- `Full build and publish release` first reserves an immutable tag at the
  workflow commit, builds the same verified artifact, then a separate
  least-privilege job publishes the release from that tag.

Full builds preserve the upstream/vendor ABI-sensitive configuration instead of
forcing debugging, symbol-export, or spinlock options. The pipeline also pins
the kernel release suffix to the exact source commit (for example,
`-g0d516eb3375f`) and verifies that release in the final `Image` banner. This
keeps the kernel vermagic aligned with the ROM's vendor modules while the
selected root preset changes only its required feature options.

## crDroid 13 (Android 17)

The existing crDroid profiles cover Nord CE4, OnePlus 11 / 12R / Ace 3, and
OnePlus 12 on crDroid 13. Automatic branch selection follows the upstream
default, currently `17.0`, for both the kernel and matching modules. Manual
selection also offers `17.0`; retain `16.0` for crDroid 12 / Android 16.
[crDroid 13 is based on Android 17](https://crdroid.net/blog/2026-09-28-crDroid-13-BETA-source-is-now-pushed/),
so the ROM major version `13` must not be confused with the Android branch
`13.0`.

Android 17 branches select the pinned AOSP `clang-r584948` toolchain to match
[crDroid's compiler default](https://github.com/crdroidandroid/android_build_soong/blob/17.0/cc/config/global.go).
Flashable ZIPs enforce `supported.versions=17`. SUSFS and ZeroMount still use
the devices' GKI kernel families: Android 14 / 5.15 for Nord CE4 and OnePlus
11 / 12R / Ace 3, and Android 14 / 6.1 for OnePlus 12. The ROM Android version
does not change those kernel-base mappings.

The OnePlus 11 / 12R crDroid profile passes the common OPlus DTB flag and both
the Salami and Aston device flags on every make invocation, matching the
upstream device configurations for the shared kernel image.

## Root integrations

Available workflow presets:

| Preset | Integration | Status |
| --- | --- | --- |
| `No root changes` | No root integration | Baseline |
| `Official KernelSU` | Official KernelSU | Supported |
| `KernelSU-Next` | KernelSU-Next | Supported |
| `KernelSU-Next + SUSFS` | KernelSU-Next with SUSFS | Supported |
| `KernelSU-Next + SUSFS + NoMount (experimental)` | KernelSU-Next with SUSFS and NoMount | Experimental |
| `KernelSU-Next + SUSFS + ZeroMount (experimental)` | KernelSU-Next with SUSFS and ZeroMount | Experimental |
| `KowSU` | KowSU | Supported |
| `FinaSU (experimental)` | FinaSU, built into the kernel | Experimental |
| `FinaSU + SUSFS (experimental)` | FinaSU with SUSFS (Tracepoint hook backend) | Experimental |
| `FinaSU + SUSFS + NoMount (experimental)` | FinaSU with SUSFS and FinaSU's NoMount VFS driver built in | Experimental |
| `SukiSU Ultra + KPM (experimental)` | SukiSU Ultra with KPM | Experimental |
| `SukiSU Ultra + SUSFS + KPM (experimental)` | SukiSU Ultra with SUSFS and KPM | Experimental |
| `SukiSU Ultra + SUSFS + ZeroMount + KPM (experimental)` | SukiSU Ultra with SUSFS, ZeroMount, and KPM | Experimental |
| `SukiSU Ultra + SUSFS + NoMount + KPM (experimental)` | SukiSU Ultra with SUSFS, NoMount, and KPM | Experimental |
| `BakaSU` | BakaSU | Supported |
| `BakaSU + SUSFS` | BakaSU with SUSFS | Supported |
| `BakaSU + SUSFS + ZeroMount (experimental)` | BakaSU with SUSFS and ZeroMount | Experimental |
| `BakaSU + SUSFS + NoMount (experimental)` | BakaSU with SUSFS and NoMount | Experimental |

FinaSU is fetched from [`LyraVoid/FinaSU`](https://github.com/LyraVoid/FinaSU)
at an exact commit resolved from `master`. Select `FinaSU (experimental)` in
the root dropdown and use the matching FinaSU manager. This preset enables
the driver's KPROBES/EXT4 dependencies, `CONFIG_KALLSYMS_ALL` for runtime data
symbol lookup, and manager support. It pins the official
v1.2.1 manager's signing certificate (`2d89b50a…5d448458`, 716 bytes) in the
release signature slot, as required by FinaSU's upstream release workflow.
Both post-build verification and packaging check that the final Image contains
this certificate hash; `build-info.json` records it. A build using only the
upstream default certificate can boot but reject FinaSU Manager as not installed.
The plain
`FinaSU (experimental)` preset has SUSFS, KPM, and the builder's
NoMount/ZeroMount integrations disabled; FinaSU's own manager/userspace
features remain managed by FinaSU. The optional
preinit runner follows upstream's header availability check. Upstream-health
includes driver object smoke builds on representative 5.10, 5.15, and 6.1
profiles. Full kernel compilation and device boot still need validation before
this preset can be considered stable.

`FinaSU + SUSFS (experimental)` adds only the kernel-side SUSFS patch set
(FinaSU already ships its own SUSFS layer, controlled through `ksud susfs`),
keeps FinaSU's default Tracepoint hook backend (`CONFIG_KSU_HOOK_TRACEPOINT=y`,
`CONFIG_KSU_HOOK_SUSFS_INLINE` off), and uses the pinned SUSFS v2.3.0 revision.
The final config is checked for `SUS_MAP` and `OPEN_REDIRECT`.

`FinaSU + SUSFS + NoMount (experimental)` additionally builds NoMount into the
kernel (`CONFIG_NOMOUNT=y`, `CONFIG_KEYS=y`). Unlike the other NoMount presets it
does not take upstream `master`: it wires in the copy of the NoMount driver
vendored inside the pinned FinaSU checkout (`userspace/nomount/kernel/src`),
because FinaSU's `ksud` only speaks the protocol version that copy implements.
The build verifies the source wiring and the final config. To use it, open the
FinaSU manager -> Settings -> Features -> Folk Mount, set the mode to
`Built-in (VFS)`, and reboot; the NoMount page should then report the driver as
Ready with all rules active. NoMount's default visibility is the opposite of
Magic Mount's: every app sees injected files unless it is added to the NoMount
exception list, so configure that list before switching modes. If a NoMount
boot never completes, FinaSU falls back to its built-in mount engine on the
next boot and records the reason in `/data/adb/ksu/log/mount.log`.

BakaSU (formerly ReSukiSU) is fetched from
[`Baka-SU/BakaSU`](https://github.com/Baka-SU/BakaSU) at an exact commit (resolved from `main` without SUSFS, or pinned for SUSFS).
Legacy ReSukiSU preset inputs remain accepted and resolve to the matching
BakaSU integration; package names and provenance use `BakaSU`.

Selecting `Build all 3 featured SUSFS variants (batch)` starts a three-entry
matrix in which all three SUSFS integrations also include NoMount. Selecting
`Build all 3 ZeroMount variants (batch)` instead builds `SukiSU Ultra + SUSFS +
ZeroMount + KPM`, `BakaSU + SUSFS + ZeroMount`, and
`KernelSU-Next + SUSFS + ZeroMount`.
Each entry keeps its own package and diagnostics artifact; release mode publishes
all three builds under the same immutable release tag.

KPM is available only through the dedicated SukiSU Ultra presets because current
BakaSU no longer supports it. The pipeline resolves SukiSU Ultra to an exact
`main` commit for KPM-only builds, checks its KPM sources and Kbuild wiring,
and enables `CONFIG_KPM`, `CONFIG_KALLSYMS`, and `CONFIG_KALLSYMS_ALL`.
The SUSFS presets pin SukiSU Ultra to
`7fbbb1f12e2410b69c8ebf958be84f165b8d0c93`, which passed a full
SUSFS/NoMount/KPM build, and use the matching SUSFS v2.3.0 pins described
below. Newer SukiSU `main` revisions changed the hook ABI
and require a new compatibility patch before this pin can be advanced. The four-feature
preset also resolves NoMount at an exact commit and enables `CONFIG_KEYS` and
`CONFIG_NOMOUNT`. Validation mode compiles the KPM, SUSFS, VFS, and NoMount
integration objects and checks their exported signatures; a full build repeats
the signature checks against the final kernel artifacts. Both paths fail closed
when expected wiring, config, objects, or symbols are missing. KPM resolver
verification uses AOSP Clang's LTO-aware `llvm-nm` on the compiled resolver
object instead of GNU `nm` on the aggregate LTO intermediate.
Full KPM builds also inject the implementation into the final `Image` with
SukiSU KernelPatch **0.13.9**. Both `kptools-linux` and `kpimg` are SHA-256
pinned. The build requires a changed Image and `patched=true` from the image
inspector; packaging checks the resulting Image hash against
`kpm-image-proof.txt`. `CONFIG_KPM=y` and loader symbols alone only establish
the hook stubs, not a working KPM implementation. Validation-only builds do
not perform this final Image injection.

BakaSU SUSFS presets pin `fa8311f632a215b5381ec644627c6198d1e8a13e`,
which passed a full batch build on September 27. Its latest `main` suspends
SUSFS builds pending upstream SELinux hook updates; this pin must be revisited
when those updates land. BakaSU without SUSFS continues to follow `main`.
BakaSU SUSFS presets also pin the matching SUSFS v2.3.0 revision for each GKI
branch, using the same su-session ABI map as SukiSU Ultra. These pins include
upstream fixes through September 15, 2026 for the enabled-features NULL
dereference, CTIME spoof bit, and `super.c` declaration placement. The version
string remains v2.3.0. Following the latest SUSFS branch with this older driver
can introduce undefined preinit and SELinux
hook symbols at the final kernel link.

The pinned drivers originally exposed UAPI 4, which causes `Kernel update
required` with BakaSU UAPI 5 and SukiSU UAPI 6 managers even when the kernel
build succeeds. The pipeline now backports the actual interfaces:

- BakaSU SUSFS: UAPI **5**, including the service-stage start/skip result and
  reset for an emulated soft reboot, from upstream commit `8770c7e3`.
- SukiSU SUSFS: UAPI **6**, including the same service-stage handling,
  root-only batch symbol lookup, and `/metadata/vold/ksu/modules.rc` support,
  from upstream commits `7ef2dbb7` and `3b607917`. The optional preinit runner
  is disabled and its capability flag stays clear. The older KPM interfaces
  are retained. The extension-hub ioctl also bridges KPM discovery/control and
  SuSFS discovery to the pinned implementations. CPU spoof, umount paths, and
  dynamic-manager hub operations remain unsupported by this bridge.

Backports apply only to the exact tested driver commits; unknown patch drift
fails the build. `build-info.json` and release notes record the resulting UAPI
and patch SHA-256. The pinned BakaSU driver's full name can still contain
ReSukiSU; its interface suffix should now be `/5`. SukiSU should show UAPI 6.
Older downloaded ZIPs still contain UAPI 4 and must be replaced by a new build;
updating the manager alone does not update an embedded kernel driver.
Device boot, root grants, and module installation require device testing after
flashing the device/ROM-matched package.

If the home screen reports SuSFS v2.3.0 but the **Extension features** page
reports no support, the running driver may have UAPI 6 without the extension
hub bridge. For example, release `kernel-build-39906179867-1` contains this
older backport and an unpatched KPM Image. Rebuild with the updated pipeline
and flash the device/ROM-matched ZIP, then reboot. Updating the manager or
reinstalling modules cannot add these kernel interfaces. Current managers
also perform live KPM-version and SuSFS-version probes before displaying
support; the bridge does not override those checks.

Patch/config validation uses the runner's distribution Clang, LLD, and LLVM
binutils; full builds use the selected pinned AOSP toolchain.

The three ZeroMount presets fetch the version-matched VFS patch from a pinned
Super-Builders commit, verify a per-GKI SHA-256, and apply it only after SUSFS.
The pipeline verifies the `getname()` and directory-entry hooks, requires
`CONFIG_ZEROMOUNT=y`, and checks the compiled driver. ZeroMount and NoMount are
kept in separate presets because both implement VFS path redirection and are not
safe to stack without device-specific runtime testing.

SUSFS branches are selected from the SoC and Android/kernel branch. Known vendor
include drift and the current SukiSU Ultra UTS-spoof, KPM resolver, kernel-umount,
and allowlist drift are repaired only for explicitly recognized conflicts. The
compatibility checks keep the KPM symbol resolver linked and initialized and
preserve SukiSU's WebView zygote policy after the SUSFS patch. Unknown patch
rejects fail closed and are included in diagnostics.

The KernelSU-Next + SUSFS presets, including the NoMount and ZeroMount variants,
resolve `pershoot/KernelSU-Next@dev-susfs` to an exact commit. The regular
KernelSU-Next preset remains on the official
`KernelSU-Next/KernelSU-Next@dev` branch. The compatibility branch is required
because the SUSFS KernelSU-side patch does not apply to the current official
development tree; the pipeline still takes the kernel-side SUSFS files and
patch from `simonpunk/susfs4ksu` at an exact commit.

SUSFS builds require upstream v2.3.0 or newer and explicitly verify the
`SUS_MAP` and `OPEN_REDIRECT` features in the final config. The NoMount presets
integrate the exact resolved `master` commit, enable `CONFIG_NOMOUNT=y`, and
checks both source wiring and final kernel signatures. NoMount hooks VFS
operations and is marked experimental by its upstream project, so it remains
an explicit opt-in instead of changing existing build presets.
SukiSU Ultra SUSFS presets also enable and verify
`CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS`, which filters KernelSU and SUSFS
names from `/proc/kallsyms`.

## Optional kernel features

These workflow inputs are off by default, so existing presets build exactly as
before. Each one is recorded in the run summary and in the diagnostics artifact.

| Input | Options | Effect |
| --- | --- | --- |
| `susfs_logging` | `Keep SUSFS logging (default)` / `Disable SUSFS logging` | SUSFS builds only. The disabled option clears `CONFIG_KSU_SUSFS_ENABLE_LOG` and the build verifies it. |
| `tcp_congestion` | `Keep stock TCP congestion control (default)` / `Enable BBR as default (experimental)` | Builds `CONFIG_TCP_CONG_BBR=y` and `CONFIG_NET_SCH_FQ=y` and makes BBR the default congestion control (`CONFIG_DEFAULT_TCP_CONG="bbr"`). The default queue discipline is not changed. The build fails if the final `.config` does not end up with BBR as the default. Check on the device with `cat /proc/sys/net/ipv4/tcp_congestion_control`. |
| `root_hiding_fixes` | `Keep stock kernel code (default)` / `Apply ptrace + Unicode fixes (experimental)` | Applies two patches from [`WildKernels/kernel_patches`](https://github.com/WildKernels/kernel_patches), vendored in `scripts/patches/`: a ptrace message leak fix for kernels older than 5.16 (`gki_ptrace.patch`) and a Unicode normalisation path-bypass fix (`unicode_bypass_fix.patch`). Both target root-detection leaks. The build stops if either patch does not apply or is not present afterwards. |
| `nethunter`         | `Keep stock kernel config (default)` / `Add NetHunter USB/Bluetooth/NFC/CAN/SDR support (experimental)` | Builds in the options listed in `scripts/configs/nethunter-core.config` (USB gadget RNDIS/OBEX/ECM subset, USB serial, USB Bluetooth; the build fails if any is dropped) and `scripts/configs/nethunter-optional.config` (USB serial/Bluetooth/Ethernet adapters, PN533 NFC, CAN, RTL-SDR; Kconfig may drop these and the build only reports it). The result is written to `nethunter-proof.txt` in the diagnostics artifact. See the NetHunter notes below. |
| `baseband_guard`    | `Off (default)` / `Enable Baseband-guard LSM (experimental)` | Integrates [Baseband-guard](https://github.com/vc-teahouse/Baseband-guard) at a pinned commit as a built-in LSM (`CONFIG_BBG=y`, `baseband_guard` appended to `CONFIG_LSM`). Boot/recovery protection is left off so the kernel can still be flashed from Android. Proof: `bbg-proof.txt`, `bbg-source-proof.txt`. |
| `droidspaces`       | `Off (default)` / `Enable Droidspaces support with kABI patch (experimental)` | Applies the Droidspaces-OSS GKI patch that moves `sysvsem`/`sysvshm` into `task_struct`'s `ANDROID_KABI_RESERVE(6..8)` padding (the build fails if those slots are not free), then enables the ABI-safe options in `scripts/configs/droidspaces.config`. `CONFIG_CFS_BANDWIDTH` and `CONFIG_CGROUP_PIDS` are never enabled and the build fails if they end up on, because they change the kABI. Proof: `droidspaces-proof.txt`, `droidspaces-source-proof.txt`. |
| `wifi_driver`       | `Off (default)` / `Build RTL8812BU module for TP-Link Archer T3U Plus (separate KernelSU module ZIP)` | After the `Image`, builds the morrownr `88x2bu` driver (pinned commit, USB 2357:0138, cfg80211 only, monitor mode) as an external module against the same tree and signs it with the kernel's key. Output is `NetHunter-WiFi-RTL88x2BU_<kernel>_<timestamp>.zip` in the release assets, a KernelSU module that loads nothing at boot (`nh-wifi.sh load`). A failure here only warns; the kernel is still produced. Proof: `wifi-driver-proof.txt`. |

### NetHunter notes

Setting `nethunter` builds everything NetHunter needs from the kernel into the `Image`. Pair it with the Kali chroot and the NetHunter app (userspace, root only). The ZIP and Image names get a `_nethunter` suffix so these builds are easy to tell apart from the rest.

What the option includes (all built in, none of it touches the ROM's modules):

| Area | Options |
| --- | --- |
| USB gadget | RNDIS, OBEX and ECM subset (configfs, HID, ACM, ECM, NCM, EEM and mass storage are already built in on the crDroid SM8550 source, so HID attacks need no kernel change) |
| USB serial | generic, FTDI, CP210x, CH341, PL2303 |
| Bluetooth | USB dongles (generic, Broadcom, Realtek, MediaTek) and virtual HCI |
| USB Ethernet | CDC Ethernet/NCM/subset, RNDIS host, AX88xxx, SMSC95xx, DM9601, MCS7830 |
| NFC | NFC digital, PN533 (USB) |
| CAN | CAN core, raw/BCM/GW/J1939/ISO-TP, vcan, SLCAN, C_CAN, M_CAN, MCP251X and the USB adapters (gs_usb, 8devices, EMS, ESD, Kvaser, PEAK, UCAN, MCBA, ETAS, F81604) |
| SDR | Airspy and HackRF |
| Firewall | IP Set (all set types) and `xt_set` |

The "core" options must stay enabled or the build fails; the "optional" ones are reported as kept or dropped in `nethunter-proof.txt`.

- **Wi-Fi:** `CFG80211` and `MAC80211` are modules on these kernels, so USB Wi-Fi drivers can only be modules as well. The kernel build does not put them in the `Image`. The `wifi_driver` input builds one as a separate KernelSU module ZIP against the exact running kernel (currently the RTL8812BU of the TP-Link Archer T3U Plus). Monitor mode on the internal Qualcomm chip needs a patched vendor driver; no kernel option provides it.
- **Droidspaces and SYSVIPC:** `CONFIG_SYSVIPC`, cgroup controllers and netfilter changes alter core structure layouts and break the ROM's modules. They are never enabled by `nethunter`; the `droidspaces` input handles SYSVIPC through its own kABI patch.
- The Kali chroot, NetHunter app and USB Arsenal are userspace. HID is enabled from userspace.

## Kali NetHunter kernel: technical reference

### Design rule: keep the ROM's modules loading

The pipeline builds only the GKI `Image`. The ROM keeps its own `vendor_dlkm`
and `system_dlkm` modules, which were linked against exported-symbol CRCs
(`CONFIG_MODVERSIONS=y`) and a fixed `vermagic`. Anything that changes a
structure layout seen by those modules changes the CRCs and the device
bootloops or loses hardware. So every feature below is either:

- **built in and layout-neutral** (drivers whose objects live only in the `Image`),
- **made layout-neutral by a patch** (Droidspaces/SYSVIPC), or
- **kept out of the `Image`** (Wi-Fi drivers, shipped as a separate module).

The kernel release string is copied from the ROM kernel on purpose, so
`uname -r` and the build date match the stock kernel.

### What each input changes

| Input | Mechanism | ABI effect |
| --- | --- | --- |
| `nethunter` | Config fragments `scripts/configs/nethunter-core.config` (build fails if dropped) and `nethunter-optional.config` (reported as kept or dropped), applied before `olddefconfig`, then checked in `verify_nethunter_config` | None: only driver and protocol code |
| `baseband_guard` | Pinned export (no `.git`) of Baseband-guard linked into `security/`, `CONFIG_BBG=y`, `baseband_guard` appended to `CONFIG_LSM`, boot/recovery blocking off | None: stackable LSM, no fields added to core structs |
| `droidspaces` | Vendored Droidspaces-OSS patch moves `sysvsem`/`sysvshm` into `task_struct`'s `ANDROID_KABI_RESERVE(6..8)` slots; then `scripts/configs/droidspaces.config` | Size and offsets of `task_struct` unchanged. The build fails if the slots are not free, if the patch does not apply, or if `CFS_BANDWIDTH` or `CGROUP_PIDS` end up enabled |
| `wifi_driver` | External module built against the finished tree and signed with the kernel's own key | None: nothing is linked into the `Image` |

Proof files in the diagnostics artifact: `nethunter-proof.txt`, `bbg-proof.txt`,
`bbg-source-proof.txt`, `droidspaces-proof.txt`, `droidspaces-source-proof.txt`,
`wifi-driver-proof.txt`.

### Root stack used with it

FinaSU carries its own KernelSU and SUSFS layer, so two things are special
for it (both in `scripts/`):

- SUSFS is pinned to the commit `ffa69590787d097f54cb60ed79fa6fd5e285bb41`
  (`gki-android14-5.15`). Newer SUSFS kernel patches need `susfs_security_*`
  hooks and `SUSFS_LOGI_RL` stubs that FinaSU does not have.
- The kernel-side SUSFS patch references `fake_state` in `security/selinux`,
  which FinaSU's own `selinux_hide.c` does not define. The pipeline adds only
  that missing symbol so `vmlinux` links.

### Build order (`scripts/compile-kernel.sh`)

1. Install the root solution, SUSFS, UAPI backports and NoMount.
2. Root-hiding fixes (`ptrace`, Unicode) when enabled.
3. `droidspaces`: slot pre-check, patch, post-check on `include/linux/sched.h`.
4. `baseband_guard`: export, symlink, Makefile and Kconfig entries.
5. Config: `gki_defconfig` plus device fragments, the NetHunter / Droidspaces / BBG options, `make olddefconfig`, then the required-option and ABI-guard checks.
6. Integration smoke compile (includes `security/baseband-guard/`), then the full `Image`.
7. Release-identity verification, then the AnyKernel3 ZIP.
8. `wifi_driver` (optional): `make modules`, external module build, vermagic check, signature with the kernel key, KernelSU module ZIP. A failure here only warns.

### Wi-Fi USB driver (TP-Link Archer T3U Plus)

- Chip: RTL8812BU/8822BU, USB `2357:0138`. Driver: `morrownr/88x2bu-20210702`, pinned commit, `cfg80211` only (monitor mode and injection supported), no firmware files needed.
- Why not `rtw88`: it needs `mac80211` with LED support, which the OnePlus `mac80211.ko` lacks; that would mean replacing `mac80211` at runtime.
- The module ZIP is a KernelSU module that loads nothing at boot. Use `su -c sh /data/adb/modules/nethunter-wifi-rtl88x2bu/nh-wifi.sh load|status|unload`.
- Verified at build time: `vermagic` equals the kernel release, USB ID present in the module aliases, module signed with the kernel key when available.

### Checking a flashed kernel

```sh
cat /sys/kernel/security/lsm                    # contains baseband_guard
cat /proc/sys/net/ipv4/tcp_congestion_control   # bbr
ls /proc/sysvipc                                # msg sem shm (Droidspaces)
ip link add vcan0 type vcan && ip link set vcan0 up   # CAN stack
```

### Known limits

- Built-in options Kconfig drops are listed in `nethunter-proof.txt` (for example `CAN_ESD_USB2` and `CAN_F81604` on the crDroid source).
- Wi-Fi support is per adapter. `mac80211` LED triggers, Minstrel, `ath9k`, `ath10k`, `mt76` and out-of-tree `rtw88` need replacing the ROM's `mac80211` at runtime and are not provided yet.
- Monitor mode on the internal Qualcomm Wi-Fi needs a patched vendor driver; no kernel option provides it.
- The NetHunter app is old; the Kali chroot and Droidspaces are the more reliable paths on recent Android.
- Always keep a stock `boot` image available when flashing.

## Quick start

1. Open `Actions` -> `Build OnePlus Kernel` -> `Run workflow`.
2. Select one device/source profile.
3. Keep automatic branch and Clang selection unless testing a known branch.
4. Select the root integration.
5. Start with `Patch/config validation only` after an upstream update, then run
   a full build when validation passes.
6. Use release mode only for an artifact you intend to keep or distribute.

Manually selected branch names are validated with Git before they are written
to GitHub Actions environment files. Every kernel, modules, root implementation,
SUSFS, NoMount, ZeroMount patches, and AnyKernel input are resolved to exact
commits before cloning.

The manual branch menu is shared across sources: selecting LineageOS does not
make branches such as `seventeen` or crDroid's `17.0` valid for that repository.
Use automatic branch selection, or select an existing `lineage-*` branch that
matches the installed ROM. Missing branches fail immediately with a source URL
and a selection hint, before optional root or patch dependencies are queried.

## Build performance

The full build passes `CC="ccache clang"` and host compiler wrappers directly
on every `make` invocation so Kbuild cannot replace the ccache launcher.
Build timestamps, user, and host metadata are deterministic for a given kernel
commit, which improves repeat-build cache hits.

The workflow also:

- clones kernel and modules repositories in parallel at exact commits
- caches the exact pinned AOSP Clang archive
- restores a profile/branch/compiler-specific 3 GB compressed ccache
- reports config, compile, total time, and ccache statistics in the job summary
- reclaims unused hosted runner SDKs and creates up to 32 GB of swap for Full LTO
- records memory, disk, and linker resource usage during full builds

GitHub cache entries are an optimization only. A build remains able to download
or regenerate every cached input.
Each run saves a fresh ccache snapshot while restoring earlier matching runs,
so an empty cache from an early failure cannot prevent later builds from saving
their compiled objects.

## Safe packaging and provenance

Generated AnyKernel3 ZIPs enable `do.devicecheck=1` and contain only the
device-specific codenames and stock board IDs assigned to the selected profile.
Android version checking is also enabled when the selected branch identifies a
known Android generation. The installer targets the current active `boot`
partition by name, refuses to continue unless the resolved `boot_a`/`boot_b`
path matches that slot, splits and rebuilds the boot image without unpacking
its ramdisk, and replaces only the kernel Image. Slot detection uses the boot
properties, `/proc/cmdline`, and `/proc/bootconfig`, supporting recoveries that
do not publish `ro.boot.slot_suffix`. Missing or invalid slot metadata still
aborts installation without writing a partition. This supports newer devices such as OnePlus 11,
where the first-stage ramdisk lives in `init_boot` and `boot` legitimately has
no ramdisk, while preserving a boot ramdisk when one is present. Upstream
AnyKernel example-device paths and demo ramdisk edits are not included. KPM
packages replace AnyKernel's legacy 32-bit ARM BusyBox and
MagiskBoot with verified AArch64 builds. BusyBox comes from the exact SukiSU
source revision used by the build; MagiskBoot comes from a pinned official
Magisk APK with both archive and extracted-binary SHA-256 verification. On
arm64-only SoCs such as the Snapdragon 8 Gen 3 in OnePlus 12, the installer
also discards the manager app's incompatible ARM32 `mkbootfs` injection and
uses BusyBox `cpio` instead. Other unused ARM32 AnyKernel partition utilities
are removed, and packaging fails if any remaining native runtime tool is not
ELF64/AArch64.

Each full build produces `release-assets/` containing:

- a device-checked AnyKernel3 ZIP
- a uniquely named raw `Image`
- `build-info.json` with all exact source commits, the KPM enabled state, and
  the workflow run URL
- `SHA256SUMS`
- generated `release-notes.md`

GitHub Actions uploads these release-ready files as one flat package artifact.
Build logs and configuration are kept in a separate diagnostics artifact,
along with `kpm-source-proof.txt` and `kpm-proof.txt` when KPM is selected (and
equivalent SUSFS/NoMount proofs for those presets). The release job downloads
only the package artifact and verifies its checksums before publishing.

The same `build-info.json` is embedded in the flashable ZIP. Keep a known-good
stock boot image available and never flash a package whose device check does
not match the phone.

## CI security and reliability

The tag-reservation job has `contents: write` but checks out and executes no
repository or external source. The build job keeps read-only repository
permissions and does not persist checkout credentials, so external kernel
Makefiles never run with release write credentials. After a successful build,
the separate publication job receives `contents: write`, verifies the reserved
tag and artifact checksums, and creates the Release. A failed build removes its
unused reserved tag automatically.

Network Git operations use bounded retries. Release creation and asset uploads
are idempotent, time-limited, and retried, preventing a stalled upload from
holding the build runner indefinitely.

All third-party GitHub Actions are pinned to full commit hashes. AOSP Clang
archive URLs are pinned to exact Gitiles commits, and changing the downloader
invalidates the toolchain cache.
The downloader validates gzip integrity, archive extraction, and required tools
before installing the toolchain. Truncated HTTP-success responses trigger a
fresh download, with at most five attempts; partial extractions cannot become
the cached toolchain.

## Validation and upstream health

Pushes and pull requests run:

- Bash syntax checks
- ShellCheck at warning severity
- offline tests for all twelve profile mappings, root mappings (including the
  three ZeroMount variants), Clang selection, KPM configuration, SUSFS
  selection/version floor, NoMount/ZeroMount selection and wiring,
  Android version inference, and workflow option synchronization
- actionlint for all workflow files

`Check upstream health` runs every Monday and can also be started manually. It
resolves exact commits for all twelve profiles, then runs a thirty-job
smoke-test matrix: KernelSU-Next + SUSFS + NoMount, SukiSU Ultra + SUSFS +
NoMount + KPM
(including the crDroid OnePlus 12 / Android 6.1 vendor include drift),
and BakaSU + SUSFS + NoMount are validated on representative SM7550 (including
both CE4 source families), SM8450, SM8550 (including crDroid), and SM8650
sources, with an additional
baseline validation for the LunarisOS OnePlus 11 and crDroid OnePlus 12 sources.
The SukiSU Ultra ZeroMount preset is validated across the representative
5.10, 5.15, and 6.1 source families; the KernelSU-Next and BakaSU ZeroMount
presets additionally run against the representative SM8550 LineageOS source.
BakaSU ZeroMount also runs against the SM8550 crDroid source.

## Important limitations

- A successful build does not prove that a kernel is safe for every firmware,
  region, or boot stack of the listed device.
- Community sources are not official OnePlus sources.
- Manual or unusual branches may disable Android version checking when their
  version cannot be inferred safely.
- This pipeline builds the raw GKI `Image`; it does not rebuild every vendor
  module or replace device-specific firmware.
- NoMount and ZeroMount modify VFS behavior and their upstreams label them
  experimental. Test their opt-in presets on a recoverable device before
  distributing them.
- KPM dynamically patches kernel behavior at runtime. Treat all SukiSU Ultra
  presets as experimental and test them only on a recoverable device.
- Runtime performance tuning is intentionally left at upstream/vendor config
  defaults. Options such as KASAN, LTO mode, scheduler changes, and compiler
  optimization flags require device-specific boot, stability, power, and
  benchmark testing before becoming defaults.

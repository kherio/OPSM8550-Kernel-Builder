#!/usr/bin/env bash
#
# Pure build-profile mappings shared by the resolver and its offline tests.
# This file performs no network or filesystem operations.
#
# Functions intentionally populate globals consumed by the sourcing script.
# shellcheck disable=SC2034

list_build_profiles() {
  printf '%s\n' \
    "SM8550 | OnePlus 11 | OnePlus official" \
    "SM8550 | OnePlus 11 | LunarisOS" \
    "SM8550 | OnePlus 11 / 12R | LineageOS (recommended)" \
    "SM8550 | OnePlus 11 / 12R | crDroid"
}

resolve_build_profile() {
  local profile="$1"

  # Most profiles use the conventional android_kernel_* repository names and
  # the same branch for the kernel and modules. Source-specific profiles can
  # override those defaults without complicating the common resolver path.
  KERNEL_REPO_OVERRIDE=""
  MODULES_REPO_OVERRIDE=""
  MODULES_BRANCH_OVERRIDE=""
  KERNEL_MAKE_FLAGS=""

  case "$profile" in
    "SM8550 | OnePlus 11 | OnePlus official")
      PROFILE_ID="sm8550-oneplus11-official"
      SOC="sm8550"
      TARGET_NAME="OnePlus 11"
      DEVICE_CODENAMES="salami"
      DEVICE_NAMES="salami OP591BL1 OP594DL1"
      KERNEL_SOURCE="OnePlusOSS"
      SOURCE_LAYOUT="oneplus-official"
      ;;
    "SM8550 | OnePlus 11 | LunarisOS")
      PROFILE_ID="sm8550-oneplus11-lunarisos"
      SOC="sm8550"
      TARGET_NAME="OnePlus 11"
      DEVICE_CODENAMES="salami"
      DEVICE_NAMES="salami OP591BL1 OP594DL1"
      KERNEL_SOURCE="LunarisOS"
      SOURCE_LAYOUT="community-flat"
      KERNEL_REPO_OVERRIDE="https://github.com/osm1019/kernel_oneplus_sm8550.git"
      MODULES_REPO_OVERRIDE="https://github.com/osm1019/android_kernel_oneplus_sm8550-modules.git"
      MODULES_BRANCH_OVERRIDE="los"
      ;;
    "SM8550 | OnePlus 11 / 12R | LineageOS (recommended)")
      PROFILE_ID="sm8550-oneplus11-12r-lineage"
      SOC="sm8550"
      TARGET_NAME="OnePlus 11 / 12R"
      DEVICE_CODENAMES="salami aston astonc"
      DEVICE_NAMES="salami OP591BL1 OP594DL1 aston OP5D35L1 astonc OP5CF9L1"
      KERNEL_SOURCE="LineageOS"
      SOURCE_LAYOUT="community-flat"
      ;;
    "SM8550 | OnePlus 11 / 12R | crDroid")
      PROFILE_ID="sm8550-oneplus11-12r-crdroid"
      SOC="sm8550"
      TARGET_NAME="OnePlus 11 / 12R"
      DEVICE_CODENAMES="salami aston astonc"
      DEVICE_NAMES="salami OP591BL1 OP594DL1 aston OP5D35L1 astonc OP5CF9L1"
      KERNEL_SOURCE="crdroidandroid"
      SOURCE_LAYOUT="community-flat"
      # Match the common and salami/aston device BoardConfig make flags.
      KERNEL_MAKE_FLAGS="CONFIG_OPLUS_DEVICE_DTBS=y CONFIG_SALAMI_DTB=y CONFIG_ASTON_DTB=y"
      ;;
    *)
      echo "::error::Unknown build profile: $profile"
      return 1
      ;;
  esac

  UPSTREAM_SOC="$SOC"

  case "$SOC" in
    sm8550)
      PLATFORM_SLUG="8gen2"
      PLATFORM_NAME="Snapdragon 8 Gen 2"
      BUILD_CONFIGS="vendor/kalama_GKI.config vendor/oplus/kalama_GKI.config vendor/debugfs.config"
      OFFICIAL_BUILD_TARGET="kalama"
      OFFICIAL_GKI_FRAGMENT="arch/arm64/configs/vendor/kalama_GKI.config"
      ;;
  esac

  case "$KERNEL_SOURCE" in
    OnePlusOSS)
      SOURCE_NAME="OnePlus official source"
      SOURCE_SLUG="oneplus-official"
      ;;
    LineageOS)
      SOURCE_NAME="LineageOS"
      SOURCE_SLUG="lineageos"
      ;;
    LunarisOS)
      SOURCE_NAME="LunarisOS (OnePlus 11)"
      SOURCE_SLUG="lunarisos"
      ;;
    crdroidandroid)
      SOURCE_NAME="crDroid"
      SOURCE_SLUG="crdroid"
      ;;
  esac
}

resolve_root_solution() {
  case "$1" in
    "No root changes") KSU_TYPE="None" ;;
    "Official KernelSU") KSU_TYPE="Official-KernelSU" ;;
    "KernelSU-Next") KSU_TYPE="KernelSU-Next" ;;
    "KernelSU-Next + SUSFS") KSU_TYPE="KernelSU-Next-with-susfs" ;;
    "KernelSU-Next + SUSFS + NoMount (experimental)") KSU_TYPE="KernelSU-Next-with-susfs-nomount" ;;
    "KernelSU-Next + SUSFS + ZeroMount (experimental)") KSU_TYPE="KernelSU-Next-with-susfs-zeromount" ;;
    "KowSU") KSU_TYPE="KowSU" ;;
    "FinaSU (experimental)") KSU_TYPE="FinaSU" ;;
    "FinaSU + SUSFS (experimental)") KSU_TYPE="FinaSU-with-susfs" ;;
    "FinaSU + SUSFS + NoMount (experimental)") KSU_TYPE="FinaSU-with-susfs-nomount" ;;
    "SukiSU Ultra + KPM (experimental)") KSU_TYPE="SukiSU-Ultra-with-KPM" ;;
    "SukiSU Ultra + SUSFS + KPM (experimental)") KSU_TYPE="SukiSU-Ultra-with-susfs-KPM" ;;
    "SukiSU Ultra + SUSFS + ZeroMount + KPM (experimental)") KSU_TYPE="SukiSU-Ultra-with-susfs-zeromount-KPM" ;;
    "SukiSU Ultra + SUSFS + NoMount + KPM (experimental)") KSU_TYPE="SukiSU-Ultra-with-susfs-nomount-KPM" ;;
    # Keep existing workflow_dispatch clients working after the upstream rename.
    "BakaSU"|"ReSukiSU") KSU_TYPE="BakaSU" ;;
    "BakaSU + SUSFS"|"ReSukiSU + susfs") KSU_TYPE="BakaSU-with-susfs" ;;
    "BakaSU + SUSFS + ZeroMount (experimental)"|"ReSukiSU + SUSFS + ZeroMount (experimental)") KSU_TYPE="BakaSU-with-susfs-zeromount" ;;
    "BakaSU + SUSFS + NoMount (experimental)"|"ReSukiSU + SUSFS + NoMount (experimental)") KSU_TYPE="BakaSU-with-susfs-nomount" ;;
    *)
      echo "::error::Unsupported root solution: $1"
      return 1
      ;;
  esac
}

resolve_clang_version() {
  local choice="$1"
  local branch="$2"

  case "$choice" in
    "Recommended (auto-select based on branch)")
      case "$branch" in
        main|master|android-mainline*) CLANG_VERSION="clang-r596125" ;;
        lineage-24*|seventeen*|android17*|17.*) CLANG_VERSION="clang-r584948" ;;
        lineage-19.1*|oneplus/*_s_12.1*|oneplus/*_s_12.0*) CLANG_VERSION="clang-r416183b1" ;;
        lineage-20*|thirteen*|android13*|13.*|oneplus/*_t_13*|oneplus_*_t_13*) CLANG_VERSION="clang-r450784d" ;;
        lineage-21*|fourteen*|android14*|14.*|oneplus/*_u_14*|oneplus_*_u_14*) CLANG_VERSION="clang-r487747c" ;;
        lineage-22*|fifteen*|android15*|15.*|oneplus/*_v_15*|oneplus_*_v_15*) CLANG_VERSION="clang-r536225" ;;
        lineage-23.0*) CLANG_VERSION="clang-r547379" ;;
        16.0|lineage-23*|sixteen*|android16*|16.*|oneplus/*_b_16*|oneplus_*_b_16*) CLANG_VERSION="clang-r563880c" ;;
        *)
          CLANG_VERSION="clang-r563880c"
          echo "::warning::Could not confidently infer clang for '$branch'; using $CLANG_VERSION."
          ;;
      esac
      ;;
    "clang-r596125 (Clang 22.0.2 / current AOSP mainline era)") CLANG_VERSION="clang-r596125" ;;
    "clang-r584948 (Android 17 / crDroid 13 era)") CLANG_VERSION="clang-r584948" ;;
    "clang-r563880c (Android 16 / LineageOS 23.2+ era)") CLANG_VERSION="clang-r563880c" ;;
    "clang-r547379 (Android 16 / LineageOS 23.0 era)") CLANG_VERSION="clang-r547379" ;;
    "clang-r536225 (Android 15 / LineageOS 22.2 era)") CLANG_VERSION="clang-r536225" ;;
    "clang-r487747c (Android 14 / LineageOS 21 era)") CLANG_VERSION="clang-r487747c" ;;
    "clang-r450784d (Android 13 / LineageOS 20 era)") CLANG_VERSION="clang-r450784d" ;;
    "clang-r416183b1 (Android 12 / LineageOS 19.1 era)") CLANG_VERSION="clang-r416183b1" ;;
    *)
      echo "::error::Unknown clang choice: $choice"
      return 1
      ;;
  esac
}

resolve_susfs_settings() {
  local soc="$1"
  local branch="$2"

  case "$soc" in
    sm7550)
      SUSFS_REF="gki-android14-5.15"
      ;;
    sm8450)
      SUSFS_REF="gki-android13-5.10"
      ;;
    sm8550)
      case "$branch" in
        lineage-20*|thirteen*|android13*|13.*|oneplus/*_t_13*|oneplus_*_t_13*)
          SUSFS_REF="gki-android13-5.15"
          ;;
        *)
          SUSFS_REF="gki-android14-5.15"
          ;;
      esac
      ;;
    sm8650)
      SUSFS_REF="gki-android14-6.1"
      ;;
    *)
      echo "::error::No susfs mapping is configured for platform $soc"
      return 1
      ;;
  esac

  SUSFS_PATCH_FILE="50_add_susfs_in_${SUSFS_REF}.patch"
}

su_session_compatible_susfs_commit() {
  local susfs_ref="$1"

  # Keep every kernel branch pinned to a SUSFS v2.3.0 revision whose KernelSU
  # patch matches the su-session fd ABI in the pinned SukiSU Ultra and BakaSU
  # drivers. Newer patches require preinit and external SELinux hooks that
  # these driver revisions do not export. FinaSU uses the same pins: it carries
  # its own SUSFS layer and does not provide the susfs_security_* hooks (or the
  # SUSFS_LOGI_RL stubs) that the newest upstream branch heads expect.
  # Updated through 2026-09-15: includes the enabled-features NULL-deref fix,
  # corrected CTIME spoof bit, and super.c declaration compatibility fix.
  # Later upstream revisions change the KernelSU patch and need a new adapter.
  # The revisions share that KernelSU patch but retain branch-specific patches.
  case "$susfs_ref" in
    gki-android13-5.10) echo "7b08b969e3577d282b352a267cb343b02b707d2a" ;;
    gki-android13-5.15) echo "adaef1c599e770707311ad36b015a0de3f30ac28" ;;
    gki-android14-5.15) echo "ffa69590787d097f54cb60ed79fa6fd5e285bb41" ;;
    gki-android14-6.1) echo "2e9f720d3af25e2c6678633cc5be82edae9708b3" ;;
    *)
      echo "::error::No su-session-compatible SUSFS commit is pinned for $susfs_ref" >&2
      return 1
      ;;
  esac
}

infer_android_versions() {
  local branch="$1"

  case "$branch" in
    lineage-24*|seventeen*|android17*|17.*) SUPPORTED_ANDROID_VERSIONS="17" ;;
    lineage-19.1*|oneplus/*_s_12*|oneplus_*_s_12*) SUPPORTED_ANDROID_VERSIONS="12" ;;
    lineage-20*|thirteen*|android13*|13.*|oneplus/*_t_13*|oneplus_*_t_13*) SUPPORTED_ANDROID_VERSIONS="13" ;;
    lineage-21*|fourteen*|android14*|14.*|oneplus/*_u_14*|oneplus_*_u_14*) SUPPORTED_ANDROID_VERSIONS="14" ;;
    lineage-22*|fifteen*|android15*|15.*|oneplus/*_v_15*|oneplus_*_v_15*) SUPPORTED_ANDROID_VERSIONS="15" ;;
    16.0|lineage-23*|sixteen*|android16*|16.*|oneplus/*_b_16*|oneplus_*_b_16*) SUPPORTED_ANDROID_VERSIONS="16" ;;
    *) SUPPORTED_ANDROID_VERSIONS="" ;;
  esac
}

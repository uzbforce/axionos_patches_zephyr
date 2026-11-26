# axionos_patches_zephyr

Everything needed to turn a fresh **AxionOS 2.9 (NOESIS)** checkout into the
same build as this one for the **Redmi Note 17 4G** — codename `zephyr`, Xiaomi
project `p19a`, **SM6225-AF** (`bengal`, Snapdragon 6s Gen 2).

Target: AxionOS `lineage-23.2` branch, `bp4a` release (Android 16.2,
`BP4A.251205.006`), **userdebug**, vanilla (no GMS) by default.

| Piece | Source |
|---|---|
| ROM | `https://github.com/AxionAOSP/android.git`, branch `lineage-23.2` |
| Device tree | `uzbforce/android_device_xiaomi_zephyr`, `lineage-23.2` (pinned in `local_manifests/`) |
| Vendor / blobs | `uzbforce/android_vendor_xiaomi_zephyr`, `lineage-23.2` (pinned) |
| SM6225 platform | `uzbforce/android_hardware_qcom-caf_sm6225_*`, `uzbforce/android_hardware_qcom-caf_common`, `uzbforce/android_device_qcom_sepolicy_vndr_sm6225` (pinned) |
| Kernel | stock **prebuilt** 5.15.194 from `zephyr_global_images_OS3.0.311.0.WBUMIXM_16.0`; the MiCode source tree is used only for `make headers_install` |

This repo is the AxionOS counterpart of
[lineage_patches_zephyr](https://github.com/uzbforce/lineage_patches_zephyr):
it carries the patches that are still needed, the patches that had to be
rebased for AxionOS, and the AxionOS-only fixes.

## Layout

```
local_manifests/zephyr.xml   pinned device/vendor/platform projects
patches/<project>/<n>-*.patch   applies in $ANDROID_BUILD_TOP/<project>
sync.sh                      copy the manifest in and repo sync the projects
apply.sh                     apply every patch; skip ones already in the tree
capture.sh                   capture a new change as a patch
```

## Reproduce

```bash
# 1. AxionOS source
mkdir axion && cd axion
repo init -u https://github.com/AxionAOSP/android.git -b lineage-23.2 --git-lfs
repo sync -c -j"$(nproc)"

# 2. Device, vendor, platform repos + kernel source (headers only)
/path/to/axionos_patches_zephyr/sync.sh "$PWD"

# 3. Apply the patches
/path/to/axionos_patches_zephyr/apply.sh "$PWD"

# 4. Host tools for the firmware extractor (lpunpack, lpdump, simg2img, dtc,
#    fsck.erofs). simg2img comes from android-sdk-libsparse-utils, dtc from
#    device-tree-compiler and fsck.erofs from erofs-utils; lpunpack/lpdump are
#    built from the tree. zephyr's BoardConfig refuses to lunch until
#    device/xiaomi/zephyr-kernel/kernel exists, so use a throw-away placeholder
#    for this step and delete it again:
mkdir -p device/xiaomi/zephyr-kernel/dtbs
: > device/xiaomi/zephyr-kernel/kernel
: > device/xiaomi/zephyr-kernel/dtbs/dtbo.img
source build/envsetup.sh && axion zephyr userdebug
export PATH="$PWD/out/host/linux-x86/bin:$PATH"
mka lpunpack lpdump
rm -rf device/xiaomi/zephyr-kernel

# 5. Firmware -> prebuilt kernel tree (see "Kernel" below)
device/xiaomi/zephyr/tools/extract-firmware.sh \
    /path/to/zephyr_global_images_OS3.0.311.0.WBUMIXM_16.0 work
device/xiaomi/zephyr/tools/gen-prebuilt-kernel.py \
    --dump work/root \
    --firmware /path/to/zephyr_global_images_OS3.0.311.0.WBUMIXM_16.0 \
    --out device/xiaomi/zephyr-kernel
ANDROID_BUILD_TOP="$PWD" device/xiaomi/zephyr/tools/gen-kernel-headers.sh

# 6. Build
source build/envsetup.sh
axion zephyr userdebug          # lunches lineage_zephyr-bp4a-userdebug
mka bacon -j"$(nproc)"
```

Output: `out/target/product/zephyr/axion-2.9-NOESIS-<YYYYMMDD>-UNOFFICIAL-VANILLA-zephyr.zip`
(about 1.8 GB; `lineage_zephyr-ota.zip` is the same package under the internal
name). For a GMS build use `axion zephyr userdebug gms` before `mka bacon`.

The build that produced this patch set finished in 30:00 with `mka bacon -j64`
and the resulting `boot.img` contains the stock `5.15.194-android13-8` kernel.
It has **not** been boot-tested on hardware yet.

## AxionOS device configuration

Set in `device/xiaomi/zephyr/lineage_zephyr.mk` (patch
`device/xiaomi/zephyr/0001-*`) and `BoardConfig.mk`:

| Variable | Value | Why |
|---|---|---|
| `AXION_MAINTAINER` | `uzbforce` | |
| `AXION_PROCESSOR` | `Snapdragon_6s_Gen2` | underscores, no spaces |
| `AXION_CAMERA_REAR_INFO` | `50` | 50 MP rear |
| `AXION_CAMERA_FRONT_INFO` | `16` | 16 MP front |
| `HBM_SUPPORTED` | `true` | panel exposes `hbm_mode`; FOD uses local HBM |
| `HBM_NODE` | `/sys/class/backlight/panel0-backlight/hbm_mode` | |
| `TARGET_DISABLES_LIBPERF` | `false` | libperfmgr path enabled ("true" = disabled) |
| `TARGET_SUPPORTS_KERNEL_MANAGER` | `false` | prebuilt kernel has no Axion kmods |
| `TARGET_SHIPS_AXION_KERNEL_MODULES` | `false` | same |
| `TARGET_NEEDS_DOZE_FIX` | `false` | not needed |
| `TARGET_INCLUDE_AXFX` | `false` | first bring-up build |
| `TARGET_TAP_TO_WAKE` | `/proc/tp_gesture` | double-tap-to-wake via QTI power HAL extension |

UDFPS is the AIDL fingerprint service
(`android.hardware.biometrics.fingerprint-service.lineage`) plus
`hardware/lineage/interfaces` patch 0001, which drives the Goodix `extCmd`
press/release and the panel's local white 1000-nit HBM. AxionOS has no separate
`libudfpshandler` module anymore, so that package was removed from `device.mk`.

Note: AxionOS 2.9 does not ship a `libperfmgr` package. The flag currently only
controls `persist.sys.ax_disable_pwrhal` (and the AxionParts switch behind it).
If the device turns out to need the QTI perf HAL instead, set
`TARGET_DISABLES_LIBPERF := true`.

## Patches that needed rebasing for AxionOS

These are the same fixes as in `lineage_patches_zephyr`, adapted to AxionOS'
diverged forks:

| Patch | What changed |
|---|---|
| `packages/apps/Dialer/0001-*` | Axion's Dialer carries the "disable proximity sensor" preference; the fix was rebased onto that file |
| `system/sepolicy/0003-*` | Axion's `Android.bp` already has `permissive_domains_on_user_builds` lists (the upstream patch inserted a second list, which soong rejects); the Xiaomi domains are merged into the existing lists. Compat ignore lists, recovery f2fs, system_suspend, `vibrator_init.te` and the `policy.py` fix are the same. |
| `hardware/qcom-caf/common/0003-*` | New: the generic `os_pickup.bp` namespace (used by msm8998) also needs `hardware/google/pixel/kernel_headers`, or soong aborts on `libc2dcolorconvert`. |
| `prebuilts/misc/0001-*` | New: AxionOS defines the `libprotobuf-cpp-*-vendorcompat` modules twice (also in `hardware/lineage/compat`); the duplicate definitions are removed from `prebuilts/misc`, which is the incomplete copy (no arm64 21.12). |
| `device/axion/common/0001-*` | New: `ax_diagnostics.te` and `ax_kernel_manager.te` grant the system-wide `sysfs_battery_supply` / `sysfs_devfreq` / `sysfs_graphics` / `sysfs_kgsl` types, which only exist in the legacy-UM policy. zephyr uses the sm6225 QSSI policy, where the same nodes are `vendor_sysfs_*`; the legacy rules are removed so `checkpolicy` does not abort. |

## LineageOS-specific patches that are deliberately NOT used

| Patch | Why not |
|---|---|
| `kernel/xiaomi/zephyr/0003-sync-the-current-kernel-and-techpack-changes.patch` | The build uses the stock prebuilt kernel. The source tree is only needed for `headers_install`; the one relevant hunk (the `struct sched_param` guard) is kept as `kernel/xiaomi/zephyr/0001-*`. |
| `kernel/xiaomi/zephyr/0004-add-the-vendor-dts-tree.patch` | Same: no source-built kernel, no vendor DTS tree. |
| `vendor/lineage/0004-report-november-2026-platform-security-patch.patch` | Only moved Lineage's October platform SPL to November. AxionOS already carries `2026-11-01`. |

Everything else from `lineage_patches_zephyr` is included, including the
device-generic fixes (UDFPS, IMS, codecs, Wi-Fi, thermal, vibrator, power,
libbase, extract-utils, Settings, Dialer).

## Kernel

The kernel is **not built**. `board-info.txt` and the stock firmware pin
`5.15.194-android13-8`; the vendor blobs (including the 268 `vendor_dlkm` and
295 first-stage modules) are ABI-matched to it. Xiaomi's OSS drop has no
`techpack/`, so a source-built kernel would come up without display, GPU, video
and audio. The prebuilt route assembles:

```
device/xiaomi/zephyr-kernel/
  kernel                   stock Image (5.15.194)
  dtbs/dtbo.img            stock DTBO (70 entries)
  dtbs/dtb/*.dtb           stock vendor_boot base DTBs (27)
  vendor_dlkm/             268 modules + modules.load + modules.blocklist
  system_dlkm/             zram.ko, zsmalloc.ko + modules.load
  vendor_ramdisk/          295 modules + modules.load + modules.load.recovery
  kernel-headers/          headers_install output (1938 headers)
```

Firmware used:

```
zephyr_global_images_OS3.0.311.0.WBUMIXM_20260911.0000.00_16.0_global_dcb7f8e08e.tgz
https://bigota.d.miui.com/OS3.0.311.0.WBUMIXM/...
md5 dcb7f8e08eb4adcd935baafa084d9b03
```

`gen-kernel-headers.sh` must run with `ANDROID_BUILD_TOP` exported (it calls
`bionic/libc/kernel/tools/clean_header.py`, which requires it) and after the
kernel `sched_param` patch has been applied.

The kernel source is not a `repo` project; `sync.sh` clones it to
`kernel/xiaomi/zephyr` if it is missing.

## Notes

- `apply.sh` leaves changes unstaged. Nothing in this repo requires a commit.
- The build is `userdebug`; `WITH_ADB_INSECURE` is set by the device tree for
  non-user builds so adb works before SystemUI is up.
- Stock images are EROFS, the super partition uses virtual A/B v3, and AVB keys
  are the AOSP test keys (first bring-up build).
- The device tree and vendor repo are pinned to the commits this patch series
  was generated against (`aa4204a8...` / `34c36af0...`).

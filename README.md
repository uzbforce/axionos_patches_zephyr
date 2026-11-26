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
build.sh                     build vanilla / gms / core / pico
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

# 6. Build (vanilla, or pass gms / core / pico)
./axionos_patches_zephyr/build.sh vanilla
```

Output: `out/target/product/zephyr/axion-2.9-NOESIS-<YYYYMMDD>-UNOFFICIAL-VANILLA-zephyr.zip`
(about 1.8 GB; `lineage_zephyr-ota.zip` is the same package under the internal
name). `./build.sh gms` produces the `GMS` variant; see "Build variants".

`build.sh` creates an empty `vendor/lineage-priv/keys` before sourcing
`envsetup.sh`. Axion's `setup_keys()` runs before it exports `ANDROID_KEY_PATH`,
so on a tree without keys it calls `gk` with an empty path and aborts; the empty
directory keeps that a no-op and keeps the AOSP test keys these packages use.

The first build finished in 30:00 with `mka bacon -j64`; the 2026-11-26 rebuild
with the 24.0 backport took 5:26. The resulting `boot.img` contains the stock
`5.15.194-android13-8` kernel. The 2026-11-25 package booted on hardware; the
2026-11-26 package has not been flashed yet.

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
| `TARGET_SUPPORTS_KERNEL_MANAGER` | `true` | sysfs-only, works on the stock kernel |
| `TARGET_SHIPS_AXION_KERNEL_MODULES` | `false` | prebuilt kernel has no Axion kmods |
| `TARGET_NEEDS_DOZE_FIX` | `false` | not needed |
| `TARGET_INCLUDE_AXFX` | `false` | first bring-up build |
| `qtipower.mode_ext_lib` | `//device/xiaomi/zephyr:libperfmgr-ext-xiaomi` | the only hook `vendor/qcom/opensource/power` reads; drives DT2W |

UDFPS is the AIDL fingerprint service
(`android.hardware.biometrics.fingerprint-service.lineage`) plus
`hardware/lineage/interfaces` patch 0001, which drives the Goodix `extCmd`
press/release and the panel's local white 1000-nit HBM. AxionOS has no separate
`libudfpshandler` module anymore, so that package was removed from `device.mk`.

The service attaches the stock FOD engine from `libmifpext.so` in `openHal()`
(`XiaomiFingerprint::getInstance()->setDevice()`). That engine is what arms the
touch IC and watches `fod_press_status` while the display is off, so a
screen-off touch starts the capture even before SystemUI has replayed the
gesture. Without it the panel can light up while no scan is ever started.

The same wrapper gates the vendor `extCmd`: a press waits up to 500 ms for the
`disp_param` local-HBM node to become writable (the panel is still unblanking
after a screen-off touch), and a release that arrives within 500 ms of that
press is dropped instead of being forwarded. That early release is the touch
controller's spurious finger-up while the panel wakes; the Goodix HAL aborts
the scan with `GF_ERROR_TOO_FAST` when it sees it, which was the original 13 ms
HBM flash. A real release, the authentication result, or the framework's 2.5 s
AOD timer still ends the gesture.

`frameworks/base` patch 0002 pairs with it: `UdfpsController` ignores the
HAL's `FINGERPRINT_ACQUIRED_VENDOR` lifecycle events (they are not final image
results), ignores a touch-up while the synthetic AOD gesture is active, raises
the AOD finger-up fallback to 2.5 s, and `DozeSensors` takes the wakeup UDFPS
sensor and fills the trigger coordinates from `config_udfps_sensor_props`.

Note: AxionOS 2.9 does not ship a `libperfmgr` package. The flag currently only
controls `persist.sys.ax_disable_pwrhal` (and the AxionParts switch behind it).
If the device turns out to need the QTI perf HAL instead, set
`TARGET_DISABLES_LIBPERF := true`.

## Performance audit and Kernel Manager

Audited against the booted device on 2026-11-26. Already active:

- RAM Plus: zram0 with a 2 GB swap area, `persist.sys.ax_mem.swappiness=100`,
  `persist.sys.ax_rp_supp=true`.
- QTI perf HAL (`perf-hal-2-3`) with the stock `powerhint.xml` and
  `perfconfigstore.xml` blobs.
- Dexpreopt: `SystemUI`, `Launcher3QuickStep`, `Settings`, `AxionParts`,
  `GameSpace`, `EdgeLauncher` and `AxThemePicker` use the speed filter
  (`vendor/lineage/config/common.mk` + `device/axion/common/config/dexpreopt.mk`).
- 4 GB dalvik heap table, EROFS/lz4 images, F2FS `/data` with `gc_merge`,
  120 Hz peak refresh, DT2W and local HBM.
- The Axion kernel modules (BORE/latency scheduler, ax_boost, dragonite) cannot
  load into the stock 5.15 prebuilt: it has none of their trace hooks. BORE and
  the latency scheduler are core-scheduler changes, not loadable modules, so
  `TARGET_SHIPS_AXION_KERNEL_MODULES` stays `false`.

Added by this package:

- `ax_kernel_manager.xml`: both CPU clusters (policy0 300 MHz-1.9 GHz, policy4
  300 MHz-2.9 GHz, the eight available governors) and the Adreno 610 devfreq
  limits. `TARGET_SUPPORTS_KERNEL_MANAGER := true` installs it as
  `/system_ext/etc/ax_kernel_manager.xml`.
- `ax_init_bengal.rc`: hands the root-owned `scaling_governor` and kgsl
  `devfreq/{min,max}_freq` nodes to `system:system` at boot. Before this the
  Kernel Manager could read the controls but every governor/GPU write returned
  EACCES; `scaling_governor` was `0644 root:root` on the booted device.
- `sepolicy/vendor/init_kernel_manager.te`: the setattr init needs to chown
  those nodes.

Deliberately left off, because each changes behaviour and needs a hardware
check:

- `TARGET_ENABLES_IMS_OVERRIDES` forces VoLTE/VoWiFi/VoNR carrier config on.
- `BYPASS_CHARGE_SUPPORTED` exposes the GameSpace bypass-charge toggle (the
  Lineage Health switch is already pinned to
  `/sys/class/qcom-battery/input_suspend`).
- `debug.hwui.renderer=skiavk`; the device currently runs SkiaGL.
- AxionFX (`TARGET_INCLUDE_AXFX`).

## Build variants

```bash
./build.sh vanilla      # no Google apps (default)
./build.sh gms          # FullPkgs, SetupWizard, Play Store
./build.sh core         # CorePkgs
./build.sh pico         # PicoPkgs
./build.sh gms bootimage
```

The variant has to be in the environment before `lunch`: Axion derives
`AXION_BUILD_VARIANT` (and the zip name) from `WITH_GMS` /
`TARGET_GAPPS_VARIANT` while the product is being configured. `gms` is the
full set; `core` and `pico` are the lighter Google packages, useful on a 4 GB
SKU.

Both variants share `out/`, and the OTA zip is a hardlink to
`lineage_zephyr-ota.zip`: building the second variant overwrites the first
package even though the file name differs. Copy each zip out of
`out/target/product/zephyr/` before starting the next variant. The 2026-11-26
audit rebuilds took 5:19 (vanilla) and 10:01 (GMS) incrementally.

## LineageOS 24.0 device fixes backported

`uzbforce/android_device_xiaomi_zephyr` also has a `lineage-24.0` branch whose
top commits are device fixes that apply to the 23.2 tree unchanged.
`patches/device/xiaomi/zephyr/0002-*` and
`patches/vendor/xiaomi/zephyr/0001-*` are that backport, restricted to the parts
that are not Android 17-only. The framework half of the screen-off UDFPS fix is
`patches/frameworks/base/0002-*`.

| Fix | Where | What was wrong |
|---|---|---|
| Window-level blurs | `configs/properties/vendor.prop` | `ro.surface_flinger.supports_background_blur` was missing, so `BlurUtils` reported `supportsBlursOnWindows=false` and Settings hid the blur switches. Blur still defaults to off. |
| Recovery touchscreen | `recovery/root/system/etc/init/init.qcom.recovery.rc`, `device.mk` | Recovery never loaded `ft3683g_spi` and recovery does not mount `vendor_dlkm`, so it had no touch input. The three modules are now copied from `device/xiaomi/zephyr-kernel/vendor_dlkm` into the recovery ramdisk and insmod'ed after their dependencies. |
| Double-tap to wake | `BoardConfig.mk`, `power/power-mode.cpp`, `configs/idc/fts_ts.idc`, `overlay/FrameworksResCommon` | `TARGET_POWERHAL_MODE_EXT` is not read by `vendor/qcom/opensource/power`; the extension is only linked through `soong_config_set(qtipower,mode_ext_lib,...)`. The panel is a Focaltech FT3683G, not a Synaptics TCM, so `TARGET_TAP_TO_WAKE` (`/proc/tp_gesture`) cannot work. The extension now arms touch mode 14 through `/dev/xiaomi-touch` and sends the `EV_SYN/SYN_CONFIG` event; the IDC keeps the device enabled in the inactive viewport. |
| Screen-off UDFPS | `sensors/udfps`, `device.mk`, `overlay/FrameworksResCommon`, vendor `hals.conf`, `hardware/lineage/interfaces` patch 0001, `frameworks/base` patch 0002 | The vendor SSC AOD sensor is a special-trigger sensor, which `requestTriggerSensor()` rejects. A device sub-HAL (`sensors.xiaomi.zephyr.udfps`) exposes a normal one-shot wakeup sensor, arms touch FOD mode 10 and watches `fod_press_status`. It is listed in `hals.conf` so the multi-HAL loads it. The fingerprint wrapper attaches the vendor FOD engine, gates the early release that aborted the scan, and SystemUI ignores the vendor acquired lifecycle events; see the UDFPS note above. |
| Denial cleanups | `sepolicy/vendor/*` | `wlan_logs` labelling (`cnss_diag` was denied every second; 335 of 608 denials), audio/USB/display/camera/perf battery and backlight reads, `mi_thermald` thermal inputs, fingerprint `sys_nice`, fingerprint property types, sensors UDFPS ioctls, camera/perf battery reads, battery-anti-aging kmsg and battery supply traversal, the TMS NFC `/dev/tms_nfc` and `/sys/nfc/chip_name` labels (the unlabelled node made `init`'s `wait` spin: 494 denials), `vendor_qti_init_shell` battery-node setattr (118), the camera perf-optimisation script's exec domain, and the display-feature daemon's binder calls. |
| `system_dlkm` AVB | `rootdir/etc/fstab.qcom`, `fstab.emmc` | `system_dlkm` is chained from `vbmeta_system`, not the top-level `vbmeta`; the fstab now says `avb=vbmeta_system`. |
| Early HAL start | `rootdir/etc/init/hw/init.target.rc` | `wait_for_keymaster` is not built and `keymaster-4-0` is not a service on this vendor (keymint is), so both lines only produced init errors. Replaced with `class_start early_hal`. |
| Dalvik heap | `device.mk` | The tree inherited the 6 GB heap table on a 3.7 GiB device (256m growth limit, 32m max free). Uses the 4 GB table (192m/16m). |
| Biometric dialog corners | `overlay/SystemUIResCommon/res/values/dimens.xml` | Match the panel's 54.86dp corner radius. |

Deliberately **not** backported, because it is Android 17-only or already
provided by AxionOS: `developer_gsi_keys.mk` /
`BOARD_MOVE_GSI_AVB_KEYS_TO_VENDOR_BOOT`, `libion.vendor`, the
`tracking_list.yaml` treble-labeling entry, removal of the
`hardware/google/pixel/kernel_headers` namespace, the private AVB key paths,
`FaceUnlock` (Axion ships `co.aospa.sense` already), and the `Android.bp`
recovery `prebuilt_etc` (this tree already copies `recovery/root`).

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

## Device audit (2026-11-26, post-flash)

Audit of the flashed 2026-11-26 package after the recovery/DT2W/UDFPS/blur
backport:

- recovery and DT2W are confirmed working by the maintainer; screen-off UDFPS
  unlocks, but its HBM was turning off 13 ms after it came on. See the UDFPS
  note above; the fix is in this package.
- no crashes: the crash buffer is empty, `/data/tombstones` is empty, and the
  dropbox holds only `SYSTEM_BOOT` and `storage_trim`. `exit-info` shows only
  ordinary lmkd reclaim of cached processes (acore, timeservice,
  ondevicepersonalization).
- 906 AVC denials in the boot's audit buffer. The big ones are the 494
  `/dev/tms_nfc` `getattr` loop from `init`'s `wait`, 118 charger-node `setattr`
  from `vendor_qti_init_shell`, and the battery/`chip_name` reads from
  camera/perf/sensors. All are addressed here except the `system_suspend`
  suspend-stats reads (that domain is not exported to vendor policy) and the
  `rild` QcriNvOpt service registration / TEE block-device probes, which are
  benign at boot.
- NFC is absent on this SKU (`ro.boot.hardware.sku=p19a`); `nfc-service-tms`
  only starts for `p19ae`/`p19ap`. That is a variant decision, not a bring-up
  bug; labelling `/dev/tms_nfc` only stops the `wait` loop.
- the runtime still reports `ro.build.type=user` / `ro.debuggable=0` while
  `/system/build.prop` says `userdebug`. The boot image ramdisk is empty, so
  those come from the vendor_boot ramdisk of an earlier `user` build. Flash
  `boot.img`, `vendor_boot.img`, `init_boot.img` and `recovery.img` from the
  same package to align them.

## Device audit (2026-11-26, 2026-11-25 package)

`adb shell` audit of the running package, before the backport:

- thermal zones 32–35 °C, no throttling; CPU scaling 691 MHz – 2.9 GHz; no kernel
  or `PowerManagerService` wakelocks held; battery 30–31 °C, health OK.
- the crash buffer is empty; the `Process ... has died` lines in logcat are
  ordinary lmkd reclaim of cached processes.
- 608 AVC denials in 13 minutes: 335 from `vendor_wcnss_service` on
  `/data/vendor/wlan_logs`, and most of the rest are the audio / USB / display /
  camera battery and backlight reads. All are addressed by the sepolicy part of
  the backport. `system_suspend` also has 19 read denials on the suspend-stats
  files, but that domain is not exported to vendor policy, so those stay.
- `ro.surface_flinger.supports_background_blur` was absent and `BlurUtils`
  reported `supportsBlursOnWindows=false`, so Settings had no blur switch.
- `fts_ts.idc` was not installed, `mDoubleTapWakeEnabled` was false even with
  `double_tap_to_wake=1`, and neither `sensors.xiaomi.zephyr.udfps.so` nor its
  `hals.conf` line existed.
- the flashed images are inconsistent: `/system/build.prop` says
  `ro.build.type=userdebug` but the runtime props report `ro.build.type=user`
  and `ro.debuggable=0`. No `build.prop` on any partition sets those values, so
  the boot/vendor_boot ramdisk `prop.default` comes from an earlier `user`
  build. Flash `boot.img`, `vendor_boot.img`, `init_boot.img` and `recovery.img`
  from the same package to make the runtime props match the system image.

## Notes

- `apply.sh` leaves changes unstaged. Nothing in this repo requires a commit.
- `recovery.img` is a separate partition on zephyr (not recovery-as-boot); the
  touch fix is only active once that image is flashed.
- The build is `userdebug`; `WITH_ADB_INSECURE` is set by the device tree for
  non-user builds so adb works before SystemUI is up.
- Stock images are EROFS, the super partition uses virtual A/B v3, and AVB keys
  are the AOSP test keys (first bring-up build).
- The device tree and vendor repo are pinned to the commits this patch series
  was generated against (`aa4204a8...` / `34c36af0...`).

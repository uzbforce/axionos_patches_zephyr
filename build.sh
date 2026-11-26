#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Build one of the AxionOS variants for zephyr.
#
# Usage:
#   ./build.sh [vanilla|gms|core|pico] [make-target]
#
#   vanilla   no Google apps (default)
#   gms       FullPkgs       - full GMS, SetupWizard, Play Store
#   core      CorePkgs       - GMS core without the partner setup flow
#   pico      PicoPkgs       - smallest GMS set
#
# The variant is chosen at lunch time: Axion derives AXION_BUILD_VARIANT (and
# therefore the zip name) from WITH_GMS/TARGET_GAPPS_VARIANT while the product
# is being configured, so both have to be in the environment before `lunch`.
#
# Examples:
#   ./build.sh                 # vanilla, mka bacon
#   ./build.sh gms             # full GMS, mka bacon
#   ./build.sh gms bootimage   # full GMS, single target

# envsetup.sh reads several variables without a default and its
# generate_host_overrides() closes a /dev/urandom pipeline with head, so neither
# -u nor pipefail can be on.
set -e

variant="${1:-vanilla}"
target="${2:-bacon}"

case "$variant" in
    vanilla|gms|core|pico)
        ;;
    *)
        echo "unknown variant: $variant (use vanilla, gms, core or pico)" >&2
        exit 1
        ;;
esac

if [ ! -f build/envsetup.sh ]; then
    echo "run this from the root of the AxionOS checkout" >&2
    exit 1
fi

# build/make/envsetup.sh calls setup_keys() before it exports ANDROID_KEY_PATH,
# so on a tree without vendor/lineage-priv/keys it runs `gk` with an empty path
# and dies with `mkdir: cannot create directory ''`. An existing (empty)
# directory makes setup_keys a no-op and keeps the AOSP test keys this
# unofficial build has always used; creating keys here would silently change
# the signing identity of every package.
mkdir -p vendor/lineage-priv/keys

# shellcheck disable=SC1091
source build/envsetup.sh

# axion (not lunch) is this tree's product selector: it exports WITH_GMS and
# TARGET_GAPPS_VARIANT, sources vendor/lineage/vars/aosp_target_release, and
# then lunches lineage_zephyr-<release>-userdebug.
axion zephyr userdebug "$variant"

echo "building $variant ($target)"
mka "$target" -j"$(nproc)"

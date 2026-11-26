#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Sync the Redmi Note 17 4G (zephyr) device, vendor and SM6225 platform projects
# into an AxionOS checkout, using the pinned revisions in
# local_manifests/zephyr.xml.
#
# Usage: ./sync.sh [/path/to/axion/checkout]
#   Defaults to $ANDROID_BUILD_TOP, then $PWD.

set -eu

root="${1:-${ANDROID_BUILD_TOP:-$PWD}}"
here="$(cd "$(dirname "$0")" && pwd)"

[ -d "$root/.repo" ] || {
    echo "$root is not a repo checkout (no .repo)" >&2
    exit 1
}

mkdir -p "$root/.repo/local_manifests"
cp "$here/local_manifests/zephyr.xml" "$root/.repo/local_manifests/zephyr.xml"

echo "==> syncing device, vendor and SM6225 platform projects"
(
    cd "$root"
    repo sync -c --force-sync --no-clone-bundle -j"$(nproc)" \
        device/xiaomi/zephyr \
        vendor/xiaomi/zephyr \
        hardware/qcom-caf/common \
        hardware/qcom-caf/sm6225/media \
        hardware/qcom-caf/sm6225/audio/agm \
        hardware/qcom-caf/sm6225/audio/pal \
        hardware/qcom-caf/sm6225/audio/primary-hal \
        hardware/qcom-caf/sm6225/data-ipa-cfg-mgr \
        hardware/qcom-caf/sm6225/dataipa \
        device/qcom/sepolicy_vndr/sm6225
)

# The kernel source is not a repo project. It is not built (the stock prebuilt
# Image is), but gen-kernel-headers.sh runs `make headers_install` in it, so the
# checkout has to exist before the build.
if [ ! -f "$root/kernel/xiaomi/zephyr/Makefile" ]; then
    echo "==> cloning the kernel source (headers only)"
    mkdir -p "$root/kernel/xiaomi"
    git clone --depth=1 -b zephyr-w-oss \
        https://github.com/MiCode/Xiaomi_Kernel_OpenSource.git \
        "$root/kernel/xiaomi/zephyr"
fi

echo
echo "done. Next: ./apply.sh $root"

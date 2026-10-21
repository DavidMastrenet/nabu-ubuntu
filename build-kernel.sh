#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
[[ "$(uname -m)" == aarch64 ]]
REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$REPO/.build/kernel"
KERNEL=6.17.0-xiaomi-nabu-tmm-UFS-slowdown+
[[ -f "/boot/vmlinuz-$KERNEL" ]]
mkdir -p "$BUILD"
sudo apt-get -o Acquire::http::Proxy=DIRECT -o Acquire::https::Proxy=DIRECT install -y \
    build-essential flex bison bc libssl-dev libelf-dev curl device-tree-compiler systemd-ukify
if [[ ! -f "$BUILD/linux/Makefile" ]]; then
    curl -fL https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.17.tar.xz -o "$BUILD/upstream.tar.xz"
    mkdir -p "$BUILD/linux"
    tar -xf "$BUILD/upstream.tar.xz" -C "$BUILD/linux" --strip-components=1
fi
cp "$REPO/source/kernel/config-6.17.0-nabu" "$BUILD/linux/.config"
make -C "$BUILD/linux" olddefconfig
make -C "$BUILD/linux" -j4 modules_prepare
for component in camera-sensors camera-clocks camera-cci fastrpc-fixed camss charging; do
    mkdir -p "$BUILD/$component"
    cp -a "$REPO/source/kernel/$component/." "$BUILD/$component/"
    make -C "$BUILD/linux" M="$BUILD/$component" CONFIG_VIDEO_QCOM_CAMSS=m KBUILD_MODPOST_WARN=1 -j4 modules
done
dtc -I dts -O dtb "$REPO/source/kernel/nabu.dts" -o "$BUILD/nabu.dtb"
ukify build --linux="/boot/vmlinuz-$KERNEL" --devicetree="$BUILD/nabu.dtb" \
    --cmdline='root=PARTLABEL=linux rw fw_devlink=permissive cma=256M' \
    --os-release=@/etc/os-release --uname="$KERNEL" \
    --output="$BUILD/6.17.0-nabu-smb5.efi"
echo "Built kernel modules and EFI under $BUILD"

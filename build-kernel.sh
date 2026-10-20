#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
[[ "$(uname -m)" == aarch64 ]]
REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$REPO/.build/kernel"
COMMIT=5181e1358ddd6ea8028e841d928942373e6aebc8
mkdir -p "$BUILD"
sudo apt-get -o Acquire::http::Proxy=DIRECT -o Acquire::https::Proxy=DIRECT install -y \
    build-essential flex bison bc libssl-dev libelf-dev curl device-tree-compiler systemd-ukify
if [[ ! -f "$BUILD/linux/Makefile" ]]; then
    curl -fL "https://gitlab.com/sm8150-mainline/linux/-/archive/$COMMIT/linux-$COMMIT.tar.gz" -o "$BUILD/upstream.tar.gz"
    mkdir -p "$BUILD/linux"
    tar -xf "$BUILD/upstream.tar.gz" -C "$BUILD/linux" --strip-components=1
fi
cp "$REPO/source/kernel/config-6.14.11-nabu-tmm" "$BUILD/linux/.config"
make -C "$BUILD/linux" olddefconfig
make -C "$BUILD/linux" -j4 modules_prepare
for component in camera-sensors camera-clocks camera-cci fastrpc-fixed camss; do
    mkdir -p "$BUILD/$component"
    cp -a "$REPO/source/kernel/$component/." "$BUILD/$component/"
    make -C "$BUILD/linux" M="$BUILD/$component" CONFIG_VIDEO_QCOM_CAMSS=m KBUILD_MODPOST_WARN=1 -j4 modules
done
dtc -I dts -O dtb "$REPO/source/kernel/nabu.dts" -o "$BUILD/nabu.dtb"
ukify build --linux=/boot/vmlinuz-6.14.11-nabu-tmm --devicetree="$BUILD/nabu.dtb" \
    --cmdline='root=PARTLABEL=linux rw fw_devlink=permissive cma=256M' \
    --os-release=@/etc/os-release --uname=6.14.11-nabu-tmm \
    --output="$BUILD/6.14.11-camera-autofocus.efi"
echo "Built kernel modules and EFI under $BUILD"

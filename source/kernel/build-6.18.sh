#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD="$REPO/.build/kernel-6.18"
REV=140e8f8726a9d6eafd2afe8b8089982121a4199b
PHASE="${1:-all}"
mkdir -p "$BUILD"
cd "$BUILD"
prepare() {
[[ -f /usr/lib/systemd/boot/efi/linuxaa64.efi.stub ]]
if [[ ! -f linux/Makefile ]]; then
curl --fail --location --retry 3 "https://gitlab.postmarketos.org/api/v4/projects/soc%2Fqualcomm-sm8150%2Flinux/repository/archive.tar.gz?sha=$REV" -o source.tar.gz
mkdir linux
tar -xf source.tar.gz -C linux --strip-components=1
rm source.tar.gz
fi
cp "$REPO/source/kernel/config-6.18.0-nabu" linux/.config
linux/scripts/config --file linux/.config --set-str LOCALVERSION '-xiaomi-nabu' --disable LOCALVERSION_AUTO --disable DEBUG_INFO --disable DEBUG_INFO_BTF --disable DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT --enable DEBUG_INFO_NONE --module TOUCHSCREEN_NT36523_SPI --module BATTERY_QCOM_FG --module SND_SOC_SM8150
make -C linux olddefconfig
for option in TOUCHSCREEN_NT36523_SPI BATTERY_QCOM_FG SND_SOC_SM8150; do
    grep -qx "CONFIG_$option=m" linux/.config
done
make -C linux -j"$(nproc)" modules_prepare
local failed=0
for component in camera-sensors camera-clocks camera-cci fastrpc-fixed camss charging audio; do
    mkdir -p "$BUILD/$component"
    cp -a "$REPO/source/kernel/$component/." "$BUILD/$component/"
    if ! make -C "$BUILD/linux" M="$BUILD/$component" CONFIG_VIDEO_QCOM_CAMSS=m KBUILD_MODPOST_WARN=1 -k -j"$(nproc)" modules > "$BUILD/$component-preflight.log" 2>&1; then
        cat "$BUILD/$component-preflight.log"
        failed=1
    fi
    make -C "$BUILD/linux" M="$BUILD/$component" clean
    echo "API preflight completed: $component"
done
return "$failed"
}
base() {
make -C linux -j"$(nproc)" Image modules
KERNEL="$(make -s -C linux kernelrelease)"
mkdir -p package/boot
make -C linux INSTALL_MOD_PATH="$BUILD/package" INSTALL_MOD_STRIP=1 modules_install
}
overlays() {
KERNEL="$(make -s -C linux kernelrelease)"
for component in camera-sensors camera-clocks camera-cci fastrpc-fixed camss charging audio; do
    mkdir -p "$BUILD/$component"
    cp -a "$REPO/source/kernel/$component/." "$BUILD/$component/"
    make -C "$BUILD/linux" M="$BUILD/$component" CONFIG_VIDEO_QCOM_CAMSS=m -j"$(nproc)" modules
    mkdir -p "package/lib/modules/$KERNEL/updates/nabu/$component"
    find "$BUILD/$component" -maxdepth 1 -name '*.ko' -exec install -m644 {} "package/lib/modules/$KERNEL/updates/nabu/$component/" \;
done
}
package() {
KERNEL="$(make -s -C linux kernelrelease)"
cp linux/arch/arm64/boot/Image "package/boot/vmlinuz-$KERNEL"
cp linux/.config "package/boot/config-$KERNEL"
cp linux/System.map "package/boot/System.map-$KERNEL"
dtc -I dts -O dtb "$REPO/source/kernel/nabu.dts" -o "package/boot/dtb-$KERNEL"
mkdir -p package/boot/efi/EFI/ubuntu
printf '%s\n' 'ID=ubuntu' 'NAME="Ubuntu"' 'PRETTY_NAME="Ubuntu 26.04 LTS"' 'VERSION_ID=26.04' 'VERSION_CODENAME=resolute' > os-release-target
ukify build --linux="package/boot/vmlinuz-$KERNEL" --devicetree="package/boot/dtb-$KERNEL" \
    --cmdline='root=PARTLABEL=linux rw fw_devlink=permissive cma=256M' \
    --os-release=@os-release-target --uname="$KERNEL" \
    --output="package/boot/efi/EFI/ubuntu/6.18.0-nabu-smb5.efi"
rm -f "package/lib/modules/$KERNEL/build" "package/lib/modules/$KERNEL/source"
depmod -b "$BUILD/package" -a "$KERNEL"
printf '%s\n' "$KERNEL" > package/kernel-release
printf '%s\n' "$REV" > package/source-commit
(cd package && find boot lib -type f -exec sha256sum {} + > SHA256SUMS)
tar -czf nabu-kernel-6.18.tar.gz -C package .
}
case "$PHASE" in
    prepare) prepare ;;
    base) base ;;
    overlays) overlays ;;
    package) package ;;
    all) prepare; base; overlays; package ;;
    *) echo "Unknown phase: $PHASE" >&2; exit 2 ;;
esac

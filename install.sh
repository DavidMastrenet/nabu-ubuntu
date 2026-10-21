#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BACKUP=/var/lib/nabu-ubuntu/before-install
MODEL="$(tr -d '\0' </proc/device-tree/model)"
[[ $EUID == 0 && "$MODEL" == 'Xiaomi Pad 5' ]]
[[ "$(uname -m)" == aarch64 ]]
KERNEL=6.17.0-xiaomi-nabu-tmm-UFS-slowdown+
[[ -f "/boot/vmlinuz-$KERNEL" ]]
. /etc/os-release
[[ "$ID" == ubuntu && "$VERSION_CODENAME" == resolute ]]
[[ -f "$REPO/boot/6.17.0-nabu-smb5.efi" ]]
[[ -d /boot/efi/EFI ]]
TARGET_USER="${1:-${SUDO_USER:-}}"
if [[ -z "$TARGET_USER" || "$TARGET_USER" == root ]]; then
    echo 'Usage: sudo bash install.sh DESKTOP_USERNAME' >&2
    exit 2
fi
id "$TARGET_USER" >/dev/null

if [[ ! -d "$BACKUP" ]]; then
    mkdir -p "$BACKUP"
    while IFS= read -r -d '' source; do
        relative="${source#"$REPO/rootfs/"}"
        if [[ -e "/$relative" || -L "/$relative" ]]; then
            mkdir -p "$BACKUP/$(dirname "$relative")"
            cp -a "/$relative" "$BACKUP/$relative"
        fi
    done < <(find "$REPO/rootfs" -type f -print0)
    mkdir -p "$BACKUP/boot/efi/EFI/BOOT"
    cp -a /boot/efi/EFI/BOOT/refind.conf "$BACKUP/boot/efi/EFI/BOOT/"
fi

install -m644 "$REPO/rootfs/etc/apt/sources.list.d/ubuntu.sources" /etc/apt/sources.list.d/ubuntu.sources
install -m644 "$REPO/rootfs/etc/apt/apt.conf.d/90-direct-connection" /etc/apt/apt.conf.d/90-direct-connection
apt-get -o Acquire::http::Proxy=DIRECT -o Acquire::https::Proxy=DIRECT update
DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::http::Proxy=DIRECT -o Acquire::https::Proxy=DIRECT install -y \
    python3-gi python3-libgpiod libqmi-glib5 libprotobuf-c1 iio-sensor-proxy \
    pipewire wireplumber libspa-0.2-libcamera libcamera0.7 \
    gnome-snapshot gstreamer1.0-plugins-bad gstreamer1.0-plugins-good \
    gstreamer1.0-libav ibus-libpinyin language-pack-zh-hans

for path in /usr/bin/snapshot /usr/share/alsa/ucm2/Xiaomi/nabu/HiFi.conf; do
    if ! dpkg-divert --list "$path" | grep -q "$path.distrib"; then
        dpkg-divert --local --add --rename --divert "$path.distrib" "$path"
    fi
done
while IFS= read -r -d '' source; do
    relative="${source#"$REPO/rootfs/"}"
    install -D -m644 "$source" "/$relative"
done < <(find "$REPO/rootfs" -type f -print0)
chmod 755 /usr/local/bin/{nabu-autorotate,nabu-camera,qbootctl} \
    /usr/local/sbin/{nabu-sensor-start,nabu-keyboard-resume,nabu-typec-sink,nabu-charge-guard} \
    /usr/local/libexec/nabu/hexagonrpcd /usr/local/libexec/iio-sensor-proxy \
    /usr/lib/systemd/system-sleep/nabu-keyboard \
    /opt/nabu-snapshot/bin/snapshot /opt/nabu-camera/libexec/libcamera/soft_ipa_proxy
install -m755 /usr/local/bin/nabu-camera /usr/bin/snapshot
for library in libcamera libcamera-base; do
    directory=/opt/nabu-camera/lib/aarch64-linux-gnu
    ln -sfn "$library.so.0.7.0" "$directory/$library.so.0.7"
    ln -sfn "$library.so.0.7" "$directory/$library.so"
done
mkdir -p /usr/local/share/qcom/sm8150/xiaomi/nabu/sensors/registry
if [[ -d /mnt/vendor/persist/sensors/registry ]]; then
    cp -an /mnt/vendor/persist/sensors/registry/. /usr/local/share/qcom/sm8150/xiaomi/nabu/sensors/registry/
elif [[ -b /dev/disk/by-partlabel/persist ]]; then
    PERSIST_MOUNT="$(mktemp -d /run/nabu-persist.XXXXXX)"
    trap 'umount "$PERSIST_MOUNT" 2>/dev/null || true; rmdir "$PERSIST_MOUNT" 2>/dev/null || true' EXIT
    mount -o ro /dev/disk/by-partlabel/persist "$PERSIST_MOUNT"
    if [[ -d "$PERSIST_MOUNT/sensors/registry" ]]; then
        cp -an "$PERSIST_MOUNT/sensors/registry/." /usr/local/share/qcom/sm8150/xiaomi/nabu/sensors/registry/
    fi
    umount "$PERSIST_MOUNT"
    rmdir "$PERSIST_MOUNT"
    trap - EXIT
fi
ldconfig
depmod -a "$KERNEL"
glib-compile-schemas /opt/nabu-snapshot/share/glib-2.0/schemas
update-desktop-database /usr/local/share/applications
systemctl daemon-reload
systemctl enable nabu-sensors.service nabu-mark-boot-success.service
systemctl enable nabu-typec-sink.service nabu-charge-guard.service
bash "$REPO/configure-display.sh" "$TARGET_USER"
udevadm control --reload-rules
usermod -aG video "$TARGET_USER"
timedatectl set-timezone Asia/Shanghai
timedatectl set-ntp true
mapfile -t KERNEL_PACKAGES < <(dpkg-query -W -f='${binary:Package}\n' 'linux-image*' 'linux-headers*' 'xiaomi-nabu-linux*' 2>/dev/null | grep nabu || true)
if ((${#KERNEL_PACKAGES[@]})); then apt-mark hold "${KERNEL_PACKAGES[@]}"; fi

install -Dm644 "$REPO/boot/6.17.0-nabu-smb5.efi" /boot/efi/EFI/ubuntu/6.17.0-nabu-smb5.efi
python3 - <<'PY'
from pathlib import Path
import re

p = Path('/boot/efi/EFI/BOOT/refind.conf')
s = p.read_text()
s, count = re.subn(r'(?m)^(\s*loader\s+)/EFI/ubuntu/\S+\.efi\s*$',
                   r'\1/EFI/ubuntu/6.17.0-nabu-smb5.efi', s)
if count != 1:
    raise SystemExit('Expected exactly one Ubuntu loader entry in refind.conf')

# The theme supplies the icon set; without the include rEFInd warns "no icon"
# and stalls on its placeholder before the menu appears.
theme = 'include themes/refind-theme-regular/theme.conf'
if theme not in s:
    s = s.replace('menuentry "Ubuntu"', theme + '\nmenuentry "Ubuntu"', 1)

icon = '    icon /EFI/BOOT/themes/refind-theme-regular/icons/256-96/os_ubuntu.png'
if icon not in s:
    s = s.replace('    loader /EFI/ubuntu/6.17.0-nabu-smb5.efi',
                  '    loader /EFI/ubuntu/6.17.0-nabu-smb5.efi\n' + icon, 1)

p.write_text(s)

# Only GopRotate is needed; every other filesystem driver just lengthens the
# rEFInd start-up scan.
drivers = Path('/boot/efi/EFI/BOOT/drivers')
disabled = Path('/boot/efi/EFI/BOOT/drivers-disabled')
if drivers.is_dir():
    disabled.mkdir(exist_ok=True)
    for name in ('btrfs', 'ext2', 'ext4', 'hfs', 'iso9660', 'reiserfs'):
        driver = drivers / f'{name}_aa64.efi'
        if driver.exists():
            driver.rename(disabled / driver.name)
PY
uid="$(id -u "$TARGET_USER")"
if [[ -S "/run/user/$uid/bus" ]]; then
    run_user() {
        runuser -u "$TARGET_USER" -- env XDG_RUNTIME_DIR="/run/user/$uid" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" "$@"
    }
    run_user systemctl --user daemon-reload
    run_user systemctl --user enable nabu-autorotate.service
    run_user gsettings set org.gnome.desktop.input-sources sources "[('xkb', 'us'), ('ibus', 'libpinyin')]"
    run_user gsettings set org.gnome.settings-daemon.plugins.power power-button-action suspend
    run_user gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type suspend
    run_user gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-timeout 900
    run_user gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type nothing
else
    echo 'Run the user-session commands in README.md after logging into the desktop.'
fi
sync
echo 'Installed. Reboot to load the kernel modules and device tree.'

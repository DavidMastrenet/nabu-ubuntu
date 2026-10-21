#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
[[ $EUID == 0 && "$(tr -d '\0' </proc/device-tree/model)" == 'Xiaomi Pad 5' ]]
TARGET_USER="${1:-${SUDO_USER:-}}"
if [[ -z "$TARGET_USER" || "$TARGET_USER" == root ]]; then
    echo 'Usage: sudo bash configure-display.sh DESKTOP_USERNAME' >&2
    exit 2
fi
uid="$(id -u "$TARGET_USER")"
desktop_home="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
DEBIAN_FRONTEND=noninteractive apt-get install -y python3-gi python3-libgpiod
files=(
    usr/local/bin/nabu-display-state
    usr/local/sbin/nabu-lid-switch
    etc/systemd/system/nabu-lid-switch.service
    etc/systemd/user/nabu-display-state.service
    etc/systemd/logind.conf.d/60-nabu-lid.conf
)
backup=/var/lib/nabu-ubuntu/before-display
for path in "${files[@]}"; do
    if [[ -e "/$path" && ! -e "$backup/$path" ]]; then
        mkdir -p "$backup/$(dirname "$path")"
        cp -a "/$path" "$backup/$path"
    fi
    install -D -m644 "$REPO/rootfs/$path" "/$path"
done
chmod 755 /usr/local/bin/nabu-display-state /usr/local/sbin/nabu-lid-switch
systemctl daemon-reload
systemctl kill -s HUP systemd-logind.service
systemctl enable nabu-lid-switch.service
systemctl restart nabu-lid-switch.service

# Global unit files do not enable a user service for an existing account.
install -d -o "$TARGET_USER" -g "$(id -gn "$TARGET_USER")" \
    "$desktop_home/.config/systemd/user/graphical-session.target.wants"
runuser -u "$TARGET_USER" -- ln -sfn /etc/systemd/user/nabu-display-state.service \
    "$desktop_home/.config/systemd/user/graphical-session.target.wants/nabu-display-state.service"
if [[ -S "/run/user/$uid/bus" ]]; then
    run_user() {
        runuser -u "$TARGET_USER" -- env XDG_RUNTIME_DIR="/run/user/$uid" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" "$@"
    }
    run_user gsettings set org.gnome.settings-daemon.plugins.power idle-dim false
    run_user gsettings set org.gnome.settings-daemon.plugins.power ambient-enabled false
    run_user gsettings set org.gnome.settings-daemon.plugins.power lid-close-ac-action nothing
    run_user gsettings set org.gnome.settings-daemon.plugins.power lid-close-battery-action nothing
    run_user systemctl --user daemon-reload
    run_user systemctl --user restart nabu-display-state.service
else
    echo 'Log in and run the desktop settings commands in README.md.'
fi
echo 'Display fixes installed. Brightness changes are saved after a few seconds.'

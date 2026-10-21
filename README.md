# Ubuntu for Xiaomi Pad 5 (nabu)

[中文说明](README.zh-CN.md)

Drivers, runtime files and source changes for Ubuntu 26.04 ARM64 with kernel `6.14.11-nabu-tmm`. This is a Linux-only setup for **Xiaomi Pad 5**, not Pad 5 Pro. The Ubuntu disk image is downloaded separately.

## Install

1. Unlock the bootloader. Install the [nabu Ubuntu 26.04 base image](https://github.com/TheMojoMan/xiaomi-nabu/releases/tag/ubuntu-26.04-v1.0.0), following the upstream installation instructions. The root partition must be named `linux`; the EFI partition must be mounted at `/boot/efi`. Keep Qualcomm firmware and the device's `persist` partition.
2. Finish desktop setup and connect to Wi-Fi. Copy this repository to the tablet.
3. Run from the repository directory:

   ```sh
   sudo bash install.sh "$USER"
   sudo reboot
   ```

The installer selects the included EFI image, installs the fixes, sets US keyboard layout with Chinese Pinyin input, and uses the USTC Ubuntu mirror without an APT proxy. Existing files are backed up under `/var/lib/nabu-ubuntu/before-install`.

The standalone Linux UEFI boot image and TWRP recovery image are provided as individual files in [Releases](https://github.com/DavidMastrenet/nabu-ubuntu/releases). `boot/EFI/BOOT` contains the EFI boot manager. The Ubuntu disk image is not included.

Run the installer from a logged-in desktop session. If installed outside that session, run these after logging in:

```sh
systemctl --user daemon-reload
systemctl --user enable --now nabu-autorotate.service
gsettings set org.gnome.desktop.input-sources sources "[('xkb', 'us'), ('ibus', 'libpinyin')]"
```

## Included fixes

- Front and rear cameras, rear autofocus, correct colors and orientation, photos and video with sound.
- Camera switching and restart after suspend; camera failures no longer block the audio service.
- Automatic screen rotation and touch coordinates, including after suspend.
- Original magnetic keyboard reconnects automatically after suspend.
- Speaker and microphone configuration, RTC selection and boot-success marking.
- Fast rEFInd menu: `timeout 2`, the theme's icon set (`include themes/refind-theme-regular/theme.conf` plus an explicit Ubuntu icon) and only the `GopRotate` driver, so there is no "no icon" stall before the menu.
- Stable Wi-Fi MAC: `ath10k` has no board address on nabu, so NetworkManager is configured with `wifi.cloned-mac-address=stable` instead of a random address per boot.
- Type-C sink role: a oneshot service and udev rule write `sink` into `/sys/class/typec/port0/power_role`, so a charger is accepted instead of the tablet sourcing the port.

Reboot, suspend/resume, camera switching, autofocus, display, touch, rotation, keyboard, speakers and microphone were checked on the target tablet. USB-PD charging was also checked.

## Brightness and magnetic cover

The desktop remembers brightness in `~/.local/state/nabu-brightness.json` and restores it after login. Idle dimming and ambient brightness are disabled. Closing the magnetic cover powers off the panel; opening it powers the panel on. USB networking and SSH remain available while the cover is closed. These fixes can be installed separately without changing the kernel, boot image, or installed applications:

```sh
sudo bash configure-display.sh "$USER"
```

Run this from the logged-in GNOME desktop. If installed over SSH before desktop login, apply the settings from a desktop terminal:

```sh
gsettings set org.gnome.settings-daemon.plugins.power idle-dim false
gsettings set org.gnome.settings-daemon.plugins.power ambient-enabled false
gsettings set org.gnome.settings-daemon.plugins.power lid-close-ac-action nothing
gsettings set org.gnome.settings-daemon.plugins.power lid-close-battery-action nothing
systemctl --user restart nabu-display-state.service
```

On the tested boot image, the live device tree exposes `1,code` and `1,input-type` in the GPIO keys node, and the kernel rejects it with `Button without keycode`. The installed DTB files have the correct `linux,` properties. `nabu-lid-switch` reads TLMM GPIO9, with active-low polarity and 15 ms debounce, and exposes `SW_LID` through uinput. It exits without claiming the GPIO if a native lid switch is already present. `nabu-display-state` uses UPower and Mutter to control display power because the GNOME lid-action setting alone did not blank this tablet.

## Build

Build on Ubuntu 26.04 ARM64. Install the runtime first, then:

```sh
bash build.sh
bash build-kernel.sh
```

`build.sh` downloads the pinned Ubuntu source packages, applies the included source overlays, and installs rebuilt userspace components. `build-kernel.sh` builds the modified modules and EFI image under `.build/kernel`; it does not install them. The running kernel's `/boot/vmlinuz-6.14.11-nabu-tmm` is required.

`rootfs/` contains runtime files, `boot/` the EFI image and device tree, and `source/` the modified source files and supporting libraries. Build downloads stay in `.build/`.

## Recovery

Keep the base image's EFI loader. To boot it again, change the Ubuntu `loader` line in `/boot/efi/EFI/BOOT/refind.conf` to its original path; the installer saves the original configuration in the backup directory above. If Ubuntu cannot boot, mount the EFI partition from a recovery environment and restore that configuration.

The kernel is held at `6.14.11-nabu-tmm`. Rebuild and recheck the modules before changing kernels.

## Credits

Maintained by 洪宇轩 <yuxuan.hong@ieee.org>.

Based on [TheMojoMan/xiaomi-nabu](https://github.com/TheMojoMan/xiaomi-nabu), [sm8150-mainline Linux](https://gitlab.com/sm8150-mainline/linux) (commit `5181e1358ddd6ea8028e841d928942373e6aebc8`), Ubuntu's libcamera `0.7.0-1ubuntu2` and GNOME Snapshot `50.0-0ubuntu1`, libssc, hexagonrpc, iio-sensor-proxy and qbootctl. The software autofocus adaptation builds on Robin Snyders' work in [hotdog-linux-bringup](https://github.com/Sr-0w/hotdog-linux-bringup). Sensor firmware comes from the [nabu firmware project](https://gitlab.com/panpanpanpan/nabu-firmware).

Components retain their original licenses and copyright notices. See the license files and source headers in each component directory.

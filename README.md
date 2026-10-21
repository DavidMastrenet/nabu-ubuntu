# Ubuntu for Xiaomi Pad 5 (nabu)

[中文说明](README.zh-CN.md)

Drivers, runtime files and source changes for Ubuntu 26.04 ARM64 with kernel `6.17.0-xiaomi-nabu-tmm-UFS-slowdown+`. This is a Linux-only setup for **Xiaomi Pad 5**, not Pad 5 Pro. The Ubuntu disk image is downloaded separately.

## Install

1. Unlock the bootloader. Install the [nabu Ubuntu 26.04 base image](https://github.com/TheMojoMan/xiaomi-nabu/releases/tag/ubuntu-26.04-v1.0.0), following the upstream installation instructions. The root partition must be named `linux`; the EFI partition must be mounted at `/boot/efi`. Keep Qualcomm firmware and the device's `persist` partition.
2. Finish desktop setup and connect to Wi-Fi. The matching 6.17 BSP kernel must be installed at `/boot/vmlinuz-6.17.0-xiaomi-nabu-tmm-UFS-slowdown+`. Copy this repository to the tablet.
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
- Type-C sink role: a daemon and udev rule keep the selected power role at `sink`.
- Computer USB charging through PM8150B SMB5, with a 500 mA USB input limit, a 4.35 V float target and temperature/voltage guards.
- Correct native lid and volume-up input properties in the device tree.

The 6.17 update was booted and checked on the target tablet. Front and rear camera capture, audio playback, sensor orientation, desktop display, touch and USB networking passed. A 180-second trace showed battery charging in all 37 samples, USB input 480–483 mA, temperature 29 C and charger health Good. PD hardware testing was skipped for this revision.

The Type-C role attribute brackets its selected value: `source [sink]` means the tablet is already receiving power. SMB5 handles ordinary 5 V USB. Above 5.5 V, the guard suspends SMB5; LN8000 enables its PD charge-pump path from 8 V upward. Driver sources and provenance are in [source/kernel/charging](source/kernel/charging/README.md).

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

The included device tree corrects `1,code` and `1,input-type` to `linux,code` and `linux,input-type`. The kernel now registers the physical GPIO9 lid switch and volume-up key directly. The previous GPIO-to-uinput lid service is no longer needed. `nabu-display-state` uses UPower and Mutter to power the panel off and on.

## Build

Build on Ubuntu 26.04 ARM64. Install the runtime first, then:

```sh
bash build.sh
bash build-kernel.sh
```

`build.sh` downloads the pinned Ubuntu source packages, applies the included source overlays, and installs rebuilt userspace components. `build-kernel.sh` builds the modified modules and EFI image under `.build/kernel`; it does not install them. The matching BSP image `/boot/vmlinuz-6.17.0-xiaomi-nabu-tmm-UFS-slowdown+` is required. The script prepares Linux 6.17 headers and rebuilds the overlays; it uses the installed BSP image for the EFI file.

`rootfs/` contains runtime files, `boot/` the EFI image and device tree, and `source/` the modified source files and supporting libraries. Build downloads stay in `.build/`.

## Recovery

Keep the base image's EFI loader. To boot it again, change the Ubuntu `loader` line in `/boot/efi/EFI/BOOT/refind.conf` to its original path; the installer saves the original configuration in the backup directory above. If Ubuntu cannot boot, mount the EFI partition from a recovery environment and restore that configuration.

The BSP kernel is held at `6.17.0-xiaomi-nabu-tmm-UFS-slowdown+`. Rebuild and recheck the modules before changing kernels.

## Credits

Maintained by 洪宇轩 <yuxuan.hong@ieee.org>.

Based on [TheMojoMan/xiaomi-nabu](https://github.com/TheMojoMan/xiaomi-nabu), [sm8150-mainline Linux](https://gitlab.com/sm8150-mainline/linux) (commit `5181e1358ddd6ea8028e841d928942373e6aebc8`), Ubuntu's libcamera `0.7.0-1ubuntu2` and GNOME Snapshot `50.0-0ubuntu1`, libssc, hexagonrpc, iio-sensor-proxy and qbootctl. The software autofocus adaptation builds on Robin Snyders' work in [hotdog-linux-bringup](https://github.com/Sr-0w/hotdog-linux-bringup). Sensor firmware comes from the [nabu firmware project](https://gitlab.com/panpanpanpan/nabu-firmware).

Components retain their original licenses and copyright notices. See the license files and source headers in each component directory.

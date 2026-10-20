# Automatic rotation on the Xiaomi Pad 6 (xiaomi-pipa) — postmarketOS

This branch carries the `iio-sensor-proxy` changes needed for working automatic
screen rotation on SM8250 SSC devices (Xiaomi Pad 6 / `xiaomi-pipa`) **before
the upstream fixes have landed**. Build it yourself until the fixes reach
Alpine, then drop it and go back to the stock package.

On top of upstream `iio-sensor-proxy` 3.9 it contains:

1. **Broadcast sensor capability changes to all clients** — so GNOME/mutter
   learns the accelerometer appeared (it shows up ~45 s after boot on the SSC
   backend). Submitted upstream:
   <https://gitlab.freedesktop.org/hadess/iio-sensor-proxy/-/merge_requests/414>
2. **Retry the SSC accelerometer enable** if the SLPI firmware ignores it.
3. **Tolerate a NULL `GError` from libssc** — until the libssc fix lands:
   <https://codeberg.org/DylanVanAssche/libssc/pulls/129>

Working autorotate **also** needs the mutter workaround at the bottom of this
file (mutter bug: <https://gitlab.gnome.org/GNOME/mutter/-/work_items/4931>).

---

## 1. Build it on postmarketOS (pmbootstrap)

`iio-sensor-proxy` comes from Alpine, not pmaports, so add a small local aport
to your pmaports checkout that builds this branch.

```sh
cd "$(pmbootstrap config aports)"        # your pmaports checkout
mkdir -p temp/iio-sensor-proxy
```

Save this as `temp/iio-sensor-proxy/APKBUILD`:

```sh
# Custom iio-sensor-proxy with the xiaomi-pipa autorotate fixes.
# Tracks branch xiaomi-pipa-autorotate of the fork until the changes are
# upstreamed. Remove this aport once Alpine ships them.
pkgname=iio-sensor-proxy
pkgver=3.9
pkgrel=50
pkgdesc="IIO sensors to D-Bus proxy (xiaomi-pipa autorotate build)"
url="https://gitlab.freedesktop.org/hadess/iio-sensor-proxy"
arch="all"
license="GPL-2.0-or-later"
options="!check"
depends="dbus"
makedepends="eudev-dev glib-dev libgudev-dev meson polkit-dev libssc-dev"
subpackages="$pkgname-systemd $pkgname-udev $pkgname-dbg"
_branch="xiaomi-pipa-autorotate"
source="$pkgname-$_branch.tar.gz::https://gitlab.freedesktop.org/Xelef2000/iio-sensor-proxy/-/archive/$_branch/iio-sensor-proxy-$_branch.tar.gz"
builddir="$srcdir/iio-sensor-proxy-$_branch"

build() {
	abuild-meson \
		-Db_lto=true \
		-Dssc-support=enabled \
		-Dsystemdsystemunitdir=/usr/lib/systemd/system \
		. output
	meson compile -C output
}

package() {
	DESTDIR="$pkgdir" meson install --no-rebuild -C output
}

sha512sums="" # filled in by: pmbootstrap checksum iio-sensor-proxy
```

Then compute the checksum, build, and install on the device:

```sh
pmbootstrap checksum iio-sensor-proxy
pmbootstrap build iio-sensor-proxy
pmbootstrap sideload iio-sensor-proxy      # device must be reachable over SSH
```

(If `sideload` can't reach the device, copy the `.apk` from
`"$(pmbootstrap config work)"/packages/edge/aarch64/` and, on the device,
`sudo apk add --allow-untrusted iio-sensor-proxy-3.9-r50.apk` plus the
`-systemd` and `-udev` sub-packages.)

Restart the service (or reboot):

```sh
sudo systemctl restart iio-sensor-proxy
```

## 2. Stop updates from replacing it

`apk upgrade` will overwrite this build with the stock Alpine package as soon as
Alpine ships an equal-or-newer version. Pin the patched build on the device:

```sh
sudo apk add "iio-sensor-proxy=3.9-r50"
```

This writes a versioned constraint into `/etc/apk/world`, so upgrades leave it
alone. **Once the fixes are in Alpine**, undo the pin (and remove the aport) to
resume normal updates:

```sh
sudo apk add iio-sensor-proxy
```

## 3. mutter workaround (until GNOME #4931 is fixed)

Even with the sensor daemon fixed, mutter has a bug that leaves it never
claiming the accelerometer when it appears late, so rotation stays dead (the
toggle shows, but nothing rotates) until `iio-sensor-proxy` is bounced once.
Ship a one-shot service that waits for the accelerometer, then bounces the
daemon once after login.

`/usr/local/bin/pipa-autorotate-kick.sh`:

```sh
#!/bin/sh
# Work around mutter #4931: bounce iio-sensor-proxy once after boot so mutter
# re-runs its claim logic and starts tracking orientation.
i=0
while [ "$i" -lt 150 ]; do
	case "$(busctl get-property net.hadess.SensorProxy /net/hadess/SensorProxy \
		net.hadess.SensorProxy HasAccelerometer 2>/dev/null)" in
		*true*) break ;;
	esac
	i=$((i + 1)); sleep 2
done
sleep 3
systemctl restart iio-sensor-proxy
```

`/etc/systemd/system/pipa-autorotate-kick.service`:

```ini
[Unit]
Description=Bounce iio-sensor-proxy once after boot to unstick mutter auto-rotation
After=graphical.target iio-sensor-proxy.service
Wants=iio-sensor-proxy.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/pipa-autorotate-kick.sh

[Install]
WantedBy=graphical.target
```

Enable it:

```sh
sudo chmod +x /usr/local/bin/pipa-autorotate-kick.sh
sudo systemctl enable pipa-autorotate-kick.service
```

Reboot; auto-rotation comes up on its own ~1 minute after login. Make sure the
quick-settings rotation lock is **off**.

## 4. Optional: keep autorotate working across suspend

The SLPI firmware crash-loops on resume if the FastRPC/SDSP session survives
s2idle. If you suspend the device, also add a teardown around sleep.

`/etc/systemd/system/hexagonrpc-sdsp-sleep.service`:

```ini
[Unit]
Description=Tear down the SDSP FastRPC session around system sleep
Before=sleep.target
StopWhenUnneeded=yes

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/systemctl stop iio-sensor-proxy hexagonrpcd-sdsp
ExecStop=/usr/bin/systemctl start hexagonrpcd-sdsp
ExecStop=/usr/bin/sleep 2
ExecStop=-/usr/bin/systemctl reset-failed iio-sensor-proxy
ExecStop=/usr/bin/systemctl restart iio-sensor-proxy

[Install]
WantedBy=sleep.target
```

```sh
sudo systemctl enable hexagonrpc-sdsp-sleep.service
```

Do **not** add a remoteproc bounce to this unit — a `remoteproc` stop can block
for minutes when the SLPI is wedged and would hang the resume itself.

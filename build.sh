#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Native ARM64 build. Upstream release sources stay in .build/.
set -euo pipefail
[[ "$(uname -m)" == aarch64 ]]
REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$REPO/.build"
mkdir -p "$BUILD"
configure() {
    local directory="$1"
    shift
    if [[ -f "$directory/meson-private/coredata.dat" ]]; then
        meson setup --reconfigure "$directory" "$@"
    else
        meson setup "$directory" "$@"
    fi
}
sudo apt-get -o Acquire::http::Proxy=DIRECT -o Acquire::https::Proxy=DIRECT update
sudo apt-get -o Acquire::http::Proxy=DIRECT -o Acquire::https::Proxy=DIRECT build-dep -y libcamera gnome-snapshot
sudo apt-get -o Acquire::http::Proxy=DIRECT -o Acquire::https::Proxy=DIRECT install -y \
    build-essential meson ninja-build pkg-config libglib2.0-dev libqmi-glib-dev \
    libprotobuf-c-dev protobuf-c-compiler protobuf-compiler libudev-dev \
    libsystemd-dev libqrtr-glib-dev libgudev-1.0-dev libpolkit-gobject-1-dev

cd "$BUILD"
[[ -d libcamera-0.7.0 ]] || apt-get -o Acquire::http::Proxy=DIRECT -o Acquire::https::Proxy=DIRECT source libcamera=0.7.0-1ubuntu2
[[ -d gnome-snapshot-50.0 ]] || apt-get -o Acquire::http::Proxy=DIRECT -o Acquire::https::Proxy=DIRECT source gnome-snapshot=50.0-0ubuntu1
cp -a "$REPO/source/libcamera/include/." libcamera-0.7.0/include/
cp -a "$REPO/source/libcamera/src/." libcamera-0.7.0/src/
cp -a "$REPO/source/snapshot/aperture/." gnome-snapshot-50.0/aperture/
# Ubuntu source supplies the pinned Rust crate vendor directory.
mkdir -p gnome-snapshot-50.0/.cargo
cat >gnome-snapshot-50.0/.cargo/config.toml <<'EOF'
[source.crates-io]
replace-with = "debian"
[source.debian]
directory = "debian/missing-sources"
EOF

configure libcamera-build libcamera-0.7.0 \
    --prefix=/opt/nabu-camera --buildtype=release -Dwerror=false \
    -Dpipelines=simple,uvcvideo -Dipas=simple -Dgstreamer=enabled \
    -Dcam=disabled -Dqcam=disabled -Dtest=false -Ddocumentation=disabled \
    -Dpycamera=disabled -Dv4l2=disabled
ninja -C libcamera-build -j4
sudo ninja -C libcamera-build install
configure snapshot-build gnome-snapshot-50.0 \
    --prefix=/opt/nabu-snapshot --buildtype=release -Dprofile=default
mkdir -p snapshot-build/cargo-home
cat >snapshot-build/cargo-home/config.toml <<EOF
[source.crates-io]
replace-with = "debian"
[source.debian]
directory = "$BUILD/gnome-snapshot-50.0/debian/missing-sources"
EOF
CARGO_NET_OFFLINE=true CARGO_BUILD_JOBS=4 ninja -C snapshot-build
sudo ninja -C snapshot-build install

for component in hexagonrpc libssc qbootctl; do
    configure "$BUILD/$component-build" "$REPO/source/$component" \
        --prefix=/usr/local --buildtype=release
    ninja -C "$BUILD/$component-build" -j4
    sudo ninja -C "$BUILD/$component-build" install
done
sudo install -Dm755 "$BUILD/hexagonrpc-build/hexagonrpcd/hexagonrpcd" /usr/local/libexec/nabu/hexagonrpcd
sudo ldconfig
PKG_CONFIG_PATH=/usr/local/lib/aarch64-linux-gnu/pkgconfig:/usr/local/lib/pkgconfig \
configure "$BUILD/iio-build" "$REPO/source/iio-sensor-proxy" \
    --prefix=/usr/local --buildtype=release -Dssc-support=enabled -Dtests=false -Dgtk-tests=false -Dgtk_doc=false \
    -Dudevrulesdir=/usr/lib/udev/rules.d -Dsystemdsystemunitdir=/usr/lib/systemd/system
ninja -C "$BUILD/iio-build" -j4
sudo install -Dm755 "$BUILD/iio-build/src/iio-sensor-proxy" /usr/local/libexec/iio-sensor-proxy
sudo ldconfig
echo 'Userspace rebuilt. Reboot to restart services with the new libraries.'

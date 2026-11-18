#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Compiles the C++ parts (window decoration, Qt app style, doodlebookos-qml launcher) for Fedora N — Bazzite, Kinoite,
# Fedora KDE — in a Fedora container, for systems without compilers (image-based /usr):
#   setup/build-prebuilt-fedora.sh [45]
# Result: ~/.cache/doodlebookos-prebuilt/fedoraN/ (the .so files + buildinfo.json), picked up by
# make-installer.sh; the installer uses the variant whose Plasma/Qt versions match the PC.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VER="${1:-45}"
OUT="${XDG_CACHE_HOME:-$HOME/.cache}/doodlebookos-prebuilt/fedora$VER"
ENGINE="$(command -v podman || command -v docker || true)"
[[ -n "$ENGINE" ]] || { echo "[!] podman ou docker est nécessaire." >&2; exit 1; }
mkdir -p "$OUT"
rm -f "$OUT"/*.so "$OUT"/buildinfo.json

echo "[i] Fedora $VER : compilation dans un conteneur ($ENGINE)…"
"$ENGINE" run --rm -v "$REPO/themes:/src:ro,Z" -v "$REPO/setup/qml-runner:/runner:ro,Z" -v "$OUT:/out:Z" "registry.fedoraproject.org/fedora:$VER" bash -euc '
dnf install -y -q --setopt=install_weak_deps=False cmake ninja-build gcc-c++ extra-cmake-modules \
    qt6-qtbase-devel qt6-qtbase-private-devel qt6-qtdeclarative-devel qt6-qtsvg-devel \
    kf6-kcoreaddons-devel kf6-kconfig-devel kf6-kconfigwidgets-devel kf6-kguiaddons-devel kf6-ki18n-devel \
    kf6-kiconthemes-devel kf6-kwindowsystem-devel kf6-kcolorscheme-devel kdecoration-devel >/dev/null
for m in app-style window-decoration; do
    cmake -B "/tmp/$m" -S "/src/$m/DoodlebookOS" -G Ninja -DCMAKE_BUILD_TYPE=Release >/dev/null
    cmake --build "/tmp/$m" -j"$(nproc)" >/dev/null
done
cp "$(find /tmp/app-style -name doodlebookos6.so | head -1)" /out/
cp "$(find /tmp/window-decoration -name org.doodlebookos.decoration.so | head -1)" /out/
g++ -std=c++17 -O2 -fPIC /runner/main.cpp -o /out/doodlebookos-qml $(pkg-config --cflags --libs Qt6Widgets Qt6Qml Qt6Quick)
strip --strip-unneeded /out/*.so /out/doodlebookos-qml
pv=$(rpm -q --qf "%{VERSION}" kdecoration); qv=$(rpm -q --qf "%{VERSION}" qt6-qtbase)
printf "{\"plasma\": [%s], \"qt\": [%s], \"arch\": \"%s\", \"distro\": \"fedora%s\"}\n" \
    "${pv//./, }" "${qv//./, }" "$(uname -m)" "'"$VER"'" > /out/buildinfo.json
'
cat "$OUT/buildinfo.json"
ls -la "$OUT"

#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Builds doodlebookos-qml (needs g++ and the Qt 6 Widgets/Qml/Quick development files).
#   setup/qml-runner/build.sh [OUTPUT]     (default: ~/.local/bin/doodlebookos-qml)
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${1:-$HOME/.local/bin/doodlebookos-qml}"
mkdir -p "$(dirname "$OUT")"
g++ -std=c++17 -O2 -fPIC "$DIR/main.cpp" -o "$OUT.new.$$" $(pkg-config --cflags --libs Qt6Widgets Qt6Qml Qt6Quick)
strip --strip-unneeded "$OUT.new.$$"
mv -f "$OUT.new.$$" "$OUT"

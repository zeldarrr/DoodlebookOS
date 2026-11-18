#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Builds dist/DoodlebookOS-Installer.run: one self-extracting file (run-header.sh + tar.xz of the repo,
# the precompiled decoration/style modules of THIS machine and the third-party icon assets).
#
#   setup/make-installer.sh [--capture] [--desktop] [--version vX.Y.Z]
#     --capture   export this desktop's look first (setup/capture-profile.py)
#     --desktop   also copy the result to the desktop folder
#     --version   version written into the installer (default: git describe)
# With the release key (~/.local/share/doodlebookos-release/signing-key) the file is signed:
# dist/DoodlebookOS-Installer.run.sig, checked by doodlebookos-update before installing.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$REPO/dist/DoodlebookOS-Installer.run"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/doodlebookos-pack.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
D="$STAGE/DoodlebookOS"

VERSION=""
args=("$@")
for i in "${!args[@]}"; do
    [[ "${args[$i]}" == --capture ]] && python3 "$REPO/setup/capture-profile.py"
    [[ "${args[$i]}" == --version ]] && VERSION="${args[$((i + 1))]:-}"
done
[[ -n "$VERSION" ]] || VERSION="$(git -C "$REPO" describe --tags --always 2>/dev/null || echo dev)"
KEY="$HOME/.local/share/doodlebookos-release/signing-key"

echo "[i] Copie du dépôt…"
mkdir -p "$D"
tar -C "$REPO" --exclude=./.git --exclude=./dist --exclude=./.github --exclude='__pycache__' --exclude='*.run' \
    --exclude='*.pyc' --exclude=build -cf - . | tar -C "$D" -xf -
echo "$VERSION" > "$D/VERSION"
echo "    version $VERSION"

echo "[i] Modules C++ précompilés…"
mkdir -p "$D/bundle/prebuilt"
for so in "$HOME/.local/lib64/plugins/org.kde.kdecoration3/org.doodlebookos.decoration.so" \
          "$HOME/.local/lib64/plugins/styles/doodlebookos6.so"; do
    [[ -f "$so" ]] && cp -L "$so" "$D/bundle/prebuilt/" || echo "    (absent : $so)"
done
pv=$(QT_QPA_PLATFORM=offscreen plasmashell --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
qv=$(readlink -f "$(ldd "$D/bundle/prebuilt/doodlebookos6.so" 2>/dev/null | awk '/libQt6Core/ {print $3}')" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+$' || true)
printf '{"plasma": [%s], "qt": [%s], "arch": "%s"}\n' "${pv//./, }" "${qv//./, }" "$(uname -m)" > "$D/bundle/prebuilt/buildinfo.json"
cat "$D/bundle/prebuilt/buildinfo.json"

echo "[i] Icônes tierces (Tela-circle GPL-3.0, glyphes Simple Icons CC0 / Material Symbols Apache-2.0)…"
mkdir -p "$D/bundle/icons"
for t in Tela-circle Tela-circle-dark; do
    [[ -d "$HOME/.local/share/icons/$t" ]] && cp -a "$HOME/.local/share/icons/$t" "$D/bundle/icons/"
done
for t in m3icons icon-template-tela-circle; do
    [[ -d "$HOME/.local/share/doodlebookos/$t" ]] && cp -a "$HOME/.local/share/doodlebookos/$t" "$D/bundle/"
done
find "$D/bundle/icons" -name 'icon-theme.cache' -delete 2>/dev/null || true
cat > "$D/bundle/LICENCES-TIERCES.txt" <<'EOF'
Composants tiers embarqués dans DoodlebookOS-Installer.run
- icons/Tela-circle, icons/Tela-circle-dark : Tela circle icon theme, © vinceliuice,
  GPL-3.0 (texte : LICENSE du dépôt) — https://github.com/vinceliuice/Tela-circle-icon-theme
  (les fichiers SVG sont la source).
- m3icons/ms : Material Symbols (rounded) 0.49.0, © Google, Apache-2.0.
- m3icons/si : Simple Icons 16.37.0, CC0-1.0 ; les logos restent des marques de leurs propriétaires.
- m3icons/letters.json : contours de Google Sans Flex, SIL Open Font License 1.1.
- extras/fonts/GoogleSansFlex : Google Sans Flex, SIL Open Font License 1.1 (OFL.txt).
EOF

echo "[i] Compression (xz)…"
mkdir -p "$(dirname "$OUT")"
{ cat "$REPO/setup/run-header.sh"; tar -C "$STAGE" --owner=0 --group=0 -cf - DoodlebookOS | xz -T0 -6; } > "$OUT.tmp"
chmod +x "$OUT.tmp"
mv -f "$OUT.tmp" "$OUT"
echo "[✓] $OUT ($(du -h "$OUT" | cut -f1))"
rm -f "$OUT.sig"
if [[ -f "$KEY" ]]; then
    ssh-keygen -q -Y sign -f "$KEY" -n doodlebookos-update "$OUT" && echo "[✓] signé : $OUT.sig"
else
    echo "[i] pas de clé de publication ($KEY) : installeur non signé, refusé par doodlebookos-update"
fi

for a in "$@"; do
    if [[ "$a" == --desktop ]]; then
        desk="$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")"
        cp -f "$OUT" "$desk/" && echo "[✓] Copié sur le bureau : $desk/$(basename "$OUT")"
    fi
done

#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# DoodlebookOS — installeur en un seul fichier pour KDE Plasma 6.
#   Double-clic (Dolphin : « Exécuter »), ou :  bash DoodlebookOS-Installer.run [--yes] [--no-gui]
# Le dépôt DoodlebookOS est compressé à la fin de ce fichier ; il est extrait dans un dossier
# temporaire, puis setup/doodlebookos-setup.py installe tout dans le dossier personnel (sans root).
set -euo pipefail

# lancé par double-clic sans kdialog : rouvrir dans un terminal pour voir la progression
if [[ ! -t 0 ]] && ! command -v kdialog >/dev/null 2>&1; then
    for t in konsole gnome-terminal xfce4-terminal xterm; do
        if command -v "$t" >/dev/null 2>&1; then
            [[ "$t" == gnome-terminal ]] && exec "$t" -- bash "$0" "$@"
            exec "$t" -e bash "$0" "$@"
        fi
    done
fi

fail() {
    if [[ ! -t 0 ]] && command -v kdialog >/dev/null 2>&1; then kdialog --title DoodlebookOS --error "$1"; fi
    echo "[!] $1" >&2; exit 1
}
command -v python3 >/dev/null 2>&1 || fail "python3 est nécessaire (paquet python3)."
command -v xz >/dev/null 2>&1 || fail "xz est nécessaire (paquet xz / xz-utils)."

WORK="${XDG_CACHE_HOME:-$HOME/.cache}/doodlebookos-setup.$$"
rm -rf "$WORK"; mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT
LINE=$(awk '/^__DOODLEBOOKOS_PAYLOAD__$/ { print NR + 1; exit }' "$0")
tail -n +"$LINE" "$0" | xz -dc | tar -x -C "$WORK" || fail "Archive abîmée : retélécharge DoodlebookOS-Installer.run."
python3 "$WORK/DoodlebookOS/setup/doodlebookos-setup.py" "$@"
exit $?
__DOODLEBOOKOS_PAYLOAD__

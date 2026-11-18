#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Publishes a new version: every PC with automatic updates gets it (installed at its next login).
#
#   setup/release.sh v0.9.0-fork.2 ["notes"]
#
# 1. exports this desktop's look (setup/capture-profile.py) and builds + signs the installer
# 2. commits the profile if it changed, tags, pushes
# 3. creates the GitHub release with DoodlebookOS-Installer.run and its .sig
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAG="${1:?usage : setup/release.sh <tag> [notes]}"
NOTES="${2:-Mise à jour DoodlebookOS $TAG.}"
KEY="$HOME/.local/share/doodlebookos-release/signing-key"
[[ -f "$KEY" ]] || { echo "[!] clé de publication absente : $KEY"; exit 1; }
cd "$REPO"
[[ -z "$(git status --porcelain -- . ':!setup/profile')" ]] || { echo "[!] modifications non commitées :"; git status --short; exit 1; }
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && { echo "[!] le tag $TAG existe déjà"; exit 1; }

# Bazzite / Kinoite / Fedora KDE modules, rebuilt from this commit (needs podman or docker)
if command -v podman >/dev/null 2>&1 || command -v docker >/dev/null 2>&1; then
    bash setup/build-prebuilt-fedora.sh 45
else
    echo "[!] ni podman ni docker : modules Fedora 45 (Bazzite) repris du cache, s'il existe"
fi
bash setup/make-installer.sh --capture --desktop --version "$TAG"
git add setup/profile
git diff --cached --quiet || git commit -q -m "Profil exporté pour $TAG"
git tag -a "$TAG" -m "DoodlebookOS $TAG"
git push -q origin HEAD "refs/tags/$TAG"
GH_REPO="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["repo"])' setup/update.json)"
gh release create "$TAG" dist/DoodlebookOS-Installer.run dist/DoodlebookOS-Installer.run.sig --repo "$GH_REPO" \
    --title "DoodlebookOS $TAG" --notes "$NOTES

Installer : télécharger **DoodlebookOS-Installer.run**, double-clic (ou \`bash DoodlebookOS-Installer.run\`).
Déjà installé : mise à jour automatique à la prochaine connexion (ou \`doodlebookos-update now\`)."
echo "[✓] $TAG publiée."

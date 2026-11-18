#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""DoodlebookOS — test automatique des animations au ralenti.

    python3 setup/slowmo-test.py [--factor 8] [--out DOSSIER] [--only window,qs,launcher,screenshot]

Ralentit toutes les animations (AnimationDurationFactor × --factor), joue chaque scène et
photographie l'écran plusieurs fois pendant l'animation, puis assemble une planche par scène
(PNG, si Pillow est là). La vitesse d'origine est TOUJOURS remise, même après Ctrl+C.
Scènes : ouverture/fermeture d'une fenêtre, Réglages rapides, lanceur d'applis, capture
façon Android. Il faut Spectacle ; rien n'est cliqué à votre place.
"""
import argparse
import configparser
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time

HOME = os.path.expanduser("~")
APPLETSRC = os.path.join(HOME, ".config", "plasma-org.kde.plasma.desktop-appletsrc")
QML = (shutil.which("qml6") or shutil.which("qml-qt6")
       or next((p for p in ("/usr/lib/qt6/bin/qml", "/usr/lib64/qt6/bin/qml") if os.path.exists(p)), "qml"))


def sh(*cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=kw.pop("timeout", 30), **kw)


def factor_get():
    return sh("kreadconfig6", "--file", "kdeglobals", "--group", "KDE", "--key", "AnimationDurationFactor").stdout.strip()


def factor_set(v):
    if v == "":
        sh("kwriteconfig6", "--notify", "--file", "kdeglobals", "--group", "KDE", "--key", "AnimationDurationFactor", "--delete")
    else:
        sh("kwriteconfig6", "--notify", "--file", "kdeglobals", "--group", "KDE", "--key", "AnimationDurationFactor", str(v))
    sh("gdbus", "call", "--session", "--dest", "org.kde.KWin", "--object-path", "/KWin", "--method", "org.kde.KWin.reconfigure")


def applet_id(plugin):
    cp = configparser.RawConfigParser(strict=False, interpolation=None)
    try:
        cp.read(APPLETSRC, encoding="utf-8")
    except configparser.Error:
        return None
    for sec in cp.sections():
        if cp.get(sec, "plugin", fallback="") == plugin and "][Applets][" in sec and sec.count("[") == 3:
            return sec.rsplit("[", 1)[1].rstrip("]")
    return None


def activate(plugin):
    aid = applet_id(plugin)
    if aid:
        sh("gdbus", "call", "--session", "-d", "org.kde.kglobalaccel", "-o", "/component/plasmashell",
           "-m", "org.kde.kglobalaccel.Component.invokeShortcut", f"activate widget {aid}")
    return aid


def grab(path):
    sh("spectacle", "-b", "-n", "-m", "-o", path, timeout=15)


def burst(out, name, n, gap=0.12):
    files = []
    for i in range(n):
        p = os.path.join(out, f"{name}-{i}.png")
        grab(p)
        if os.path.exists(p):
            files.append(p)
        time.sleep(gap)
    return files


def sheet(out, name, files):
    try:
        from PIL import Image
    except ImportError:
        return None
    if not files:
        return None
    w, h = 560, 350
    img = Image.new("RGB", (len(files) * (w + 10), h), "black")
    for i, f in enumerate(files):
        img.paste(Image.open(f).convert("RGB").resize((w, h)), (i * (w + 10), 0))
    p = os.path.join(out, f"{name}.png")
    img.save(p)
    for f in files:
        os.remove(f)
    return p


WINDOW_QML = """import QtQuick
import QtQuick.Window
Window { width: 640; height: 420; visible: true; title: "Test ralenti"; color: "#5b4a8a"
  Text { anchors.centerIn: parent; text: "Fenêtre de test"; color: "white"; font.pixelSize: 32 }
  Timer { interval: %d; running: true; onTriggered: Qt.quit() } }
"""


def scene_window(out, k):
    qml = os.path.join(out, "window.qml")
    with open(qml, "w", encoding="utf-8") as f:
        f.write(WINDOW_QML % int(2500 * k / 8 + 1500))
    p = subprocess.Popen([QML, qml], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    files = burst(out, "window-open", 4)
    time.sleep(max(0.5, 2500 * k / 8 / 1000 + 1.5 - 4 * 0.4))
    files += burst(out, "window-close", 4)
    p.wait(timeout=30)
    os.remove(qml)
    return sheet(out, "fenetre", files)


def scene_popup(out, plugin, name):
    if not activate(plugin):
        print(f"  (widget {plugin} absent, scène sautée)")
        return None
    files = burst(out, name, 5)
    activate(plugin)            # close it again: photograph the fold right away
    files += burst(out, name + "-close", 3, gap=0.02)
    return sheet(out, name, files)


def shots_dir():
    r = sh("bash", "-c", 'd=$(kreadconfig6 --file spectaclerc --group ImageSave --key imageSaveLocation); d=${d#file://};'
           '[ -z "$d" ] && d="$(xdg-user-dir PICTURES)/$(kreadconfig6 --file spectaclerc --group ImageSave --key translatedScreenshotsFolder)";'
           'printf %s "$d"')
    return r.stdout


def scene_screenshot(out, k):
    script = shutil.which("doodlebookos-screenshot") or os.path.join(HOME, ".local", "bin", "doodlebookos-screenshot")
    if not os.path.exists(script):
        return None
    folder = shots_dir()
    before = set(os.listdir(folder)) if os.path.isdir(folder) else set()
    p = subprocess.Popen([script], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.6)
    files = burst(out, "capture", 5)
    p.wait(timeout=60)
    # only the image this scene took goes away
    if os.path.isdir(folder):
        for f in set(os.listdir(folder)) - before:
            if f.startswith("Capture"):
                os.remove(os.path.join(folder, f))
    return sheet(out, "capture", files)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    ap.add_argument("--factor", type=float, default=8)
    ap.add_argument("--out", default=None)
    ap.add_argument("--only", default="window,qs,launcher,screenshot")
    a = ap.parse_args()
    if not shutil.which("spectacle"):
        sys.exit("Spectacle est nécessaire pour photographier l'écran.")
    out = a.out or tempfile.mkdtemp(prefix="doodlebookos-ralenti-")
    os.makedirs(out, exist_ok=True)

    old = factor_get()
    # Spectacle remembers the last file it wrote: put the user's value back afterwards
    last = sh("kreadconfig6", "--file", "spectaclerc", "--group", "ImageSave", "--key", "lastImageSaveLocation").stdout.strip()
    restore = lambda *_: (factor_set(old), sys.exit(130))
    signal.signal(signal.SIGINT, restore)
    signal.signal(signal.SIGTERM, restore)
    base = float(old) if old not in ("", "0") else 1.0
    try:
        factor_set(round(base * a.factor, 2))
        print(f"Animations × {a.factor} (vitesse d'origine : {old or 'par défaut'})")
        made = []
        only = set(a.only.split(","))
        if "window" in only:
            print("- fenêtre : ouverture / fermeture")
            made.append(scene_window(out, a.factor))
        if "qs" in only:
            print("- Réglages rapides")
            made.append(scene_popup(out, "org.doodlebookos.statuscluster", "reglages-rapides"))
        if "launcher" in only:
            print("- lanceur d'applis")
            made.append(scene_popup(out, "org.doodlebookos.dock", "lanceur"))
        if "screenshot" in only:
            print("- capture façon Android")
            made.append(scene_screenshot(out, a.factor))
    finally:
        factor_set(old)
        sh("kwriteconfig6", "--file", "spectaclerc", "--group", "ImageSave", "--key", "lastImageSaveLocation",
           *((last,) if last else ("--delete",)))
    print(f"Vitesse remise à {old or 'par défaut'}.")
    for m in made:
        if m:
            print("  " + m)
    print(f"Planches dans {out}")


if __name__ == "__main__":
    main()

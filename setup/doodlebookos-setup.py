#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""
DoodlebookOS — installe et applique le thème complet sur KDE Plasma 6, sans droits admin.

Tout va dans le dossier personnel (~/.local, ~/.config). Le bureau actuel est d'abord
sauvegardé comme profil theme-switch « avant-doodlebookos-<date> » :
    theme-switch use avant-doodlebookos-<date>     # revenir en arrière

    python3 setup/doodlebookos-setup.py [--yes] [--no-gui] [--keep-wallpaper]

Le fichier unique DoodlebookOS-Installer.run (setup/make-installer.sh) embarque ce script,
le dépôt, les icônes Tela-circle / glyphes Material, et les modules C++ précompilés.
"""
import datetime
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUNDLE = os.path.join(ROOT, "bundle")
PROFILE = os.path.join(ROOT, "setup", "profile")
try:
    with open(os.path.join(ROOT, "VERSION"), encoding="utf-8") as _f:
        VERSION = _f.read().strip()          # written by make-installer.sh (release tag)
except OSError:
    VERSION = "dev"
HOME = os.path.expanduser("~")
CFG = os.environ.get("XDG_CONFIG_HOME") or os.path.join(HOME, ".config")
SHARE = os.path.join(HOME, ".local", "share")
BIN = os.path.join(HOME, ".local", "bin")
STATE = os.path.join(HOME, ".local", "state", "doodlebookos")
LOG = os.path.join(STATE, "install.log")
UNITS = os.path.join(CFG, "systemd", "user")

ARGS = set(sys.argv[1:])
os.makedirs(STATE, exist_ok=True)
_log = open(LOG, "a", encoding="utf-8")


def log(msg):
    _log.write(msg.rstrip() + "\n")
    _log.flush()


def which(*names):
    for n in names:
        p = shutil.which(n)
        if p:
            return p
    return None


def run(cmd, check=False, timeout=600, env=None, input=None):
    log("$ " + " ".join(str(c) for c in cmd))
    try:
        r = subprocess.run([str(c) for c in cmd], capture_output=True, text=True, timeout=timeout,
                           env=env, input=input)
    except (OSError, subprocess.TimeoutExpired) as e:
        log(f"  ! {e}")
        if check:
            raise
        return None
    if r.stdout.strip():
        log(r.stdout.strip()[-2000:])
    if r.stderr.strip():
        log("  stderr: " + r.stderr.strip()[-2000:])
    if check and r.returncode != 0:
        raise RuntimeError(f"{os.path.basename(str(cmd[0]))} a échoué ({r.returncode})")
    return r


QDBUS = which("qdbus-qt6", "qdbus6", "qdbus")


def dbus(service, path, method, *args, timeout=60):
    """Session-bus call through qdbus, else gdbus. Returns stdout or None."""
    if QDBUS:
        r = run([QDBUS, service, path, method, *args], timeout=timeout)
    elif which("gdbus"):
        iface, _, meth = method.rpartition(".")
        r = run(["gdbus", "call", "--session", "--dest", service, "--object-path", path,
                 "--method", method, *[json.dumps(a) if isinstance(a, str) else str(a) for a in args]], timeout=timeout)
    else:
        return None
    return r.stdout if r is not None and r.returncode == 0 else None


# ───────────────────────────── interface (kdialog or terminal) ─────────────────────────────
class UI:
    TITLE = "DoodlebookOS"

    def __init__(self):
        has_display = bool(os.environ.get("WAYLAND_DISPLAY") or os.environ.get("DISPLAY"))
        self.gui = bool(which("kdialog")) and has_display and ("--no-gui" not in ARGS) \
            and (not sys.stdin.isatty() or "--gui" in ARGS)
        self.bar = None
        self.n = 0
        self.total = 1
        self.notes = []

    def ask(self, text):
        if "--yes" in ARGS:
            return True
        if self.gui:
            return subprocess.run(["kdialog", "--title", self.TITLE, "--yesno", text]).returncode == 0
        a = input(re.sub(r"<[^>]+>", "", text) + " [o/N] ").strip().lower()
        return a in ("o", "oui", "y", "yes")

    def start(self, total):
        self.total = total
        if self.gui:
            r = subprocess.run(["kdialog", "--title", self.TITLE, "--progressbar", "Préparation…", str(total)],
                               capture_output=True, text=True)
            parts = r.stdout.split()
            if len(parts) == 2:
                self.bar = parts

    def step(self, text):
        self.n += 1
        log(f"\n=== {text} ===")
        if self.bar:
            dbus(self.bar[0], self.bar[1], "org.kde.kdialog.ProgressDialog.setLabelText", text)
            if QDBUS:
                run([QDBUS, self.bar[0], self.bar[1], "Set", "", "value", str(self.n)])
            else:
                run(["gdbus", "call", "--session", "--dest", self.bar[0], "--object-path", self.bar[1], "--method",
                     "org.freedesktop.DBus.Properties.Set", "org.kde.kdialog.ProgressDialog", "value", f"<{self.n}>"])
        else:
            print(f"[{self.n}/{self.total}] {text}", flush=True)

    def note(self, text):
        log("NOTE: " + text)
        self.notes.append(text)
        if not self.gui:
            print("    ⚠ " + text, flush=True)

    def close(self):
        if self.bar:
            dbus(self.bar[0], self.bar[1], "org.kde.kdialog.ProgressDialog.close")
            self.bar = None

    def message(self, text, error=False):
        self.close()
        if self.gui:
            subprocess.run(["kdialog", "--title", self.TITLE, "--error" if error else "--msgbox", text])
        else:
            print(("\n[!] " if error else "\n") + re.sub(r"<br>", "\n", re.sub(r"<(?!br)[^>]+>", "", text)), flush=True)


ui = UI()


# ───────────────────────────── helpers ─────────────────────────────
def rm(path):
    if os.path.islink(path) or os.path.isfile(path):
        os.unlink(path)
    elif os.path.isdir(path):
        shutil.rmtree(path)


def copytree(src, dst):
    rm(dst)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copytree(src, dst, symlinks=True, ignore=shutil.ignore_patterns("__pycache__", "*.pyc", "build"))


def copyfile(src, dst, mode=None):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    tmp = f"{dst}.new.{os.getpid()}"
    shutil.copy2(src, tmp)
    if mode:
        os.chmod(tmp, mode)
    os.replace(tmp, dst)   # never rewrite a file in place (a loaded .so would crash its process)


def kwrite(file, group, key, value):
    groups = []
    for g in group.split("]["):
        groups += ["--group", g]
    run(["kwriteconfig6", "--file", file, *groups, "--key", key, "--", value])


def kread(file, group, key, default=""):
    r = run(["kreadconfig6", "--file", file, "--group", group, "--key", key, "--default", default])
    return r.stdout.strip() if r and r.returncode == 0 else default


def plasma_version():
    # offscreen: answers even from a text console (plasmashell is a GUI program)
    r = run(["plasmashell", "--version"], env=dict(os.environ, QT_QPA_PLATFORM="offscreen")) if which("plasmashell") else None
    m = re.search(r"(\d+)\.(\d+)(?:\.(\d+))?", r.stdout if r else "")
    return tuple(int(x or 0) for x in m.groups()) if m else None


def shell_running():
    out = dbus("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus.NameHasOwner", "org.kde.plasmashell")
    return bool(out and "true" in out)


def has_python_module(mod):
    return subprocess.run([sys.executable, "-c", f"import {mod}"], capture_output=True).returncode == 0


def lib_dirs():
    return [os.path.join(HOME, ".local", d) for d in ("lib64", "lib")]


# ───────────────────────────── steps ─────────────────────────────
def check_system():
    v = plasma_version()
    if not v or v[0] != 6:
        ui.message("DoodlebookOS demande <b>KDE Plasma 6</b>.<br>Plasma n'a pas été trouvé sur ce PC"
                   + (f" (version {'.'.join(map(str, v))})" if v else "") + ".", error=True)
        sys.exit(1)
    for tool in ("kwriteconfig6", "kreadconfig6"):
        if not which(tool):
            ui.message(f"Outil KDE manquant : {tool}", error=True)
            sys.exit(1)
    return v


def backup(ts):
    copyfile(os.path.join(ROOT, "extras", "scripts", "theme-switch"), os.path.join(BIN, "theme-switch"), 0o755)
    name = f"avant-doodlebookos-{ts}"
    r = run([os.path.join(BIN, "theme-switch"), "save", name], env=dict(os.environ, NO_RESTART="1"), input="o\n")
    if not r or r.returncode != 0:
        raise RuntimeError("sauvegarde du bureau impossible")
    return name


def install_files():
    # widgets (plasmoids) — the Desktop package replaces the folder-view containment
    pl = os.path.join(SHARE, "plasma", "plasmoids")
    for meta in sorted(glob.glob(os.path.join(ROOT, "widgets", "*", "metadata.json"))):
        with open(meta, encoding="utf-8") as f:
            pid = json.load(f)["KPlugin"]["Id"]
        copytree(os.path.dirname(meta), os.path.join(pl, pid))
    for alias, target in (("org.kde.plasma.folder", "org.kde.desktopcontainment"),
                          ("org.doodlebookos.folder", "org.doodlebookos.appgroup")):
        rm(os.path.join(pl, alias))
        os.symlink(os.path.join(pl, target), os.path.join(pl, alias))
    # StatusCluster / DateTime reuse the native notifications / digital clock C++ backends
    for alias, native in (("org.doodlebookos.statuscluster", "org.kde.plasma.notifications"),
                          ("org.doodlebookos.datetime", "org.kde.plasma.digitalclock")):
        found = None
        for base in ("/usr/lib64/qt6/plugins", "/usr/lib/qt6/plugins", "/usr/lib/x86_64-linux-gnu/qt6/plugins",
                     "/usr/lib/aarch64-linux-gnu/qt6/plugins"):
            p = os.path.join(base, "plasma", "applets", native + ".so")
            if os.path.exists(p):
                found = p
                break
        if not found:
            ui.note(f"module natif {native} introuvable : {alias} peut ne pas se charger")
            continue
        for ld in lib_dirs():
            for sub in ("plugins", os.path.join("qt6", "plugins")):
                d = os.path.join(ld, sub, "plasma", "applets")
                os.makedirs(d, exist_ok=True)
                rm(os.path.join(d, alias + ".so"))
                os.symlink(found, os.path.join(d, alias + ".so"))
    # KWin scripts, effects, task switcher
    for kind, sub in (("kwin-scripts", "scripts"), ("kwin-effects", "effects"), ("kwin-tabbox", "tabbox")):
        for d in sorted(glob.glob(os.path.join(ROOT, "themes", kind, "*", "metadata.json"))):
            with open(d, encoding="utf-8") as f:
                pid = json.load(f)["KPlugin"]["Id"]
            copytree(os.path.dirname(d), os.path.join(SHARE, "kwin", sub, pid))
    # Plasma style, global theme, colours
    for d in glob.glob(os.path.join(ROOT, "themes", "plasma-theme", "*")):
        if os.path.isdir(d):
            copytree(d, os.path.join(SHARE, "plasma", "desktoptheme", os.path.basename(d)))
    # Plasma caches rendered theme SVGs: drop them so changed backgrounds show at the next start
    for cache in glob.glob(os.path.join(HOME, ".cache", "plasma_theme_DoodlebookOS_*.kcache")):
        rm(cache)
    copytree(os.path.join(ROOT, "themes", "look-and-feel", "DoodlebookOS"),
             os.path.join(SHARE, "plasma", "look-and-feel", "org.doodlebookos.desktop"))
    for f in glob.glob(os.path.join(ROOT, "themes", "color-schemes", "*.colors")):
        copyfile(f, os.path.join(SHARE, "color-schemes", os.path.basename(f)))
    # cursors, icons, fonts, wallpapers
    ex = os.path.join(ROOT, "extras")
    copytree(os.path.join(ex, "cursors", "DoodlebookOS-Cursors"), os.path.join(SHARE, "icons", "DoodlebookOS-Cursors"))
    copytree(os.path.join(ex, "icons", "DoodlebookOS"), os.path.join(SHARE, "icons", "DoodlebookOS"))
    for f in glob.glob(os.path.join(ex, "fonts", "GoogleSansFlex", "*")):
        if os.path.isfile(f):
            copyfile(f, os.path.join(SHARE, "fonts", "GoogleSansFlex", os.path.basename(f)))
    for f in glob.glob(os.path.join(ex, "wallpapers", "*")):
        if os.path.isfile(f) and not os.path.islink(f):
            copyfile(f, os.path.join(SHARE, "wallpapers", "DoodlebookOS", os.path.basename(f)))
    if which("fc-cache"):
        run(["fc-cache", "-f", os.path.join(SHARE, "fonts")])
    # third-party icon base + glyphs (only in the .run bundle)
    for name in ("Tela-circle", "Tela-circle-dark"):
        src = os.path.join(BUNDLE, "icons", name)
        if os.path.isdir(src):
            copytree(src, os.path.join(SHARE, "icons", name))
    for name in ("m3icons", "icon-template-tela-circle"):
        src = os.path.join(BUNDLE, name)
        if os.path.isdir(src):
            copytree(src, os.path.join(SHARE, "doodlebookos", name))
    # helper commands
    for f in glob.glob(os.path.join(ex, "scripts", "*")):
        if os.path.isfile(f) and not f.endswith((".service", ".path", ".pyc")):
            copyfile(f, os.path.join(BIN, os.path.basename(f)), 0o755)
    # GTK apps follow the colours
    for v in ("3", "4"):
        d = os.path.join(CFG, f"gtk-{v}.0")
        src = os.path.join(ex, "gtk", f"doodlebookos-gtk{v}.css")
        if not os.path.exists(src):
            continue
        copyfile(src, os.path.join(d, "doodlebookos.css"))
        css = os.path.join(d, "gtk.css")
        txt = open(css, encoding="utf-8").read() if os.path.exists(css) else ""
        if "doodlebookos.css" not in txt:
            with open(css, "a", encoding="utf-8") as f:
                f.write(("\n" if txt and not txt.endswith("\n") else "") + "@import 'doodlebookos.css';\n")
    # user services (event driven: they run only when their watched files change)
    for f in (os.path.join(ex, "scripts", "doodlebookos-topbar.path"), os.path.join(ex, "scripts", "doodlebookos-topbar.service"),
              os.path.join(ex, "systemd", "doodlebookos-gamemode@.service"),
              *glob.glob(os.path.join(ex, "systemd", "m3icons", "*")),
              *glob.glob(os.path.join(ex, "systemd", "powersave", "*"))):
        if os.path.isfile(f):
            copyfile(f, os.path.join(UNITS, os.path.basename(f)))
    voice = os.path.join(ex, "systemd", "voice-priority", "50-doodlebookos-voice.conf")
    if os.path.isfile(voice):
        for scope in ("app-flatpak-dev.vencord.Vesktop-.scope.d", "app-flatpak-com.discordapp.Discord-.scope.d",
                      "app-vesktop-.scope.d", "app-discord-.scope.d", "app-dev.vencord.Vesktop-.scope.d"):
            copyfile(voice, os.path.join(UNITS, scope, os.path.basename(voice)))
    # Alt+Space opens the DoodlebookOS launcher (needs python dbus + gi, else KRunner stays)
    bridge = os.path.join(ROOT, "system-overrides", "krunner-bridge")
    if has_python_module("dbus") and has_python_module("gi.repository.GLib"):
        copyfile(os.path.join(bridge, "doodlebook-krunner-bridge.py"), os.path.join(BIN, "doodlebook-krunner-bridge.py"), 0o755)
        copyfile(os.path.join(bridge, "systemd", "plasma-krunner.service"), os.path.join(UNITS, "plasma-krunner.service"))
    # updates: daily check (timer), install at the next login before the desktop starts
    for f in glob.glob(os.path.join(ex, "systemd", "update", "*")):
        copyfile(f, os.path.join(UNITS, os.path.basename(f)))
    copyfile(os.path.join(ROOT, "setup", "update.json"), os.path.join(SHARE, "doodlebookos", "update.json"))
    # uninstaller kept next to the data
    copyfile(os.path.join(ROOT, "uninstall.sh"), os.path.join(SHARE, "doodlebookos", "uninstall.sh"), 0o755)
    if which("kbuildsycoca6"):
        run(["kbuildsycoca6"])


def plugin_env():
    """KWin and Qt apps look for plugins in ~/.local only through QT_PLUGIN_PATH (from the next login)."""
    dirs = []
    for ld in lib_dirs():
        dirs += [os.path.join(ld, "qt6", "plugins"), os.path.join(ld, "plugins")]
    dirs += ["/usr/lib64/qt6/plugins", "/usr/lib/qt6/plugins", "/usr/lib/x86_64-linux-gnu/qt6/plugins",
             "/usr/lib/aarch64-linux-gnu/qt6/plugins"]
    val = ":".join(dirs)
    envd = os.path.join(CFG, "environment.d")
    os.makedirs(envd, exist_ok=True)
    with open(os.path.join(envd, "10-qt-plugins.conf"), "w", encoding="utf-8") as f:
        f.write(f"QT_PLUGIN_PATH={val}\n")
    if which("systemctl"):
        run(["systemctl", "--user", "set-environment", f"QT_PLUGIN_PATH={val}"])
    if which("dbus-update-activation-environment"):
        run(["dbus-update-activation-environment", "--systemd", f"QT_PLUGIN_PATH={val}"])


def prebuilt_ok(so, info, pv):
    if not os.path.isfile(so) or tuple(info.get("plasma", [0, 0])[:2]) != pv[:2]:
        return False
    r = run(["ldd", "-r", so]) if which("ldd") else None
    out = (r.stdout + r.stderr) if r else ""
    return bool(r) and r.returncode == 0 and "not found" not in out and "undefined symbol" not in out


def install_so(so, sub, name):
    for ld in lib_dirs():
        dest = os.path.join(ld, "plugins", sub, name)
        copyfile(so, dest, 0o755)
        link = os.path.join(ld, "qt6", "plugins", sub, name)
        os.makedirs(os.path.dirname(link), exist_ok=True)
        rm(link)
        os.symlink(dest, link)


def can_build():
    if not (which("cmake") and which("ninja") and which("g++", "c++")):
        return False
    return any(glob.glob(p) for p in ("/usr/lib*/cmake/KDecoration3", "/usr/lib/*/cmake/KDecoration3"))


def native_parts(pv):
    """Window decoration + Qt application style. Returns (decoration, style) installed."""
    info = {}
    try:
        with open(os.path.join(BUNDLE, "prebuilt", "buildinfo.json"), encoding="utf-8") as f:
            info = json.load(f)
    except (OSError, ValueError):
        pass
    got = {}
    for key, so_name, sub, script in (
            ("deco", "org.doodlebookos.decoration.so", "org.kde.kdecoration3", "themes/window-decoration/DoodlebookOS/build.sh"),
            ("style", "doodlebookos6.so", "styles", "themes/app-style/DoodlebookOS/build.sh")):
        so = os.path.join(BUNDLE, "prebuilt", so_name)
        if prebuilt_ok(so, info, pv):
            install_so(so, sub, so_name)
            got[key] = True
        elif can_build():
            r = run(["bash", os.path.join(ROOT, script)], timeout=1800)
            got[key] = bool(r and r.returncode == 0)
        else:
            got[key] = False
    style_rc = os.path.join(ROOT, "themes", "app-style", "DoodlebookOS", "doodlebookos.themerc")
    if got.get("style") and os.path.exists(style_rc):
        copyfile(style_rc, os.path.join(SHARE, "kstyle", "themes", "doodlebookos.themerc"))
    if not got.get("deco") or not got.get("style"):
        built = ".".join(map(str, info.get("plasma", [])[:2])) or "?"
        ui.note("Décoration des fenêtres / style des applis non installés : modules compilés pour Plasma "
                f"{built}, ce PC a Plasma {pv[0]}.{pv[1]}. Pour les compiler : installer cmake, ninja, g++ et les "
                "paquets de développement KDE (voir install.sh du dépôt), puis relancer l'installeur.")
    return got.get("deco", False), got.get("style", False)


def apply_settings(settings, deco, style):
    fonts = run(["fc-list", ":", "family"]) if which("fc-list") else None
    families = fonts.stdout if fonts else ""
    for file, group, key, value in settings.get("kconfig", []):
        if file == "kwinrc" and group == "org.kde.kdecoration2" and key in ("library", "theme") and not deco:
            continue
        if file == "kdeglobals" and key == "widgetStyle" and not style:
            continue
        if file == "kdeglobals" and (key.lower().endswith("font") or key == "fixed"):
            fam = value.split(",")[0]
            if families and fam not in families:
                continue                      # keep the PC's own font rather than a missing one
        kwrite(file, group, key, value)
    mode = settings.get("doodlebookos", {}).get("mode", "dark")
    theme = "DoodlebookOS_Light" if mode == "light" else "DoodlebookOS_Dark"
    if which("plasma-apply-desktoptheme"):
        run(["plasma-apply-desktoptheme", theme])
    if which("plasma-apply-cursortheme"):
        run(["plasma-apply-cursortheme", "DoodlebookOS-Cursors"])
    if which("dbus-send"):
        run(["dbus-send", "--type=signal", "/KGlobalSettings", "org.kde.KGlobalSettings.notifyChange", "int32:1", "int32:0"])
    st = os.path.join(CFG, "doodlebookos")
    os.makedirs(st, exist_ok=True)
    extra = settings.get("doodlebookos", {})
    pack = extra.get("icon-pack", "material")
    if not os.path.isdir(os.path.join(SHARE, "icons", "Tela-circle-dark")) or \
            (pack == "material" and not os.path.isdir(os.path.join(SHARE, "doodlebookos", "m3icons"))):
        pack = None
    if pack:
        with open(os.path.join(st, "icon-pack"), "w", encoding="utf-8") as f:
            f.write(pack + "\n")
    if extra.get("icon-shape"):
        with open(os.path.join(st, "icon-shape"), "w", encoding="utf-8") as f:
            f.write(extra["icon-shape"] + "\n")
    return pack


def file_dialog_defaults():
    """KDE file dialog (also the one browsers open through the xdg portal): breadcrumb path, list
    view with normal-size icons, readable sidebar, A→Z. Applied once (marker key), so later
    choices made in the dialog itself are kept across updates."""
    grp = "KFileDialog Settings"
    if kread("kdeglobals", grp, "DoodlebookOSDefaults", "") == "1":
        return
    if kread("kdeglobals", grp, "View Style", "DetailTree") in ("DetailTree", ""):
        kwrite("kdeglobals", grp, "View Style", "Detail")
    for key, value in (("Breadcrumb Navigation", "true"), ("Sort reversed", "false"),
                       ("Sort directories first", "true"), ("Sort hidden files last", "true"),
                       ("Show Inline Previews", "true"), ("Allow Expansion", "false"),
                       ("Automatically select filename extension", "true"),
                       ("Places Icons Auto-resize", "false"), ("Places Icons Static Size", "22")):
        kwrite("kdeglobals", grp, key, value)
    try:
        width = int(kread("kdeglobals", grp, "Speedbar Width", "0") or 0)
    except ValueError:
        width = 0
    if width < 170:
        kwrite("kdeglobals", grp, "Speedbar Width", "196")
    # the portal keeps its own icon sizes: 128 px icons in the list view made every row huge
    for rc in ("xdg-desktop-portal-kderc", "kdialogrc"):
        try:
            size = int(kread(rc, grp, "detailViewIconSize", "0") or 0)
        except ValueError:
            size = 0
        if size == 0 or size > 48:
            kwrite(rc, grp, "detailViewIconSize", "32")
    kwrite("kdeglobals", grp, "DoodlebookOSDefaults", "1")


def wallpaper_path(mode):
    d = os.path.join(SHARE, "wallpapers", "DoodlebookOS")
    for name in (f"DoodlebookOS_Wallpaper_{'LIGHT' if mode == 'light' else 'DARK'}", "DoodlebookOS_Wallpaper_DARK"):
        for ext in (".png", ".jpeg", ".jpg"):
            p = os.path.join(d, name + ext)
            if os.path.exists(p):
                return p
    return None


def apply_layout(layout, wallpaper):
    panels = json.dumps(layout.get("panels", []), ensure_ascii=False)
    widgets = json.dumps(layout.get("desktopWidgets", []), ensure_ascii=False)
    shortcuts = json.dumps(layout.get("shortcuts", {}), ensure_ascii=False)
    wp = json.dumps("file://" + wallpaper if wallpaper else "")
    js = f"""
var plasma = getApiVersion(1);
var old = panels();
for (var i = 0; i < old.length; ++i) old[i].remove();
plasma.loadSerializedLayout({{"serializationFormatVersion": "1", "desktops": [], "panels": {panels}}});
var keys = {shortcuts};
var ps = panels();
for (var i = 0; i < ps.length; ++i) {{
    var ws = ps[i].widgets();
    for (var j = 0; j < ws.length; ++j) if (keys[ws[j].type]) ws[j].globalShortcut = keys[ws[j].type];
}}
var specs = {widgets};
var wpUrl = {wp};
var ds = desktops();
for (var d = 0; d < ds.length; ++d) {{
    var desk = ds[d];
    if (wpUrl.length > 0) {{
        desk.wallpaperPlugin = "org.kde.image";
        desk.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
        desk.writeConfig("Image", wpUrl);
    }}
    if (desk.screen !== 0) continue;
    var have = {{}};
    var cur = desk.widgets();
    for (var k = 0; k < cur.length; ++k) have[cur[k].type] = true;
    var g = screenGeometry(desk.screen);
    var sw = g && g.width > 0 ? g.width : 1920, sh = g && g.height > 0 ? g.height : 1080;
    for (var s = 0; s < specs.length; ++s) {{
        var sp = specs[s];
        if (have[sp.plugin]) continue;
        var geo = sp.geometry || [0.05, 0.1 + 0.2 * s, 300, 200];
        var w = desk.addWidget(sp.plugin, Math.round(geo[0] * sw), Math.round(geo[1] * sh), geo[2], geo[3]);
        if (!w) continue;
        for (var grp in sp.config) {{
            w.currentConfigGroup = grp.split("/").filter(function (x) {{ return x.length > 0; }});
            for (var key in sp.config[grp]) w.writeConfig(key, sp.config[grp][key]);
        }}
    }}
}}
"""
    out = dbus("org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell.evaluateScript", js, timeout=120)
    return out is not None


def stop_shell():
    if which("systemctl") and run(["systemctl", "--user", "stop", "plasma-plasmashell.service"]) is not None:
        time.sleep(1)
        if not shell_running():
            return
    if which("kquitapp6"):
        run(["kquitapp6", "plasmashell"])
        time.sleep(1)


def start_shell():
    shutil.rmtree(os.path.join(HOME, ".cache", "plasmashell", "qmlcache"), ignore_errors=True)
    for f in glob.glob(os.path.join(HOME, ".cache", "plasma_theme_*.kcache")) + glob.glob(os.path.join(HOME, ".cache", "ksvg-elements*")):
        try:
            rm(f)
        except OSError:
            pass
    r = run(["systemctl", "--user", "start", "plasma-plasmashell.service"]) if which("systemctl") else None
    if not r or r.returncode != 0:
        subprocess.Popen(["setsid", "plasmashell", "--replace"] if which("setsid") else ["plasmashell", "--replace"],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    for _ in range(40):
        if shell_running():
            return True
        time.sleep(0.5)
    return False


def free_right_click():
    """The DoodlebookOS desktop draws its own context menu: unbind Plasma's on every containment."""
    rc = os.path.join(CFG, "plasma-org.kde.plasma.desktop-appletsrc")
    try:
        ids = set(re.findall(r"^\[Containments\]\[(\d+)\]$", open(rc, encoding="utf-8").read(), re.M))
    except OSError:
        return
    for cid in sorted(ids, key=int):
        run(["kwriteconfig6", "--file", "plasma-org.kde.plasma.desktop-appletsrc", "--group", "ActionPlugins",
             "--group", cid, "--key", "RightButton;NoModifier", ""])


# feature → (QML module dir, PY:python module or BIN:command; package for pacman, dnf, apt-get, zypper)
DEPS = (
    ("son", "org/kde/plasma/private/volume", ("plasma-pa", "plasma-pa", "plasma-pa", "plasma6-pa")),
    ("réseau / Wi-Fi", "org/kde/plasma/networkmanagement", ("plasma-nm", "plasma-nm", "plasma-nm", "plasma6-nm")),
    ("Bluetooth", "org/kde/bluezqt", ("bluez-qt", "kf6-bluez-qt", "qml6-module-org-kde-bluezqt", "kf6-bluez-qt-imports")),
    ("luminosité", "org/kde/plasma/private/brightnesscontrolplugin", ("powerdevil", "powerdevil", "powerdevil", "powerdevil6")),
    ("téléphone (KDE Connect)", "org/kde/kdeconnect", ("kdeconnect", "kde-connect", "kdeconnect", "kdeconnect-kde")),
    ("aperçu des fenêtres du dock", "org/kde/pipewire", ("kpipewire", "kpipewire", "qml6-module-org-kde-pipewire", "kpipewire6-imports")),
    ("widget Système", "org/kde/ksysguard/sensors", ("libksysguard", "libksysguard", "qml6-module-org-kde-ksysguard", "libksysguard6-imports")),
    ("couleurs Material You", "PY:PIL", ("python-pillow", "python3-pillow", "python3-pil", "python3-Pillow")),
    ("icônes de la barre et presse-papiers", "PY:gi.repository.Gio",
     ("python-gobject", "python3-gobject", "python3-gi", "python3-gobject")),
    ("lanceur Alt+Espace", "PY:dbus", ("python-dbus", "python3-dbus", "python3-dbus", "python3-dbus-python")),
    ("mises à jour signées", "BIN:ssh-keygen", ("openssh", "openssh-clients", "openssh-client", "openssh-clients")),
)


def qml_dirs():
    dirs = []
    r = run(["qtpaths6", "--query", "QT_INSTALL_QML"]) if which("qtpaths6") else None
    if r and r.returncode == 0 and r.stdout.strip():
        dirs.append(r.stdout.strip())
    return dirs + ["/usr/lib64/qt6/qml", "/usr/lib/qt6/qml", "/usr/lib/x86_64-linux-gnu/qt6/qml",
                   "/usr/lib/aarch64-linux-gnu/qt6/qml"]


def missing_deps():
    bases = qml_dirs()
    out = []
    for label, mod, pkgs in DEPS:
        if mod.startswith("PY:"):
            ok = has_python_module(mod[3:])
        elif mod.startswith("BIN:"):
            ok = bool(which(mod[4:]))
        else:
            ok = any(os.path.isfile(os.path.join(b, mod, "qmldir")) for b in bases)
        if not ok:
            out.append((label, pkgs))
    return out


def ensure_deps():
    """Widgets need a few KDE parts that minimal installs may lack: one question, one password."""
    miss = missing_deps()
    if not miss:
        return
    labels = ", ".join(m[0] for m in miss)
    col, cmd = None, None
    if which("rpm-ostree") and os.path.exists("/run/ostree-booted"):
        pass                                             # immutable system: no live package install
    elif which("pacman"):
        col, cmd = 0, "pacman -S --needed --noconfirm"   # no -Sy: never a partial upgrade
    elif which("dnf"):
        col, cmd = 1, "dnf install -y"
    elif which("apt-get"):
        col, cmd = 2, "apt-get install -y"
    elif which("zypper"):
        col, cmd = 3, "zypper --non-interactive install"
    if col is None or not which("pkexec"):
        ui.note(f"Paquets KDE manquants ({labels}) : ces fonctions resteront absentes ; à installer "
                "avec le gestionnaire de paquets puis relancer l'installeur.")
        return
    pkgs = [m[1][col] for m in miss]
    if not ui.ask(f"Il manque des paquets pour : <b>{labels}</b>.<br>Paquets : {' '.join(pkgs)}<br><br>"
                  "Les installer maintenant ? (mot de passe administrateur)"):
        ui.note(f"Paquets non installés ({labels}) : ces fonctions resteront absentes.")
        return
    # one package at a time: a name unknown on this distribution never blocks the others
    run(["pkexec", "sh", "-c", f'for p; do {cmd} "$p"; done', "sh", *pkgs], timeout=1800)
    left = missing_deps()
    if left:
        ui.note("Toujours manquant : " + ", ".join(m[0] for m in left) + ".")


def material_you(pack, mode):
    my = os.path.join(BIN, "doodlebookos-materialyou")
    run([os.path.join(BIN, "doodlebookos-m3icons"), "shape-json"], timeout=120)   # dock / photo shapes
    if not has_python_module("PIL"):
        ui.note("Material You désactivé (Pillow absent) : couleurs DoodlebookOS fixes.")
        if which("plasma-apply-colorscheme"):
            run(["plasma-apply-colorscheme", "DoodlebookOS_LIGHT" if mode == "light" else "DoodlebookOS_DARK"])
        kwrite("kdeglobals", "Icons", "Theme", "Tela-circle-dark" if pack else "DoodlebookOS")
        return
    r = run([my, "on"], timeout=900)
    if not r or r.returncode != 0:
        ui.note("Material You n'a pas pu s'appliquer (voir le journal).")
        if which("plasma-apply-colorscheme"):
            run(["plasma-apply-colorscheme", "DoodlebookOS_LIGHT" if mode == "light" else "DoodlebookOS_DARK"])
    if pack:
        run([my, "icons"], timeout=900)


def kwin_refresh():
    if not QDBUS and not which("gdbus"):
        return
    dbus("org.kde.KWin", "/KWin", "org.kde.KWin.reconfigure")
    for eff in ("doodlebookos_motion", "blur", "squash", "maximize", "fadingpopups", "slidingpopups", "screenedge", "scale"):
        on = kread("kwinrc", "Plugins", eff + "Enabled", "false") == "true"
        dbus("org.kde.KWin", "/Effects", "org.kde.kwin.Effects." + ("loadEffect" if on else "unloadEffect"), eff)
    dbus("org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting.start")


def powersave_service():
    """Power saver profile -> no blur, instant animations (restored when leaving it)."""
    if not which("systemctl") or not os.path.exists(os.path.join(UNITS, "doodlebookos-powersave.service")):
        return
    if has_python_module("gi.repository.Gio"):
        run(["systemctl", "--user", "enable", "doodlebookos-powersave.service"])
        run(["systemctl", "--user", "restart", "doodlebookos-powersave.service"])
    else:
        ui.note("Mode économie d'énergie : PyGObject absent, le flou et les animations ne suivront pas le profil.")


def services(pack):
    if not which("systemctl"):
        return
    run(["systemctl", "--user", "daemon-reload"])
    run(["systemctl", "--user", "enable", "doodlebookos-update-apply.service"])
    if "--no-auto-update" not in ARGS:
        run(["systemctl", "--user", "enable", "--now", "doodlebookos-update.timer"])
    run(["systemctl", "--user", "enable", "--now", "doodlebookos-topbar.path"])
    if pack == "material":
        run(["systemctl", "--user", "enable", "--now", "doodlebookos-m3icons.path"])
    powersave_service()
    if os.path.exists(os.path.join(UNITS, "plasma-krunner.service")):
        run(["systemctl", "--user", "restart", "plasma-krunner.service"])
    run([os.path.join(BIN, "doodlebookos-topbar-color"), "--check"], timeout=120)


def azerty_shortcuts(settings):
    if not settings.get("doodlebookos", {}).get("azertyDesktopShortcuts"):
        return
    first = kread("kxkbrc", "Layout", "LayoutList", "").split(",")[0].strip()
    if first in ("fr", "be"):
        run([os.path.join(BIN, "doodlebookos-desktop-shortcuts"), "on"])


def update_main(pv, settings):
    """Files only: panels, placed widgets, wallpaper and the user's own settings stay untouched.
    Run by doodlebookos-update (at login, before the desktop starts, or on demand)."""
    if not (os.environ.get("WAYLAND_DISPLAY") or os.environ.get("DISPLAY")):
        os.environ["QT_QPA_PLATFORM"] = "offscreen"     # KDE tools work without a screen
    path = os.path.join(STATE, "installed.json")
    try:
        with open(path, encoding="utf-8") as f:
            inst = json.load(f)
    except (OSError, ValueError):
        inst = {}
    log(f"mise à jour {inst.get('version', '?')} -> {VERSION}")
    try:
        install_files()
        plugin_env()
        deco, style = native_parts(pv)
        # settings added by the new version only (keys this PC has never had)
        for file, group, key, value in settings.get("kconfig", []):
            if file == "kwinrc" and group == "org.kde.kdecoration2" and key in ("library", "theme") and not deco:
                continue
            if file == "kdeglobals" and key == "widgetStyle" and not style:
                continue
            if kread(file, group, key, "__doodlebookos_absent__") == "__doodlebookos_absent__":
                kwrite(file, group, key, value)
        file_dialog_defaults()
        if which("systemctl"):
            run(["systemctl", "--user", "daemon-reload"])
            run(["systemctl", "--user", "enable", "doodlebookos-update-apply.service"])
            if has_python_module("gi.repository.Gio"):     # added in 0.9.x: started with the session
                run(["systemctl", "--user", "enable", "doodlebookos-powersave.service"])
        try:
            with open(os.path.join(CFG, "doodlebookos", "materialyou.json"), encoding="utf-8") as f:
                my_on = bool(json.load(f).get("enabled"))
        except (OSError, ValueError):
            my_on = False
        if my_on:
            run([os.path.join(BIN, "doodlebookos-materialyou"), "icons"], timeout=900)
        if not shell_running():
            shutil.rmtree(os.path.join(HOME, ".cache", "plasmashell", "qmlcache"), ignore_errors=True)
    except Exception as e:  # noqa: BLE001
        log(f"ERREUR mise à jour: {e!r}")
        return 1
    inst.update(version=VERSION, updated=datetime.datetime.now().strftime("%Y%m%d-%H%M%S"),
                decoration=deco or inst.get("decoration", False), style=style or inst.get("style", False))
    inst.pop("failedVersion", None)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(inst, f)
    log("mise à jour terminée")
    return 0


# ───────────────────────────── main ─────────────────────────────
def main():
    log(f"\n##### {datetime.datetime.now().isoformat(timespec='seconds')} — {ROOT}")
    pv = check_system()
    with open(os.path.join(PROFILE, "settings.json"), encoding="utf-8") as f:
        settings = json.load(f)
    with open(os.path.join(PROFILE, "layout.json"), encoding="utf-8") as f:
        layout = json.load(f)
    if "--update" in ARGS:
        return update_main(pv, settings)
    live = shell_running()
    if not ui.ask("<b>Installer DoodlebookOS</b> (thème Material 3 Expressive pour KDE Plasma) ?<br><br>"
                  "• Barres, dock, widgets, couleurs du fond d'écran, icônes, curseurs, effets.<br>"
                  "• Ton bureau actuel est sauvegardé avant (retour possible).<br>"
                  "• Pas besoin du mot de passe administrateur.<br><br>"
                  "Les panneaux actuels seront remplacés. Continuer ?"):
        return 0
    keep_wp = "--keep-wallpaper" in ARGS or (ui.gui and "--yes" not in ARGS and not ui.ask(
        "Mettre le <b>fond d'écran DoodlebookOS</b> ?<br>(Non = garder ton fond d'écran ; les couleurs en sont tirées)"))
    ensure_deps()
    ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    ui.start(9)
    try:
        ui.step("Sauvegarde du bureau actuel…")
        saved = backup(ts)
        ui.step("Copie des thèmes, widgets, icônes et polices…")
        install_files()
        ui.step("Modules natifs (décoration des fenêtres, style des applis)…")
        plugin_env()
        deco, style = native_parts(pv)
        ui.step("Réglages (polices, effets, curseurs)…")
        pack = apply_settings(settings, deco, style)
        file_dialog_defaults()
        mode = settings.get("doodlebookos", {}).get("mode", "dark")
        wp = None if keep_wp else wallpaper_path(mode)
        ui.step("Barres et widgets du bureau…")
        if live:
            if not apply_layout(layout, wp):
                ui.note("Disposition des barres non appliquée (Plasma n'a pas répondu).")
            time.sleep(2)
            stop_shell()                       # Plasma writes its layout when it quits
        else:
            ui.note("Plasma ne tourne pas : barres et widgets seront à appliquer en relançant l'installeur depuis Plasma.")
        free_right_click()
        ui.step("Couleurs Material You et icônes (≈ 1 min)…")
        material_you(pack, mode)
        ui.step("Raccourcis et services…")
        azerty_shortcuts(settings)
        services(pack)
        ui.step("Relance de Plasma…")
        if live:
            start_shell()
        kwin_refresh()
        ui.step("Terminé")
        with open(os.path.join(STATE, "installed.json"), "w", encoding="utf-8") as f:
            json.dump({"version": VERSION, "date": ts, "backup": saved, "decoration": deco, "style": style}, f)
    except Exception as e:  # noqa: BLE001 — show any failure to the user, details in the log
        log(f"ERREUR: {e!r}")
        if live and not shell_running():
            start_shell()
        ui.message(f"L'installation s'est arrêtée : {e}<br><br>Journal : {LOG}", error=True)
        return 1
    msg = ("<b>DoodlebookOS est installé.</b><br><br>"
           "<b>Déconnecte-toi puis reconnecte-toi</b> pour charger la décoration des fenêtres et le style des applis.<br><br>"
           f"Revenir à ton ancien bureau :<br><tt>theme-switch use {saved}</tt>")
    if ui.notes:
        msg += "<br><br>Remarques :<br>• " + "<br>• ".join(ui.notes)
    ui.message(msg)
    if ui.gui and live and "--yes" not in ARGS and ui.ask("Se déconnecter maintenant ?"):
        dbus("org.kde.Shutdown", "/Shutdown", "org.kde.Shutdown.logout")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Application metadata for the DoodlebookOS launcher (run on demand, never polled).

  apps.py index              -> {"apps": {storageId: {c, k, d, src}}}   categories + search words
  apps.py info ID            -> {name, version, source, size, installed, path, flatpak, exec}
  apps.py uninstall ID       -> {"ok": bool, "msg": str}                Flatpak only
  apps.py locate ID          -> opens the .desktop file location in the file manager
  apps.py desktop ID         -> copies the launcher to the desktop folder
"""
import configparser
import json
import os
import shutil
import subprocess
import sys
import time

HOME = os.path.expanduser("~")
LANG = (os.environ.get("LANG") or "en").split(".")[0]          # fr_FR
SHORT = LANG.split("_")[0]                                      # fr

# XDG main categories -> launcher chips (first match wins)
CATS = [
    ("games", {"Game"}),
    ("internet", {"Network", "WebBrowser", "Email", "Chat", "InstantMessaging", "P2P", "FileTransfer"}),
    ("media", {"AudioVideo", "Audio", "Video", "Music", "Player", "Recorder", "TV"}),
    ("graphics", {"Graphics", "Photography", "2DGraphics", "3DGraphics", "RasterGraphics", "VectorGraphics"}),
    ("office", {"Office", "WordProcessor", "Spreadsheet", "Presentation", "Calendar", "ContactManagement"}),
    ("dev", {"Development", "IDE", "TextEditor", "Debugger", "RevisionControl"}),
    ("education", {"Education", "Science", "Math"}),
    ("system", {"System", "Settings", "Monitor", "PackageManager", "HardwareSettings", "Security", "TerminalEmulator"}),
    ("utilities", {"Utility", "Accessibility", "Archiving", "Compression", "FileManager", "Clock", "Calculator"}),
]


def app_dirs():
    data_home = os.environ.get("XDG_DATA_HOME") or os.path.join(HOME, ".local", "share")
    dirs = [data_home] + (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":")
    extra = [os.path.join(HOME, ".local/share/flatpak/exports/share"), "/var/lib/flatpak/exports/share"]
    out, seen = [], set()
    for d in dirs + extra:
        p = os.path.realpath(os.path.join(d, "applications"))
        if p not in seen and os.path.isdir(p):
            seen.add(p)
            out.append(p)
    return out


def iter_desktop_files():
    """(storageId, path) with XDG precedence: the first directory wins."""
    found = {}
    for base in app_dirs():
        for root, _dirs, files in os.walk(base):
            for f in files:
                if not f.endswith(".desktop"):
                    continue
                path = os.path.join(root, f)
                sid = os.path.relpath(path, base).replace(os.sep, "-")
                if sid not in found:
                    found[sid] = path
    return found


def read_entry(path):
    cp = configparser.RawConfigParser(strict=False, interpolation=None)
    cp.optionxform = str
    try:
        cp.read(path, encoding="utf-8")
    except (configparser.Error, UnicodeDecodeError, OSError):
        return None
    if not cp.has_section("Desktop Entry"):
        return None
    return dict(cp.items("Desktop Entry"))


def loc(e, key):
    for k in (f"{key}[{LANG}]", f"{key}[{SHORT}]", key):
        if e.get(k):
            return e[k]
    return ""


def category(cats):
    s = set(c for c in cats.split(";") if c)
    for key, members in CATS:
        if s & members:
            return key
    return "other"


def flatpak_ref(e, path):
    fid = e.get("X-Flatpak", "")
    if not fid:
        return None
    inst = "user" if path.startswith(os.path.join(HOME, ".local")) else "system"
    return fid, inst


def exe_word(cmd):
    exe = os.path.basename((cmd.split() or [""])[0])
    return "" if exe in ("flatpak", "env", "sh", "bash", "waydroid") else exe


def themed_icons_on():
    """The generated Material You theme also draws apps whose .desktop Icon is a file path, under their
    desktop id (doodlebookos-m3icons): the dock asks for that name instead of the fixed picture."""
    try:
        with open(os.path.join(os.environ.get("XDG_CONFIG_HOME", os.path.join(HOME, ".config")), "doodlebookos", "icon-pack")) as f:
            return f.read().strip() == "material"
    except OSError:
        return False


def index():
    apps = {}
    themed = themed_icons_on()
    for sid, path in iter_desktop_files().items():
        e = read_entry(path)
        if not e or e.get("Type", "Application") != "Application":
            continue
        if e.get("NoDisplay", "").lower() == "true" or e.get("Hidden", "").lower() == "true":
            continue
        words = " ".join(filter(None, [
            loc(e, "Name"), e.get("Name", ""), loc(e, "GenericName"), e.get("GenericName", ""),
            loc(e, "Keywords").replace(";", " "), e.get("Keywords", "").replace(";", " "),
            exe_word(e.get("Exec", "")),
        ]))
        fp = flatpak_ref(e, path)
        apps[sid] = {
            "c": category(e.get("Categories", "")),
            "k": words.lower(),
            "d": loc(e, "Comment").lower(),
            "src": ("flatpak-" + fp[1]) if fp else ("local" if path.startswith(HOME) else "rpm"),
        }
        if themed and e.get("Icon", "").startswith("/"):
            apps[sid]["ti"] = os.path.basename(path)[:-8]
    print(json.dumps({"apps": apps}, ensure_ascii=False, separators=(",", ":")))


def human(n):
    for unit in ("o", "Ko", "Mo", "Go"):
        if n < 1024:
            return f"{n:.0f} {unit}" if unit == "o" else f"{n:.1f} {unit}".replace(".", ",")
        n /= 1024.0
    return f"{n:.1f} To".replace(".", ",")


def run(cmd, timeout=10):
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, env=dict(os.environ, LC_ALL="C"))
        return r.returncode, r.stdout
    except (OSError, subprocess.TimeoutExpired):
        return 1, ""


def resolve(sid):
    files = iter_desktop_files()
    sid = sid.replace("applications:", "")
    if sid.startswith("file://"):
        sid = sid[7:]
    if os.path.isabs(sid) and os.path.exists(sid):
        return os.path.basename(sid), sid
    if not sid.endswith(".desktop"):
        sid += ".desktop"
    return sid, files.get(sid)


def info(sid):
    sid, path = resolve(sid)
    if not path:
        print(json.dumps({"error": "not found"}))
        return
    e = read_entry(path) or {}
    out = {"id": sid, "name": loc(e, "Name"), "generic": loc(e, "GenericName"), "comment": loc(e, "Comment"),
           "path": path, "exec": e.get("Exec", ""), "version": "", "size": "", "installed": "", "source": "local",
           "flatpak": ""}
    fp = flatpak_ref(e, path)
    if fp:
        fid, inst = fp
        out["flatpak"], out["source"] = fid, "flatpak-" + inst
        rc, txt = run(["flatpak", "info", "--" + inst, fid])
        for line in txt.splitlines():
            k, _, v = line.strip().partition(":")
            k, v = k.strip().lower(), v.strip()
            if k == "version":
                out["version"] = v
            elif k == "installed size":
                out["size"] = v.replace(".", ",")
            elif k == "date":
                out["installed"] = v[:10]
    elif not path.startswith(HOME):
        rc, txt = run(["rpm", "-qf", "--qf", "%{NAME}\t%{VERSION}-%{RELEASE}\t%{SIZE}\t%{INSTALLTIME}\n", path])
        line = (txt.splitlines() or [""])[0].split("\t")
        if rc == 0 and len(line) == 4:
            out["source"], out["package"], out["version"] = "rpm", line[0], line[1]
            try:
                out["size"] = human(int(line[2]))
                out["installed"] = time.strftime("%Y-%m-%d", time.localtime(int(line[3])))
            except ValueError:
                pass
    else:
        out["installed"] = time.strftime("%Y-%m-%d", time.localtime(os.path.getmtime(path)))
    print(json.dumps(out, ensure_ascii=False))


def uninstall(sid):
    sid, path = resolve(sid)
    e = read_entry(path) if path else None
    fp = flatpak_ref(e, path) if e else None
    if not fp:
        print(json.dumps({"ok": False, "msg": "not-flatpak"}))
        return
    fid, inst = fp
    rc, _ = run(["flatpak", "uninstall", "--" + inst, "-y", "--noninteractive", fid], timeout=300)
    print(json.dumps({"ok": rc == 0, "msg": fid}))


def locate(sid):
    _sid, path = resolve(sid)
    if path:
        subprocess.Popen(["dolphin", "--select", path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)


def desktop(sid):
    _sid, path = resolve(sid)
    if not path:
        return
    rc, out = run(["xdg-user-dir", "DESKTOP"])
    target = out.strip() if rc == 0 and out.strip() else os.path.join(HOME, "Desktop")
    os.makedirs(target, exist_ok=True)
    dst = os.path.join(target, os.path.basename(path))
    shutil.copyfile(path, dst)
    os.chmod(dst, 0o755)
    print(json.dumps({"ok": True, "path": dst}))


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "index"
    arg = sys.argv[2] if len(sys.argv) > 2 else ""
    {"index": lambda: index(), "info": lambda: info(arg), "uninstall": lambda: uninstall(arg),
     "locate": lambda: locate(arg), "desktop": lambda: desktop(arg)}.get(cmd, lambda: sys.exit(1))()

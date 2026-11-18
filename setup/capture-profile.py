#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""
DoodlebookOS — export the look of THIS desktop into setup/profile/ so the installer can
reproduce it on another PC.

Only theme settings are kept (fonts, effects, decoration, panels and widgets with their
options). Personal data is stripped: weather city, photo path, paired phone, wallpaper,
desktop file positions, notes, window sizes of settings dialogs.

    python3 setup/capture-profile.py          # writes setup/profile/{layout,settings}.json
"""
import json
import os
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "profile")
CFG = os.path.join(os.path.expanduser("~"), ".config")

# file -> {group: [keys] | "*"}   ("Effect-*" = every group with that prefix)
SPEC = {
    "kdeglobals": {
        "General": ["font", "menuFont", "smallestReadableFont", "toolBarFont", "wmFont", "fixed",
                    "XftAntialias", "XftHintStyle", "XftSubPixel", "ShowDesktopPreviewBanner"],
        "KDE": ["AnimationDurationFactor", "LookAndFeelPackage", "SingleClick", "ShowIconsInMenuItems",
                "ShowIconsOnPushButtons", "contrast", "frameContrast", "widgetStyle"],
        "WM": ["activeFont"],
        "Sounds": ["Theme"],
    },
    "kwinrc": {
        "Plugins": "*", "org.kde.kdecoration2": "*", "Effect-*": "*", "ElectricBorders": "*",
        "ScreenEdges": "*", "TouchEdges": "*", "TabBox": "*", "Script-*": "*", "EdgeBarrier": "*",
    },
    "plasmarc": {"OSD": "*", "PlasmaToolTips": "*", "Theme": "*"},
    "kcminputrc": {"Mouse": ["cursorTheme", "cursorSize"]},
    "klaunchrc": {"*": "*"},
    "plasmaparc": {"General": ["VolumeOsd", "MuteOsd"]},
    "doodlebookosrc": {"*": "*"},
    "kglobalshortcutsrc": {"plasmashell": ["show-on-mouse-pos"]},
    "kscreenlockerrc": {"Greeter": ["WallpaperPlugin"],
                        "Greeter][LnF][General": ["alwaysShowClock", "hideClockWhenIdle", "showMediaControls"]},
}
# keys never exported (machine state, not theme)
DROP_KEYS = {"kwinrc": {"Plugins": re.compile(r"^(kwin4_effect_shapecorners|shapecorners|round-corners)Enabled$")}}

# widget options that are personal or runtime state
PERSONAL = {"cityName", "latitude", "longitude", "imagePath", "slideshowFolder", "phoneHubDevice",
            "gameMode", "launcherFolders", "favoritesPortedToKAstats", "noteText", "text"}
DROP_GROUPS = {"/ConfigDialog"}


def parse_kconfig(path):
    """{group_path_string: {key: value}} for a KDE ini file (raw values, groups like 'A][B')."""
    groups, cur = {}, None
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.rstrip("\n")
                if line.startswith("[") and line.endswith("]"):
                    cur = line[1:-1]
                    groups.setdefault(cur, {})
                elif cur is not None and "=" in line and not line.startswith("#"):
                    k, v = line.split("=", 1)
                    groups[cur][k] = v
    except OSError:
        pass
    return groups


def group_match(pattern, name):
    if pattern == "*":
        return "][" not in name
    if pattern.endswith("*"):
        return name.startswith(pattern[:-1]) and "][" not in name
    return name == pattern


# doodlebookos-powersave lowers a few settings on battery and keeps the user's values here:
# capture those, not the battery ones (else a release made unplugged ships without animations)
POWERSAVE_STATE = os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"),
                               "doodlebookos", "powersave.json")


def powersave_originals():
    try:
        with open(POWERSAVE_STATE, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        return {}
    return {tuple(k.split("|", 2)): rec for k, rec in data.items() if isinstance(rec, dict)}


def capture_settings():
    out = []
    saved = powersave_originals()
    for fname, groups_spec in SPEC.items():
        data = parse_kconfig(os.path.join(CFG, fname))
        for gname, kv in data.items():
            for pat, keys in groups_spec.items():
                if not group_match(pat, gname):
                    continue
                for k, v in kv.items():
                    key = k.split("[$")[0]          # "AccentColor[$d]" etc.
                    if "[$" in k or (keys != "*" and key not in keys):
                        continue
                    drop = DROP_KEYS.get(fname, {}).get(gname)
                    if drop and drop.match(key):
                        continue
                    if fname == "kcminputrc" and key == "cursorTheme" and \
                            not os.path.isdir(os.path.join(HERE, "..", "extras", "cursors", v)):
                        continue                    # a cursor theme the installer doesn't ship
                    rec = saved.get((fname, gname, key))
                    if rec and v == rec.get("new"):
                        if rec.get("old") in (None, ""):
                            continue
                        v = rec["old"]
                    if fname == "kwinrc" and gname == "org.kde.kdecoration2" and key == "library" \
                            and v.startswith("org.doodlebookos.decoration"):
                        v = "org.doodlebookos.decoration"   # local hot-reload ids → the shipped id
                    out.append([fname, gname, key, v])
                break
    return out


def qdbus():
    for b in ("qdbus-qt6", "qdbus6", "qdbus"):
        if shutil.which(b):
            return b
    sys.exit("qdbus introuvable")


def dump_layout():
    js = subprocess.run([qdbus(), "org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell.dumpCurrentLayoutJS"],
                        capture_output=True, text=True, check=True).stdout
    m = re.search(r"var layout = (\{.*\})\s*;\s*plasma\.loadSerializedLayout", js, re.S)
    if not m:
        sys.exit("format de dumpCurrentLayoutJS inattendu")
    return json.loads(m.group(1))


def clean_config(cfg):
    res = {}
    for grp, kv in (cfg or {}).items():
        if grp in DROP_GROUPS or grp.startswith("/Wallpaper"):
            continue
        kv = {k: v for k, v in kv.items() if k not in PERSONAL}
        if kv:
            res[grp] = kv
    return res


def desktop_geometries():
    """plugin -> [x, y, w, h] as fractions of the screen, from the first desktop containment."""
    rc = parse_kconfig(os.path.join(CFG, "plasma-org.kde.plasma.desktop-appletsrc"))
    plugins = {}
    for g, kv in rc.items():
        m = re.fullmatch(r"Containments\]\[(\d+)\]\[Applets\]\[(\d+)", g)
        if m and "plugin" in kv:
            plugins[m.group(2)] = kv["plugin"]
    for g, kv in rc.items():
        if not re.fullmatch(r"Containments\]\[\d+", g) or kv.get("formfactor", "0") != "0":
            continue
        if kv.get("plugin") not in ("org.kde.desktopcontainment", "org.kde.plasma.folder"):
            continue
        res = None
        geo = None
        for k, v in kv.items():
            m = re.fullmatch(r"ItemGeometries-(\d+)x(\d+)", k)
            if m:
                res, geo = (int(m.group(1)), int(m.group(2))), v
                break
        if not geo:
            continue
        out = {}
        for part in geo.split(";"):
            m = re.fullmatch(r"Applet-(\d+):(-?\d+),(-?\d+),(\d+),(\d+),\d+", part)
            if m and m.group(1) in plugins:
                x, y, w, h = (int(m.group(i)) for i in range(2, 6))
                out[plugins[m.group(1)]] = [round(x / res[0], 4), round(y / res[1], 4), w, h]
        return out
    return {}


def main():
    layout = dump_layout()
    geos = desktop_geometries()
    desk_widgets = []
    if layout.get("desktops"):
        for a in layout["desktops"][0].get("applets", []):
            entry = {"plugin": a["plugin"], "config": clean_config(a.get("config"))}
            if a["plugin"] in geos:
                entry["geometry"] = geos[a["plugin"]]
            desk_widgets.append(entry)
    panels = []
    for p in layout.get("panels", []):
        p = dict(p)
        p["applets"] = [{"plugin": a["plugin"], "config": clean_config(a.get("config"))} for a in p.get("applets", [])]
        p["config"] = clean_config(p.get("config"))
        panels.append(p)
    shortcuts = {}
    sc = parse_kconfig(os.path.join(CFG, "kglobalshortcutsrc")).get("plasmashell", {})
    rc = parse_kconfig(os.path.join(CFG, "plasma-org.kde.plasma.desktop-appletsrc"))
    for g, kv in rc.items():
        m = re.fullmatch(r"Containments\]\[\d+\]\[Applets\]\[(\d+)", g)
        if m:
            key = sc.get(f"activate widget {m.group(1)}", "")
            if key and not key.startswith("none"):
                shortcuts[kv.get("plugin", "")] = key.split(",")[0]
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, "layout.json"), "w", encoding="utf-8") as f:
        json.dump({"panels": panels, "desktopWidgets": desk_widgets, "shortcuts": shortcuts}, f, indent=1, ensure_ascii=False)
        f.write("\n")
    st = os.path.join(CFG, "doodlebookos")
    extra = {}
    for name in ("icon-pack", "icon-shape"):
        try:
            with open(os.path.join(st, name), encoding="utf-8") as f:
                extra[name] = f.read().strip()
        except OSError:
            pass
    try:
        with open(os.path.join(st, "materialyou.json"), encoding="utf-8") as f:
            my = json.load(f)
        extra["materialyou"] = bool(my.get("enabled"))
        extra["mode"] = my.get("mode") or "dark"
    except (OSError, ValueError):
        pass
    r = subprocess.run([os.path.expanduser("~/.local/bin/doodlebookos-desktop-shortcuts"), "status"],
                       capture_output=True, text=True) if os.path.exists(os.path.expanduser("~/.local/bin/doodlebookos-desktop-shortcuts")) else None
    extra["azertyDesktopShortcuts"] = bool(r and "268435494" in r.stdout)   # Meta+& bound
    with open(os.path.join(OUT, "settings.json"), "w", encoding="utf-8") as f:
        rows = ",\n  ".join(json.dumps(r, ensure_ascii=False) for r in capture_settings())
        f.write('{\n "doodlebookos": ' + json.dumps(extra, ensure_ascii=False) + ',\n "kconfig": [\n  ' + rows + "\n ]\n}\n")
    print(f"[✓] Profil exporté dans {OUT}")


if __name__ == "__main__":
    main()

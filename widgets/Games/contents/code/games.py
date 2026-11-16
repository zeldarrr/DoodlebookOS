#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# DoodlebookOS Jeux: prints installed Steam games as JSON, most recently played first.
# Pure stdlib, reads only small text manifests; runs once at load and every 15 min.
import json, os, re, sys

HOME = os.path.expanduser("~")
ROOTS = [
    os.path.join(HOME, ".local/share/Steam"),
    os.path.join(HOME, ".steam/steam"),
    os.path.join(HOME, ".var/app/com.valvesoftware.Steam/.local/share/Steam"),
]
SKIP = re.compile(r"proton|steam linux runtime|steamworks|redistributable|steamvr|soundtrack|"
                  r"dedicated server|\bsdk\b|^spacewar$", re.I)
KV = re.compile(r'^\s*"([^"]+)"\s+"([^"]*)"', re.M)


def roots():
    seen, out = set(), []
    for r in ROOTS:
        if os.path.isdir(r):
            real = os.path.realpath(r)
            if real not in seen:
                seen.add(real)
                out.append(real)
    return out


def libraries(root):
    libs = [root]
    try:
        with open(os.path.join(root, "steamapps/libraryfolders.vdf"), encoding="utf-8", errors="replace") as f:
            for k, v in KV.findall(f.read()):
                if k == "path":
                    libs.append(v)
    except OSError:
        pass
    return libs


def cover(root, appid):
    base = os.path.join(root, "appcache/librarycache")
    d = os.path.join(base, appid)
    p = os.path.join(d, "library_600x900.jpg")
    if os.path.isfile(p):
        return p, True
    try:
        for e in os.scandir(d):           # newer clients: <appid>/<hash>/library_600x900.jpg
            if e.is_dir():
                p = os.path.join(e.path, "library_600x900.jpg")
                if os.path.isfile(p):
                    return p, True
    except OSError:
        pass
    p = os.path.join(base, appid + "_library_600x900.jpg")   # old flat layout
    if os.path.isfile(p):
        return p, True
    for p in (os.path.join(d, "header.jpg"), os.path.join(base, appid + "_header.jpg")):
        if os.path.isfile(p):
            return p, False
    return "", False


def main():
    games, seen_ids, seen_libs = [], set(), set()
    for root in roots():
        for lib in libraries(root):
            apps = os.path.join(os.path.realpath(lib), "steamapps")
            if apps in seen_libs:
                continue
            seen_libs.add(apps)
            try:
                names = os.listdir(apps)
            except OSError:
                continue
            for n in names:
                if not (n.startswith("appmanifest_") and n.endswith(".acf")):
                    continue
                try:
                    with open(os.path.join(apps, n), encoding="utf-8", errors="replace") as f:
                        txt = f.read(4096)    # the keys we need are at the top
                except OSError:
                    continue
                info = {}
                for k, v in KV.findall(txt):
                    info.setdefault(k, v)     # first occurrence = top-level key
                appid, name = info.get("appid", ""), info.get("name", "")
                if not appid or not name or appid in seen_ids or SKIP.search(name):
                    continue
                try:
                    if not int(info.get("StateFlags", "0")) & 4:   # not fully installed
                        continue
                except ValueError:
                    continue
                seen_ids.add(appid)
                c, portrait = cover(root, appid)
                games.append({"id": appid, "name": name, "cover": c, "portrait": portrait,
                              "last": int(info.get("LastPlayed", "0") or 0)})
    games.sort(key=lambda g: (-g["last"], g["name"].lower()))
    json.dump(games, sys.stdout, ensure_ascii=False, separators=(",", ":"))


if __name__ == "__main__":
    main()

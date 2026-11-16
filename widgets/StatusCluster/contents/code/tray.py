#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""
DoodlebookOS tray helper (StatusNotifierItem client for the StatusCluster widget).

The widget listens to D-Bus signals itself and only runs this helper when something
changed, so nothing polls in the background.

  tray.py list                              -> JSON array of visible tray items
  tray.py activate|secondary SVC PATH X Y   -> left / middle click
  tray.py contextmenu SVC PATH X Y          -> ask the app to show its own menu
  tray.py scroll SVC PATH DELTA ORIENTATION
  tray.py menu SVC MENUPATH                 -> JSON tree of the DBusMenu
  tray.py event SVC MENUPATH ID             -> "clicked" on a menu entry
"""
import hashlib
import json
import os
import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

WATCHER = "org.kde.StatusNotifierWatcher"
SNI_IFACES = ("org.kde.StatusNotifierItem", "org.freedesktop.StatusNotifierItem")
MENU_IFACE = "com.canonical.dbusmenu"
CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")), "doodlebookos", "tray")

bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)


def call(dest, path, iface, method, params=None, reply=None, timeout=1500):
    return bus.call_sync(dest, path, iface, method, params,
                         GLib.VariantType(reply) if reply else None,
                         Gio.DBusCallFlags.NONE, timeout, None)


def get_all(dest, path, iface):
    res = call(dest, path, "org.freedesktop.DBus.Properties", "GetAll",
               GLib.Variant("(s)", (iface,)), "(a{sv})")
    return res.unpack()[0]


def split_item(entry):
    # "org.foo.bar/Path" or ":1.42/Path" or just a bus name
    if "/" in entry:
        i = entry.index("/")
        return entry[:i], entry[i:]
    return entry, "/StatusNotifierItem"


def pixmap_to_png(pixmaps, key):
    """IconPixmap is a(iiay) with ARGB32 in network byte order; keep the size closest to 64px."""
    if not pixmaps:
        return ""
    try:
        from PIL import Image
    except ImportError:
        return ""
    best = None
    for w, h, data in pixmaps:
        if w <= 0 or h <= 0 or len(data) < w * h * 4:
            continue
        score = abs(w - 64) + (0 if w >= 32 else 1000)
        if best is None or score < best[0]:
            best = (score, w, h, bytes(data))
    if not best:
        return ""
    _, w, h, data = best
    digest = hashlib.md5(data).hexdigest()[:16]
    os.makedirs(CACHE, exist_ok=True)
    out = os.path.join(CACHE, f"{key}-{digest}.png")
    if not os.path.exists(out):
        Image.frombytes("RGBA", (w, h), data[: w * h * 4], "raw", "ARGB").save(out)
        # drop older renders of the same item
        for f in os.listdir(CACHE):
            if f.startswith(key + "-") and f != os.path.basename(out):
                try:
                    os.remove(os.path.join(CACHE, f))
                except OSError:
                    pass
    return out


def safe_key(text):
    return "".join(c if c.isalnum() else "_" for c in text)[:48] or "item"


def cmd_list():
    try:
        entries = call(WATCHER, "/StatusNotifierWatcher", "org.freedesktop.DBus.Properties", "Get",
                       GLib.Variant("(ss)", (WATCHER, "RegisteredStatusNotifierItems")), "(v)").unpack()[0]
    except GLib.Error:
        entries = []
    items = []
    for entry in entries:
        svc, path = split_item(entry)
        props, iface = None, None
        for candidate in SNI_IFACES:
            try:
                props = get_all(svc, path, candidate)
                iface = candidate
                break
            except GLib.Error:
                continue
        if props is None:
            continue
        status = props.get("Status", "Active")
        if status == "Passive":
            continue
        item_id = props.get("Id", "") or svc
        attention = status == "NeedsAttention"
        icon_name = (props.get("AttentionIconName") if attention else "") or props.get("IconName", "") or ""
        pix = (props.get("AttentionIconPixmap") if attention else None) or props.get("IconPixmap") or []
        icon_file = ""
        if icon_name and icon_name.startswith("/") and os.path.exists(icon_name):
            icon_file, icon_name = icon_name, ""
        theme_path = props.get("IconThemePath", "") or ""
        if icon_name and theme_path:
            for sub in ("", "hicolor/scalable/apps", "hicolor/48x48/apps", "hicolor/32x32/apps"):
                for ext in (".svg", ".png"):
                    cand = os.path.join(theme_path, sub, icon_name + ext)
                    if os.path.exists(cand):
                        icon_file = cand
                        break
                if icon_file:
                    break
        if not icon_name and not icon_file:
            icon_file = pixmap_to_png(pix, safe_key(item_id))
        tooltip = props.get("ToolTip")
        tip_title, tip_text = "", ""
        if tooltip and len(tooltip) >= 4:
            tip_title, tip_text = tooltip[2] or "", tooltip[3] or ""
        # guess the application icon from the item id ("vesktop_status_icon_1" -> "vesktop")
        app_guess = item_id.lower().split("_status")[0].split("_")[0]
        items.append({
            "key": entry,
            "service": svc,
            "path": path,
            "iface": iface,
            "id": item_id,
            "title": props.get("Title", "") or tip_title or item_id,
            "tooltip": tip_text,
            "status": status,
            "iconName": icon_name,
            "iconFile": icon_file,
            "appIcon": app_guess,
            "menu": props.get("Menu", "") or "",
            "itemIsMenu": bool(props.get("ItemIsMenu", False)),
            "category": props.get("Category", ""),
        })
    print(json.dumps(items))


def item_call(svc, path, method, sig, args):
    for iface in SNI_IFACES:
        try:
            call(svc, path, iface, method, GLib.Variant(sig, tuple(args)))
            return True
        except GLib.Error:
            continue
    return False


def clean_label(label):
    # strip mnemonic underscores ("_File" -> "File", "__" -> "_")
    return label.replace("__", "\0").replace("_", "").replace("\0", "_")


def menu_node(node):
    item_id, props, children = node
    kids = [menu_node(c) for c in children]
    return {
        "id": item_id,
        "label": clean_label(props.get("label", "")),
        "enabled": props.get("enabled", True),
        "visible": props.get("visible", True),
        "type": props.get("type", "standard"),
        "toggleType": props.get("toggle-type", ""),
        "toggleState": props.get("toggle-state", -1),
        "iconName": props.get("icon-name", ""),
        "submenu": len(kids) > 0 or props.get("children-display", "") == "submenu",
        "children": [k for k in kids if k["visible"]],
    }


def cmd_menu(svc, menu_path):
    try:
        call(svc, menu_path, MENU_IFACE, "AboutToShow", GLib.Variant("(i)", (0,)))
    except GLib.Error:
        pass
    try:
        res = call(svc, menu_path, MENU_IFACE, "GetLayout", GLib.Variant("(iias)", (0, -1, [])), None)
        _rev, layout = res.unpack()
        root = menu_node(layout)
        # load submenus one level deep (lazy apps only fill them after AboutToShow)
        for child in root["children"]:
            if child["submenu"] and not child["children"]:
                try:
                    call(svc, menu_path, MENU_IFACE, "AboutToShow", GLib.Variant("(i)", (child["id"],)))
                    sub = call(svc, menu_path, MENU_IFACE, "GetLayout",
                               GLib.Variant("(iias)", (child["id"], -1, [])), None).unpack()[1]
                    child["children"] = [k for k in menu_node(sub)["children"]]
                except GLib.Error:
                    pass
        print(json.dumps(root["children"]))
    except GLib.Error as e:
        print(json.dumps({"error": str(e)}))


def cmd_event(svc, menu_path, item_id):
    call(svc, menu_path, MENU_IFACE, "Event",
         GLib.Variant("(isvu)", (int(item_id), "clicked", GLib.Variant("i", 0), 0)))


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 1
    cmd = argv[1]
    if cmd == "list":
        cmd_list()
    elif cmd in ("activate", "secondary", "contextmenu") and len(argv) >= 6:
        method = {"activate": "Activate", "secondary": "SecondaryActivate", "contextmenu": "ContextMenu"}[cmd]
        item_call(argv[2], argv[3], method, "(ii)", (int(float(argv[4])), int(float(argv[5]))))
    elif cmd == "scroll" and len(argv) >= 6:
        item_call(argv[2], argv[3], "Scroll", "(is)", (int(argv[4]), argv[5]))
    elif cmd == "menu" and len(argv) >= 4:
        cmd_menu(argv[2], argv[3])
    elif cmd == "event" and len(argv) >= 5:
        cmd_event(argv[2], argv[3], argv[4])
    else:
        print(__doc__)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

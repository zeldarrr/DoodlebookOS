#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Clipboard history helper for the Quick Settings panel (Klipper D-Bus, run on demand only).

  clipboard.py list [N]   -> JSON [{i, text, lines}] (text shortened for display)
  clipboard.py set I      -> make history entry I the current clipboard
  clipboard.py clear      -> clear the history
"""
import json
import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)


def call(method, params=None, reply=None):
    res = bus.call_sync("org.kde.klipper", "/klipper", "org.kde.klipper.klipper", method, params,
                        GLib.VariantType(reply) if reply else None, Gio.DBusCallFlags.NONE, 2000, None)
    return res.unpack() if reply else None


def main(argv):
    cmd = argv[1] if len(argv) > 1 else "list"
    try:
        if cmd == "list":
            n = int(argv[2]) if len(argv) > 2 else 30
            items = call("getClipboardHistoryMenu", None, "(as)")[0][:n]
            out = []
            for i, t in enumerate(items):
                if not t.strip():
                    continue
                out.append({"i": i, "text": t[:280], "lines": t.count("\n") + 1})
            print(json.dumps(out))
        elif cmd == "set" and len(argv) > 2:
            text = call("getClipboardHistoryItem", GLib.Variant("(i)", (int(argv[2]),)), "(s)")[0]
            call("setClipboardContents", GLib.Variant("(s)", (text,)))
        elif cmd == "clear":
            call("clearClipboardHistory")
        else:
            print(__doc__)
            return 1
    except GLib.Error:
        print("[]" if cmd == "list" else "")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Display helper for Quick Settings (kscreen-doctor, run on demand only).

  display.py list                 -> JSON [{name, enabled, w, h, hz, scale, rates:[{id, hz}]}]
  display.py scale NAME VALUE     -> set the output scale (1, 1.25, 1.5, ...)
  display.py mode NAME MODE_ID    -> set a mode (refresh rate for the current resolution)
  display.py enable|disable NAME  -> turn an output on/off (refused for the last enabled one)
"""
import json
import re
import subprocess
import sys


def doctor_json():
    out = subprocess.run(["kscreen-doctor", "-j"], capture_output=True, text=True, timeout=8).stdout
    return json.loads(out or '{"outputs": []}').get("outputs", [])


def summary():
    res = []
    for o in doctor_json():
        if not o.get("connected", True):
            continue
        cur = next((m for m in o.get("modes", []) if m["id"] == o.get("currentModeId")), None)
        rates = {}
        if cur:
            for m in o["modes"]:
                if m["size"] == cur["size"]:
                    hz = round(m["refreshRate"])
                    if hz not in rates or m["id"] == cur["id"]:
                        rates[hz] = m["id"]
        res.append({"name": o["name"], "enabled": bool(o.get("enabled")),
                    "w": cur["size"]["width"] if cur else 0, "h": cur["size"]["height"] if cur else 0,
                    "hz": round(cur["refreshRate"]) if cur else 0, "scale": o.get("scale", 1),
                    "modeId": o.get("currentModeId"),
                    "rates": [{"hz": hz, "id": mid} for hz, mid in sorted(rates.items())]})
    return res


def main(argv):
    cmd = argv[1] if len(argv) > 1 else "list"
    outs = summary()
    names = {o["name"] for o in outs}
    if cmd == "list":
        print(json.dumps(outs))
        return 0
    if len(argv) < 3 or argv[2] not in names:
        return 1
    name = argv[2]
    if cmd == "scale" and len(argv) > 3 and re.fullmatch(r"[0-9.]{1,5}", argv[3]):
        args = [f"output.{name}.scale.{argv[3]}"]
    elif cmd == "mode" and len(argv) > 3 and re.fullmatch(r"[0-9A-Za-z_-]{1,32}", argv[3]):
        args = [f"output.{name}.mode.{argv[3]}"]
    elif cmd == "disable" and sum(o["enabled"] for o in outs) > 1:
        args = [f"output.{name}.disable"]
    elif cmd == "enable":
        args = [f"output.{name}.enable"]
    else:
        return 1
    subprocess.run(["kscreen-doctor", *args], capture_output=True, timeout=15)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

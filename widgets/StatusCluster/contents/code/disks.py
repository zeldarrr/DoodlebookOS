#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Removable storage helper for Quick Settings (lsblk + udisksctl, run on demand only).

  disks.py list          -> JSON [{path, disk, label, size, fstype, mountpoint, used}]
  disks.py open PATH     -> mount if needed, then open in the file manager
  disks.py eject DISK    -> unmount every partition of DISK and power it off
"""
import json
import os
import subprocess
import sys


def lsblk():
    out = subprocess.run(["lsblk", "-J", "-b", "-o", "NAME,PATH,LABEL,SIZE,FSTYPE,MOUNTPOINT,RM,HOTPLUG,TRAN,TYPE,MODEL"],
                         capture_output=True, text=True, timeout=5).stdout
    return json.loads(out or '{"blockdevices": []}')["blockdevices"]


def removable_parts():
    parts = []
    for disk in lsblk():
        if disk.get("type") != "disk" or not (disk.get("rm") or disk.get("hotplug") or disk.get("tran") == "usb"):
            continue
        children = disk.get("children") or [disk]
        for p in children:
            if not p.get("fstype") or p.get("fstype") in ("swap", "crypto_LUKS"):
                continue
            mp = p.get("mountpoint") or ""
            used = -1.0
            if mp:
                try:
                    st = os.statvfs(mp)
                    used = 1.0 - st.f_bavail / st.f_blocks if st.f_blocks else -1.0
                except OSError:
                    pass
            parts.append({"path": p["path"], "disk": disk["path"],
                          "label": p.get("label") or disk.get("model") or os.path.basename(p["path"]),
                          "size": int(p.get("size") or 0), "fstype": p.get("fstype"), "mountpoint": mp, "used": used})
    return parts


def safe_dev(path, parts, key):
    return any(p[key] == path for p in parts)


def main(argv):
    cmd = argv[1] if len(argv) > 1 else "list"
    parts = removable_parts()
    if cmd == "list":
        print(json.dumps(parts))
    elif cmd == "open" and len(argv) > 2 and safe_dev(argv[2], parts, "path"):
        p = next(x for x in parts if x["path"] == argv[2])
        mp = p["mountpoint"]
        if not mp:
            subprocess.run(["udisksctl", "mount", "-b", p["path"]], capture_output=True, timeout=30)
            mp = next((x["mountpoint"] for x in removable_parts() if x["path"] == p["path"]), "")
        if mp:
            subprocess.Popen(["xdg-open", mp], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    elif cmd == "eject" and len(argv) > 2 and safe_dev(argv[2], parts, "disk"):
        for p in parts:
            if p["disk"] == argv[2] and p["mountpoint"]:
                subprocess.run(["udisksctl", "unmount", "-b", p["path"]], capture_output=True, timeout=30)
        subprocess.run(["udisksctl", "power-off", "-b", argv[2]], capture_output=True, timeout=30)
    else:
        print(__doc__)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

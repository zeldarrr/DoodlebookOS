#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# DoodlebookOS Stockage: prints the user-relevant mounted filesystems as JSON (statvfs only).
import json, os, sys

REAL_FS = {"ext2", "ext3", "ext4", "btrfs", "xfs", "f2fs", "vfat", "exfat", "ntfs", "ntfs3",
           "fuseblk", "zfs", "bcachefs", "jfs", "reiserfs"}
SKIP_PREFIX = ("/boot", "/efi", "/sysroot", "/etc", "/usr", "/var/lib", "/var/log", "/var/cache",
               "/var/tmp", "/opt", "/srv", "/root", "/snap", "/proc", "/sys", "/run/host")
HOME = os.path.realpath(os.path.expanduser("~"))
GIB = 1 << 30


def unescape(s):
    return s.replace("\\040", " ").replace("\\011", "\t").replace("\\134", "\\")


def main():
    seen_dev, out = set(), []
    try:
        with open("/proc/self/mounts", encoding="utf-8", errors="replace") as f:
            lines = f.read().splitlines()
    except OSError:
        lines = []
    for line in lines:
        parts = line.split()
        if len(parts) < 3:
            continue
        dev, mnt, fs = parts[0], unescape(parts[1]), parts[2]
        if fs not in REAL_FS or mnt.startswith(SKIP_PREFIX) and not HOME.startswith(mnt):
            continue
        try:
            st = os.statvfs(mnt)
        except OSError:
            continue
        total = st.f_blocks * st.f_frsize
        if total < GIB:
            continue
        free = st.f_bavail * st.f_frsize
        key = (dev, total)                 # btrfs subvolumes of one disk show up several times
        if key in seen_dev:
            continue
        seen_dev.add(key)
        if HOME == mnt or HOME.startswith(mnt.rstrip("/") + "/") and mnt in ("/", "/var", "/var/home", "/home"):
            name, prio = "Système", 0
        else:
            name, prio = os.path.basename(mnt.rstrip("/")) or mnt, 1
        out.append({"name": name, "path": mnt, "open": HOME if prio == 0 else mnt, "total": total, "used": total - free, "prio": prio})
    out.sort(key=lambda d: (d["prio"], d["name"].lower()))
    json.dump(out, sys.stdout, ensure_ascii=False, separators=(",", ":"))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""
Phone Hub "Recent photos" helper (KDE Connect SFTP).

  phonephotos.py list DEVICE_ID [COUNT]  -> JSON {ok, photos:[{path,name,mtime,thumb}]}
  phonephotos.py save-open PATH          -> copy the photo to the Downloads folder and open it

Only the small EXIF thumbnail at the start of each JPEG is read (≈20 KB instead of the
whole 5–10 MB photo), so the row fills in a fraction of a second over Wi-Fi.
"""
import hashlib
import io
import json
import os
import shutil
import subprocess
import sys

CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")), "doodlebookos", "phonehub")
EXTS = (".jpg", ".jpeg", ".png", ".webp")
SUBDIRS = ("DCIM/Camera", "Pictures/Screenshots", "DCIM/Screenshots")
RUN_DIR = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")


def out(obj):
    print(json.dumps(obj))
    return 0


def sftp_roots(device_id):
    import gi
    gi.require_version("Gio", "2.0")
    from gi.repository import Gio, GLib
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    path = f"/modules/kdeconnect/devices/{device_id}/sftp"
    iface = "org.kde.kdeconnect.device.sftp"

    def call(method, reply, timeout=20000):
        return bus.call_sync("org.kde.kdeconnect", path, iface, method, None,
                             GLib.VariantType(reply), Gio.DBusCallFlags.NONE, timeout, None).unpack()[0]

    if not call("isMounted", "(b)", 3000):
        if not call("mountAndWait", "(b)"):
            raise RuntimeError(call("getMountError", "(s)", 3000) or "mount failed")
    mount_point = call("mountPoint", "(s)", 3000)
    roots = list(call("getDirectories", "(a{sv})", 3000).keys())
    roots.append(os.path.join(mount_point, "storage/emulated/0"))
    return [r for r in roots if os.path.isdir(os.path.join(r, "DCIM")) or os.path.isdir(os.path.join(r, "Pictures"))]


def embedded_thumbnail(path):
    from PIL import Image
    with open(path, "rb") as f:
        head = f.read(524288)
    orientation = 1
    try:
        orientation = Image.open(io.BytesIO(head)).getexif().get(0x0112, 1) or 1
    except Exception:
        pass
    start = head.find(b"\xff\xd8\xff", 2)
    if start > 0:
        end = head.find(b"\xff\xd9", start)
        if end > 0:
            try:
                im = Image.open(io.BytesIO(head[start:end + 2]))
                im.load()
                return im, orientation
            except Exception:
                pass
    return None, orientation


def make_thumb(path, dest):
    from PIL import Image, ImageOps
    im, orientation = (None, 1)
    if path.lower().endswith((".jpg", ".jpeg")):
        im, orientation = embedded_thumbnail(path)
    if im is None:  # PNG screenshots or JPEGs without an EXIF thumbnail
        im = Image.open(path)
        im.draft("RGB", (384, 384))
        im = ImageOps.exif_transpose(im)
        orientation = 1
    transpose = {2: Image.Transpose.FLIP_LEFT_RIGHT, 3: Image.Transpose.ROTATE_180, 4: Image.Transpose.FLIP_TOP_BOTTOM,
                 5: Image.Transpose.TRANSPOSE, 6: Image.Transpose.ROTATE_270, 7: Image.Transpose.TRANSVERSE,
                 8: Image.Transpose.ROTATE_90}.get(orientation)
    if transpose is not None:
        im = im.transpose(transpose)
    im = im.convert("RGB")
    im.thumbnail((384, 384))
    im.save(dest, "JPEG", quality=86)


def cmd_list(device_id, count):
    try:
        roots = sftp_roots(device_id)
    except Exception as e:  # noqa: BLE001
        return out({"ok": False, "error": str(e)})
    files, seen = [], set()
    for root in roots:
        for sub in SUBDIRS:
            d = os.path.join(root, sub)
            if not os.path.isdir(d):
                continue
            try:
                with os.scandir(d) as it:
                    for entry in it:
                        if entry.name.startswith(".") or not entry.name.lower().endswith(EXTS):
                            continue
                        real = os.path.realpath(entry.path)
                        if real in seen:
                            continue
                        seen.add(real)
                        try:
                            files.append((entry.stat().st_mtime, entry.path, entry.name))
                        except OSError:
                            pass
            except OSError:
                pass
    files.sort(reverse=True)
    os.makedirs(CACHE, exist_ok=True)
    photos, keep = [], set()
    for mtime, path, name in files[:count]:
        key = hashlib.sha1(f"{path}:{mtime}".encode()).hexdigest()[:16] + ".jpg"
        dest = os.path.join(CACHE, key)
        keep.add(key)
        if not os.path.exists(dest):
            try:
                make_thumb(path, dest)
            except Exception:  # noqa: BLE001
                continue
        photos.append({"path": path, "name": name, "mtime": mtime, "thumb": dest})
    for f in os.listdir(CACHE):
        if f not in keep:
            try:
                os.remove(os.path.join(CACHE, f))
            except OSError:
                pass
    return out({"ok": True, "photos": photos})


def downloads_dir():
    try:
        d = subprocess.run(["xdg-user-dir", "DOWNLOAD"], capture_output=True, text=True, timeout=3).stdout.strip()
        if d and os.path.isdir(d):
            return d
    except Exception:  # noqa: BLE001
        pass
    return os.path.expanduser("~/Downloads")


def cmd_save_open(path):
    real = os.path.realpath(path)
    if not real.startswith(RUN_DIR + "/") or not real.lower().endswith(EXTS) or not os.path.isfile(real):
        return out({"ok": False, "error": "refused"})
    dest_dir = downloads_dir()
    os.makedirs(dest_dir, exist_ok=True)
    dest = os.path.join(dest_dir, os.path.basename(real))
    if not (os.path.exists(dest) and os.path.getsize(dest) == os.path.getsize(real)):
        shutil.copy2(real, dest)
    subprocess.Popen(["xdg-open", dest], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    return out({"ok": True, "saved": dest})


def main(argv):
    if len(argv) >= 3 and argv[1] == "list":
        return cmd_list(argv[2], int(argv[3]) if len(argv) > 3 else 4)
    if len(argv) >= 3 and argv[1] == "save-open":
        return cmd_save_open(argv[2])
    print(__doc__)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))

#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Maciej Kujawiński <maciek.kujawinski@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later

import configparser
import hashlib
import io
import json
import os
import re
import signal
import sys
import time
from pathlib import Path

import dbus
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib
from PIL import Image

BRIDGE_SERVICE = "org.doodlebookos.TrayBridge"
BRIDGE_PATH = "/TrayBridge"
BRIDGE_IFACE = "org.doodlebookos.TrayBridge"

WATCHER_SERVICE = "org.kde.StatusNotifierWatcher"
WATCHER_PATH = "/StatusNotifierWatcher"
WATCHER_IFACE = "org.kde.StatusNotifierWatcher"

SNI_IFACE = "org.kde.StatusNotifierItem"
SNI_IFACE_ALT = "org.freedesktop.StatusNotifierItem"
DBUSMENU_IFACE = "com.canonical.dbusmenu"

DBUS_CALL_TIMEOUT = 2.0
ICON_MAX_PX = 128


def _get_cache_dir() -> Path:
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR")
    if runtime_dir and os.path.isdir(runtime_dir):
        base = Path(runtime_dir)
    else:
        base = Path(f"/tmp/doodlebookos-runtime-{os.getuid()}")
    cache = base / "doodlebookos-tray-icons"
    cache.mkdir(parents=True, exist_ok=True)
    return cache


def _strip_mnemonic(label: str) -> str:
    if not label:
        return ""
    out = []
    i = 0
    n = len(label)
    while i < n:
        ch = label[i]
        if ch == "_":
            if i + 1 < n and label[i + 1] == "_":
                out.append("_")
                i += 2
            else:
                i += 1
        else:
            out.append(ch)
            i += 1
    return "".join(out).strip()


def _parse_sni_identifier(raw: str) -> tuple[str, str]:
    s = str(raw).strip()
    if not s:
        return "", ""
    if "/" in s:
        service, rest = s.split("/", 1)
        path = "/" + rest.lstrip("/")
        return service, path
    return s, "/StatusNotifierItem"


def _read_active_icon_themes() -> list[str]:
    themes = []
    kdeglobals = Path.home() / ".config" / "kdeglobals"
    if kdeglobals.is_file():
        cfg = configparser.ConfigParser(interpolation=None)
        try:
            cfg.read(kdeglobals, encoding="utf-8")
            t = cfg.get("Icons", "Theme", fallback="").strip()
            if t:
                themes.append(t)
        except Exception:
            pass
    for fallback in ("DoodlebookOS", "breeze-dark", "breeze", "Adwaita", "hicolor"):
        if fallback not in themes:
            themes.append(fallback)
    return themes


class IconResolver:
    def __init__(self, cache_dir: Path):
        self.cache_dir = cache_dir
        self._lookup_cache: dict[tuple[str, str], str] = {}
        self._written_files_by_slot: dict[str, str] = {}
        self._cleanup_stale_files()

    def _cleanup_stale_files(self):
        try:
            for entry in self.cache_dir.iterdir():
                if entry.is_file() and entry.suffix == ".png":
                    entry.unlink(missing_ok=True)
        except Exception:
            pass

    def _write_png_for_slot(self, slot_id: str, png_bytes: bytes) -> str:
        digest = hashlib.sha1(png_bytes).hexdigest()[:12]
        safe_slot = re.sub(r"[^A-Za-z0-9_.-]+", "_", slot_id)[:48]
        target = self.cache_dir / f"{safe_slot}_{digest}.png"

        prev = self._written_files_by_slot.get(slot_id)
        if prev and prev != str(target):
            try:
                Path(prev).unlink(missing_ok=True)
            except Exception:
                pass

        if not target.exists():
            try:
                target.write_bytes(png_bytes)
            except Exception:
                return ""
        self._written_files_by_slot[slot_id] = str(target)
        return target.as_uri()

    def clear_slot(self, slot_id: str):
        prev = self._written_files_by_slot.pop(slot_id, None)
        if prev:
            try:
                Path(prev).unlink(missing_ok=True)
            except Exception:
                pass

    def pixmap_to_uri(self, slot_id: str, pixmaps) -> str:
        if not pixmaps:
            return ""
        candidates = []
        for entry in pixmaps:
            try:
                w = int(entry[0])
                h = int(entry[1])
                raw = bytes(entry[2])
                if w > 0 and h > 0 and len(raw) == w * h * 4:
                    candidates.append((w, h, raw))
            except Exception:
                continue
        if not candidates:
            return ""

        ge64 = [c for c in candidates if min(c[0], c[1]) >= 64]
        if ge64:
            w, h, raw = min(ge64, key=lambda c: c[0] * c[1])
        else:
            w, h, raw = max(candidates, key=lambda c: c[0] * c[1])

        try:
            img = Image.frombytes("RGBA", (w, h), raw, "raw", "ARGB")
            if max(w, h) > ICON_MAX_PX:
                img.thumbnail((ICON_MAX_PX, ICON_MAX_PX), Image.Resampling.LANCZOS)
            buf = io.BytesIO()
            img.save(buf, format="PNG")
            return self._write_png_for_slot(slot_id, buf.getvalue())
        except Exception:
            return ""

    def raw_png_bytes_to_uri(self, slot_id: str, raw_bytes: bytes) -> str:
        if not raw_bytes:
            return ""
        try:
            if raw_bytes[:8] == b"\x89PNG\r\n\x1a\n":
                return self._write_png_for_slot(slot_id, raw_bytes)
            img = Image.open(io.BytesIO(raw_bytes)).convert("RGBA")
            if max(img.size) > ICON_MAX_PX:
                img.thumbnail((ICON_MAX_PX, ICON_MAX_PX), Image.Resampling.LANCZOS)
            buf = io.BytesIO()
            img.save(buf, format="PNG")
            return self._write_png_for_slot(slot_id, buf.getvalue())
        except Exception:
            return ""

    def resolve_icon_name(self, icon_name: str, theme_path: str) -> str:
        name = (icon_name or "").strip()
        if not name:
            return ""

        cache_key = (name, theme_path or "")
        cached = self._lookup_cache.get(cache_key)
        if cached is not None:
            if not cached or Path(cached.replace("file://", "")).exists():
                return cached

        p = Path(name)
        if p.is_absolute() and p.is_file():
            uri = p.as_uri()
            self._lookup_cache[cache_key] = uri
            return uri

        exts = (".svg", ".png", ".xpm")
        name_variants = [name]
        if name.endswith("-symbolic"):
            name_variants.append(name[: -len("-symbolic")])

        search_bases: list[Path] = []
        if theme_path and Path(theme_path).is_dir():
            search_bases.append(Path(theme_path))

        icon_roots = [
            Path.home() / ".local" / "share" / "icons",
            Path.home() / ".icons",
            Path("/usr/local/share/icons"),
            Path("/usr/share/icons"),
        ]
        themes = _read_active_icon_themes()
        for t in themes:
            for root in icon_roots:
                tdir = root / t
                if tdir.is_dir():
                    search_bases.append(tdir)

        preferred_subdirs = (
            "scalable/apps",
            "scalable/status",
            "scalable/panel",
            "64x64/apps",
            "64x64/status",
            "48x48/apps",
            "48x48/status",
            "32x32/apps",
            "32x32/status",
            "32x32/panel",
            "24x24/apps",
            "24x24/status",
            "24x24/panel",
            "22x22/apps",
            "22x22/status",
            "22x22/panel",
            "16x16/apps",
            "16x16/status",
            "16x16/panel",
            "apps/scalable",
            "status/scalable",
            "apps/64",
            "apps/48",
            "apps/32",
            "apps/24",
            "apps/22",
            "apps/16",
            "status/24",
            "status/22",
            "status/16",
            "",
        )

        # Direct path inside IconThemePath (AppImages / Electron often store flat files)
        if theme_path and Path(theme_path).is_dir():
            tp = Path(theme_path)
            for candidate_name in name_variants:
                for ext in ("", ".svg", ".png", ".xpm"):
                    direct = tp / f"{candidate_name}{ext}"
                    if direct.is_file():
                        uri = direct.as_uri()
                        self._lookup_cache[cache_key] = uri
                        return uri
                # Bounded walk inside app-local theme_path
                for match in tp.rglob(f"{candidate_name}.*"):
                    if match.suffix.lower() in exts and match.is_file():
                        uri = match.as_uri()
                        self._lookup_cache[cache_key] = uri
                        return uri

        for base in search_bases:
            for sub in preferred_subdirs:
                d = base / sub if sub else base
                if not d.is_dir():
                    continue
                for candidate_name in name_variants:
                    for ext in exts:
                        f = d / f"{candidate_name}{ext}"
                        if f.is_file():
                            uri = f.as_uri()
                            self._lookup_cache[cache_key] = uri
                            return uri

        for pix_dir in (Path.home() / ".local" / "share" / "pixmaps", Path("/usr/share/pixmaps")):
            if pix_dir.is_dir():
                for candidate_name in name_variants:
                    for ext in exts:
                        f = pix_dir / f"{candidate_name}{ext}"
                        if f.is_file():
                            uri = f.as_uri()
                            self._lookup_cache[cache_key] = uri
                            return uri

        self._lookup_cache[cache_key] = ""
        return ""


class TrayBridge(dbus.service.Object):
    def __init__(self, bus: dbus.SessionBus):
        self.bus = bus
        self._host_name_str = f"org.kde.StatusNotifierHost-{os.getpid()}-1"
        self._host_bus_name = dbus.service.BusName(self._host_name_str, bus=bus, do_not_queue=True)
        self._bridge_bus_name = dbus.service.BusName(BRIDGE_SERVICE, bus=bus, do_not_queue=True)
        super().__init__(self._bridge_bus_name, BRIDGE_PATH)

        self.icon_resolver = IconResolver(_get_cache_dir())
        self.items: dict[str, dict] = {}
        self._signal_matches: dict[str, list] = {}
        self._refresh_timers: dict[str, int] = {}
        self._seq_counter = 0
        self.items_json = "[]"
        self.version = 0

        self._setup_watcher_signals()
        self._register_host_and_sync()

    def _setup_watcher_signals(self):
        self.bus.add_signal_receiver(
            self._on_item_registered,
            signal_name="StatusNotifierItemRegistered",
            dbus_interface=WATCHER_IFACE,
            bus_name=WATCHER_SERVICE,
            path=WATCHER_PATH,
        )
        self.bus.add_signal_receiver(
            self._on_item_unregistered,
            signal_name="StatusNotifierItemUnregistered",
            dbus_interface=WATCHER_IFACE,
            bus_name=WATCHER_SERVICE,
            path=WATCHER_PATH,
        )
        self.bus.add_signal_receiver(
            self._on_name_owner_changed,
            signal_name="NameOwnerChanged",
            dbus_interface="org.freedesktop.DBus",
            bus_name="org.freedesktop.DBus",
            path="/org/freedesktop/DBus",
        )

    def _register_host_and_sync(self):
        try:
            watcher_obj = self.bus.get_object(WATCHER_SERVICE, WATCHER_PATH)
            watcher_iface = dbus.Interface(watcher_obj, WATCHER_IFACE)
            try:
                watcher_iface.RegisterStatusNotifierHost(self._host_name_str, timeout=DBUS_CALL_TIMEOUT)
            except Exception:
                pass
            watcher_props = dbus.Interface(watcher_obj, dbus.PROPERTIES_IFACE)
            registered = watcher_props.Get(WATCHER_IFACE, "RegisteredStatusNotifierItems", timeout=DBUS_CALL_TIMEOUT)
            for raw in registered:
                service, path = _parse_sni_identifier(str(raw))
                if service:
                    key = f"{service}{path}"
                    self._add_or_update_item(key, service, path, emit=False)
            self._rebuild_and_emit()
        except Exception as e:
            sys.stderr.write(f"[TrayBridge] Watcher sync skipped/waiting: {e}\n")

    def _on_name_owner_changed(self, name, old_owner, new_owner):
        name_s = str(name)
        new_s = str(new_owner)
        if name_s == WATCHER_SERVICE and new_s:
            GLib.timeout_add(150, self._deferred_watcher_resync)
            return
        if not new_s:
            stale_keys = [
                k for k, v in list(self.items.items())
                if v.get("service") == name_s or v.get("owner") == name_s
            ]
            if stale_keys:
                for k in stale_keys:
                    self._remove_item(k, emit=False)
                self._rebuild_and_emit()

    def _deferred_watcher_resync(self):
        self._register_host_and_sync()
        return False

    def _on_item_registered(self, raw):
        service, path = _parse_sni_identifier(str(raw))
        if not service:
            return
        key = f"{service}{path}"
        self._add_or_update_item(key, service, path, emit=True)

    def _on_item_unregistered(self, raw):
        service, path = _parse_sni_identifier(str(raw))
        if not service:
            return
        key = f"{service}{path}"
        if key in self.items:
            self._remove_item(key, emit=True)

    def _attach_item_signals(self, key: str, service: str, path: str):
        self._detach_item_signals(key)
        matches = []
        for sig in ("NewTitle", "NewIcon", "NewAttentionIcon", "NewOverlayIcon", "NewToolTip", "NewStatus"):
            try:
                m = self.bus.add_signal_receiver(
                    lambda *args, k=key: self._schedule_item_refresh(k),
                    signal_name=sig,
                    dbus_interface=SNI_IFACE,
                    bus_name=service,
                    path=path,
                )
                matches.append(m)
            except Exception:
                pass
        self._signal_matches[key] = matches

    def _detach_item_signals(self, key: str):
        timer_id = self._refresh_timers.pop(key, None)
        if timer_id:
            try:
                GLib.source_remove(timer_id)
            except Exception:
                pass
        for m in self._signal_matches.pop(key, []):
            try:
                m.remove()
            except Exception:
                pass

    def _schedule_item_refresh(self, key: str):
        if key in self._refresh_timers:
            return
        self._refresh_timers[key] = GLib.timeout_add(50, self._run_scheduled_refresh, key)

    def _run_scheduled_refresh(self, key: str):
        self._refresh_timers.pop(key, None)
        entry = self.items.get(key)
        if entry:
            self._add_or_update_item(key, entry["service"], entry["path"], emit=True)
        return False

    def _fetch_sni_props(self, service: str, path: str) -> dict | None:
        try:
            obj = self.bus.get_object(service, path, introspect=False)
            props_iface = dbus.Interface(obj, dbus.PROPERTIES_IFACE)
            try:
                return dict(props_iface.GetAll(SNI_IFACE, timeout=DBUS_CALL_TIMEOUT))
            except Exception:
                return dict(props_iface.GetAll(SNI_IFACE_ALT, timeout=DBUS_CALL_TIMEOUT))
        except Exception:
            return None

    def _resolve_owner(self, service: str) -> str:
        if service.startswith(":"):
            return service
        try:
            dbus_obj = self.bus.get_object("org.freedesktop.DBus", "/org/freedesktop/DBus", introspect=False)
            return str(dbus.Interface(dbus_obj, "org.freedesktop.DBus").GetNameOwner(service, timeout=1.0))
        except Exception:
            return service

    def _add_or_update_item(self, key: str, service: str, path: str, emit: bool):
        raw_props = self._fetch_sni_props(service, path)
        if raw_props is None:
            if key in self.items:
                self._remove_item(key, emit=emit)
            return

        existing = self.items.get(key)
        if existing is None:
            self._seq_counter += 1
            seq = self._seq_counter
            self._attach_item_signals(key, service, path)
        else:
            seq = existing["seq"]

        item_id = str(raw_props.get("Id", "") or "").strip()
        title = str(raw_props.get("Title", "") or "").strip()
        category = str(raw_props.get("Category", "ApplicationStatus") or "ApplicationStatus").strip()
        status = str(raw_props.get("Status", "Active") or "Active").strip()

        tt_title = ""
        tt_sub = ""
        raw_tt = raw_props.get("ToolTip")
        if isinstance(raw_tt, (tuple, list)) and len(raw_tt) >= 4:
            tt_title = str(raw_tt[2] or "").strip()
            tt_sub = str(raw_tt[3] or "").strip()
            if "\n" in tt_title and not tt_sub:
                first_line, rest = tt_title.split("\n", 1)
                tt_title = first_line.strip()
                tt_sub = " ".join(part.strip() for part in rest.splitlines() if part.strip())

        display_title = (tt_title or title or item_id or service).replace("\n", " ").strip()
        item_is_menu = bool(raw_props.get("ItemIsMenu", False))
        menu_path = str(raw_props.get("Menu", "") or "").strip()
        if menu_path == "/":
            menu_path = ""

        icon_name = str(raw_props.get("IconName", "") or "").strip()
        icon_theme_path = str(raw_props.get("IconThemePath", "") or "").strip()
        icon_pixmap = raw_props.get("IconPixmap")

        att_name = str(raw_props.get("AttentionIconName", "") or "").strip()
        att_pixmap = raw_props.get("AttentionIconPixmap")

        chosen_icon_name = icon_name
        icon_path = ""
        if status == "NeedsAttention":
            if att_pixmap:
                icon_path = self.icon_resolver.pixmap_to_uri(key, att_pixmap)
            if not icon_path and att_name:
                chosen_icon_name = att_name
                icon_path = self.icon_resolver.resolve_icon_name(att_name, icon_theme_path)

        if not icon_path and icon_pixmap:
            icon_path = self.icon_resolver.pixmap_to_uri(key, icon_pixmap)
        if not icon_path and icon_name:
            icon_path = self.icon_resolver.resolve_icon_name(icon_name, icon_theme_path)

        self.items[key] = {
            "key": key,
            "service": service,
            "owner": existing["owner"] if existing else self._resolve_owner(service),
            "path": path,
            "id": item_id,
            "title": title,
            "displayTitle": display_title,
            "tooltipTitle": tt_title or display_title,
            "tooltipSubtitle": tt_sub,
            "category": category,
            "status": status,
            "iconName": chosen_icon_name,
            "iconPath": icon_path,
            "itemIsMenu": item_is_menu,
            "menuPath": menu_path,
            "hasMenu": bool(menu_path),
            "seq": seq,
        }

        if emit:
            self._rebuild_and_emit()

    def _remove_item(self, key: str, emit: bool):
        self._detach_item_signals(key)
        self.icon_resolver.clear_slot(key)
        self.items.pop(key, None)
        if emit:
            self._rebuild_and_emit()

    def _rebuild_and_emit(self):
        ordered = sorted(
            self.items.values(),
            key=lambda it: (0 if it.get("status") == "NeedsAttention" else 1, it.get("seq", 0)),
        )
        public_list = [
            {
                "key": it["key"],
                "id": it["id"],
                "title": it["title"],
                "displayTitle": it["displayTitle"],
                "tooltipTitle": it["tooltipTitle"],
                "tooltipSubtitle": it["tooltipSubtitle"],
                "category": it["category"],
                "status": it["status"],
                "iconName": it["iconName"],
                "iconPath": it["iconPath"],
                "itemIsMenu": it["itemIsMenu"],
                "hasMenu": it["hasMenu"],
            }
            for it in ordered
        ]
        new_json = json.dumps(public_list, ensure_ascii=False, separators=(",", ":"))
        if new_json != self.items_json:
            self.items_json = new_json
            self.version += 1
            try:
                self.PropertiesChanged(
                    BRIDGE_IFACE,
                    {
                        "ItemsJson": dbus.String(self.items_json),
                        "Version": dbus.Int32(self.version),
                    },
                    [],
                )
            except Exception as e:
                sys.stderr.write(f"[TrayBridge] PropertiesChanged failed: {e}\n")

    # ==========================================================
    # org.freedesktop.DBus.Properties
    # ==========================================================
    @dbus.service.method(dbus.PROPERTIES_IFACE, in_signature="ss", out_signature="v")
    def Get(self, interface_name, property_name):
        return self.GetAll(interface_name).get(property_name, "")

    @dbus.service.method(dbus.PROPERTIES_IFACE, in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface_name):
        return {
            "ItemsJson": dbus.String(self.items_json),
            "Version": dbus.Int32(self.version),
        }

    @dbus.service.signal(dbus.PROPERTIES_IFACE, signature="sa{sv}as")
    def PropertiesChanged(self, interface_name, changed_properties, invalidated_properties):
        pass

    # ==========================================================
    # org.doodlebookos.TrayBridge Methods
    # ==========================================================
    @dbus.service.method(BRIDGE_IFACE, in_signature="", out_signature="s")
    def GetItemsJson(self):
        return self.items_json

    def _call_sni_method(self, key: str, member: str, *args):
        it = self.items.get(str(key))
        if not it:
            return
        try:
            obj = self.bus.get_object(it["service"], it["path"], introspect=False)
            iface = dbus.Interface(obj, SNI_IFACE)
            getattr(iface, member)(*args, timeout=DBUS_CALL_TIMEOUT)
        except Exception as e:
            sys.stderr.write(f"[TrayBridge] {member}({key}) failed: {e}\n")

    @dbus.service.method(BRIDGE_IFACE, in_signature="sii", out_signature="")
    def ActivateItem(self, key, x, y):
        self._call_sni_method(key, "Activate", dbus.Int32(x), dbus.Int32(y))

    @dbus.service.method(BRIDGE_IFACE, in_signature="sii", out_signature="")
    def SecondaryActivateItem(self, key, x, y):
        self._call_sni_method(key, "SecondaryActivate", dbus.Int32(x), dbus.Int32(y))

    @dbus.service.method(BRIDGE_IFACE, in_signature="sii", out_signature="")
    def ContextMenuItem(self, key, x, y):
        self._call_sni_method(key, "ContextMenu", dbus.Int32(x), dbus.Int32(y))

    @dbus.service.method(BRIDGE_IFACE, in_signature="sis", out_signature="")
    def ScrollItem(self, key, delta, orientation):
        if int(delta) == 0:
            return
        self._call_sni_method(key, "Scroll", dbus.Int32(delta), dbus.String(orientation or "vertical"))

    def _parse_dbusmenu_node(self, item_key: str, node) -> dict | None:
        menu_id = int(node[0])
        props = dict(node[1])
        children_raw = list(node[2])

        visible = bool(props.get("visible", True))
        if menu_id != 0 and not visible:
            return None

        item_type = str(props.get("type", "standard") or "standard")
        is_separator = item_type == "separator"
        label = _strip_mnemonic(str(props.get("label", "") or ""))
        enabled = bool(props.get("enabled", True))
        toggle_type = str(props.get("toggle-type", "") or "")
        toggle_state = int(props.get("toggle-state", -1))
        children_display = str(props.get("children-display", "") or "")

        icon_name = str(props.get("icon-name", "") or "").strip()
        icon_path = ""
        raw_icon_data = props.get("icon-data")
        if raw_icon_data:
            slot_id = f"menu_{item_key}_{menu_id}"
            icon_path = self.icon_resolver.raw_png_bytes_to_uri(slot_id, bytes(raw_icon_data))
        if not icon_path and icon_name:
            icon_path = self.icon_resolver.resolve_icon_name(icon_name, "")

        parsed_children = []
        for child_variant in children_raw:
            child_node = self._parse_dbusmenu_node(item_key, child_variant)
            if child_node is not None:
                parsed_children.append(child_node)

        # Collapse leading/trailing/consecutive separators cleanly
        cleaned_children = []
        for ch in parsed_children:
            if ch["isSeparator"]:
                if not cleaned_children or cleaned_children[-1]["isSeparator"]:
                    continue
            cleaned_children.append(ch)
        while cleaned_children and cleaned_children[-1]["isSeparator"]:
            cleaned_children.pop()

        return {
            "id": menu_id,
            "label": label,
            "enabled": enabled,
            "isSeparator": is_separator,
            "toggleType": toggle_type,
            "toggleState": toggle_state,
            "iconName": icon_name,
            "iconPath": icon_path,
            "hasSubmenu": bool(children_display == "submenu" or len(cleaned_children) > 0),
            "children": cleaned_children,
        }

    def _fetch_menu_tree(self, key: str, parent_id: int) -> dict:
        it = self.items.get(str(key))
        if not it or not it.get("menuPath"):
            return {"ok": False, "hasMenu": False, "items": []}

        try:
            obj = self.bus.get_object(it["service"], it["menuPath"], introspect=False)
            miface = dbus.Interface(obj, DBUSMENU_IFACE)
            try:
                miface.AboutToShow(dbus.Int32(parent_id), timeout=DBUS_CALL_TIMEOUT)
            except Exception:
                pass
            _rev, layout = miface.GetLayout(
                dbus.Int32(parent_id),
                dbus.Int32(-1),
                dbus.Array([], signature="s"),
                timeout=DBUS_CALL_TIMEOUT,
            )
            root_parsed = self._parse_dbusmenu_node(it["key"], layout)
            items = root_parsed["children"] if root_parsed else []
            return {"ok": True, "hasMenu": True, "items": items}
        except Exception as e:
            sys.stderr.write(f"[TrayBridge] GetMenuJson({key}, parent={parent_id}) failed: {e}\n")
            return {"ok": False, "hasMenu": False, "items": []}

    @dbus.service.method(BRIDGE_IFACE, in_signature="s", out_signature="s")
    def GetMenuJson(self, key):
        return json.dumps(self._fetch_menu_tree(str(key), 0), ensure_ascii=False, separators=(",", ":"))

    @dbus.service.method(BRIDGE_IFACE, in_signature="si", out_signature="s")
    def AboutToShowSubmenu(self, key, menu_id):
        return json.dumps(self._fetch_menu_tree(str(key), int(menu_id)), ensure_ascii=False, separators=(",", ":"))

    @dbus.service.method(BRIDGE_IFACE, in_signature="si", out_signature="")
    def ActivateMenuItem(self, key, menu_id):
        it = self.items.get(str(key))
        if not it or not it.get("menuPath"):
            return
        try:
            obj = self.bus.get_object(it["service"], it["menuPath"], introspect=False)
            miface = dbus.Interface(obj, DBUSMENU_IFACE)
            ts = dbus.UInt32(int(time.time()) & 0xFFFFFFFF)
            miface.Event(
                dbus.Int32(menu_id),
                dbus.String("clicked"),
                dbus.String("", variant_level=1),
                ts,
                timeout=DBUS_CALL_TIMEOUT,
            )
        except Exception as e:
            sys.stderr.write(f"[TrayBridge] ActivateMenuItem({key}, {menu_id}) failed: {e}\n")

    @dbus.service.method(BRIDGE_IFACE, in_signature="s", out_signature="")
    def NotifyMenuClosed(self, key):
        it = self.items.get(str(key))
        if not it or not it.get("menuPath"):
            return
        try:
            obj = self.bus.get_object(it["service"], it["menuPath"], introspect=False)
            miface = dbus.Interface(obj, DBUSMENU_IFACE)
            ts = dbus.UInt32(int(time.time()) & 0xFFFFFFFF)
            miface.Event(
                dbus.Int32(0),
                dbus.String("closed"),
                dbus.String("", variant_level=1),
                ts,
                timeout=DBUS_CALL_TIMEOUT,
            )
        except Exception:
            pass


def main():
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    try:
        session_bus = dbus.SessionBus()
    except Exception as e:
        sys.stderr.write(f"[TrayBridge] Failed to connect to session bus: {e}\n")
        sys.exit(1)

    try:
        _bridge = TrayBridge(session_bus)
    except Exception as e:
        sys.stderr.write(f"[TrayBridge] Failed to claim {BRIDGE_SERVICE}: {e}\n")
        sys.exit(1)

    loop = GLib.MainLoop()

    def _shutdown(*_args):
        loop.quit()

    signal.signal(signal.SIGTERM, _shutdown)
    signal.signal(signal.SIGINT, _shutdown)

    try:
        loop.run()
    except (KeyboardInterrupt, SystemExit):
        loop.quit()


if __name__ == "__main__":
    main()

/*
    SPDX-FileCopyrightText: 2026 Maciej Kujawiński <maciek.kujawinski@gmail.com>
    SPDX-License-Identifier: GPL-3.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.workspace.dbus as DBus

Item {
    id: backend

    required property var appletRoot

    readonly property string bridgeService: "org.doodlebookos.TrayBridge"
    readonly property string bridgePath: "/TrayBridge"
    readonly property string bridgeIface: "org.doodlebookos.TrayBridge"

    readonly property var builtInDuplicates: ({
        "klipper": true,
        "org.kde.plasma.volume": true,
        "kded_pulseaudio": true,
        "kmix": true,
        "org.kde.plasma.networkmanagement": true,
        "org.kde.plasma.battery": true,
        "powerdevil": true,
        "org.kde.plasma.mediacontroller": true,
        "org.kde.plasma.keyboardlayout": true,
        "org.kde.plasma.notifications": true,
        "org.kde.plasma.nightcolor": true,
        "org.kde.plasma.bluetooth": true
    })

    readonly property int maxInlineSlots: {
        var raw = (Plasmoid && Plasmoid.configuration && typeof Plasmoid.configuration.trayMaxInlineIcons === "number")
            ? Math.round(Plasmoid.configuration.trayMaxInlineIcons)
            : 3;
        return Math.max(1, Math.min(8, raw));
    }

    readonly property bool showPassive: Boolean(Plasmoid && Plasmoid.configuration && Plasmoid.configuration.trayShowPassive)

    readonly property var userHiddenLookup: {
        var map = {};
        var raw = (Plasmoid && Plasmoid.configuration && typeof Plasmoid.configuration.trayHiddenIds === "string")
            ? Plasmoid.configuration.trayHiddenIds
            : "";
        if (raw.trim().length > 0) {
            var parts = raw.split(",");
            for (var i = 0; i < parts.length; ++i) {
                var tok = parts[i].trim().toLowerCase();
                if (tok.length > 0) {
                    map[tok] = true;
                }
            }
        }
        return map;
    }

    property var rawItems: []

    readonly property var allItems: {
        var out = [];
        for (var i = 0; i < rawItems.length; ++i) {
            var item = rawItems[i];
            if (!item) {
                continue;
            }
            var idLower = String(item.id || "").trim().toLowerCase();
            var keyLower = String(item.key || "").trim().toLowerCase();
            if ((idLower.length > 0 && builtInDuplicates[idLower])
                    || (idLower.length > 0 && userHiddenLookup[idLower])
                    || (keyLower.length > 0 && userHiddenLookup[keyLower])) {
                continue;
            }
            if (!showPassive && String(item.status || "Active") === "Passive") {
                continue;
            }
            out.push(item);
        }
        return out;
    }

    readonly property bool hasOverflow: allItems.length > maxInlineSlots

    readonly property var inlineItems: {
        if (!hasOverflow) {
            return allItems;
        }
        var visibleCount = Math.max(0, maxInlineSlots - 1);
        return allItems.slice(0, visibleCount);
    }

    readonly property var overflowItems: {
        if (!hasOverflow) {
            return [];
        }
        var visibleCount = Math.max(0, maxInlineSlots - 1);
        return allItems.slice(visibleCount);
    }

    function applyItemsJson(jsonVal) {
        var jsonStr = (jsonVal !== undefined && jsonVal !== null) ? String(jsonVal) : "";
        if (jsonStr.length === 0) {
            rawItems = [];
            return;
        }
        try {
            var parsed = JSON.parse(jsonStr);
            rawItems = Array.isArray(parsed) ? parsed : [];
        } catch (e) {
            rawItems = [];
        }
    }

    function fetchItems() {
        DBus.SessionBus.asyncCall({
            service: bridgeService,
            path: bridgePath,
            iface: bridgeIface,
            member: "GetItemsJson",
            arguments: []
        }, function(reply) {
            if (reply && !reply.isError && reply.value !== undefined && reply.value !== null) {
                backend.applyItemsJson(reply.value);
            }
        }, function(_err) {
        });
    }

    function activateItem(key, x, y) {
        DBus.SessionBus.asyncCall({
            service: bridgeService,
            path: bridgePath,
            iface: bridgeIface,
            member: "ActivateItem",
            arguments: [String(key), new DBus.int32(Math.round(x)), new DBus.int32(Math.round(y))]
        }, function(_reply) {}, function(_err) {});
    }

    function secondaryActivateItem(key, x, y) {
        DBus.SessionBus.asyncCall({
            service: bridgeService,
            path: bridgePath,
            iface: bridgeIface,
            member: "SecondaryActivateItem",
            arguments: [String(key), new DBus.int32(Math.round(x)), new DBus.int32(Math.round(y))]
        }, function(_reply) {}, function(_err) {});
    }

    function contextMenuItem(key, x, y) {
        DBus.SessionBus.asyncCall({
            service: bridgeService,
            path: bridgePath,
            iface: bridgeIface,
            member: "ContextMenuItem",
            arguments: [String(key), new DBus.int32(Math.round(x)), new DBus.int32(Math.round(y))]
        }, function(_reply) {}, function(_err) {});
    }

    function scrollItem(key, delta, orientation) {
        var d = Math.round(delta);
        if (d === 0) {
            return;
        }
        DBus.SessionBus.asyncCall({
            service: bridgeService,
            path: bridgePath,
            iface: bridgeIface,
            member: "ScrollItem",
            arguments: [String(key), new DBus.int32(d), String(orientation || "vertical")]
        }, function(_reply) {}, function(_err) {});
    }

    function loadMenu(key, callback) {
        DBus.SessionBus.asyncCall({
            service: bridgeService,
            path: bridgePath,
            iface: bridgeIface,
            member: "GetMenuJson",
            arguments: [String(key)]
        }, function(reply) {
            var result = { ok: false, hasMenu: false, items: [] };
            if (reply && !reply.isError && reply.value !== undefined && reply.value !== null) {
                try {
                    result = JSON.parse(String(reply.value));
                } catch (e) {
                    result = { ok: false, hasMenu: false, items: [] };
                }
            }
            if (callback) {
                callback(result);
            }
        }, function(_err) {
            if (callback) {
                callback({ ok: false, hasMenu: false, items: [] });
            }
        });
    }

    function loadSubmenu(key, menuId, callback) {
        DBus.SessionBus.asyncCall({
            service: bridgeService,
            path: bridgePath,
            iface: bridgeIface,
            member: "AboutToShowSubmenu",
            arguments: [String(key), new DBus.int32(Math.round(menuId))]
        }, function(reply) {
            var result = { ok: false, hasMenu: false, items: [] };
            if (reply && !reply.isError && reply.value !== undefined && reply.value !== null) {
                try {
                    result = JSON.parse(String(reply.value));
                } catch (e) {
                    result = { ok: false, hasMenu: false, items: [] };
                }
            }
            if (callback) {
                callback(result);
            }
        }, function(_err) {
            if (callback) {
                callback({ ok: false, hasMenu: false, items: [] });
            }
        });
    }

    function activateMenuItem(key, menuId) {
        DBus.SessionBus.asyncCall({
            service: bridgeService,
            path: bridgePath,
            iface: bridgeIface,
            member: "ActivateMenuItem",
            arguments: [String(key), new DBus.int32(Math.round(menuId))]
        }, function(_reply) {}, function(_err) {});
    }

    function notifyMenuClosed(key) {
        if (!key) {
            return;
        }
        DBus.SessionBus.asyncCall({
            service: bridgeService,
            path: bridgePath,
            iface: bridgeIface,
            member: "NotifyMenuClosed",
            arguments: [String(key)]
        }, function(_reply) {}, function(_err) {});
    }

    DBus.DBusServiceWatcher {
        id: bridgeWatcher
        busType: DBus.BusType.Session
        watchedService: backend.bridgeService
        onRegisteredChanged: {
            if (registered) {
                backend.fetchItems();
            } else {
                backend.rawItems = [];
            }
        }
    }

    DBus.Properties {
        id: bridgeProps
        busType: DBus.BusType.Session
        service: backend.bridgeService
        path: backend.bridgePath
        iface: backend.bridgeIface

        onPropertiesChanged: (_iface, changed, _invalidated) => {
            if (changed && changed.ItemsJson !== undefined && changed.ItemsJson !== null) {
                backend.applyItemsJson(changed.ItemsJson);
            } else if (bridgeProps.properties.ItemsJson !== undefined && bridgeProps.properties.ItemsJson !== null) {
                backend.applyItemsJson(bridgeProps.properties.ItemsJson);
            }
        }
    }

    Component.onCompleted: {
        if (bridgeProps.properties.ItemsJson !== undefined && bridgeProps.properties.ItemsJson !== null) {
            applyItemsJson(bridgeProps.properties.ItemsJson);
        }
        fetchItems();
    }
}

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasmoid
import org.kde.plasma.private.brightnesscontrolplugin as BrightnessControl
import org.kde.plasma.private.volume as Volume
import org.kde.kitemmodels as KItemModels
import org.kde.bluezqt as BluezQt
import org.kde.kcmutils as KCMUtils
import org.kde.plasma.networkmanagement as PlasmaNM
import org.kde.plasma.workspace.dbus as DBus
import org.kde.plasma.plasma5support as Plasma5Support
import QtQuick.Effects
import org.kde.plasma.private.sessions as Sessions
import "i18n.js" as I18n

PlasmaExtras.Representation {
    id: fullRep

    function i18n(k, a1, a2) { return I18n.t(k, a1, a2); }

    property var appletRoot: null
    property bool powerMenuOpen: false
    property bool manualNightLightActive: false
    property bool isEditingTiles: false
    property string activeSubView: "" // "", "wifi", "bluetooth", "power"

    readonly property real dpr: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1.0
    function snap(val) {
        return Math.round(val * dpr) / dpr;
    }

    readonly property bool isSystemDark: {
        var c = Kirigami.Theme.backgroundColor;
        var lum = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b;
        return lum < 0.5;
    }

    readonly property var defaultTiles: ["wifi", "bluetooth", "dark_mode", "battery_saver", "modes", "mic", "screenshot", "quickshare"]
    property var activeTiles: ["wifi", "bluetooth", "dark_mode", "battery_saver", "modes", "mic", "screenshot", "quickshare"]
    property var tileSpans: ({})
    readonly property var builtinTiles: ["wifi", "bluetooth", "dark_mode", "battery_saver", "modes", "mic", "screenshot", "quickshare", "keyboard",
                                         "night_light", "airplane", "caffeine", "screen_record", "clipboard", "material_you", "storage", "display", "focus", "game_mode"]
    // User-defined tiles: [{ id: "custom_xxx", name, icon, command }]
    property var customTiles: []
    readonly property var allSupportedTiles: builtinTiles.concat(customTiles.map(function(t) { return t.id; }))

    function isCustomTile(id) {
        return typeof id === "string" && id.indexOf("custom_") === 0;
    }

    function findCustomTile(id) {
        for (var i = 0; i < customTiles.length; i++) {
            if (customTiles[i].id === id) return customTiles[i];
        }
        return null;
    }

    function loadCustomTiles() {
        var raw = (Plasmoid && Plasmoid.configuration && Plasmoid.configuration.customTiles) ? Plasmoid.configuration.customTiles : "";
        var list = [];
        if (raw && raw.length > 0) {
            try {
                var parsed = JSON.parse(raw);
                if (Array.isArray(parsed)) {
                    for (var i = 0; i < parsed.length; i++) {
                        var t = parsed[i];
                        if (t && isCustomTile(t.id)) {
                            list.push({ id: t.id, name: String(t.name || ""), icon: String(t.icon || ""), command: String(t.command || "") });
                        }
                    }
                }
            } catch (e) {
                console.warn("DoodlebookOS QS: invalid customTiles config:", e);
            }
        }
        customTiles = list;
    }

    function saveCustomTiles() {
        if (Plasmoid && Plasmoid.configuration) {
            Plasmoid.configuration.customTiles = JSON.stringify(customTiles);
        }
    }

    // Creates a custom tile and places it on the panel right away (live, no restart needed)
    function addCustomTile(name, icon, command) {
        var id = "custom_" + Date.now().toString(36);
        var copy = customTiles.slice();
        copy.push({ id: id, name: String(name).trim(), icon: String(icon || "").trim(), command: String(command).trim() });
        customTiles = copy;
        saveCustomTiles();
        var arr = activeTiles.slice();
        arr.push(id);
        activeTiles = arr;
        setTileSpan(id, 2);
        return id;
    }

    function removeCustomTile(id) {
        customTiles = customTiles.filter(function(t) { return t.id !== id; });
        saveCustomTiles();
        if (activeTiles.indexOf(id) !== -1) {
            activeTiles = activeTiles.filter(function(t) { return t !== id; });
            saveActiveTiles();
        }
    }

    // Monochrome (masked) rendering for our bundled SVGs and *-symbolic theme icons;
    // full-colour rendering for regular application icons used by custom tiles.
    function tileIconIsMask(id) {
        if (!isCustomTile(id)) return true;
        var t = findCustomTile(id);
        var icon = t ? t.icon : "";
        return icon.length === 0 || /-symbolic$/.test(icon) || icon.indexOf("/") !== -1;
    }

    function closePopup() {
        if (appletRoot && typeof appletRoot.closeAllPopups === "function") {
            appletRoot.closeAllPopups();
        }
    }

    // Opens the tile editor, optionally pre-selecting a tile (right-click / "+" tile)
    function openTileEditor(tileId) {
        powerMenuOpen = false;
        activeSubView = "";
        isEditingTiles = true;
        var idx = (tileId && tileId.length > 0) ? activeTiles.indexOf(tileId) : -1;
        Qt.callLater(function() {
            if (editTilesLoader.item) {
                editTilesLoader.item.selectedTileIndex = idx;
            }
        });
    }

    // ---------- Night Light (shared by the moon button and the "night_light" tile) ----------
    readonly property bool isNightLightOn: {
        if (manualNightLightActive) {
            return true;
        }
        if (nightLightControl.available && nightLightControl.running && !nightLightControl.inhibited) {
            if (!nightLightControl.daylight || (nightLightControl.currentTemperature > 0 && nightLightControl.currentTemperature < 6000)) {
                return true;
            }
        }
        return false;
    }

    function toggleNightLight() {
        var nightTemp = (nightLightControl.targetTemperature > 0 && nightLightControl.targetTemperature < 6000)
                        ? nightLightControl.targetTemperature
                        : 3300;
        if (isNightLightOn) {
            if (manualNightLightActive) {
                manualNightLightActive = false;
                executable.exec("$(command -v qdbus-qt6 || command -v qdbus6 || command -v qdbus) org.kde.KWin /org/kde/KWin/NightLight org.kde.KWin.NightLight.stopPreview");
            }
            if (nightLightControl.running && !nightLightControl.inhibited && !nightLightControl.daylight) {
                BrightnessControl.NightLightInhibitor.toggleInhibition();
            }
        } else {
            if (nightLightControl.inhibited) {
                BrightnessControl.NightLightInhibitor.toggleInhibition();
            }
            if (nightLightControl.daylight || !nightLightControl.running) {
                manualNightLightActive = true;
                executable.exec("$(command -v qdbus-qt6 || command -v qdbus6 || command -v qdbus) org.kde.KWin /org/kde/KWin/NightLight org.kde.KWin.NightLight.preview " + nightTemp);
            }
        }
    }

    // ---------- System queries (power profiles, "stay awake") ----------
    // PowerDevil proxies power-profiles-daemon / tuned-ppd on the session bus.
    readonly property string ppCall: "busctl --user call org.kde.Solid.PowerManagement /org/kde/Solid/PowerManagement/Actions/PowerProfile org.kde.Solid.PowerManagement.Actions.PowerProfile"
    property var powerProfiles: []
    property string currentPowerProfile: ""
    property bool caffeineActive: false

    function parseDbusStrings(out) {
        var re = /"([^"]*)"/g;
        var m;
        var res = [];
        while ((m = re.exec(String(out))) !== null) {
            res.push(m[1]);
        }
        return res;
    }

    function runQuery(cmd, tag) {
        sysQuery.connectSource(cmd + " # " + tag + "-" + Date.now());
    }

    function refreshPowerProfile() {
        runQuery(ppCall + " profileChoices", "ppchoices");
        runQuery(ppCall + " currentProfile", "ppcurrent");
    }

    function setPowerProfile(profile) {
        if (!/^[a-z-]+$/.test(profile) || powerProfiles.indexOf(profile) === -1) return;
        if (profile === currentPowerProfile) return; // avoid a needless system-wide re-tune
        currentPowerProfile = profile; // optimistic, confirmed by the follow-up query
        runQuery(ppCall + " setProfile s " + profile + " ; " + ppCall + " currentProfile", "ppcurrent");
    }

    function powerProfileTitle(p) {
        switch (p) {
            case "power-saver": return i18n("Power saver");
            case "balanced": return i18n("Balanced");
            case "performance": return i18n("Performance");
            default: return p;
        }
    }

    function powerProfileIcon(p) {
        switch (p) {
            case "power-saver": return Qt.resolvedUrl("icons/eco.svg");
            case "performance": return Qt.resolvedUrl("icons/speed.svg");
            default: return Qt.resolvedUrl("icons/gauge.svg");
        }
    }

    // "Stay awake" runs as a transient systemd user unit holding a logind idle+sleep
    // inhibitor, so it is independent from (and survives restarts of) plasmashell.
    readonly property string caffeineUnit: "doodlebookos-stay-awake"

    function refreshCaffeine() {
        runQuery("systemctl --user is-active --quiet " + caffeineUnit + " && echo on || echo off", "caffeine");
    }

    // Material You: colour scheme generated from the wallpaper (extras/scripts/doodlebookos-materialyou)
    property bool materialYouActive: false
    readonly property string materialYouCmd: "\"$HOME/.local/bin/doodlebookos-materialyou\""

    function refreshMaterialYou() {
        runQuery(materialYouCmd + " status 2>/dev/null || echo off", "materialyou");
    }

    function toggleMaterialYou() {
        materialYouActive = !materialYouActive; // optimistic, the scheme follows in ~0.3 s
        executable.exec(materialYouCmd + (materialYouActive ? " on" : " off"));
    }

    function toggleCaffeine() {
        if (caffeineActive) {
            caffeineActive = false;
            executable.exec("systemctl --user stop " + caffeineUnit);
        } else {
            caffeineActive = true;
            executable.exec("systemd-run --user --collect --unit=" + caffeineUnit + " --description='DoodlebookOS stay awake'"
                            + " systemd-inhibit --what=idle:sleep --who=DoodlebookOS --why='Stay awake (Quick Settings)' sleep infinity");
        }
    }

    Plasma5Support.DataSource {
        id: sysQuery
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            var out = data["stdout"] || "";
            if (sourceName.indexOf("# ppchoices") !== -1) {
                var choices = fullRep.parseDbusStrings(out);
                fullRep.powerProfiles = choices.length > 1 ? choices : [];
            } else if (sourceName.indexOf("# ppcurrent") !== -1) {
                var cur = fullRep.parseDbusStrings(out);
                if (cur.length > 0) fullRep.currentPowerProfile = cur[0];
            } else if (sourceName.indexOf("# caffeine") !== -1) {
                fullRep.caffeineActive = String(out).trim() === "on";
            } else if (sourceName.indexOf("# materialyou") !== -1) {
                fullRep.materialYouActive = String(out).trim() === "on";
            }
            disconnectSource(sourceName);
        }
    }

    // ---------- Material 3 motion: staggered reveal when the drawer opens ----------
    readonly property bool animationsEnabled: Kirigami.Units.longDuration > 1
    property real revealT: 1.0
    NumberAnimation {
        id: revealAnim
        target: fullRep
        property: "revealT"
        from: 0
        to: 1
        duration: 480
        easing.type: Easing.Linear
    }

    // Emphasized-decelerate approximation (M3 "enter" curve)
    function m3ease(x) {
        var c = Math.max(0, Math.min(1, x));
        return 1 - Math.pow(1 - c, 4);
    }

    // Progress of an element whose entrance starts at `delay` (0..0.5) of the timeline
    function reveal(delay) {
        return m3ease((revealT - Math.min(0.5, delay)) / 0.5);
    }

    function playReveal() {
        if (!animationsEnabled) {
            revealT = 1.0;
            return;
        }
        revealAnim.stop();
        revealT = 0;
        revealAnim.start();
    }

    property bool popupShown: false

    function onPopupShown() {
        popupShown = true;
        slider1Item.syncFromSystem();
        slider2Item.syncFromSystem();
        refreshPowerProfile();
        refreshCaffeine();
        refreshMaterialYou();
        playReveal();
    }

    function onPopupHidden() {
        popupShown = false;
        revealAnim.stop();
        powerMenuOpen = false;
        isEditingTiles = false;
        activeSubView = "";
        revealT = 1.0;
    }

    onActiveSubViewChanged: {
        if (popupShown && activeSubView === "" && !isEditingTiles) playReveal();
    }
    onIsEditingTilesChanged: {
        if (popupShown && !isEditingTiles && activeSubView === "") playReveal();
    }

    function getTileSpan(id) {
        if (tileSpans && tileSpans[id] !== undefined) {
            return tileSpans[id] === 1 ? 1 : 2;
        }
        return 2;
    }

    function setTileSpan(id, span) {
        var copy = Object.assign({}, tileSpans);
        copy[id] = (span === 1 ? 1 : 2);
        tileSpans = copy;
        saveActiveTiles();
    }

    readonly property bool isBtOn: (typeof BluezQt !== "undefined" && BluezQt.Manager &&
        (BluezQt.Manager.usableAdapter ? BluezQt.Manager.usableAdapter.powered : (BluezQt.Manager.bluetoothOperational && !BluezQt.Manager.bluetoothBlocked)))

    function loadActiveTiles() {
        var cfg = (Plasmoid && Plasmoid.configuration) ? Plasmoid.configuration.activeTiles : "";
        var spans = {};
        if (cfg && typeof cfg === "string" && cfg.trim().length > 0) {
            var list = cfg.split(",");
            var clean = [];
            for (var i = 0; i < list.length; i++) {
                var item = list[i].trim();
                if (item.length === 0) continue;
                var parts = item.split(":");
                var t = parts[0].trim();
                var s = parts.length > 1 ? parseInt(parts[1], 10) : 2;
                if (s !== 1 && s !== 2) s = 2;
                if (t.length > 0 && allSupportedTiles.indexOf(t) !== -1 && clean.indexOf(t) === -1) {
                    clean.push(t);
                    spans[t] = s;
                }
            }
            if (clean.length > 0) {
                tileSpans = spans;
                activeTiles = clean;
                return;
            }
        }
        tileSpans = {};
        activeTiles = defaultTiles.slice();
    }

    function saveActiveTiles() {
        if (Plasmoid && Plasmoid.configuration) {
            var formatted = [];
            for (var i = 0; i < activeTiles.length; i++) {
                var id = activeTiles[i];
                var s = getTileSpan(id);
                formatted.push(id + ":" + s);
            }
            Plasmoid.configuration.activeTiles = formatted.join(",");
        }
    }

    function getWifiSubtitle() {
        if (!nmEnabled.wirelessEnabled) {
            return i18n("Off");
        }
        if (appletRoot && appletRoot.nmStatus && appletRoot.nmStatus.activeConnections) {
            var conn = appletRoot.nmStatus.activeConnections;
            var raw = "";
            if (typeof conn === "string" && conn.trim().length > 0) {
                raw = conn;
            } else if (Array.isArray(conn) && conn.length > 0) {
                raw = conn[0];
            }
            if (raw.length > 0) {
                var s = raw.trim();
                s = s.replace(/^[wW][iI]-[fF][iI]:\s*/i, "");
                s = s.replace(/^(?:połączono z|connected to|verbunden mit|connecté à)\s+/i, "");
                if (s.indexOf(":") !== -1) {
                    var parts = s.split(":");
                    s = parts[parts.length - 1].trim();
                    s = s.replace(/^(?:połączono z|connected to)\s+/i, "");
                }
                s = s.trim();
                if (s.length > 0) {
                    return s;
                }
            }
        }
        return i18n("Not connected");
    }

    function getBluetoothSubtitle() {
        if (!isBtOn) {
            return i18n("Off");
        }
        if (typeof BluezQt !== "undefined" && BluezQt.Manager && BluezQt.Manager.connectedDevices && BluezQt.Manager.connectedDevices.length > 0) {
            var dev = BluezQt.Manager.connectedDevices[0];
            var devName = dev.name || dev.friendlyName || dev.alias || "";
            // headphones battery (BlueZ Battery1) right in the tile, like Android
            if (devName.length > 0 && dev.battery && dev.battery.percentage >= 0) {
                devName += " · " + dev.battery.percentage + " %";
            }
            if (devName.length > 0) {
                if (BluezQt.Manager.connectedDevices.length > 1) {
                    return devName + " (+" + (BluezQt.Manager.connectedDevices.length - 1) + ")";
                }
                return devName;
            }
        }
        return i18n("On");
    }

    function getBatterySubtitle() {
        var bm = (appletRoot && appletRoot.batteryModel) ? appletRoot.batteryModel : null;
        var hasInternal = (appletRoot && appletRoot.hasInternalBattery !== undefined)
            ? appletRoot.hasInternalBattery
            : (bm ? Boolean(bm.hasCumulative || (bm.hasInternalBatteries && bm.percent > 0)) : false);

        if (hasInternal && bm) {
            var pct = (bm.percent !== undefined) ? bm.percent : 0;
            var st = "";
            if (bm.state === 1) st = i18n("Charging");
            else if (bm.state === 3) st = i18n("Fully charged");
            else if (bm.pluggedIn) st = i18n("Connected to AC");
            else st = i18n("On battery");
            return i18n("%1% (%2)", pct, st);
        }
        return (bm && bm.pluggedIn) ? i18n("AC Power") : i18n("Connected to power");
    }

    function getTileTitle(id) {
        switch (id) {
            case "wifi": return i18n("Wi-Fi");
            case "bluetooth": return i18n("Bluetooth");
            case "dark_mode": return i18n("Dark theme");
            case "battery_saver": return i18n("Power & battery");
            case "modes": return i18n("Do not disturb");
            case "mic": return i18n("Microphone access");
            case "screenshot": return i18n("Screenshot");
            case "quickshare": return i18n("Quick Share");
            case "keyboard": return i18n("Keyboard");
            case "night_light": return i18n("Night Light");
            case "airplane": return i18n("Airplane mode");
            case "caffeine": return i18n("Stay awake");
            case "screen_record": return i18n("Screen record");
            case "clipboard": return i18n("Clipboard");
            case "material_you": return "Material You";
            case "storage": return i18n("Storage");
            case "focus": return i18n("Focus");
            case "game_mode": return i18n("Game mode");
            case "display": return i18n("Display");
            default: {
                var ct = findCustomTile(id);
                return ct ? ct.name : id;
            }
        }
    }

    function getTileSubtitle(id) {
        switch (id) {
            case "wifi": return getWifiSubtitle();
            case "bluetooth": return getBluetoothSubtitle();
            case "dark_mode": return fullRep.isSystemDark ? i18n("On") : i18n("Off");
            case "battery_saver":
                // Desktop PCs have no internal battery: show the active power profile instead
                if (!(appletRoot && appletRoot.hasInternalBattery) && currentPowerProfile.length > 0) {
                    return powerProfileTitle(currentPowerProfile);
                }
                return getBatterySubtitle();
            case "modes": return (appletRoot && appletRoot.isDndActive)
                ? (appletRoot.dndUntil - new Date() < 86400000 ? i18n("Until %1", Qt.formatTime(appletRoot.dndUntil, "HH:mm")) : i18n("On"))
                : (appletRoot && appletRoot.dndSchedule ? i18n("Scheduled") : i18n("Off"));
            case "mic":
                if (!fullRep.activeSource) return i18n("Unavailable");
                return fullRep.activeSource.muted ? i18n("Muted") : i18n("Available");
            case "screenshot": return i18n("Area capture");
            case "quickshare": return i18n("KDE Connect");
            case "keyboard": return i18n("Virtual keyboard");
            case "night_light": return isNightLightOn ? i18n("On") : i18n("Off");
            case "airplane": return PlasmaNM.Configuration.airplaneModeEnabled ? i18n("On") : i18n("Off");
            case "caffeine": return caffeineActive ? i18n("On") : i18n("Off");
            case "screen_record": return i18n("Region");
            case "clipboard": return i18n("History");
            case "material_you": return materialYouActive ? i18n("Wallpaper colors") : i18n("Off");
            case "storage": return i18n("USB & disks");
            case "focus": return (appletRoot && appletRoot.focusMode) ? i18n("On") : i18n("Off");
            case "game_mode": return (appletRoot && appletRoot.gameMode) ? i18n("Max CPU performance") : i18n("Automatic");
            case "display": return i18n("Scale & refresh rate");
            default: return isCustomTile(id) ? i18n("Shortcut") : "";
        }
    }

    function getTileIcon(id) {
        switch (id) {
            case "wifi": return (appletRoot && appletRoot.currentWifiIcon) ? appletRoot.currentWifiIcon : Qt.resolvedUrl("icons/wifi_3.svg");
            case "bluetooth": return Qt.resolvedUrl("icons/bluetooth.svg");
            case "dark_mode": return Qt.resolvedUrl("icons/dark_mode.svg");
            case "battery_saver": return Qt.resolvedUrl("icons/battery_saver.svg");
            case "modes": return Qt.resolvedUrl("icons/modes.svg");
            case "mic": return Qt.resolvedUrl("icons/mic.svg");
            case "screenshot": return Qt.resolvedUrl("icons/screenshot.svg");
            case "quickshare": return Qt.resolvedUrl("icons/quickshare.svg");
            case "keyboard": return Qt.resolvedUrl("icons/keyboard.svg");
            case "night_light": return Qt.resolvedUrl("icons/moon.svg");
            case "airplane": return Qt.resolvedUrl("icons/airplane.svg");
            case "caffeine": return Qt.resolvedUrl("icons/coffee.svg");
            case "screen_record": return Qt.resolvedUrl("icons/screen_record.svg");
            case "clipboard": return Qt.resolvedUrl("icons/clipboard.svg");
            case "material_you": return Qt.resolvedUrl("icons/palette.svg");
            case "storage": return Qt.resolvedUrl("icons/usb.svg");
            case "focus": return Qt.resolvedUrl("icons/focus.svg");
            case "game_mode": return Qt.resolvedUrl("icons/gamepad.svg");
            case "display": return Qt.resolvedUrl("icons/monitor.svg");
            default: {
                var ct = findCustomTile(id);
                return (ct && ct.icon.length > 0) ? ct.icon : Qt.resolvedUrl("icons/touch.svg");
            }
        }
    }

    function tileHasCircleBadge(id) {
        return id === "wifi" || id === "bluetooth" || id === "modes";
    }

    function isTileActive(id) {
        switch (id) {
            case "wifi": return Boolean(nmEnabled.wirelessEnabled);
            case "bluetooth": return Boolean(isBtOn);
            case "dark_mode": return fullRep.isSystemDark;
            case "battery_saver": return currentPowerProfile === "power-saver";
            case "modes": return Boolean(appletRoot && appletRoot.isDndActive);
            case "mic": return Boolean(fullRep.activeSource && !fullRep.activeSource.muted);
            case "screenshot": return false;
            case "quickshare": return false;
            case "keyboard": return false;
            case "night_light": return isNightLightOn;
            case "airplane": return Boolean(PlasmaNM.Configuration.airplaneModeEnabled);
            case "caffeine": return caffeineActive;
            case "material_you": return materialYouActive;
            case "focus": return Boolean(appletRoot && appletRoot.focusMode);
            case "game_mode": return Boolean(appletRoot && appletRoot.gameMode);
            default: return false;
        }
    }

    function executeTileAction(id) {
        switch (id) {
            case "wifi":
                fullRep.powerMenuOpen = false;
                fullRep.activeSubView = "wifi";
                break;
            case "bluetooth":
                fullRep.powerMenuOpen = false;
                fullRep.activeSubView = "bluetooth";
                break;
            case "dark_mode":
                executable.exec("dostheme toggle");
                break;
            case "battery_saver":
                fullRep.powerMenuOpen = false;
                fullRep.activeSubView = "power";
                break;
            case "modes":
                fullRep.powerMenuOpen = false;
                fullRep.activeSubView = "dnd";
                break;
            case "mic":
                if (fullRep.activeSource) {
                    fullRep.activeSource.muted = !fullRep.activeSource.muted;
                } else {
                    executable.exec("pactl set-source-mute @DEFAULT_SOURCE@ toggle");
                }
                break;
            case "screenshot":
                // Collapse the drawer first so it is not part of the capture (Android behaviour)
                closePopup();
                executable.exec("sleep 0.25; spectacle -r");
                break;
            case "quickshare":
                closePopup();
                executable.exec("kdeconnect-app");
                break;
            case "keyboard":
                executable.exec("$(command -v qdbus-qt6 || command -v qdbus6 || command -v qdbus) org.kde.KWin /KWin org.kde.KWin.showVirtualKeyboard");
                break;
            case "night_light":
                toggleNightLight();
                break;
            case "airplane": {
                var enable = !PlasmaNM.Configuration.airplaneModeEnabled;
                nmHandler.enableAirplaneMode(enable);
                PlasmaNM.Configuration.airplaneModeEnabled = enable;
                break;
            }
            case "caffeine":
                toggleCaffeine();
                break;
            case "material_you":
                toggleMaterialYou();
                break;
            case "focus":
                if (appletRoot && appletRoot.toggleFocusMode) appletRoot.toggleFocusMode();
                break;
            case "game_mode":
                if (appletRoot && appletRoot.toggleGameMode) appletRoot.toggleGameMode();
                break;
            case "storage":
                fullRep.powerMenuOpen = false;
                fullRep.activeSubView = "storage";
                break;
            case "display":
                fullRep.powerMenuOpen = false;
                fullRep.activeSubView = "display";
                break;
            case "screen_record":
                closePopup();
                executable.exec("sleep 0.25; spectacle -R region");
                break;
            case "clipboard":
                fullRep.powerMenuOpen = false;
                fullRep.activeSubView = "clipboard";
                break;
            default: {
                var ct = findCustomTile(id);
                if (ct && ct.command.length > 0) {
                    closePopup();
                    executable.exec("nohup sh -c " + JSON.stringify(ct.command) + " </dev/null >/dev/null 2>&1 &");
                }
                break;
            }
        }
    }

    // short, quiet click (PipeWire); one process per tap, nothing resident
    function playClick() {
        if (Plasmoid.configuration.tileSound) executable.exec("pw-play --volume 0.3 /usr/share/sounds/ocean/stereo/button-pressed.oga");
    }

    function executeTileIconAction(id) {
        if (id === "wifi") {
            nmHandler.enableWireless(!nmEnabled.wirelessEnabled);
        } else if (id === "bluetooth") {
            if (typeof BluezQt !== "undefined" && BluezQt.Manager) {
                if (BluezQt.Manager.usableAdapter) {
                    BluezQt.Manager.usableAdapter.powered = !BluezQt.Manager.usableAdapter.powered;
                }
                BluezQt.Manager.bluetoothBlocked = !BluezQt.Manager.bluetoothBlocked;
            }
        } else if (id === "modes") {
            if (appletRoot && appletRoot.toggleDoNotDisturbMode) appletRoot.toggleDoNotDisturbMode();
        } else {
            executeTileAction(id);
        }
    }

    Component.onCompleted: {
        loadCustomTiles();
        loadActiveTiles();
        refreshPowerProfile();
    }

    Sessions.SessionManagement {
        id: sessionManagement
    }

    function requestLogout() {
        fullRep.powerMenuOpen = false;
        if (fullRep.appletRoot) {
            fullRep.appletRoot.expanded = false;
        }
        try {
            if (sessionManagement && typeof sessionManagement.requestLogout === "function") {
                sessionManagement.requestLogout();
                return;
            }
        } catch (e) {
            console.warn("SessionManagement requestLogout error:", e);
        }
        executable.exec("$(command -v qdbus-qt6 || command -v qdbus6 || command -v qdbus) org.kde.LogoutPrompt /LogoutPrompt org.kde.LogoutPrompt.promptLogout");
    }

    function requestReboot() {
        fullRep.powerMenuOpen = false;
        if (fullRep.appletRoot) {
            fullRep.appletRoot.expanded = false;
        }
        try {
            if (sessionManagement && typeof sessionManagement.requestReboot === "function") {
                sessionManagement.requestReboot();
                return;
            }
        } catch (e) {
            console.warn("SessionManagement requestReboot error:", e);
        }
        executable.exec("$(command -v qdbus-qt6 || command -v qdbus6 || command -v qdbus) org.kde.LogoutPrompt /LogoutPrompt org.kde.LogoutPrompt.promptReboot");
    }

    function requestShutdown() {
        fullRep.powerMenuOpen = false;
        if (fullRep.appletRoot) {
            fullRep.appletRoot.expanded = false;
        }
        try {
            if (sessionManagement && typeof sessionManagement.requestShutdown === "function") {
                sessionManagement.requestShutdown();
                return;
            }
        } catch (e) {
            console.warn("SessionManagement requestShutdown error:", e);
        }
        executable.exec("$(command -v qdbus-qt6 || command -v qdbus6 || command -v qdbus) org.kde.LogoutPrompt /LogoutPrompt org.kde.LogoutPrompt.promptShutDown");
    }

    Binding {
        when: Boolean(fullRep.Window && fullRep.Window.window !== null && fullRep.Window.window.hasOwnProperty("margin"))
        target: fullRep.Window ? fullRep.Window.window : null
        property: "margin"
        value: 1
    }

    Binding {
        when: Boolean(fullRep.Window && fullRep.Window.window !== null && fullRep.Window.window.hasOwnProperty("visualParent") && fullRep.appletRoot && fullRep.appletRoot.popupAnchorItem !== null)
        target: fullRep.Window ? fullRep.Window.window : null
        property: "visualParent"
        value: fullRep.appletRoot ? fullRep.appletRoot.popupAnchorItem : null
    }

    Connections {
        target: fullRep.Window ? fullRep.Window.window : null
        function onVisibleChanged() {
            var win = fullRep.Window ? fullRep.Window.window : null;
            // The drawer is a PlasmaCore.AppletPopup driven by visibility, not by
            // Plasmoid.expanded, so open/close lifecycle hooks live here.
            if (win && win.visible) {
                fullRep.onPopupShown();
            } else {
                fullRep.onPopupHidden();
            }
            if (win && win.visible) {
                Qt.callLater(() => {
                    if (!win || !win.visible || !win.screen) return;
                    var screenW = win.screen.geometry.width;
                    var screenX = win.screen.geometry.x;
                    var rightEdge = screenX + screenW;
                    var offset = 8;
                    if ((win.x + win.width) > (rightEdge - offset)) {
                        win.x = rightEdge - win.width - offset;
                    }
                });
            }
        }
    }

    Plasma5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName);
        }
        function exec(cmd) {
            // Unique source name so repeating the same action is never swallowed
            connectSource(cmd + " # " + Date.now());
        }
    }

    DBus.Properties {
        id: nightLightControl
        busType: DBus.BusType.Session
        service: "org.kde.KWin.NightLight"
        path: "/org/kde/KWin/NightLight"
        iface: "org.kde.KWin.NightLight"

        readonly property bool available: Boolean(properties.available)
        readonly property bool running: Boolean(properties.running)
        readonly property bool inhibited: Boolean(properties.inhibited)
        readonly property bool daylight: Boolean(properties.daylight)
        readonly property int currentTemperature: Number(properties.currentTemperature)
        readonly property int targetTemperature: Number(properties.targetTemperature)
    }

    PlasmaNM.Handler {
        id: nmHandler
    }

    PlasmaNM.EnabledConnections {
        id: nmEnabled
    }

    BrightnessControl.ScreenBrightnessControl {
        id: screenBrightnessControl
    }

    Instantiator {
        id: displaysInstantiator
        model: screenBrightnessControl.displays
        delegate: QtObject {
            property string dName: model.displayName
            property int bVal: model.brightness
            property int bMax: model.maxBrightness

            onBValChanged: {
                if (!slider1Item.isDragging) {
                    slider1Item.syncFromSystem();
                }
            }
        }
        onCountChanged: {
            slider1Item.syncFromSystem();
        }
    }

    Connections {
        target: screenBrightnessControl
        function onIsBrightnessAvailableChanged() {
            slider1Item.syncFromSystem();
        }
    }

    readonly property var paSinkModel: (appletRoot && appletRoot.paSinkModel) ? appletRoot.paSinkModel : null

    Volume.SourceModel {
        id: localSourceModel
    }

    readonly property var activeSource: {
        if (Volume.PreferredDevice && Volume.PreferredDevice.source) {
            return Volume.PreferredDevice.source;
        }
        var model = localSourceModel;
        if (model && model.count > 0) {
            var role = model.KItemModels.KRoleNames.role("PulseObject");
            for (var i = 0; i < model.count; ++i) {
                var po = model.data(model.index(i, 0), role);
                if (po && po.default) {
                    return po;
                }
            }
            return model.data(model.index(0, 0), role);
        }
        return null;
    }

    readonly property var activeSink: {
        if (Volume.PreferredDevice && Volume.PreferredDevice.sink) {
            return Volume.PreferredDevice.sink;
        }
        var model = fullRep.paSinkModel;
        if (model && model.count > 0) {
            var role = model.KItemModels.KRoleNames.role("PulseObject");
            for (var i = 0; i < model.count; ++i) {
                var po = model.data(model.index(i, 0), role);
                if (po && po.default) {
                    return po;
                }
            }
            return model.data(model.index(0, 0), role);
        }
        return null;
    }

    onActiveSinkChanged: {
        slider2Item.syncFromSystem();
    }

    Connections {
        target: Volume.PreferredDevice
        function onSinkChanged() {
            slider2Item.syncFromSystem();
        }
    }

    Connections {
        target: fullRep.paSinkModel
        function onCountChanged() {
            slider2Item.syncFromSystem();
        }
    }

    Connections {
        target: fullRep.activeSink
        function onVolumeChanged() {
            if (!slider2Item.isDragging) {
                slider2Item.syncFromSystem();
            }
        }
        function onMutedChanged() {
            if (!slider2Item.isDragging) {
                slider2Item.syncFromSystem();
            }
        }
    }

    Connections {
        target: fullRep.appletRoot
        function onExpandedChanged() {
            if (fullRep.appletRoot && fullRep.appletRoot.expanded) {
                slider1Item.syncFromSystem();
                slider2Item.syncFromSystem();
            } else {
                fullRep.powerMenuOpen = false;
                fullRep.isEditingTiles = false;
                fullRep.activeSubView = "";
            }
        }
    }

    // Material You tertiary (from doodlebookos-materialyou's palette.json); falls back to the accent.
    // Re-read only when the colour scheme changes.
    property color tertiaryColor: effectiveAccentColor
    property color onTertiaryColor: Kirigami.Theme.highlightedTextColor
    readonly property color schemeHighlight: Kirigami.Theme.highlightColor
    onSchemeHighlightChanged: loadPalette()
    function loadPalette() { paletteSource.connectSource("cat \"$HOME/.config/doodlebookos/palette.json\" 2>/dev/null # " + Date.now()); }
    Plasma5Support.DataSource {
        id: paletteSource
        engine: "executable"
        connectedSources: []
        Component.onCompleted: fullRep.loadPalette()
        onNewData: (src, data) => {
            disconnectSource(src);
            var p = null;
            try { p = JSON.parse(data["stdout"] || "{}"); } catch (e) { p = null; }
            if (p && p.enabled && p.tertiary) {
                fullRep.tertiaryColor = p.tertiary;
                fullRep.onTertiaryColor = p.onTertiary;
            } else {
                fullRep.tertiaryColor = Qt.binding(() => fullRep.effectiveAccentColor);
                fullRep.onTertiaryColor = Qt.binding(() => Kirigami.Theme.highlightedTextColor);
            }
        }
    }

    readonly property color effectiveAccentColor: {
        if (appletRoot && appletRoot.effectiveAccentColor) {
            return appletRoot.effectiveAccentColor;
        }
        var cfg = (typeof Plasmoid !== "undefined" && Plasmoid.configuration) ? Plasmoid.configuration : null;
        if (cfg && cfg.useCustomAccentColor && cfg.accentColor) {
            return cfg.accentColor;
        }
        return Kirigami.Theme.highlightColor;
    }

    readonly property color oneUiTrackBg: containerScope ? containerScope.Kirigami.Theme.backgroundColor : Kirigami.Theme.backgroundColor

    Layout.preferredWidth: snap(338.4) // 423px fizycznych: 18px lewy margines + 387px siatka kafelków + 18px prawy margines
    Layout.minimumWidth: Layout.preferredWidth
    Layout.maximumWidth: Layout.preferredWidth

    readonly property real availableScreenH: (typeof Screen !== "undefined" && Screen.desktopAvailableHeight > 0)
        ? Screen.desktopAvailableHeight
        : ((typeof Screen !== "undefined" && Screen.height > 0) ? Screen.height : 1080)
    readonly property real maxDrawerHeight: Math.max(snap(360.0), availableScreenH - snap(52.0) - snap(16.0))

    Layout.preferredHeight: {
        var wantedH = snap(440.0);
        if (fullRep.isEditingTiles) {
            wantedH = (editTilesLoader.item ? editTilesLoader.item.implicitHeight : 0) + fullRep.snap(14.4) + fullRep.snap(28.8);
            wantedH = Math.max(fullRep.snap(300.0), wantedH);
        } else if (fullRep.activeSubView === "wifi") {
            wantedH = (wifiLoader.item ? wifiLoader.item.implicitHeight : 0) + fullRep.snap(14.4) + fullRep.snap(28.8);
            wantedH = Math.max(fullRep.snap(260.0), wantedH);
        } else if (fullRep.activeSubView === "bluetooth") {
            wantedH = (bluetoothLoader.item ? bluetoothLoader.item.implicitHeight : 0) + fullRep.snap(14.4) + fullRep.snap(28.8);
            wantedH = Math.max(fullRep.snap(260.0), wantedH);
        } else if (fullRep.activeSubView !== "") {
            wantedH = snap(544.0);
        } else {
            wantedH = (mainCol && mainCol.implicitHeight > 100) ? (mainCol.implicitHeight + fullRep.snap(14.4) * 2) : snap(440.0);
        }
        return Math.min(maxDrawerHeight, Math.max(snap(280.0), wantedH));
    }
    Layout.minimumHeight: snap(260.0)
    Layout.maximumHeight: maxDrawerHeight

    implicitWidth: Layout.preferredWidth
    implicitHeight: Layout.preferredHeight
    width: Layout.preferredWidth
    height: Layout.preferredHeight

    contentItem: Item {
        id: container

        Item {
            id: containerScope
            Kirigami.Theme.colorSet: Kirigami.Theme.Button
            Kirigami.Theme.inherit: false
        }

        // Main content column
        ColumnLayout {
            id: mainCol
            visible: (!fullRep.isEditingTiles && fullRep.activeSubView === "")
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: fullRep.snap(14.4)   // 18px fizycznych
            anchors.rightMargin: fullRep.snap(14.4)  // 18px fizycznych
            anchors.topMargin: fullRep.snap(14.4)    // 18px fizycznych
            spacing: fullRep.snap(8)

            // 1. Top Header Row
            RowLayout {
                id: headerRow
                readonly property real enter: fullRep.reveal(0.0)
                opacity: enter
                transform: Translate { y: (1 - headerRow.enter) * -fullRep.snap(10) }
                Layout.fillWidth: true
                Layout.preferredHeight: fullRep.snap(29.6) // dokładnie 37px fizycznych (29.6 dp)
                Layout.bottomMargin: fullRep.snap(14.4) - fullRep.snap(3.6) - mainCol.spacing // dokładnie 18px fizycznych od dolnej krawędzi boxów do toru suwaka jasności (na linii testowej)
                spacing: fullRep.snap(6.4)

                // Edit tiles icon button (grid with pencil)
                Rectangle {
                    Layout.preferredWidth: fullRep.snap(29.6)  // 37px fizycznych
                    Layout.preferredHeight: fullRep.snap(29.6) // 37px fizycznych
                    radius: fullRep.snap(8)
                    Layout.alignment: Qt.AlignVCenter
                    color: editMouse.pressed ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.18)
                                             : (editMouse.containsMouse ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.1) : "transparent")

                    Kirigami.Icon {
                        anchors.centerIn: parent
                        width: fullRep.snap(17.6)  // zwiększone o 1px: 22px fizyczne (17.6 dp)
                        height: fullRep.snap(17.6)
                        source: Qt.resolvedUrl("icons/edit.svg")
                        isMask: true
                        color: Kirigami.Theme.textColor
                    }

                    MouseArea {
                        id: editMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            fullRep.powerMenuOpen = false;
                            fullRep.activeSubView = "";
                            fullRep.isEditingTiles = true;
                        }
                    }
                }

                // Settings gear button
                Rectangle {
                    Layout.preferredWidth: fullRep.snap(29.6)  // 37px fizycznych
                    Layout.preferredHeight: fullRep.snap(29.6) // 37px fizycznych
                    radius: fullRep.snap(8)
                    Layout.alignment: Qt.AlignVCenter
                    color: settingsMouse.pressed ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.18)
                                                 : (settingsMouse.containsMouse ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.1) : "transparent")

                    Kirigami.Icon {
                        anchors.centerIn: parent
                        width: fullRep.snap(15.2)  // 19px fizycznych
                        height: fullRep.snap(15.2) // 19px fizycznych
                        source: Qt.resolvedUrl("icons/settings.svg")
                        isMask: true
                        color: Kirigami.Theme.textColor
                    }

                    MouseArea {
                        id: settingsMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            KCMUtils.KCMLauncher.openSystemSettings("");
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                // Power button: Power icon + Chevron
                Rectangle {
                    id: powerButton
                    Layout.preferredHeight: fullRep.snap(29.6) // 37px fizycznych
                    Layout.preferredWidth: pwrRow.implicitWidth + fullRep.snap(16.0)
                    radius: Math.round(height / 2)
                    Layout.alignment: Qt.AlignVCenter

                    readonly property color activeContentColor: Kirigami.Theme.highlightedTextColor

                    color: fullRep.powerMenuOpen
                           ? fullRep.effectiveAccentColor
                           : (pwrMouse.pressed ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.18)
                              : (pwrMouse.containsMouse ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.1) : "transparent"))

                    Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }

                    Row {
                        id: pwrRow
                        anchors.centerIn: parent
                        spacing: fullRep.snap(4.0)

                        Kirigami.Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            width: fullRep.snap(17.28)  // canvas 21.6px -> rysowana ścieżka zasilania ma dokładnie 18px fizycznych
                            height: fullRep.snap(17.28) // 21.6px fizycznych (17.28 dp)
                            implicitWidth: width
                            implicitHeight: height
                            source: Qt.resolvedUrl("icons/power_btn.svg")
                            isMask: true
                            color: fullRep.powerMenuOpen ? powerButton.activeContentColor : Kirigami.Theme.textColor
                            Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }
                        }

                        Kirigami.Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            width: fullRep.snap(20.48)  // canvas 25.6px -> rysowana strzałka (chevron) ma dokładnie 7px fizycznych
                            height: fullRep.snap(20.48) // 25.6px fizycznych (20.48 dp)
                            implicitWidth: width
                            implicitHeight: height
                            source: Qt.resolvedUrl(fullRep.powerMenuOpen ? "icons/chevron_up.svg" : "icons/chevron_down.svg")
                            isMask: true
                            color: fullRep.powerMenuOpen ? powerButton.activeContentColor : Kirigami.Theme.textColor
                            Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }
                        }
                    }

                    MouseArea {
                        id: pwrMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            fullRep.powerMenuOpen = !fullRep.powerMenuOpen;
                        }
                    }
                }
            }

            // 2. Sliders Section
            ColumnLayout {
                id: slidersCol
                Layout.fillWidth: true
                spacing: fullRep.snap(10.4) // zwiększone o 2px fizyczne (+1.6 dp) dla idealnego odstępu między suwakami (10.4 dp = 13px fizycznych)
                Layout.bottomMargin: fullRep.snap(21.6) - fullRep.snap(3.6) - mainCol.spacing // dokładnie 27px fizycznych od toru suwaka do kafelków

                // Row 1: Brightness Slider + Moon Button
                RowLayout {
                    id: brightnessRow
                    readonly property real enter: fullRep.reveal(0.06)
                    opacity: enter
                    transform: Translate { y: (1 - brightnessRow.enter) * fullRep.snap(14) }
                    Layout.fillWidth: true
                    spacing: fullRep.snap(9.6) // 12px fizycznych

                    // Slider 1: Brightness
                    Item {
                        id: slider1Item
                        Layout.fillWidth: true
                        Layout.preferredHeight: handleHeight // 36dp (45px fizycznych)
                        clip: false

                        property real value: 0.5
                        property bool isDragging: sliderMouse.pressed

                        readonly property real trackHeight: fullRep.snap(28.8) // 36px fizycznych
                        readonly property real handleWidth: fullRep.snap(2.4)  // 3px fizycznych
                        readonly property real handleHeight: fullRep.snap(36.0) // 45px fizycznych
                        readonly property real gapSize: fullRep.snap(5.6)       // 7px fizycznych
                        readonly property real clampedValue: Math.max(0.01, Math.min(1.0, value))
                        readonly property real handleX: width > handleWidth ? fullRep.snap(clampedValue * (width - handleWidth)) : 0

                        function syncFromSystem() {
                            if (isDragging) return;
                            if (displaysInstantiator.count > 0) {
                                var d = displaysInstantiator.objectAt(0);
                                if (d && d.bMax > 0) {
                                    slider1Item.value = Math.max(0.01, Math.min(1.0, d.bVal / d.bMax));
                                }
                            }
                        }

                        function applyBrightness(ratio) {
                            var clamped = Math.max(0.01, Math.min(1.0, ratio));
                            slider1Item.value = clamped;
                            if (displaysInstantiator.count > 0) {
                                for (var i = 0; i < displaysInstantiator.count; i++) {
                                    var d = displaysInstantiator.objectAt(i);
                                    if (d && d.dName) {
                                        var targetVal = Math.round(Math.max(1, Math.min(d.bMax, clamped * d.bMax)));
                                        screenBrightnessControl.setBrightness(d.dName, targetVal);
                                    }
                                }
                            }
                        }

                        Component.onCompleted: {
                            syncFromSystem();
                        }

                        // Left active fill
                        Rectangle {
                            id: fill1
                            x: 0
                            anchors.verticalCenter: parent.verticalCenter
                            height: slider1Item.trackHeight
                            width: Math.max(0, slider1Item.handleX - slider1Item.gapSize)
                            color: fullRep.effectiveAccentColor
                            visible: width > 0

                            topLeftRadius: fullRep.snap(11.2) // 14px fizycznych
                            bottomLeftRadius: fullRep.snap(11.2) // 14px fizycznych
                            topRightRadius: width < height ? (width / 2) : fullRep.snap(2)
                            bottomRightRadius: width < height ? (width / 2) : fullRep.snap(2)
                        }


                        // Vertical floating handle: grubość 3px (2.4 dp)
                        Rectangle {
                            id: handle1
                            x: slider1Item.handleX
                            anchors.verticalCenter: parent.verticalCenter
                            width: slider1Item.handleWidth
                            height: slider1Item.handleHeight
                            radius: width / 2
                            color: fullRep.effectiveAccentColor
                            z: 2
                        }

                        // Right inactive track
                        Rectangle {
                            id: rightTrack1
                            x: slider1Item.handleX + slider1Item.handleWidth + slider1Item.gapSize
                            anchors.verticalCenter: parent.verticalCenter
                            height: slider1Item.trackHeight
                            width: Math.max(0, parent.width - x)
                            color: fullRep.oneUiTrackBg
                            visible: width > 0

                            topLeftRadius: width < height ? (width / 2) : fullRep.snap(2)
                            bottomLeftRadius: width < height ? (width / 2) : fullRep.snap(2)
                            topRightRadius: fullRep.snap(11.2) // 14px fizycznych
                            bottomRightRadius: fullRep.snap(11.2) // 14px fizycznych
                        }

                        // Interactive MouseArea across full slider width
                        MouseArea {
                            id: sliderMouse
                            anchors.fill: parent
                            hoverEnabled: true

                            onPositionChanged: (mouse) => {
                                if (pressed) {
                                    slider1Item.applyBrightness(mouse.x / width);
                                }
                            }
                            onPressed: (mouse) => {
                                slider1Item.applyBrightness(mouse.x / width);
                            }
                            onWheel: (wheel) => {
                                var step = wheel.angleDelta.y > 0 ? 0.05 : -0.05;
                                slider1Item.applyBrightness(slider1Item.value + step);
                            }
                        }

                        // Sun / gear icon: transitions onto the active bar when crossing 0.85
                        Item {
                            id: icon1Container
                            anchors.verticalCenter: parent.verticalCenter
                            height: slider1Item.trackHeight
                            width: slider1Item.trackHeight
                            z: 3

                            readonly property bool isOnBar: slider1Item.clampedValue > 0.85
                            readonly property real normalX: slider1Item.width - width
                            readonly property real onBarX: Math.max(0, fill1.width - width - 2)

                            x: isOnBar ? onBarX : normalX

                            Behavior on x {
                                NumberAnimation {
                                    duration: slider1Item.isDragging ? 0 : Kirigami.Units.shortDuration
                                    easing.type: Easing.OutCubic
                                }
                            }

                            Kirigami.Icon {
                                id: icon1
                                anchors.centerIn: parent
                                width: fullRep.snap(17.6)  // zmniejszone z 26 (22px fizyczne / 17.6 dp)
                                height: fullRep.snap(17.6)
                                source: Qt.resolvedUrl("icons/sun.svg")
                                isMask: true
                                color: icon1Container.isOnBar
                                       ? Kirigami.Theme.highlightedTextColor
                                       : Kirigami.Theme.textColor
                                Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }
                            }
                        }
                    }

                    // Button: Moon / Night light
                    Rectangle {
                        id: moonButton
                        Layout.preferredWidth: fullRep.snap(28.8) // 36px fizycznych
                        Layout.preferredHeight: fullRep.snap(28.8) // 36px fizycznych
                        radius: Math.round(height / 2)

                        readonly property bool isNightLightOn: fullRep.isNightLightOn

                        readonly property color activeContentColor: fullRep.onTertiaryColor

                        color: isNightLightOn ? fullRep.tertiaryColor : fullRep.oneUiTrackBg

                        Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }

                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            color: moonButton.isNightLightOn ? moonButton.activeContentColor : Kirigami.Theme.textColor
                            opacity: moonMouse.pressed ? 0.20 : (moonMouse.containsMouse ? 0.08 : 0)
                        }

                        Kirigami.Icon {
                            anchors.centerIn: parent
                            width: fullRep.snap(14.4)  // 18px fizycznych (zbalansowany margines)
                            height: fullRep.snap(14.4) // 18px fizycznych
                            source: Qt.resolvedUrl("icons/moon.svg")
                            isMask: true
                            color: moonButton.isNightLightOn ? moonButton.activeContentColor : Kirigami.Theme.textColor
                            Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }
                        }

                        MouseArea {
                            id: moonMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                fullRep.toggleNightLight();
                            }
                        }
                    }
                }

                // Row 2: Volume Slider + Equalizer Button
                RowLayout {
                    id: volumeRow
                    readonly property real enter: fullRep.reveal(0.10)
                    opacity: enter
                    transform: Translate { y: (1 - volumeRow.enter) * fullRep.snap(14) }
                    Layout.fillWidth: true
                    spacing: fullRep.snap(9.6) // 12px fizycznych

                    // Slider 2: Volume
                    Item {
                        id: slider2Item
                        Layout.fillWidth: true
                        Layout.preferredHeight: handleHeight // 36dp (45px fizycznych)
                        clip: false

                        property real value: 0.70
                        property bool isDragging: slider2Mouse.pressed

                        readonly property real trackHeight: fullRep.snap(28.8) // 36px fizycznych
                        readonly property real handleWidth: fullRep.snap(2.4)  // 3px fizycznych
                        readonly property real handleHeight: fullRep.snap(36.0) // 45px fizycznych
                        readonly property real gapSize: fullRep.snap(5.6)       // 7px fizycznych
                        readonly property real clampedValue: Math.max(0.0, Math.min(1.0, value))
                        readonly property real handleX: width > handleWidth ? fullRep.snap(clampedValue * (width - handleWidth)) : 0

                        function syncFromSystem() {
                            if (isDragging) return;
                            var sink = fullRep.activeSink;
                            if (sink) {
                                slider2Item.value = Math.max(0.0, Math.min(1.0, sink.volume / 65536.0));
                            }
                        }

                        function applyVolume(ratio) {
                            var clamped = Math.max(0.0, Math.min(1.0, ratio));
                            slider2Item.value = clamped;
                            var sink = fullRep.activeSink;
                            if (sink) {
                                if (sink.muted && clamped > 0.0) {
                                    sink.muted = false;
                                }
                                var targetVal = Math.round(clamped * 65536);
                                sink.volume = targetVal;
                            }
                        }

                        function toggleMute() {
                            var sink = fullRep.activeSink;
                            if (sink) {
                                sink.muted = !sink.muted;
                            }
                        }

                        Component.onCompleted: {
                            syncFromSystem();
                        }

                        // Left active fill
                        Rectangle {
                            id: fill2
                            x: 0
                            anchors.verticalCenter: parent.verticalCenter
                            height: slider2Item.trackHeight
                            width: Math.max(0, slider2Item.handleX - slider2Item.gapSize)
                            color: fullRep.effectiveAccentColor
                            visible: width > 0
                            opacity: (fullRep.activeSink && fullRep.activeSink.muted) ? 0.45 : 1.0
                            Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }

                            topLeftRadius: fullRep.snap(11.2) // 14px fizycznych
                            bottomLeftRadius: fullRep.snap(11.2) // 14px fizycznych
                            topRightRadius: width < height ? (width / 2) : fullRep.snap(2)
                            bottomRightRadius: width < height ? (width / 2) : fullRep.snap(2)
                        }

                        // Vertical floating handle (protrudes symmetrically)
                        Rectangle {
                            id: handle2
                            x: slider2Item.handleX
                            anchors.verticalCenter: parent.verticalCenter
                            width: slider2Item.handleWidth
                            height: slider2Item.handleHeight
                            radius: width / 2
                            color: fullRep.effectiveAccentColor
                            opacity: (fullRep.activeSink && fullRep.activeSink.muted) ? 0.45 : 1.0
                            Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }
                            z: 2
                        }

                        // Right inactive track
                        Rectangle {
                            id: rightTrack2
                            x: slider2Item.handleX + slider2Item.handleWidth + slider2Item.gapSize
                            anchors.verticalCenter: parent.verticalCenter
                            height: slider2Item.trackHeight
                            width: Math.max(0, parent.width - x)
                            color: fullRep.oneUiTrackBg
                            visible: width > 0

                            topLeftRadius: width < height ? (width / 2) : fullRep.snap(2)
                            bottomLeftRadius: width < height ? (width / 2) : fullRep.snap(2)
                            topRightRadius: fullRep.snap(11.2) // 14px fizycznych
                            bottomRightRadius: fullRep.snap(11.2) // 14px fizycznych
                        }

                        // MouseArea for dragging & clicking
                        MouseArea {
                            id: slider2Mouse
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton

                            onPositionChanged: (mouse) => {
                                if (pressed && (mouse.buttons & Qt.LeftButton)) {
                                    slider2Item.applyVolume(mouse.x / width);
                                }
                            }
                            onPressed: (mouse) => {
                                if (mouse.button === Qt.LeftButton) {
                                    slider2Item.applyVolume(mouse.x / width);
                                } else if (mouse.button === Qt.MiddleButton) {
                                    slider2Item.toggleMute();
                                }
                            }
                            onWheel: (wheel) => {
                                var step = wheel.angleDelta.y > 0 ? 0.05 : -0.05;
                                slider2Item.applyVolume(slider2Item.value + step);
                            }
                        }

                        // Musical note icon: transitions onto the active bar when crossing 0.85
                        Item {
                            id: icon2Container
                            anchors.verticalCenter: parent.verticalCenter
                            height: slider2Item.trackHeight
                            width: slider2Item.trackHeight
                            z: 3

                            readonly property bool isOnBar: slider2Item.clampedValue > 0.85
                            readonly property real normalX: slider2Item.width - width
                            readonly property real onBarX: Math.max(0, fill2.width - width - 2)

                            x: isOnBar ? onBarX : normalX

                            Behavior on x {
                                NumberAnimation {
                                    duration: slider2Item.isDragging ? 0 : Kirigami.Units.shortDuration
                                    easing.type: Easing.OutCubic
                                }
                            }

                            Kirigami.Icon {
                                id: musicNoteIcon
                                anchors.centerIn: parent
                                width: fullRep.snap(17.6)  // zmniejszone z 26 (22px fizyczne / 17.6 dp)
                                height: fullRep.snap(17.6)
                                source: Qt.resolvedUrl("icons/music_note.svg")
                                isMask: true
                                color: icon2Container.isOnBar
                                       ? Kirigami.Theme.highlightedTextColor
                                       : Kirigami.Theme.textColor
                                opacity: (fullRep.activeSink && fullRep.activeSink.muted) ? 0.45 : 1.0
                                Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }
                                Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }
                            }

                            MouseArea {
                                id: noteMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton
                                onClicked: {
                                    slider2Item.toggleMute();
                                }
                            }
                        }
                    }

                    // Button: Equalizer / Sound settings
                    Rectangle {
                        id: eqButton
                        Layout.preferredWidth: fullRep.snap(28.8) // 36px fizycznych
                        Layout.preferredHeight: fullRep.snap(28.8) // 36px fizycznych
                        radius: Math.round(height / 2)

                        color: fullRep.oneUiTrackBg

                        Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }

                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            color: Kirigami.Theme.textColor
                            opacity: eqMouse.pressed ? 0.20 : (eqMouse.containsMouse ? 0.08 : 0)
                        }

                        Kirigami.Icon {
                            anchors.centerIn: parent
                            width: fullRep.snap(14.4)  // 18px fizycznych (zbalansowany margines)
                            height: fullRep.snap(14.4) // 18px fizycznych
                            source: Qt.resolvedUrl("icons/equalizer.svg")
                            isMask: true
                            color: Kirigami.Theme.textColor
                        }

                        MouseArea {
                            id: eqMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                fullRep.powerMenuOpen = false;
                                fullRep.activeSubView = "audio";
                            }
                        }
                    }
                }

                // Row 3: Power profile bar (discrete 3-stop slider) + Power & battery button
                RowLayout {
                    id: powerRow
                    visible: fullRep.powerProfiles.length > 1
                    readonly property real enter: fullRep.reveal(0.14)
                    opacity: enter
                    transform: Translate { y: (1 - powerRow.enter) * fullRep.snap(14) }
                    Layout.fillWidth: true
                    spacing: fullRep.snap(9.6)

                    Item {
                        id: powerBar
                        Layout.fillWidth: true
                        Layout.preferredHeight: handleHeight

                        readonly property real trackHeight: fullRep.snap(28.8)
                        readonly property real handleWidth: fullRep.snap(2.4)
                        readonly property real handleHeight: fullRep.snap(36.0)
                        readonly property real gapSize: fullRep.snap(5.6)
                        readonly property int steps: Math.max(1, fullRep.powerProfiles.length)
                        readonly property int activeIndex: Math.max(0, fullRep.powerProfiles.indexOf(fullRep.currentPowerProfile))
                        property int previewIndex: -1 // while pressing / dragging
                        readonly property int shownIndex: previewIndex >= 0 ? previewIndex : activeIndex
                        readonly property string shownProfile: fullRep.powerProfiles.length > 0 ? fullRep.powerProfiles[shownIndex] : ""

                        // One stop per profile: saver = start, balanced = middle, performance = end.
                        // A small minimum pill keeps the profile icon readable at the first stop.
                        readonly property real minFill: fullRep.snap(36)
                        readonly property real range: Math.max(1, width - handleWidth - minFill)
                        property real animatedValue: steps > 1 ? shownIndex / (steps - 1) : 1
                        Behavior on animatedValue {
                            NumberAnimation {
                                duration: fullRep.animationsEnabled ? 420 : 0
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: [0.2, 0.0, 0.0, 1.0, 1.0, 1.0] // M3 emphasized
                            }
                        }
                        readonly property real handleX: width > handleWidth ? fullRep.snap(minFill + animatedValue * range) : 0
                        function stopX(i) { return minFill + (steps > 1 ? i / (steps - 1) : 1) * range; }

                        // Nearest stop to the pointer
                        function indexAt(px) {
                            if (steps <= 1) return 0;
                            return Math.max(0, Math.min(steps - 1, Math.round(((px - minFill) / range) * (steps - 1))));
                        }

                        Rectangle {
                            id: fill3
                            x: 0
                            anchors.verticalCenter: parent.verticalCenter
                            height: powerBar.trackHeight
                            width: Math.max(0, powerBar.handleX - powerBar.gapSize)
                            color: fullRep.effectiveAccentColor
                            visible: width > 0
                            topLeftRadius: fullRep.snap(11.2)
                            bottomLeftRadius: fullRep.snap(11.2)
                            topRightRadius: width < height ? (width / 2) : fullRep.snap(2)
                            bottomRightRadius: width < height ? (width / 2) : fullRep.snap(2)
                        }

                        Rectangle {
                            x: powerBar.handleX
                            anchors.verticalCenter: parent.verticalCenter
                            width: powerBar.handleWidth
                            height: powerBar.handleHeight
                            radius: width / 2
                            color: fullRep.effectiveAccentColor
                            z: 2
                            scale: powerMouse.pressed ? 1.12 : 1.0
                            Behavior on scale { NumberAnimation { duration: Kirigami.Units.shortDuration; easing.type: Easing.OutCubic } }
                        }

                        Rectangle {
                            id: rightTrack3
                            x: powerBar.handleX + powerBar.handleWidth + powerBar.gapSize
                            anchors.verticalCenter: parent.verticalCenter
                            height: powerBar.trackHeight
                            width: Math.max(0, parent.width - x)
                            color: fullRep.oneUiTrackBg
                            visible: width > 0
                            topLeftRadius: width < height ? (width / 2) : fullRep.snap(2)
                            bottomLeftRadius: width < height ? (width / 2) : fullRep.snap(2)
                            topRightRadius: fullRep.snap(11.2)
                            bottomRightRadius: fullRep.snap(11.2)
                        }

                        // M3 discrete-slider stop indicators on the inactive track
                        Repeater {
                            model: powerBar.steps
                            Rectangle {
                                required property int index
                                readonly property real stopX: Math.min(powerBar.stopX(index) + powerBar.handleWidth / 2, powerBar.width - fullRep.snap(7))
                                visible: stopX > powerBar.handleX + powerBar.gapSize * 2 && stopX < powerBar.width - profileLabel.implicitWidth - fullRep.snap(18)
                                x: fullRep.snap(stopX - width / 2)
                                anchors.verticalCenter: parent.verticalCenter
                                width: fullRep.snap(4)
                                height: width
                                radius: width / 2
                                color: Kirigami.Theme.textColor
                                opacity: 0.45
                                z: 3
                            }
                        }

                        // Profile icon sits at the start of the active fill
                        Kirigami.Icon {
                            id: profileIcon
                            anchors.verticalCenter: parent.verticalCenter
                            x: fullRep.snap(8.8)
                            width: fullRep.snap(17.6)
                            height: width
                            z: 4
                            source: fullRep.powerProfileIcon(powerBar.shownProfile)
                            isMask: true
                            color: fill3.width > x + width ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                            Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }
                        }

                        // Profile name, right-aligned; switches to on-accent colour when the fill reaches it
                        PlasmaComponents3.Label {
                            id: profileLabel
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.right: parent.right
                            anchors.rightMargin: fullRep.snap(11.2)
                            z: 4
                            text: fullRep.powerProfileTitle(powerBar.shownProfile)
                            font.family: "Google Sans Flex"
                            font.pixelSize: fullRep.snap(10.4)
                            font.weight: Font.Medium
                            readonly property bool onFill: (powerBar.width - anchors.rightMargin - implicitWidth) < fill3.width
                            color: onFill ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                            Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }
                        }

                        MouseArea {
                            id: powerMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onPressed: (mouse) => {
                                powerBar.previewIndex = powerBar.indexAt(mouse.x);
                            }
                            onPositionChanged: (mouse) => {
                                if (pressed) {
                                    powerBar.previewIndex = powerBar.indexAt(mouse.x);
                                }
                            }
                            onReleased: (mouse) => {
                                var idx = powerBar.indexAt(mouse.x);
                                powerBar.previewIndex = -1;
                                fullRep.setPowerProfile(fullRep.powerProfiles[idx]);
                            }
                            onCanceled: {
                                powerBar.previewIndex = -1;
                            }
                            // Wheel previews instantly but commits once scrolling settles:
                            // on Bazzite every profile switch re-tunes the whole system (tuned).
                            onWheel: (wheel) => {
                                var dir = wheel.angleDelta.y > 0 ? 1 : -1;
                                var base = powerBar.previewIndex >= 0 ? powerBar.previewIndex : powerBar.activeIndex;
                                powerBar.previewIndex = Math.max(0, Math.min(powerBar.steps - 1, base + dir));
                                wheelCommit.restart();
                            }
                        }

                        Timer {
                            id: wheelCommit
                            interval: 450
                            onTriggered: {
                                if (powerBar.previewIndex >= 0) {
                                    var idx = powerBar.previewIndex;
                                    powerBar.previewIndex = -1;
                                    fullRep.setPowerProfile(fullRep.powerProfiles[idx]);
                                }
                            }
                        }
                    }

                    // Button: block sleep ("Stay awake" / caffeine), M3 toggle icon button
                    Rectangle {
                        id: stayAwakeButton
                        Layout.preferredWidth: fullRep.snap(28.8)
                        Layout.preferredHeight: fullRep.snap(28.8)
                        radius: fullRep.caffeineActive ? fullRep.snap(9.6) : Math.round(height / 2)
                        color: fullRep.caffeineActive ? fullRep.tertiaryColor : fullRep.oneUiTrackBg
                        Behavior on radius { NumberAnimation { duration: 350; easing.type: Easing.OutQuart } }
                        Behavior on color { ColorAnimation { duration: 250 } }
                        scale: stayAwakeMouse.pressed ? 0.9 : 1.0
                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutQuart } }

                        PlasmaComponents3.ToolTip.text: fullRep.caffeineActive ? i18n("Sleep blocked") : i18n("Block sleep")
                        PlasmaComponents3.ToolTip.visible: stayAwakeMouse.containsMouse
                        PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay

                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            color: fullRep.caffeineActive ? fullRep.onTertiaryColor : Kirigami.Theme.textColor
                            opacity: stayAwakeMouse.pressed ? 0.20 : (stayAwakeMouse.containsMouse ? 0.08 : 0)
                        }

                        Kirigami.Icon {
                            anchors.centerIn: parent
                            width: fullRep.snap(14.4)
                            height: fullRep.snap(14.4)
                            source: Qt.resolvedUrl("icons/coffee.svg")
                            isMask: true
                            color: fullRep.caffeineActive ? fullRep.onTertiaryColor : Kirigami.Theme.textColor
                        }

                        MouseArea {
                            id: stayAwakeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: fullRep.toggleCaffeine()
                        }
                    }

                    // Button: Power & battery details
                    Rectangle {
                        id: energyButton
                        Layout.preferredWidth: fullRep.snap(28.8)
                        Layout.preferredHeight: fullRep.snap(28.8)
                        radius: Math.round(height / 2)
                        color: fullRep.oneUiTrackBg

                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            color: Kirigami.Theme.textColor
                            opacity: energyMouse.pressed ? 0.20 : (energyMouse.containsMouse ? 0.08 : 0)
                        }

                        Kirigami.Icon {
                            anchors.centerIn: parent
                            width: fullRep.snap(14.4)
                            height: fullRep.snap(14.4)
                            source: Qt.resolvedUrl("icons/bolt.svg")
                            isMask: true
                            color: Kirigami.Theme.textColor
                        }

                        MouseArea {
                            id: energyMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                fullRep.powerMenuOpen = false;
                                fullRep.activeSubView = "power";
                            }
                        }
                    }
                }
            }

            // 3. Grid of Quick Setting Tiles (4-Segment Grid)
            GridLayout {
                id: tilesGrid
                Layout.fillWidth: true
                columns: 4
                rowSpacing: fullRep.snap(7.2)    // 9px fizycznych
                columnSpacing: fullRep.snap(7.2) // 9px fizycznych

                // Reusable Marquee Label with edge fade overlays and smooth hover scrolling (pattern from MediaPill)
                component MarqueeText: Item {
                    id: mRoot
                    property string text: ""
                    property color color: Kirigami.Theme.textColor
                    property color fadeColor: tile.color
                    property real fontPixelSize: fullRep.snap(10.4)
                    property int fontWeight: Font.Normal
                    property real textOpacity: 1.0
                    property bool isHovered: false

                    Layout.fillWidth: true
                    implicitHeight: Math.ceil(scrollLabel.implicitHeight)

                    readonly property real overflow: Math.max(0, measureText.advanceWidth - width)
                    readonly property bool needsScroll: overflow > 2

                    // PERF: lightweight text measurement (was a hidden Label per text)
                    TextMetrics {
                        id: measureText
                        text: mRoot.text
                        font.family: "Google Sans Flex"
                        font.pixelSize: mRoot.fontPixelSize
                        font.weight: mRoot.fontWeight
                    }

                    // Clipped text container
                    Item {
                        id: textContainer
                        anchors.fill: parent
                        clip: true

                        PlasmaComponents3.Label {
                            id: scrollLabel
                            x: 0
                            anchors.verticalCenter: parent.verticalCenter
                            text: mRoot.text
                            font.family: "Google Sans Flex"
                            font.pixelSize: mRoot.fontPixelSize
                            font.weight: mRoot.fontWeight
                            color: mRoot.color
                            opacity: mRoot.textOpacity
                            elide: Text.ElideNone

                            SequentialAnimation on x {
                                id: scrollAnim
                                running: mRoot.isHovered && mRoot.needsScroll
                                loops: Animation.Infinite

                                PauseAnimation { duration: 600 }
                                NumberAnimation {
                                    to: -mRoot.overflow - 6
                                    duration: Math.max(1600, mRoot.overflow * 32)
                                    easing.type: Easing.Linear
                                }
                                PauseAnimation { duration: 1500 }
                                NumberAnimation {
                                    to: 0
                                    duration: Kirigami.Units.longDuration * 2
                                    easing.type: Easing.InOutQuad
                                }
                                PauseAnimation { duration: 600 }
                            }

                            Connections {
                                target: mRoot
                                function onIsHoveredChanged() {
                                    if (!mRoot.isHovered) {
                                        returnAnim.restart();
                                    }
                                }
                            }

                            NumberAnimation {
                                id: returnAnim
                                target: scrollLabel
                                property: "x"
                                to: 0
                                duration: 250
                                easing.type: Easing.OutQuad
                            }
                        }
                    }

                    // Left fade overlay (visible when text is scrolled to the left)
                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: fullRep.snap(12.0)
                        z: 5
                        opacity: (scrollLabel.x < -1.0) ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }

                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: mRoot.fadeColor }
                            GradientStop { position: 1.0; color: Qt.rgba(mRoot.fadeColor.r, mRoot.fadeColor.g, mRoot.fadeColor.b, 0.0) }
                        }
                    }

                    // Right fade overlay (visible when text overflows the right boundary)
                    Rectangle {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: fullRep.snap(16.0)
                        z: 5
                        opacity: mRoot.needsScroll ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }

                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: Qt.rgba(mRoot.fadeColor.r, mRoot.fadeColor.g, mRoot.fadeColor.b, 0.0) }
                            GradientStop { position: 1.0; color: mRoot.fadeColor }
                        }
                    }
                }

                // Reusable Quick Tile component
                component QuickTile: Rectangle {
                    id: tile
                    property string tileId: ""
                    property string title: ""
                    property string subtitle: ""
                    property string iconSource: ""
                    property bool hasCircleBadge: false
                    property bool isActive: false
                    property bool iconIsMask: true
                    property var clickHandler: null
                    property var iconClickHandler: null
                    property int revealIndex: 0

                    // Staggered "pop" entrance (M3 expressive): fade + scale from 86 %
                    readonly property real enter: fullRep.reveal(0.16 + revealIndex * 0.03)
                    opacity: enter
                    scale: 0.86 + 0.14 * enter

                    readonly property int span: fullRep.getTileSpan(tileId)
                    readonly property bool isCompact: span === 1

                    Layout.fillWidth: false
                    Layout.columnSpan: span
                    Layout.preferredWidth: isCompact ? fullRep.snap(72.0) : fullRep.snap(151.2)
                    Layout.preferredHeight: fullRep.snap(50.4) // 63px fizycznych
                    radius: isActive ? fullRep.snap(16) : Math.round(height / 2)
                    Behavior on radius { NumberAnimation { duration: Kirigami.Units.shortDuration; easing.type: Easing.OutCubic } }

                    color: isCompact
                           ? (isActive ? fullRep.effectiveAccentColor : fullRep.oneUiTrackBg)
                           : ((hasCircleBadge || !isActive) ? fullRep.oneUiTrackBg : fullRep.effectiveAccentColor)

                    Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }

                    // Content color for tile labels
                    readonly property color contentColor: isCompact
                                                          ? (isActive ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor)
                                                          : ((!hasCircleBadge && isActive)
                                                             ? Kirigami.Theme.highlightedTextColor
                                                             : Kirigami.Theme.textColor)

                    // Contrast color for active icon badge
                    readonly property color activeBadgeContentColor: tile.hasCircleBadge ? fullRep.onTertiaryColor : Kirigami.Theme.highlightedTextColor

                    property bool isBadgeHovered: false
                    property bool isBodyHovered: false
                    property bool isPressed: false
                    property bool isBadgePressed: false

                    // M3 ripple from the click point, masked to the tile shape — layers exist only while it runs
                    function playRipple(px, py) { ripple.cx = px; ripple.cy = py; rippleAnim.restart(); }
                    Rectangle { id: rippleMask; anchors.fill: parent; radius: tile.radius; visible: false; layer.enabled: rippleAnim.running }
                    Item {
                        anchors.fill: parent
                        visible: rippleAnim.running
                        layer.enabled: rippleAnim.running
                        layer.effect: MultiEffect { maskEnabled: true; maskSource: rippleMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
                        Rectangle {
                            id: ripple
                            property real cx: 0
                            property real cy: 0
                            property real r: 0
                            x: cx - r; y: cy - r; width: 2 * r; height: 2 * r; radius: r
                            color: tile.contentColor
                            opacity: 0
                        }
                    }
                    ParallelAnimation {
                        id: rippleAnim
                        NumberAnimation { target: ripple; property: "r"; from: 0; to: Math.sqrt(tile.width * tile.width + tile.height * tile.height); duration: 450; easing.type: Easing.OutCubic }
                        NumberAnimation { target: ripple; property: "opacity"; from: 0.24; to: 0; duration: 560; easing.type: Easing.InQuad }
                    }

                    function isInBadge(mx, my) {
                        if (tile.isCompact || !tile.hasCircleBadge) return false;
                        var pos = badgeContainer.mapToItem(tile, 0, 0);
                        var cx = pos.x + badgeContainer.width / 2;
                        var cy = pos.y + badgeContainer.height / 2;
                        var r = (badgeContainer.width / 2) + 2;
                        var dx = mx - cx;
                        var dy = my - cy;
                        return (dx * dx + dy * dy) <= (r * r);
                    }

                    // Compact icon (centered for 1-span tile)
                    Kirigami.Icon {
                        visible: tile.isCompact
                        anchors.centerIn: parent
                        width: fullRep.snap(20.8)
                        height: width
                        source: tile.iconSource
                        color: tile.contentColor
                        isMask: tile.iconIsMask
                        Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }
                    }

                    RowLayout {
                        id: tileRow
                        visible: !tile.isCompact
                        anchors.fill: parent
                        anchors.leftMargin: tile.hasCircleBadge ? fullRep.snap(5.6) : fullRep.snap(9.6)
                        anchors.rightMargin: fullRep.snap(5.6)
                        anchors.topMargin: fullRep.snap(5.6)
                        anchors.bottomMargin: fullRep.snap(5.6)
                        spacing: fullRep.snap(9.6)

                        // Icon badge / container: 50x50px (40x40 dp) dla wifi i bluetooth
                        Rectangle {
                            id: badgeContainer
                            Layout.alignment: Qt.AlignVCenter
                            Layout.preferredWidth: tile.hasCircleBadge ? fullRep.snap(40.0) : fullRep.snap(28.8)
                            Layout.preferredHeight: tile.hasCircleBadge ? fullRep.snap(40.0) : fullRep.snap(28.8)
                            radius: tile.hasCircleBadge
                                    ? (tile.isActive ? fullRep.snap(12.0) : Math.round(height / 2))
                                    : fullRep.snap(12.0)
                            Behavior on radius { NumberAnimation { duration: Kirigami.Units.shortDuration; easing.type: Easing.OutCubic } }

                            color: tile.hasCircleBadge
                                   ? (tile.isActive
                                      ? fullRep.tertiaryColor
                                      : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12))
                                   : "transparent"

                            Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }

                            Kirigami.Icon {
                                anchors.centerIn: parent
                                width: tile.hasCircleBadge ? fullRep.snap(20.8) : fullRep.snap(19.2)
                                height: width
                                source: tile.iconSource
                                color: (tile.hasCircleBadge && tile.isActive)
                                       ? tile.activeBadgeContentColor
                                       : tile.contentColor
                                isMask: tile.iconIsMask
                                Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }
                            }

                            // Hover / Press feedback on badge
                            Rectangle {
                                anchors.fill: parent
                                radius: parent.radius
                                color: (tile.hasCircleBadge && tile.isActive)
                                       ? tile.activeBadgeContentColor
                                       : tile.contentColor
                                opacity: tile.isBadgePressed ? 0.28 : (tile.isBadgeHovered ? 0.14 : 0)
                                visible: tile.hasCircleBadge
                            }
                        }

                        // Label Column
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 1

                            MarqueeText {
                                text: tile.title
                                fontWeight: Font.Medium
                                fontPixelSize: fullRep.snap(12.4)
                                color: tile.contentColor
                                isHovered: tile.isBodyHovered || tile.isBadgeHovered
                            }

                            MarqueeText {
                                visible: tile.subtitle.length > 0
                                text: tile.subtitle
                                fontWeight: Font.Normal
                                fontPixelSize: fullRep.snap(9.6)
                                color: (!tile.hasCircleBadge && tile.isActive) ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.disabledTextColor
                                textOpacity: (!tile.hasCircleBadge && tile.isActive) ? 0.85 : 1.0
                                isHovered: tile.isBodyHovered || tile.isBadgeHovered
                            }
                        }
                    }

                    // Hover / Press feedback on tile body
                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        color: tile.contentColor
                        opacity: (tile.isPressed && !tile.isBadgePressed) ? 0.20 : (tile.isBodyHovered ? 0.08 : 0)
                    }

                    MouseArea {
                        id: tileMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onPositionChanged: (mouse) => {
                            var inBadge = tile.isInBadge(mouse.x, mouse.y);
                            tile.isBadgeHovered = inBadge;
                            tile.isBodyHovered = !inBadge;
                        }

                        onEntered: {
                            tile.isBodyHovered = true;
                        }

                        onExited: {
                            tile.isBadgeHovered = false;
                            tile.isBodyHovered = false;
                            tile.isPressed = false;
                            tile.isBadgePressed = false;
                        }

                        onPressed: (mouse) => {
                            var inBadge = tile.isInBadge(mouse.x, mouse.y);
                            tile.isBadgePressed = inBadge;
                            tile.isPressed = true;
                        }

                        onReleased: {
                            tile.isPressed = false;
                            tile.isBadgePressed = false;
                        }

                        onPressAndHold: {
                            if (tile.isCompact) {
                                if (tile.clickHandler) tile.clickHandler();
                            }
                        }

                        onClicked: (mouse) => {
                            // Right-click: jump straight into "Edit tiles" with this tile selected
                            if (mouse.button === Qt.RightButton) {
                                fullRep.openTileEditor(tile.tileId);
                                return;
                            }
                            tile.playRipple(mouse.x, mouse.y);
                            fullRep.playClick();
                            if (tile.isCompact) {
                                if (tile.tileId === "wifi" || tile.tileId === "bluetooth") {
                                    if (tile.iconClickHandler) {
                                        tile.iconClickHandler();
                                    } else if (tile.clickHandler) {
                                        tile.clickHandler();
                                    }
                                } else {
                                    if (tile.clickHandler) {
                                        tile.clickHandler();
                                    } else {
                                        tile.isActive = !tile.isActive;
                                    }
                                }
                                return;
                            }
                            var inBadge = tile.isInBadge(mouse.x, mouse.y);
                            if (inBadge) {
                                if (tile.iconClickHandler) {
                                    tile.iconClickHandler();
                                } else {
                                    tile.isActive = !tile.isActive;
                                }
                            } else {
                                if (tile.clickHandler) {
                                    tile.clickHandler();
                                } else {
                                    tile.isActive = !tile.isActive;
                                }
                            }
                        }
                    }
                }

                Repeater {
                    model: fullRep.activeTiles

                    QuickTile {
                        required property string modelData
                        required property int index

                        tileId: modelData
                        revealIndex: index
                        title: fullRep.getTileTitle(modelData)
                        subtitle: fullRep.getTileSubtitle(modelData)
                        iconSource: fullRep.getTileIcon(modelData)
                        iconIsMask: fullRep.tileIconIsMask(modelData)
                        hasCircleBadge: fullRep.tileHasCircleBadge(modelData)
                        isActive: fullRep.isTileActive(modelData)

                        iconClickHandler: function() {
                            fullRep.executeTileIconAction(modelData);
                        }
                        clickHandler: function() {
                            fullRep.executeTileAction(modelData);
                        }
                    }
                }

                // "+" tile: add tiles live, straight from the drawer
                Rectangle {
                    id: addTileButton
                    readonly property real enter: fullRep.reveal(0.16 + fullRep.activeTiles.length * 0.03)
                    opacity: enter
                    scale: 0.86 + 0.14 * enter
                    Layout.columnSpan: 1
                    Layout.fillWidth: false
                    Layout.preferredWidth: fullRep.snap(72.0)
                    Layout.preferredHeight: fullRep.snap(50.4)
                    // M3 shape morph: pill -> rounded square on hover/press
                    radius: addMouse.pressed ? fullRep.snap(10) : (addMouse.containsMouse ? fullRep.snap(16) : Math.round(height / 2))
                    Behavior on radius { NumberAnimation { duration: 400; easing.type: Easing.OutQuart } }
                    color: "transparent"
                    border.width: fullRep.snap(1.2)
                    border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, addMouse.containsMouse ? 0.45 : 0.22)
                    Behavior on border.color { ColorAnimation { duration: 300 } }

                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        color: Kirigami.Theme.textColor
                        opacity: addMouse.pressed ? 0.16 : (addMouse.containsMouse ? 0.06 : 0)
                    }

                    Kirigami.Icon {
                        anchors.centerIn: parent
                        width: fullRep.snap(20.8)
                        height: width
                        source: Qt.resolvedUrl("icons/add.svg")
                        isMask: true
                        color: Kirigami.Theme.textColor
                        opacity: 0.85
                        rotation: addMouse.containsMouse ? 90 : 0
                        Behavior on rotation { NumberAnimation { duration: 500; easing.type: Easing.OutQuart } }
                    }

                    MouseArea {
                        id: addMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: fullRep.openTileEditor("")
                    }
                }
            }
        }

        // PERF: sub-views are created on demand and destroyed when closed. They used to be
        // instantiated (with their NetworkManager / BlueZ models) as soon as the top bar loaded.
        // Entering view uses the M3 "shared axis X" transition (fade + slide from the right).
        component SubViewLoader: Loader {
            id: svl
            // Inside the loaded component, "fullRep" resolves to the view's own (null) property,
            // so views receive the drawer through this alias instead.
            readonly property var qs: fullRep
            property real enterT: 1.0
            readonly property real enterEased: fullRep.m3ease(enterT)
            anchors.fill: parent
            anchors.leftMargin: fullRep.snap(14.4)   // 18px fizycznych
            anchors.rightMargin: fullRep.snap(14.4)  // 18px fizycznych
            anchors.topMargin: fullRep.snap(14.4)    // 18px fizycznych
            anchors.bottomMargin: fullRep.snap(28.8) // 36px fizycznych
            visible: active
            opacity: Math.min(1, svl.enterT * 1.6)
            transform: Translate { x: (1 - svl.enterEased) * fullRep.snap(56) }
            onLoaded: {
                if (fullRep.animationsEnabled && fullRep.popupShown) {
                    svl.enterT = 0;
                    svlAnim.restart();
                }
            }
            NumberAnimation {
                id: svlAnim
                target: svl
                property: "enterT"
                from: 0
                to: 1
                duration: 560
            }
        }

        // Edit Tiles & Layout Mode
        SubViewLoader {
            id: editTilesLoader
            active: fullRep.isEditingTiles
            sourceComponent: Component {
                EditTilesView {
                    fullRep: editTilesLoader.qs
                    onCloseRequested: {
                        editTilesLoader.qs.isEditingTiles = false;
                    }
                }
            }
        }

        // Wi-Fi Details & Basic Settings View
        SubViewLoader {
            id: wifiLoader
            active: !fullRep.isEditingTiles && fullRep.activeSubView === "wifi"
            sourceComponent: Component {
                WifiDetailsView {
                    fullRep: wifiLoader.qs
                    onCloseRequested: {
                        wifiLoader.qs.activeSubView = "";
                    }
                }
            }
        }

        // Bluetooth Details & Basic Settings View
        SubViewLoader {
            id: bluetoothLoader
            active: !fullRep.isEditingTiles && fullRep.activeSubView === "bluetooth"
            sourceComponent: Component {
                BluetoothDetailsView {
                    fullRep: bluetoothLoader.qs
                    onCloseRequested: {
                        bluetoothLoader.qs.activeSubView = "";
                    }
                }
            }
        }

        // Power Details & Basic Settings View
        SubViewLoader {
            id: powerLoader
            active: !fullRep.isEditingTiles && fullRep.activeSubView === "power"
            sourceComponent: Component {
                PowerDetailsView {
                    appletRoot: powerLoader.qs.appletRoot
                    fullRep: powerLoader.qs
                    onCloseRequested: {
                        powerLoader.qs.activeSubView = "";
                    }
                }
            }
        }

        // Per-app volume
        SubViewLoader {
            id: audioLoader
            active: !fullRep.isEditingTiles && fullRep.activeSubView === "audio"
            sourceComponent: Component {
                AudioMixerView {
                    onCloseRequested: audioLoader.qs.activeSubView = ""
                }
            }
        }

        // Display (scale / refresh rate)
        SubViewLoader {
            id: displayLoader
            active: !fullRep.isEditingTiles && fullRep.activeSubView === "display"
            sourceComponent: Component {
                DisplayView { onCloseRequested: displayLoader.qs.activeSubView = "" }
            }
        }

        // Do not disturb (durations + schedule)
        SubViewLoader {
            id: dndLoader
            active: !fullRep.isEditingTiles && fullRep.activeSubView === "dnd"
            sourceComponent: Component {
                DndView {
                    applet: dndLoader.qs.appletRoot
                    tertiary: dndLoader.qs.tertiaryColor
                    onTertiary: dndLoader.qs.onTertiaryColor
                    onCloseRequested: dndLoader.qs.activeSubView = ""
                }
            }
        }

        // Removable storage
        SubViewLoader {
            id: storageLoader
            active: !fullRep.isEditingTiles && fullRep.activeSubView === "storage"
            sourceComponent: Component {
                StorageView {
                    onCloseRequested: storageLoader.qs.activeSubView = ""
                    onOpened: storageLoader.qs.closePopup()
                }
            }
        }

        // Clipboard history
        SubViewLoader {
            id: clipboardLoader
            active: !fullRep.isEditingTiles && fullRep.activeSubView === "clipboard"
            sourceComponent: Component {
                ClipboardView {
                    onCloseRequested: clipboardLoader.qs.activeSubView = ""
                    onPasted: { clipboardLoader.qs.activeSubView = ""; clipboardLoader.qs.closePopup(); }
                }
            }
        }

        // Click blocker to close power menu when clicking outside
        MouseArea {
            id: powerMenuDismissOverlay
            anchors.fill: parent
            z: 99
            visible: fullRep.powerMenuOpen && !fullRep.isEditingTiles && fullRep.activeSubView === ""
            hoverEnabled: true
            onClicked: {
                fullRep.powerMenuOpen = false;
            }
        }

        // 4. Floating Power Dropdown Menu
        Rectangle {
            id: powerMenuCard
            z: 100
            visible: fullRep.powerMenuOpen && !fullRep.isEditingTiles && fullRep.activeSubView === ""
            anchors.top: parent.top
            anchors.topMargin: mainCol.y + headerRow.y + powerButton.y + powerButton.height + fullRep.snap(6.4)
            anchors.right: parent.right
            anchors.rightMargin: fullRep.snap(14.4) // 18px fizycznych (wyrównany z prawym marginesem szuflady)
            width: fullRep.snap(156.0)  // dokładnie 195px fizycznych
            height: fullRep.snap(120.0) // dokładnie 150px fizycznych
            radius: 16
            color: fullRep.isSystemDark ? "#23252d" : "#ffffff"
            border.width: 1
            border.color: fullRep.isSystemDark ? Qt.rgba(255, 255, 255, 0.08) : Qt.rgba(0, 0, 0, 0.12)

            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowHorizontalOffset: 0
                shadowVerticalOffset: 6
                shadowBlur: 0.5
                shadowColor: fullRep.isSystemDark ? Qt.rgba(0, 0, 0, 0.32) : Qt.rgba(0, 0, 0, 0.16)
            }

            ColumnLayout {
                id: menuCol
                anchors.fill: parent
                anchors.margins: fullRep.snap(6.4)
                spacing: fullRep.snap(4.0)

                component PowerMenuItem: Rectangle {
                    id: menuItem
                    property string title: ""
                    property string iconName: ""
                    signal triggered()

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 10
                    color: itemMouse.pressed ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
                                             : (itemMouse.containsMouse ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08) : "transparent")

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: fullRep.snap(9.6)
                        anchors.rightMargin: fullRep.snap(9.6)
                        spacing: fullRep.snap(9.6)

                        Kirigami.Icon {
                            Layout.preferredWidth: fullRep.snap(17.6)
                            Layout.preferredHeight: fullRep.snap(17.6)
                            source: menuItem.iconName
                            isMask: true
                            color: Kirigami.Theme.textColor
                        }

                        PlasmaComponents3.Label {
                            Layout.fillWidth: true
                            text: menuItem.title
                            font.family: "Google Sans Flex"
                            font.pixelSize: fullRep.snap(10.4)
                            font.weight: Font.Normal
                            color: Kirigami.Theme.textColor
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        id: itemMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            fullRep.powerMenuOpen = false;
                            menuItem.triggered();
                        }
                    }
                }

                PowerMenuItem {
                    title: i18n("Sign out")
                    iconName: Qt.resolvedUrl("icons/logout.svg")
                    onTriggered: {
                        fullRep.requestLogout();
                    }
                }

                PowerMenuItem {
                    title: i18n("Restart")
                    iconName: Qt.resolvedUrl("icons/restart.svg")
                    onTriggered: {
                        fullRep.requestReboot();
                    }
                }

                PowerMenuItem {
                    title: i18n("Power off")
                    iconName: Qt.resolvedUrl("icons/power_btn.svg")
                    onTriggered: {
                        fullRep.requestShutdown();
                    }
                }
            }
        }
    }
}

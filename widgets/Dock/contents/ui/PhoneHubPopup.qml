/*
 * SPDX-FileCopyrightText: 2024-2026 Maciej Kujawiński <maciek.kujawinski@gmail.com>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import QtCore
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtQuick.Dialogs as QtDialogs
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kdeconnect as KDEConnect
import "i18n.js" as I18n
import "motion.js" as Motion

// Phone Hub (ChromeOS / Android desktop style) on top of KDE Connect:
//  - header with device, battery, mobile signal, reachability and device switcher
//  - user-editable action tiles (remove "–", add "+", drag to reorder), saved in
//    Plasmoid configuration key "phoneHubTiles"
//  - phone notifications with dismiss & quick reply
//  - Material 3 staggered entrance motion, colours follow the Plasma scheme
PlasmaCore.Dialog {
    id: root

    function i18n(k, a1, a2) { return I18n.t(k, a1, a2); }

    property Item visualParentItem: null
    property var plasmoidConfiguration: null

    objectName: "phoneHubPopup"
    flags: Qt.WindowStaysOnTopHint

    visualParent: null
    location: (typeof Plasmoid !== "undefined" && Plasmoid.location !== undefined) ? Plasmoid.location : PlasmaCore.Types.BottomEdge
    floating: 16
    hideOnWindowDeactivate: true
    backgroundHints: PlasmaCore.Types.StandardBackground

    property int popupWidth: 420
    property int maxPopupHeight: 620
    readonly property int contentMargin: 20
    readonly property int popupHeight: Math.min(maxPopupHeight, Math.ceil(contentCol.implicitHeight + contentMargin * 2))
    property real panelHeight: 52

    width: popupWidth
    height: popupHeight

    // ───────────────────────── State ─────────────────────────
    property bool editMode: false
    property bool pickerOpen: false
    property bool isRinging: false
    property string flashTileId: ""

    // ── Motion state (Material 3 expressive) ──
    property real modeT: 1.0          // edit mode on/off transition driver
    property real pickerT: 1.0        // device picker transition driver
    property string lastAddedTile: ""
    property real addT: 1.0
    property string removingTile: ""
    property real removeT: 0.0
    function ease4(x) { x = Math.max(0, Math.min(1, x)); return 1 - Math.pow(1 - x, 4); }
    function modeEnter(delay) { return ease4((modeT - delay) / 0.5); }
    function pickerEnter(delay) { return ease4((pickerT - delay) / 0.45); }
    // tiles shrink slightly while editing (Android QS edit mode), animated both ways
    readonly property real editShrink: editMode ? 0.04 * modeEnter(0) : 0.04 * (1 - modeEnter(0))
    onEditModeChanged: { if (visible) modeAnim.restart(); }
    onPickerOpenChanged: { if (pickerOpen) pickerAnim.restart(); }

    property var devices: []          // objects from deviceInst
    property string deviceId: ""
    readonly property var currentDevice: {
        for (var i = 0; i < devices.length; ++i)
            if (devices[i].devId === deviceId) return devices[i];
        return null;
    }
    readonly property bool hasDevice: currentDevice !== null
    readonly property bool reachable: hasDevice && currentDevice.reachable
    readonly property string deviceName: hasDevice ? currentDevice.devName : i18n("No connected phone")
    readonly property var backend: backendInst.object

    // ── Phone media (KDE Connect "mprisremote") ──
    readonly property var mpris: backend ? backend.mpris : null
    readonly property bool hasMedia: reachable && mpris !== null && String(mpris.title || "").length > 0
    function mediaAction(action) {
        if (mpris) mpris.sendAction(action);
    }

    // ── Recent photos (KDE Connect "sftp", opt-in) ──
    readonly property bool photosEnabled: plasmoidConfiguration ? Boolean(plasmoidConfiguration.phoneHubPhotos) : false
    readonly property bool photosAvailable: reachable && backend !== null && backend.sftpChk.available
    property var photos: []
    property bool photosLoading: false
    property string photosError: ""
    property real photosT: 1.0
    readonly property string photoHelper: decodeURIComponent(String(Qt.resolvedUrl("../code/phonephotos.py")).replace("file://", ""))
    function shq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'"; }
    function refreshPhotos() {
        if (!photosEnabled || !photosAvailable || photosLoading) return;
        photosLoading = true;
        photosError = "";
        photoQuery.connectSource("python3 " + shq(photoHelper) + " list " + shq(deviceId) + " 4 # photos-" + Date.now());
    }
    function enablePhotos() {
        if (plasmoidConfiguration) plasmoidConfiguration.phoneHubPhotos = true;
        Qt.callLater(refreshPhotos);
    }
    function openPhoto(path) {
        executor.exec("python3 " + shq(photoHelper) + " save-open " + shq(path));
        close();
    }
    onPhotosAvailableChanged: { if (photosAvailable && visible) refreshPhotos(); }
    onDeviceIdChanged: photos = []

    // ───────────────────────── Tiles ─────────────────────────
    readonly property var tileCatalog: [
        { id: "ring",            title: "Ring",            icon: "mobile_ring", plugin: "findmyphone" },
        { id: "files",           title: "Files",           icon: "files",       plugin: "sftp" },
        { id: "send_file",       title: "Send file",       icon: "send_to",     plugin: "share" },
        { id: "clipboard",       title: "Send clipboard",  icon: "clipboard",   plugin: "clipboard" },
        { id: "sms",             title: "Messages",        icon: "sms",         plugin: "sms" },
        { id: "virtual_display", title: "Virtual display", icon: "cast",        plugin: "virtualmonitor" },
        { id: "app",             title: "KDE Connect",     icon: "phone_hub",   plugin: "" }
    ]

    property var tileIds: []

    function catalogEntry(id) {
        for (var i = 0; i < tileCatalog.length; ++i)
            if (tileCatalog[i].id === id) return tileCatalog[i];
        return null;
    }

    function loadTiles() {
        var raw = plasmoidConfiguration ? String(plasmoidConfiguration.phoneHubTiles || "") : "ring,files,send_file,clipboard";
        var out = [];
        raw.split(",").forEach(function (s) {
            s = s.trim();
            if (s && catalogEntry(s) && out.indexOf(s) < 0) out.push(s);
        });
        tileIds = out;
        syncTileModel();
    }

    function syncTileModel() {
        if (typeof tileModel === "undefined" || !tileModel) return;
        tileModel.clear();
        for (var i = 0; i < tileIds.length; ++i) tileModel.append({ tileId: tileIds[i] });
    }

    function saveTiles(list) {
        tileIds = list;
        if (plasmoidConfiguration) {
            plasmoidConfiguration.phoneHubTiles = list.join(",");
            if (typeof plasmoidConfiguration.writeConfig === "function") plasmoidConfiguration.writeConfig();
        }
    }

    // Remove: the tile shrinks/fades out first, then the others glide into place.
    function removeTile(id) {
        if (removingTile !== "") return;
        removingTile = id;
        removeT = 0;
        removeAnim.restart();
    }

    function finishRemove() {
        var id = removingTile;
        var i = tileIds.indexOf(id);
        removingTile = "";
        if (i < 0) return;
        tileModel.remove(i);
        saveTiles(tileIds.filter(function (t) { return t !== id; }));
    }

    // Add: the new tile grows in at the end of the grid.
    function addTile(id) {
        if (tileIds.indexOf(id) >= 0) return;
        var l = tileIds.slice();
        l.push(id);
        lastAddedTile = id;
        addT = 0;
        saveTiles(l);
        tileModel.append({ tileId: id });
        addAnim.restart();
    }

    function moveTile(from, to) {
        if (from === to || from < 0 || to < 0 || from >= tileIds.length || to >= tileIds.length) return;
        var l = tileIds.slice();
        var it = l.splice(from, 1)[0];
        l.splice(to, 0, it);
        tileModel.move(from, to, 1);
        saveTiles(l);
    }

    readonly property var addableTiles: tileCatalog.filter(function (t) { return tileIds.indexOf(t.id) < 0; })

    function pluginAvailable(plugin) {
        if (!plugin) return true;
        var b = backend;
        if (!b || !reachable) return false;
        switch (plugin) {
        case "findmyphone":    return b.findMyPhoneChk.available;
        case "sftp":           return b.sftpChk.available;
        case "share":          return b.shareChk.available;
        case "clipboard":      return b.clipboardChk.available;
        case "sms":            return b.smsChk.available;
        case "virtualmonitor": return b.virtualMonitorChk.available;
        }
        return false;
    }

    function tileTitle(id) {
        if (id === "ring" && isRinging) return i18n("Ringing…");
        var e = catalogEntry(id);
        return e ? i18n(e.title) : id;
    }

    function tileSubtitle(id) {
        if (flashTileId === id) return i18n("Sent");
        if (id === "virtual_display" && pluginAvailable("virtualmonitor"))
            return tileActive(id) ? i18n("On") : i18n("Off");
        return "";
    }

    function tileActive(id) {
        if (id === "ring") return isRinging;
        if (id === "virtual_display") return Boolean(backend && backend.virtualMonitor && backend.virtualMonitor.active);
        return flashTileId === id;
    }

    function safeId() { return deviceId.replace(/[^A-Za-z0-9_\-]/g, ""); }

    function runTile(id) {
        var b = backend;
        switch (id) {
        case "ring":
            if (b && b.findMyPhone) b.findMyPhone.ring();
            isRinging = true;
            ringTimer.restart();
            break;
        case "files":
            if (b && b.sftp) b.sftp.startBrowsing();
            close();
            break;
        case "send_file":
            fileDialog.targetShare = b ? b.share : null;
            fileDialog.open();
            close();
            break;
        case "clipboard":
            if (b && b.clipboard) {
                b.clipboard.sendClipboard();
                flash(id);
            }
            break;
        case "sms":
            if (b && b.sms) b.sms.launchApp();
            else executor.exec("kdeconnect-sms --device '" + safeId() + "'");
            close();
            break;
        case "virtual_display":
            if (b && b.virtualMonitor) {
                if (b.virtualMonitor.active) b.virtualMonitor.stop();
                else b.virtualMonitor.requestVirtualMonitor();
            }
            break;
        case "app":
            openApp();
            break;
        }
    }

    function openApp() {
        executor.exec(deviceId ? "kdeconnect-app --device '" + safeId() + "'" : "kdeconnect-app");
        close();
    }

    function flash(id) {
        flashTileId = id;
        flashTimer.restart();
    }

    // ───────────────────────── Devices ─────────────────────────
    function rebuildDevices() {
        var arr = [];
        for (var i = 0; i < deviceInst.count; ++i) {
            var o = deviceInst.objectAt(i);
            if (o && o.devId) arr.push(o);
        }
        devices = arr;
        pickDevice();
    }

    // Saved choice first, then first reachable phone, then anything reachable, then first paired.
    function pickDevice() {
        var pref = plasmoidConfiguration ? String(plasmoidConfiguration.phoneHubDevice || "") : "";
        var chosen = "";
        var i;
        for (i = 0; i < devices.length && !chosen; ++i)
            if (pref && devices[i].devId === pref) chosen = pref;
        for (i = 0; i < devices.length && !chosen; ++i)
            if (devices[i].reachable && (devices[i].devType === "phone" || devices[i].devType === "tablet")) chosen = devices[i].devId;
        for (i = 0; i < devices.length && !chosen; ++i)
            if (devices[i].reachable) chosen = devices[i].devId;
        for (i = 0; i < devices.length && !chosen; ++i)
            if (devices[i].devType === "phone") chosen = devices[i].devId;
        if (!chosen && devices.length > 0) chosen = devices[0].devId;
        if (deviceId !== chosen) deviceId = chosen;
    }

    function selectDevice(id) {
        if (plasmoidConfiguration) {
            plasmoidConfiguration.phoneHubDevice = id;
            if (typeof plasmoidConfiguration.writeConfig === "function") plasmoidConfiguration.writeConfig();
        }
        deviceId = id;
        pickerOpen = false;
    }

    function deviceIcon(type) {
        if (type === "desktop") return "computer-symbolic";
        if (type === "laptop") return "computer-laptop-symbolic";
        if (type === "tablet") return "tablet-symbolic";
        if (type === "tv") return "video-television-symbolic";
        return Qt.resolvedUrl("icons/phone_hub.svg");
    }

    readonly property string statusText: {
        if (!hasDevice) return "";
        if (!reachable) return i18n("Not reachable");
        var parts = [i18n("Connected")];
        var b = backend;
        if (b && b.battery && b.battery.charge > -1) {
            var s = i18n("%1%", b.battery.charge);
            if (b.battery.isCharging) s += " · " + i18n("Charging");
            parts.push(s);
        }
        if (b && b.connectivity && b.connectivity.cellularNetworkType)
            parts.push(b.connectivity.cellularNetworkType);
        return parts.join(" · ");
    }

    // ───────────────────────── Motion ─────────────────────────
    // Opening: sections and tile rows rise into place one after the other on M3 Expressive
    // springs (motion.js) — opacity on the effects spring, position on the default spatial one.
    // `delay` keeps the old timeline units (fraction of 400 ms).
    property real revealMs: 100000
    NumberAnimation on revealMs {
        id: revealAnim; running: false; from: 0; to: 800
        duration: Kirigami.Units.longDuration > 1 ? 800 * Motion.speed(Kirigami.Units.longDuration) : 0
    }
    function enterAt(delay) { return Motion.effects(revealMs - 30 - delay * 400); }
    function enterMove(delay) { return Motion.defaultSpatial(revealMs - delay * 400); }

    // ───────────────────────── Popup plumbing ─────────────────────────
    function updatePosition() {
        var scr = (visualParentItem && visualParentItem.Screen) ? visualParentItem.Screen : Screen;
        var scrWidth = scr.width;
        var scrHeight = scr.height;
        var scrX = (scr.virtualX !== undefined) ? scr.virtualX : 0;
        var scrY = (scr.virtualY !== undefined) ? scr.virtualY : 0;

        var effPanelHeight = root.panelHeight;
        if (visualParentItem && visualParentItem.Window && visualParentItem.Window.window && visualParentItem.Window.window.height > 0) {
            effPanelHeight = visualParentItem.Window.window.height;
        }

        var bottomGap = 16;
        var currentW = root.width > 0 ? root.width : popupWidth;
        var currentH = root.height > 0 ? root.height : popupHeight;
        var panelTop = scrY + scrHeight - effPanelHeight;
        var targetY = Math.max(24, Math.round(panelTop - currentH - bottomGap));

        var targetX = scrX + Math.round((scrWidth - currentW) / 2);
        if (visualParentItem) {
            var btnCenterX = 0;
            if (typeof visualParentItem.mapToGlobal === "function") {
                try {
                    var gPt = visualParentItem.mapToGlobal(visualParentItem.width / 2, 0);
                    if (gPt && gPt.x !== undefined && gPt.x > 0) btnCenterX = gPt.x;
                } catch (e) {}
            }
            if (btnCenterX === 0 && typeof visualParentItem.mapToItem === "function") {
                try {
                    var lPt = visualParentItem.mapToItem(null, visualParentItem.width / 2, 0);
                    var winX = (visualParentItem.Window && visualParentItem.Window.window) ? visualParentItem.Window.window.x : 0;
                    btnCenterX = winX + lPt.x;
                } catch (e2) {}
            }
            if (btnCenterX > 0) targetX = Math.round(btnCenterX - currentW / 2);
        }

        targetX = Math.max(scrX + 16, Math.min(scrX + scrWidth - currentW - 16, targetX));
        if (root.x !== targetX) root.x = targetX;
        if (root.y !== targetY) root.y = targetY;
    }

    function toggle() {
        if (root.visible) close(); else open();
    }

    function open() {
        pickDevice();
        updatePosition();
        root.visible = true;
        updatePosition();
        root.requestActivate();
    }

    function close() {
        root.visible = false;
    }

    onVisibleChanged: {
        if (visible) {
            updatePosition();
            revealMs = Kirigami.Units.longDuration > 1 ? 0 : 100000;
            revealAnim.restart();
            refreshPhotos();
            if (mpris) {
                try { mpris.requestPlayerList(); } catch (e) {}
            }
        } else {
            editMode = false;
            pickerOpen = false;
        }
    }
    onWidthChanged: { if (visible) updatePosition(); }
    onHeightChanged: { if (visible) updatePosition(); }

    onPlasmoidConfigurationChanged: { loadTiles(); pickDevice(); }
    Component.onCompleted: loadTiles()

    mainItem: Item {
        id: container
        implicitWidth: root.popupWidth
        implicitHeight: root.popupHeight
        width: root.popupWidth
        height: root.popupHeight

        readonly property color fg: Kirigami.Theme.textColor
        readonly property color accent: Kirigami.Theme.highlightColor
        function tint(a) { return Qt.rgba(fg.r, fg.g, fg.b, a); }
        function accentA(a) { return Qt.rgba(accent.r, accent.g, accent.b, a); }

        Connections {
            target: root.plasmoidConfiguration
            ignoreUnknownSignals: true
            function onPhoneHubTilesChanged() {
                var cur = root.tileIds.join(",");
                if (String(root.plasmoidConfiguration.phoneHubTiles || "") !== cur) root.loadTiles();
            }
        }

        ListModel { id: tileModel }

        NumberAnimation { id: modeAnim; target: root; property: "modeT"; from: 0; to: 1; duration: Kirigami.Units.longDuration > 1 ? 620 : 0 }
        NumberAnimation { id: pickerAnim; target: root; property: "pickerT"; from: 0; to: 1; duration: Kirigami.Units.longDuration > 1 ? 560 : 0 }
        NumberAnimation { id: addAnim; target: root; property: "addT"; from: 0; to: 1; duration: Kirigami.Units.longDuration > 1 ? 520 : 0 }
        NumberAnimation {
            id: removeAnim; target: root; property: "removeT"; from: 0; to: 1; duration: Kirigami.Units.longDuration > 1 ? 280 : 0
            onFinished: root.finishRemove()
        }

        Timer { id: ringTimer; interval: 8000; onTriggered: root.isRinging = false }
        Timer { id: flashTimer; interval: 1800; onTriggered: root.flashTileId = "" }

        Plasma5Support.DataSource {
            id: executor
            engine: "executable"
            connectedSources: []
            onNewData: (sourceName, data) => disconnectSource(sourceName)
            function exec(cmd) {
                var fullCmd = "nohup sh -c " + JSON.stringify(cmd) + " </dev/null >/dev/null 2>&1 & # " + Date.now();
                connectSource(fullCmd);
            }
        }

        Plasma5Support.DataSource {
            id: photoQuery
            engine: "executable"
            connectedSources: []
            onNewData: (sourceName, data) => {
                disconnectSource(sourceName);
                root.photosLoading = false;
                try {
                    var res = JSON.parse(data["stdout"] || "{}");
                    if (res.ok) {
                        var thumbs = function (list) { return list.map(function (p) { return p.thumb; }).join("|"); };
                        if (thumbs(res.photos) !== thumbs(root.photos)) {
                            root.photos = res.photos;
                            photosAnim.restart();
                        }
                    } else {
                        root.photosError = res.error || "error";
                    }
                } catch (e) {
                    root.photosError = String(data["stderr"] || e);
                }
            }
        }
        NumberAnimation { id: photosAnim; target: root; property: "photosT"; from: 0; to: 1; duration: Kirigami.Units.longDuration > 1 ? 720 : 0 }

        // All paired devices (reachable or not) — reachability tracked live per device.
        Instantiator {
            id: deviceInst
            model: KDEConnect.DevicesModel {
                displayFilter: KDEConnect.DevicesModel.Paired
            }
            delegate: QtObject {
                readonly property string devId: model.deviceId || ""
                readonly property QtObject iface: devId ? KDEConnect.DeviceDbusInterfaceFactory.create(devId) : null
                readonly property string devName: iface && iface.name ? iface.name : (model.name || devId)
                readonly property string devType: iface ? String(iface.type || "") : ""
                readonly property bool reachable: iface ? Boolean(iface.isReachable) : false
                onReachableChanged: root.pickDevice()
            }
            onObjectAdded: (index, object) => root.rebuildDevices()
            onObjectRemoved: (index, object) => root.rebuildDevices()
        }

        // Plugin interfaces for the selected device; recreated when the device changes.
        Instantiator {
            id: backendInst
            model: root.deviceId !== "" ? [root.deviceId] : []
            delegate: QtObject {
                id: bk
                required property string modelData
                readonly property KDEConnect.DeviceDbusInterface device: KDEConnect.DeviceDbusInterfaceFactory.create(bk.modelData)

                readonly property KDEConnect.PluginChecker batteryChk: KDEConnect.PluginChecker { pluginName: "battery"; device: bk.device }
                readonly property KDEConnect.PluginChecker connectivityChk: KDEConnect.PluginChecker { pluginName: "connectivity_report"; device: bk.device }
                readonly property KDEConnect.PluginChecker findMyPhoneChk: KDEConnect.PluginChecker { pluginName: "findmyphone"; device: bk.device }
                readonly property KDEConnect.PluginChecker sftpChk: KDEConnect.PluginChecker { pluginName: "sftp"; device: bk.device }
                readonly property KDEConnect.PluginChecker shareChk: KDEConnect.PluginChecker { pluginName: "share"; device: bk.device }
                readonly property KDEConnect.PluginChecker clipboardChk: KDEConnect.PluginChecker { pluginName: "clipboard"; device: bk.device }
                readonly property KDEConnect.PluginChecker smsChk: KDEConnect.PluginChecker { pluginName: "sms"; device: bk.device }
                readonly property KDEConnect.PluginChecker virtualMonitorChk: KDEConnect.PluginChecker { pluginName: "virtualmonitor"; device: bk.device }
                readonly property KDEConnect.PluginChecker mprisChk: KDEConnect.PluginChecker { pluginName: "mprisremote"; device: bk.device }

                readonly property QtObject battery: batteryChk.available ? KDEConnect.DeviceBatteryDbusInterfaceFactory.create(bk.modelData) : null
                readonly property QtObject connectivity: connectivityChk.available ? KDEConnect.DeviceConnectivityReportDbusInterfaceFactory.create(bk.modelData) : null
                readonly property QtObject findMyPhone: findMyPhoneChk.available ? KDEConnect.FindMyPhoneDbusInterfaceFactory.create(bk.modelData) : null
                readonly property QtObject sftp: sftpChk.available ? KDEConnect.SftpDbusInterfaceFactory.create(bk.modelData) : null
                readonly property QtObject share: shareChk.available ? KDEConnect.ShareDbusInterfaceFactory.create(bk.modelData) : null
                readonly property QtObject clipboard: clipboardChk.available ? KDEConnect.ClipboardDbusInterfaceFactory.create(bk.modelData) : null
                readonly property QtObject sms: smsChk.available ? KDEConnect.SmsDbusInterfaceFactory.create(bk.modelData) : null
                readonly property QtObject virtualMonitor: virtualMonitorChk.available ? KDEConnect.VirtualmonitorDbusInterfaceFactory.create(bk.modelData) : null
                readonly property QtObject mpris: mprisChk.available ? KDEConnect.MprisDbusInterfaceFactory.create(bk.modelData) : null
            }
        }

        QtDialogs.FileDialog {
            id: fileDialog
            property QtObject targetShare: null
            title: root.i18n("Choose files to send")
            currentFolder: StandardPaths.standardLocations(StandardPaths.HomeLocation)[0]
            modality: Qt.NonModal
            fileMode: QtDialogs.FileDialog.OpenFiles
            onAccepted: {
                if (targetShare) {
                    targetShare.shareUrls(selectedFiles);
                    root.flash("send_file");
                }
            }
        }

        ColumnLayout {
            id: contentCol
            anchors.fill: parent
            anchors.margins: root.contentMargin
            spacing: 14

            // ── 1. Device header ──
            RowLayout {
                id: header
                Layout.fillWidth: true
                spacing: 12
                opacity: root.enterAt(0)
                transform: Translate { y: (1 - root.enterMove(0)) * 10 }

                Rectangle {
                    Layout.preferredWidth: 46
                    Layout.preferredHeight: 46
                    radius: 23
                    color: container.accentA(root.reachable ? 0.22 : 0.10)
                    Behavior on color { ColorAnimation { duration: Kirigami.Units.longDuration } }

                    Kirigami.Icon {
                        anchors.centerIn: parent
                        width: 22
                        height: 22
                        source: root.deviceIcon(root.hasDevice ? root.currentDevice.devType : "phone")
                        isMask: true
                        color: root.reachable ? container.accent : container.tint(0.6)
                    }

                    // reachability dot
                    Rectangle {
                        visible: root.hasDevice
                        width: 12
                        height: 12
                        radius: 6
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        color: root.reachable ? Kirigami.Theme.positiveTextColor : container.tint(0.35)
                        border.width: 2
                        border.color: Kirigami.Theme.backgroundColor
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        Layout.fillWidth: true
                        text: root.deviceName
                        font.family: "Google Sans Flex"
                        font.pixelSize: 17
                        font.weight: Font.DemiBold
                        color: container.fg
                        elide: Text.ElideRight
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        visible: root.statusText.length > 0

                        Kirigami.Icon {
                            Layout.preferredWidth: 14
                            Layout.preferredHeight: 14
                            visible: Boolean(root.backend && root.backend.battery && root.backend.battery.charge > -1)
                            source: (root.backend && root.backend.battery && root.backend.battery.iconName) ? root.backend.battery.iconName : "battery-good-symbolic"
                            isMask: true
                            color: container.tint(0.7)
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root.statusText
                            font.family: "Google Sans Flex"
                            font.pixelSize: 12
                            color: container.tint(0.7)
                            elide: Text.ElideRight
                        }

                        Kirigami.Icon {
                            Layout.preferredWidth: 14
                            Layout.preferredHeight: 14
                            visible: Boolean(root.reachable && root.backend && root.backend.connectivity && root.backend.connectivity.cellularNetworkType)
                            source: visible ? root.backend.connectivity.iconName : ""
                            isMask: true
                            color: container.tint(0.7)
                        }
                    }
                }

                HeaderButton {
                    visible: root.devices.length > 1 && !root.editMode
                    opacity: root.modeEnter(0.05)
                    iconSource: Qt.resolvedUrl("icons/swap.svg")
                    toggled: root.pickerOpen
                    tooltip: root.i18n("Switch device")
                    onClicked: root.pickerOpen = !root.pickerOpen
                }

                HeaderButton {
                    visible: !root.editMode && root.hasDevice
                    opacity: root.modeEnter(0.1)
                    iconSource: Qt.resolvedUrl("icons/settings.svg")
                    tooltip: root.i18n("Settings")
                    onClicked: root.openApp()
                }

                HeaderButton {
                    visible: !root.editMode
                    opacity: root.modeEnter(0.15)
                    iconSource: Qt.resolvedUrl("icons/edit.svg")
                    tooltip: root.i18n("Edit tiles")
                    onClicked: { root.pickerOpen = false; root.editMode = true; }
                }

                // "Done" filled pill in edit mode
                Rectangle {
                    visible: root.editMode
                    opacity: root.modeEnter(0.05)
                    scale: 0.7 + 0.3 * root.modeEnter(0.05)
                    Layout.preferredHeight: 36
                    Layout.preferredWidth: doneLabel.implicitWidth + 32
                    radius: 18
                    color: doneMa.pressed ? Qt.darker(container.accent, 1.1) : container.accent

                    Text {
                        id: doneLabel
                        anchors.centerIn: parent
                        text: root.i18n("Done")
                        font.family: "Google Sans Flex"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        color: Kirigami.Theme.highlightedTextColor
                    }

                    MouseArea {
                        id: doneMa
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.editMode = false
                    }
                }
            }

            // ── 1b. Device picker (inline, expands under the header) ──
            Flow {
                id: picker
                Layout.fillWidth: true
                spacing: 8
                visible: root.pickerOpen

                Repeater {
                    model: root.devices
                    delegate: Rectangle {
                        id: chip
                        required property var modelData
                        required property int index
                        readonly property bool selected: modelData.devId === root.deviceId
                        readonly property real e: root.pickerEnter(index * 0.08)
                        opacity: e
                        transform: Translate { y: (1 - chip.e) * -10 }
                        height: 36
                        width: chipRow.implicitWidth + 28
                        radius: selected ? 12 : 18
                        color: selected ? container.accentA(0.25) : (chipMa.containsMouse ? container.tint(0.10) : container.tint(0.05))
                        border.width: selected ? 0 : 1
                        border.color: container.tint(0.15)
                        Behavior on radius { NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }

                        RowLayout {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: 8

                            Rectangle {
                                width: 8
                                height: 8
                                radius: 4
                                color: modelData.reachable ? Kirigami.Theme.positiveTextColor : container.tint(0.35)
                            }

                            Text {
                                text: modelData.devName
                                font.family: "Google Sans Flex"
                                font.pixelSize: 12
                                font.weight: selected ? Font.DemiBold : Font.Normal
                                color: container.fg
                            }
                        }

                        MouseArea {
                            id: chipMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.selectDevice(modelData.devId)
                        }
                    }
                }
            }

            // ── 2. Tiles ──
            Text {
                id: dragHint
                Layout.fillWidth: true
                visible: root.editMode
                opacity: root.modeEnter(0)
                transform: Translate { y: (1 - root.modeEnter(0)) * -8 }
                text: root.i18n("Drag to reorder")
                font.family: "Google Sans Flex"
                font.pixelSize: 12
                color: container.tint(0.6)
            }

            Item {
                id: tilesArea
                Layout.fillWidth: true
                readonly property int tileH: 64
                readonly property int gap: 10
                readonly property int rows: Math.ceil(tileModel.count / 2)
                Layout.preferredHeight: rows > 0 ? rows * tileH + (rows - 1) * gap : 0
                visible: tileModel.count > 0

                property int dragFrom: -1
                property int dropTo: -1

                function slotX(i) { return (i % 2) * ((width - gap) / 2 + gap); }
                function slotY(i) { return Math.floor(i / 2) * (tileH + gap); }
                function indexAt(x, y) {
                    var col = x < width / 2 ? 0 : 1;
                    var row = Math.max(0, Math.min(rows - 1, Math.floor(y / (tileH + gap))));
                    return Math.max(0, Math.min(tileModel.count - 1, row * 2 + col));
                }

                Repeater {
                    model: tileModel
                    delegate: Item {
                        id: slot
                        required property string tileId
                        required property int index
                        readonly property bool dragging: tilesArea.dragFrom === index
                        // Visual position: while dragging, other tiles shift to preview the drop.
                        readonly property int visualIndex: {
                            var f = tilesArea.dragFrom, t = tilesArea.dropTo;
                            if (f < 0 || t < 0 || dragging) return index;
                            if (f < t && index > f && index <= t) return index - 1;
                            if (f > t && index >= t && index < f) return index + 1;
                            return index;
                        }
                        width: (tilesArea.width - tilesArea.gap) / 2
                        height: tilesArea.tileH
                        x: dragging ? dragX : tilesArea.slotX(visualIndex)
                        y: dragging ? dragY : tilesArea.slotY(visualIndex)
                        z: dragging ? 10 : 1
                        property real dragX: 0
                        property real dragY: 0
                        Behavior on x { enabled: !slot.dragging; NumberAnimation { duration: Kirigami.Units.longDuration > 1 ? 450 : 0; easing.type: Easing.OutQuart } }
                        Behavior on y { enabled: !slot.dragging; NumberAnimation { duration: Kirigami.Units.longDuration > 1 ? 450 : 0; easing.type: Easing.OutQuart } }

                        // Reorder handle (edit mode only); sits under the tile so the "–" badge stays clickable.
                        MouseArea {
                            anchors.fill: parent
                            enabled: root.editMode
                            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                            property point grab
                            onPressed: mouse => {
                                grab = Qt.point(mouse.x, mouse.y);
                                slot.dragX = slot.x;
                                slot.dragY = slot.y;
                                tilesArea.dragFrom = slot.index;
                                tilesArea.dropTo = slot.index;
                            }
                            onPositionChanged: mouse => {
                                if (tilesArea.dragFrom !== slot.index) return;
                                var p = mapToItem(tilesArea, mouse.x, mouse.y);
                                slot.dragX = p.x - grab.x;
                                slot.dragY = p.y - grab.y;
                                tilesArea.dropTo = tilesArea.indexAt(p.x, p.y);
                            }
                            onReleased: {
                                var f = tilesArea.dragFrom, t = tilesArea.dropTo;
                                tilesArea.dragFrom = -1;
                                tilesArea.dropTo = -1;
                                root.moveTile(f, t);
                            }
                            onCanceled: { tilesArea.dragFrom = -1; tilesArea.dropTo = -1; }
                        }

                        PhoneHubActionTile {
                            id: actionTile
                            anchors.fill: parent
                            title: root.tileTitle(slot.tileId)
                            subtitle: root.tileSubtitle(slot.tileId)
                            iconSource: Qt.resolvedUrl("icons/" + (root.catalogEntry(slot.tileId) ? root.catalogEntry(slot.tileId).icon : "info") + ".svg")
                            isActive: root.tileActive(slot.tileId)
                            activeColor: slot.tileId === "ring" ? Kirigami.Theme.negativeTextColor : container.accent
                            available: root.catalogEntry(slot.tileId) ? root.pluginAvailable(root.catalogEntry(slot.tileId).plugin) : false
                            editMode: root.editMode
                            // opening: the tiles rise with their row (no per-tile pop);
                            // adding / removing a tile keeps its scale in / out
                            readonly property bool addOrRemove: slot.tileId === root.removingTile || slot.tileId === root.lastAddedTile
                            readonly property real rowDelay: 0.08 + Math.floor(slot.index / 2) * 0.07
                            enter: slot.tileId === root.removingTile ? (1 - root.ease4(root.removeT))
                                 : (slot.tileId === root.lastAddedTile ? root.ease4(root.addT)
                                 : root.enterAt(rowDelay))
                            scale: slot.dragging ? 1.05 : (addOrRemove ? 0.6 + 0.4 * enter : 1) * (1 - root.editShrink)
                            transform: Translate { y: actionTile.addOrRemove ? 0 : (1 - root.enterMove(actionTile.rowDelay)) * 14 }
                            onClicked: root.runTile(slot.tileId)
                            onRemoveRequested: root.removeTile(slot.tileId)
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                visible: tileModel.count === 0 && !root.editMode
                text: root.i18n("No tiles yet — tap the pencil to add some.")
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                font.family: "Google Sans Flex"
                font.pixelSize: 12
                color: container.tint(0.55)
            }

            // ── 2b. Add tiles (edit mode) ──
            ColumnLayout {
                Layout.fillWidth: true
                visible: root.editMode
                spacing: 8
                opacity: root.modeEnter(0.1)
                transform: Translate { y: (1 - root.modeEnter(0.1)) * 16 }

                Text {
                    text: root.i18n("Add tiles")
                    font.family: "Google Sans Flex"
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    color: container.tint(0.75)
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 8
                    // chips glide when one leaves, and pop when one comes back
                    move: Transition { NumberAnimation { properties: "x,y"; duration: Kirigami.Units.longDuration > 1 ? 450 : 0; easing.type: Easing.OutQuart } }
                    add: Transition { NumberAnimation { property: "scale"; from: 0.5; to: 1; duration: Kirigami.Units.longDuration > 1 ? 450 : 0; easing.type: Easing.OutBack } }

                    Repeater {
                        model: root.tileCatalog
                        delegate: Rectangle {
                            id: addChip
                            required property var modelData
                            required property int index
                            visible: root.tileIds.indexOf(modelData.id) < 0 && root.removingTile !== modelData.id
                            readonly property real e: root.modeEnter(0.15 + index * 0.05)
                            opacity: e
                            height: 40
                            width: addRow.implicitWidth + 28
                            radius: 20
                            color: addMa.containsMouse ? container.accentA(0.16) : "transparent"
                            border.width: 1
                            border.color: container.tint(0.28)
                            Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }

                            RowLayout {
                                id: addRow
                                anchors.centerIn: parent
                                spacing: 8

                                Kirigami.Icon {
                                    Layout.preferredWidth: 16
                                    Layout.preferredHeight: 16
                                    source: Qt.resolvedUrl("icons/add.svg")
                                    isMask: true
                                    color: container.accent
                                }

                                Kirigami.Icon {
                                    Layout.preferredWidth: 18
                                    Layout.preferredHeight: 18
                                    source: Qt.resolvedUrl("icons/" + modelData.icon + ".svg")
                                    isMask: true
                                    color: container.fg
                                }

                                Text {
                                    text: root.i18n(modelData.title)
                                    font.family: "Google Sans Flex"
                                    font.pixelSize: 12
                                    color: container.fg
                                }
                            }

                            MouseArea {
                                id: addMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.addTile(modelData.id)
                            }
                        }
                    }
                }
            }

            // ── 2b. Phone media (what's playing on the phone, like ChromeOS Phone Hub) ──
            Rectangle {
                id: mediaCard
                Layout.fillWidth: true
                Layout.preferredHeight: 76
                visible: root.hasMedia && !root.editMode
                opacity: Math.min(root.enterAt(0.16), root.modeEnter(0.08))
                transform: Translate { y: (1 - root.enterMove(0.16)) * 14 }
                radius: 24
                color: container.accentA(0.14)

                readonly property bool playing: root.mpris ? Boolean(root.mpris.isPlaying) : false
                readonly property string art: root.mpris ? String(root.mpris.localAlbumArtUrl || "") : ""
                readonly property string sub: {
                    if (!root.mpris) return "";
                    var parts = [];
                    if (String(root.mpris.artist || "").length > 0) parts.push(root.mpris.artist);
                    parts.push(root.deviceName); // mprisremote.player has no change signal
                    return parts.join(" · ");
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 10

                    Item {
                        Layout.preferredWidth: 52
                        Layout.preferredHeight: 52

                        Rectangle {
                            anchors.fill: parent
                            radius: 14
                            color: container.accentA(0.22)
                            visible: artImg.status !== Image.Ready

                            Kirigami.Icon {
                                anchors.centerIn: parent
                                width: 24
                                height: 24
                                source: Qt.resolvedUrl("icons/music_note.svg")
                                isMask: true
                                color: container.accent
                            }
                        }

                        Kirigami.ShadowedImage {
                            id: artImg
                            anchors.fill: parent
                            radius: 14
                            color: "transparent"
                            source: mediaCard.art
                            fillMode: Image.PreserveAspectCrop
                            sourceSize: Qt.size(104, 104)
                            asynchronous: true
                            visible: status === Image.Ready
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            Layout.fillWidth: true
                            text: root.mpris ? String(root.mpris.title || "") : ""
                            font.family: "Google Sans Flex"
                            font.pixelSize: 14
                            font.weight: Font.Medium
                            color: container.fg
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: text.length > 0
                            text: mediaCard.sub
                            font.family: "Google Sans Flex"
                            font.pixelSize: 12
                            color: container.tint(0.65)
                            elide: Text.ElideRight
                        }
                    }

                    MediaButton { iconName: "skip_previous"; onClicked: root.mediaAction("Previous") }
                    MediaButton {
                        primary: true
                        toggled: mediaCard.playing
                        iconName: mediaCard.playing ? "pause" : "play"
                        onClicked: root.mediaAction("PlayPause")
                    }
                    MediaButton { iconName: "skip_next"; onClicked: root.mediaAction("Next") }
                }
            }

            // ── 2c. Recent photos (opt-in: needs the phone storage mounted over SFTP) ──
            ColumnLayout {
                id: photosSection
                Layout.fillWidth: true
                spacing: 8
                visible: root.photosAvailable && !root.editMode
                opacity: Math.min(root.enterAt(0.2), root.modeEnter(0.1))
                transform: Translate { y: (1 - root.enterMove(0.2)) * 14 }

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        Layout.fillWidth: true
                        text: root.i18n("Recent photos")
                        font.family: "Google Sans Flex"
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        color: container.tint(0.75)
                    }

                    Rectangle {
                        visible: root.photosEnabled
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        radius: 14
                        color: hideMa.containsMouse ? container.tint(0.10) : "transparent"
                        Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }
                        QQC2.ToolTip.text: root.i18n("Hide recent photos")
                        QQC2.ToolTip.visible: hideMa.containsMouse
                        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay

                        Kirigami.Icon {
                            anchors.centerIn: parent
                            width: 18
                            height: 18
                            source: Qt.resolvedUrl("icons/visibility_off.svg")
                            isMask: true
                            color: container.tint(0.7)
                        }

                        MouseArea {
                            id: hideMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.plasmoidConfiguration) root.plasmoidConfiguration.phoneHubPhotos = false;
                                root.photos = [];
                            }
                        }
                    }

                    Rectangle {
                        visible: root.photosEnabled
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        radius: 14
                        color: refreshMa.containsMouse ? container.tint(0.10) : "transparent"
                        Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }

                        Kirigami.Icon {
                            id: refreshIcon
                            anchors.centerIn: parent
                            width: 18
                            height: 18
                            source: Qt.resolvedUrl("icons/refresh.svg")
                            isMask: true
                            color: container.tint(0.7)
                            RotationAnimation on rotation {
                                running: root.photosLoading
                                loops: Animation.Infinite
                                from: 0
                                to: 360
                                duration: 900
                                onRunningChanged: if (!running) refreshIcon.rotation = 0
                            }
                        }

                        MouseArea {
                            id: refreshMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.refreshPhotos()
                        }
                    }
                }

                // Opt-in card
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: optRow.implicitHeight + 24
                    visible: !root.photosEnabled
                    radius: 20
                    color: container.tint(0.06)

                    RowLayout {
                        id: optRow
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 12

                        Rectangle {
                            Layout.preferredWidth: 40
                            Layout.preferredHeight: 40
                            radius: 20
                            color: container.accentA(0.16)

                            Kirigami.Icon {
                                anchors.centerIn: parent
                                width: 20
                                height: 20
                                source: Qt.resolvedUrl("icons/photo.svg")
                                isMask: true
                                color: container.accent
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            text: root.i18n("See your phone's latest photos here.")
                            font.family: "Google Sans Flex"
                            font.pixelSize: 12
                            color: container.tint(0.7)
                        }

                        Rectangle {
                            Layout.preferredHeight: 34
                            Layout.preferredWidth: turnOnLabel.implicitWidth + 28
                            radius: turnOnMa.pressed ? 10 : 17
                            color: container.accent
                            Behavior on radius { NumberAnimation { duration: Kirigami.Units.longDuration > 1 ? 250 : 0; easing.type: Easing.OutCubic } }

                            Text {
                                id: turnOnLabel
                                anchors.centerIn: parent
                                text: root.i18n("Turn on")
                                font.family: "Google Sans Flex"
                                font.pixelSize: 13
                                font.weight: Font.Medium
                                color: Kirigami.Theme.highlightedTextColor
                            }

                            MouseArea {
                                id: turnOnMa
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.enablePhotos()
                            }
                        }
                    }
                }

                // Thumbnails: staggered pop-in, shape morph on hover, click = save to Downloads + open
                Item {
                    id: thumbRow
                    Layout.fillWidth: true
                    Layout.preferredHeight: thumbSize
                    visible: root.photosEnabled
                    readonly property int gap: 8
                    readonly property real thumbSize: Math.floor((width - 3 * gap) / 4)
                    property real pulse: 1
                    SequentialAnimation on pulse {
                        running: root.photosLoading && thumbRow.visible && Kirigami.Units.longDuration > 1
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.4; duration: 650; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1; duration: 650; easing.type: Easing.InOutSine }
                        onStopped: thumbRow.pulse = 1
                    }

                    Repeater {
                        model: 4
                        delegate: Item {
                            id: ph
                            required property int index
                            readonly property var photo: index < root.photos.length ? root.photos[index] : null
                            readonly property real e: root.ease4((root.photosT - index * 0.09) / 0.55)
                            x: index * (thumbRow.thumbSize + thumbRow.gap)
                            width: thumbRow.thumbSize
                            height: thumbRow.thumbSize

                            QQC2.ToolTip.text: ph.photo ? ph.photo.name + "\n" + root.i18n("Save to Downloads and open") : ""
                            QQC2.ToolTip.visible: thMa.containsMouse && ph.photo !== null
                            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay

                            Rectangle {
                                anchors.fill: parent
                                radius: 16
                                color: container.tint(0.07)
                                opacity: root.photosLoading ? thumbRow.pulse : 1
                                visible: !ph.photo || thumb.status !== Image.Ready || ph.e < 1
                            }

                            Kirigami.ShadowedImage {
                                id: thumb
                                anchors.fill: parent
                                radius: thMa.containsMouse ? 26 : 16
                                Behavior on radius { NumberAnimation { duration: Kirigami.Units.longDuration > 1 ? 320 : 0; easing.type: Easing.OutCubic } }
                                color: "transparent"
                                source: ph.photo ? "file://" + ph.photo.thumb : ""
                                fillMode: Image.PreserveAspectCrop
                                sourceSize: Qt.size(192, 192)
                                asynchronous: true
                                opacity: ph.photo ? ph.e : 0
                                scale: (0.82 + 0.18 * ph.e) * (thMa.pressed ? 0.94 : 1)
                                Behavior on scale { enabled: ph.e >= 1; NumberAnimation { duration: Kirigami.Units.longDuration > 1 ? 160 : 0; easing.type: Easing.OutCubic } }
                            }

                            Rectangle {
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.margins: 6
                                width: 28
                                height: 28
                                radius: 14
                                color: Qt.rgba(0, 0, 0, 0.55)
                                opacity: thMa.containsMouse ? 1 : 0
                                scale: thMa.containsMouse ? 1 : 0.6
                                Behavior on opacity { NumberAnimation { duration: Kirigami.Units.longDuration > 1 ? 200 : 0 } }
                                Behavior on scale { NumberAnimation { duration: Kirigami.Units.longDuration > 1 ? 260 : 0; easing.type: Easing.OutBack } }

                                Kirigami.Icon {
                                    anchors.centerIn: parent
                                    width: 16
                                    height: 16
                                    source: Qt.resolvedUrl("icons/download.svg")
                                    isMask: true
                                    color: "white"
                                }
                            }

                            MouseArea {
                                id: thMa
                                anchors.fill: parent
                                enabled: ph.photo !== null
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.openPhoto(ph.photo.path)
                            }
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: root.photosEnabled && !root.photosLoading && (root.photosError.length > 0 || root.photos.length === 0)
                    text: root.photosError.length > 0 ? root.i18n("Couldn't reach the phone's storage") : root.i18n("No recent photos")
                    font.family: "Google Sans Flex"
                    font.pixelSize: 11
                    color: container.tint(0.55)
                }
            }

            // ── 3. Notifications ──
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                visible: !root.editMode
                opacity: root.modeEnter(0.05)
                color: container.tint(0.10)
            }

            RowLayout {
                Layout.fillWidth: true
                visible: root.reachable && !root.editMode
                opacity: Math.min(root.enterAt(0.22), root.modeEnter(0.1))

                Text {
                    Layout.fillWidth: true
                    text: root.i18n("Notifications")
                    font.family: "Google Sans Flex"
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    color: container.tint(0.75)
                }

                Text {
                    text: root.i18n("Clear all")
                    font.family: "Google Sans Flex"
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    color: clearMa.containsMouse ? container.accent : container.tint(0.6)
                    visible: notifsModel.count > 0 && notifsModel.isAnyDimissable

                    MouseArea {
                        id: clearMa
                        anchors.fill: parent
                        anchors.margins: -6
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: notifsModel.dismissAll()
                    }
                }
            }

            Item {
                id: notifArea
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: !root.editMode
                readonly property real emptyH: 120
                Layout.preferredHeight: (root.reachable && notifsModel.count > 0) ? notifsList.contentHeight : emptyH
                Layout.minimumHeight: Math.min(emptyH, Layout.preferredHeight)
                opacity: Math.min(root.enterAt(0.26), root.modeEnter(0.15))
                transform: Translate { y: (1 - root.modeEnter(0.15)) * 16 }

                KDEConnect.NotificationsModel {
                    id: notifsModel
                    deviceId: root.reachable ? root.deviceId : ""
                }

                // All caught up
                Column {
                    anchors.centerIn: parent
                    spacing: 8
                    visible: root.reachable && notifsModel.count === 0

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 40
                        height: 40
                        radius: 20
                        color: container.accentA(0.16)

                        Kirigami.Icon {
                            anchors.centerIn: parent
                            width: 20
                            height: 20
                            source: Qt.resolvedUrl("icons/check.svg")
                            isMask: true
                            color: container.accent
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.i18n("All caught up")
                        font.family: "Google Sans Flex"
                        font.pixelSize: 13
                        color: container.tint(0.6)
                    }
                }

                // Not reachable / no device
                ColumnLayout {
                    anchors.centerIn: parent
                    width: parent.width - 24
                    spacing: 10
                    visible: !root.reachable

                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        text: root.hasDevice
                              ? root.i18n("Open the KDE Connect app on your phone and make sure both devices are on the same network.")
                              : root.i18n("Pair a phone with KDE Connect to use the Phone Hub.")
                        font.family: "Google Sans Flex"
                        font.pixelSize: 12
                        color: container.tint(0.6)
                    }

                    Rectangle {
                        visible: !root.hasDevice
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredHeight: 36
                        Layout.preferredWidth: openLabel.implicitWidth + 32
                        radius: 18
                        color: container.accent

                        Text {
                            id: openLabel
                            anchors.centerIn: parent
                            text: root.i18n("Open KDE Connect")
                            font.family: "Google Sans Flex"
                            font.pixelSize: 13
                            font.weight: Font.Medium
                            color: Kirigami.Theme.highlightedTextColor
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.openApp()
                        }
                    }
                }

                ListView {
                    id: notifsList
                    anchors.fill: parent
                    clip: true
                    spacing: 8
                    visible: root.reachable && notifsModel.count > 0
                    model: notifsModel
                    boundsBehavior: Flickable.StopAtBounds

                    add: Transition {
                        NumberAnimation { property: "x"; from: 40; to: 0; duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic }
                    }
                    remove: Transition {
                        NumberAnimation { property: "x"; to: notifsList.width; duration: Kirigami.Units.longDuration; easing.type: Easing.InCubic }
                    }
                    displaced: Transition {
                        NumberAnimation { properties: "y"; duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic }
                    }

                    delegate: PhoneHubNotificationCard {
                        required property var model
                        required property int index
                        notifModel: model
                        width: notifsList.width
                        enter: root.enterAt(0.28 + Math.min(index, 6) * 0.05)
                    }
                }
            }
        }
    }

    // Media transport button. The primary (play/pause) one is a filled circle that
    // morphs into a rounded square while playing (M3 expressive shape change).
    component MediaButton: Rectangle {
        id: mb
        property string iconName: ""
        property bool primary: false
        property bool toggled: false
        signal clicked()

        Layout.preferredWidth: primary ? 46 : 34
        Layout.preferredHeight: primary ? 46 : 34
        radius: primary ? (toggled ? 14 : 23) : 17
        color: primary
               ? Kirigami.Theme.highlightColor
               : (mbMa.containsMouse ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.10) : "transparent")
        scale: mbMa.pressed ? 0.9 : 1.0
        Behavior on radius { NumberAnimation { duration: Kirigami.Units.longDuration > 1 ? 380 : 0; easing.type: Easing.OutBack } }
        Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }
        Behavior on scale { NumberAnimation { duration: Kirigami.Units.longDuration > 1 ? 140 : 0; easing.type: Easing.OutCubic } }

        Kirigami.Icon {
            anchors.centerIn: parent
            width: mb.primary ? 24 : 20
            height: width
            source: Qt.resolvedUrl("icons/" + mb.iconName + ".svg")
            isMask: true
            color: mb.primary ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
        }

        MouseArea {
            id: mbMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: mb.clicked()
        }
    }

    // Small circular icon button used in the header.
    component HeaderButton: Rectangle {
        id: hb
        property string iconSource: ""
        property string tooltip: ""
        property bool toggled: false
        signal clicked()

        Layout.preferredWidth: 36
        Layout.preferredHeight: 36
        radius: toggled ? 12 : 18
        color: toggled
               ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.25)
               : (hbMa.containsMouse ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.10) : "transparent")
        Behavior on radius { NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }

        QQC2.ToolTip.text: hb.tooltip
        QQC2.ToolTip.visible: hbMa.containsMouse && hb.tooltip.length > 0
        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay

        Kirigami.Icon {
            anchors.centerIn: parent
            width: 20
            height: 20
            source: hb.iconSource
            isMask: true
            color: Kirigami.Theme.textColor
        }

        MouseArea {
            id: hbMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: hb.clicked()
        }
    }
}

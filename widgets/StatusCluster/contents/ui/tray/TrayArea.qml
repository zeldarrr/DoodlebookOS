/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Background-app icons (StatusNotifierItems: Discord/Vesktop, Sunshine, Steam…) shown
 * in the top bar like the classic KDE system tray, with Material You styling.
 *
 * Event driven: D-Bus signal watchers trigger a refresh through contents/code/tray.py,
 * nothing polls in the background (a slow safety refresh runs every 2 minutes).
 */

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.plasma.workspace.dbus as DBus

Item {
    id: tray

    property var appletRoot: null
    property real railHeight: 24
    property color contentColor: Kirigami.Theme.textColor
    property color capsuleColor: Kirigami.Theme.highlightColor
    property color highlightedContentColor: Kirigami.Theme.highlightedTextColor
    readonly property real dpr: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1.0
    readonly property bool anim: Kirigami.Units.longDuration > 1
    function snap(v) { return Math.round(v * dpr) / dpr; }

    property var items: []
    property string lastJson: ""
    property var openMenuKey: ""

    readonly property string helperPath: Qt.resolvedUrl("../../code/tray.py").toString().replace(/^file:\/\//, "")
    function q(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'"; }
    function helper(args) { return "python3 " + q(decodeURIComponent(helperPath)) + " " + args; }

    readonly property real iconSize: snap(railHeight * 0.62)
    readonly property real cellWidth: snap(railHeight * 1.05)
    readonly property real pad: snap(railHeight * 0.18)

    height: railHeight
    width: items.length > 0 ? row.width + pad * 2 : 0
    implicitWidth: width
    implicitHeight: height
    visible: items.length > 0
    Behavior on width { NumberAnimation { duration: tray.anim ? 350 : 0; easing.type: Easing.OutQuart } }

    // ───── data ─────
    Plasma5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            var out = data["stdout"] || "";
            disconnectSource(sourceName);
            if (sourceName.indexOf("# tray-list") !== -1) {
                tray.applyList(out);
            } else if (sourceName.indexOf("# tray-menu") !== -1) {
                trayMenu.load(out);
            }
        }
        function run(cmd, tag) {
            connectSource(cmd + " # " + tag + " " + Date.now());
        }
    }

    function refresh() { exec.run(helper("list"), "tray-list"); }

    function applyList(out) {
        var txt = String(out).trim();
        if (txt === tray.lastJson) return;
        var parsed;
        try { parsed = JSON.parse(txt); } catch (e) { return; }
        if (!Array.isArray(parsed)) return;
        tray.lastJson = txt;
        tray.items = parsed;
    }

    Timer { id: refreshTimer; interval: 250; onTriggered: tray.refresh() }
    Timer { interval: 120000; running: true; repeat: true; onTriggered: tray.refresh() }
    Component.onCompleted: refresh()

    // items registered / unregistered
    DBus.SignalWatcher {
        busType: DBus.BusType.Session
        service: "org.kde.StatusNotifierWatcher"
        path: "/StatusNotifierWatcher"
        iface: "org.kde.StatusNotifierWatcher"
        // Plasma's SignalWatcher calls the QML function named "dbus" + <signal name>.
        function dbusStatusNotifierItemRegistered(service) { refreshTimer.restart(); }
        function dbusStatusNotifierItemUnregistered(service) { refreshTimer.restart(); }
        function dbusStatusNotifierHostRegistered() { refreshTimer.restart(); }
        function dbusStatusNotifierHostUnregistered() { refreshTimer.restart(); }
    }

    // icon / status / title changes of each item (NewIcon, NewStatus, NewToolTip…)
    Instantiator {
        model: tray.items
        delegate: DBus.SignalWatcher {
            required property var modelData
            busType: DBus.BusType.Session
            service: modelData.service
            path: modelData.path
            iface: modelData.iface
            function dbusNewTitle() { refreshTimer.restart(); }
            function dbusNewIcon() { refreshTimer.restart(); }
            function dbusNewAttentionIcon() { refreshTimer.restart(); }
            function dbusNewOverlayIcon() { refreshTimer.restart(); }
            function dbusNewToolTip() { refreshTimer.restart(); }
            function dbusNewMenu() { refreshTimer.restart(); }
            function dbusNewStatus(status) { refreshTimer.restart(); }
            function dbusNewIconThemePath(path) { refreshTimer.restart(); }
        }
    }

    function globalPos(item) {
        var p = item.mapToGlobal(item.width / 2, item.height);
        return Qt.point(Math.round(p.x), Math.round(p.y));
    }

    function activate(it, item) {
        var p = globalPos(item);
        exec.run(helper("activate " + q(it.service) + " " + q(it.path) + " " + p.x + " " + p.y), "tray-act");
    }
    function secondary(it, item) {
        var p = globalPos(item);
        exec.run(helper("secondary " + q(it.service) + " " + q(it.path) + " " + p.x + " " + p.y), "tray-act");
    }
    function scroll(it, delta, orientation) {
        exec.run(helper("scroll " + q(it.service) + " " + q(it.path) + " " + delta + " " + orientation), "tray-act");
    }
    // Right click: show the cached menu at once (menus rarely change), then refresh it from the app.
    // First time: wait for the helper (~80 ms) so an app without a DBusMenu never flashes our popup.
    property var menuCache: ({})
    property string menuRequest: ""
    function openMenu(it, item) {
        if (!it.menu) {
            var p = globalPos(item);
            exec.run(helper("contextmenu " + q(it.service) + " " + q(it.path) + " " + p.x + " " + p.y), "tray-act");
            return;
        }
        trayMenu.request(it, item);
        var cached = tray.menuCache[it.key];
        if (cached) trayMenu.show(cached);
        tray.menuRequest = "tray-menu " + it.key;
        exec.run(helper("menu " + q(it.service) + " " + q(it.menu)), "tray-menu");
    }
    function menuEvent(it, entryId) {
        exec.run(helper("event " + q(it.service) + " " + q(it.menu) + " " + entryId), "tray-act");
    }

    // ───── tonal container ─────
    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Qt.rgba(tray.contentColor.r, tray.contentColor.g, tray.contentColor.b, 0.10)
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 0

        Repeater {
            model: tray.items
            delegate: Item {
                id: cell
                required property var modelData
                required property int index
                readonly property bool menuOpen: trayMenu.visible && tray.openMenuKey === modelData.key
                readonly property bool attention: modelData.status === "NeedsAttention"
                width: tray.cellWidth
                height: tray.railHeight

                // M3 pop-in when an app adds its icon
                property real e: 0
                Component.onCompleted: popIn.start()
                NumberAnimation { id: popIn; target: cell; property: "e"; from: 0; to: 1; duration: tray.anim ? 420 : 0; easing.type: Easing.OutBack }
                opacity: Math.min(1, e * 1.4)
                scale: 0.5 + 0.5 * e

                // state layer (hover 8 %, pressed 12 %) and the tonal capsule while its menu is open
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width
                    height: parent.height
                    radius: height / 2
                    color: Qt.rgba(tray.contentColor.r, tray.contentColor.g, tray.contentColor.b,
                                   cellMouse.pressed ? 0.12 : (cellMouse.containsMouse ? 0.08 : 0))
                    Behavior on color { ColorAnimation { duration: tray.anim ? 120 : 0 } }
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width
                    height: parent.height
                    radius: height / 2
                    color: tray.capsuleColor
                    opacity: cell.menuOpen ? 1.0 : 0
                    scale: cell.menuOpen ? 1.0 : 0.6
                    Behavior on opacity { NumberAnimation { duration: tray.anim ? 180 : 0 } }
                    Behavior on scale { NumberAnimation { duration: tray.anim ? 320 : 0; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
                }

                Kirigami.Icon {
                    id: icon
                    anchors.centerIn: parent
                    width: tray.iconSize
                    height: tray.iconSize
                    // M3 Expressive press: quick squish, springs back on release
                    transform: Scale {
                        origin.x: tray.iconSize / 2
                        origin.y: tray.iconSize / 2
                        xScale: cellMouse.pressed ? 0.84 : 1
                        yScale: xScale
                        Behavior on xScale { NumberAnimation { duration: tray.anim ? (cellMouse.pressed ? 90 : 380) : 0; easing.type: cellMouse.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: 2.4 } }
                    }
                    source: cell.modelData.iconFile ? ("file://" + cell.modelData.iconFile)
                          : (cell.modelData.iconName || cell.modelData.appIcon || "application-x-executable")
                    fallback: cell.modelData.appIcon || "application-x-executable"
                    smooth: true
                    // gentle "breathing" when the app asks for attention
                    SequentialAnimation on scale {
                        running: cell.attention && tray.anim
                        loops: Animation.Infinite
                        alwaysRunToEnd: true
                        NumberAnimation { to: 1.15; duration: 600; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.0; duration: 600; easing.type: Easing.InOutSine }
                    }
                }

                // attention badge
                Rectangle {
                    visible: cell.attention
                    width: tray.snap(tray.railHeight * 0.26)
                    height: width
                    radius: width / 2
                    color: Kirigami.Theme.negativeTextColor
                    anchors.right: icon.right
                    anchors.top: icon.top
                    anchors.rightMargin: -width / 3
                    anchors.topMargin: -width / 3
                }


                PlasmaCore.ToolTipArea {
                    anchors.fill: parent
                    active: !cell.menuOpen && !cellMouse.pressed
                    mainText: cell.modelData.title || ""
                    subText: (cell.modelData.tooltip || "").replace(/<[^>]*>/g, "").trim()
                    location: PlasmaCore.Types.TopEdge

                    MouseArea {
                        id: cellMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        // the popup hides itself as soon as the bar is pressed (focus loss):
                        // remember whether it was open so a second click closes instead of reopening
                        property bool wasOpen: false
                        onPressed: wasOpen = cell.menuOpen || (trayMenu.visible && tray.openMenuKey === cell.modelData.key)
                        onClicked: mouse => {
                            if (tray.appletRoot && typeof tray.appletRoot.closeAllPopups === "function") tray.appletRoot.closeAllPopups();
                            if (mouse.button === Qt.MiddleButton) {
                                tray.secondary(cell.modelData, cell);
                            } else if (mouse.button === Qt.RightButton || (cell.modelData.itemIsMenu && cell.modelData.menu)) {
                                if (wasOpen || cell.menuOpen) trayMenu.visible = false;
                                else tray.openMenu(cell.modelData, cell);
                            } else {
                                trayMenu.visible = false;
                                tray.activate(cell.modelData, cell);
                            }
                        }
                        onWheel: wheel => {
                            if (wheel.angleDelta.y !== 0) tray.scroll(cell.modelData, wheel.angleDelta.y, "vertical");
                            else if (wheel.angleDelta.x !== 0) tray.scroll(cell.modelData, wheel.angleDelta.x, "horizontal");
                        }
                    }
                }
            }
        }
    }

    // ───── Material 3 Expressive menu (built from the app's DBusMenu) ─────
    PlasmaCore.AppletPopup {
        id: trayMenu
        property var item: null
        property var rootEntries: []
        property var stack: []                  // submenu navigation
        readonly property var entries: stack.length > 0 ? stack[stack.length - 1].children : rootEntries
        property Item pendingAnchor: null

        visualParent: pendingAnchor
        // same floating, fully rounded popup as Quick Settings / notifications (a Dialog on the
        // top edge drops its top border → square top corners)
        popupDirection: Qt.BottomEdge
        margin: 1
        removeBorderStrategy: PlasmaCore.AppletPopup.Never
        animated: false     // no KWin slide: doodlebookos_popups unfolds it from the icon (M3)
        hideOnWindowDeactivate: true
        backgroundHints: PlasmaCore.AppletPopup.StandardBackground
        width: menuContent.implicitWidth
        height: menuContent.implicitHeight

        function request(it, anchor) {
            item = it;
            pendingAnchor = anchor;
            tray.openMenuKey = it.key;
        }

        function show(parsed) {
            stack = [];
            rootEntries = parsed;
            visible = true;
            requestActivate();
            menuContent.playEnter(0);
        }

        // helper reply: fill the cache, open (or refresh the open menu in place)
        function load(out) {
            var parsed;
            try { parsed = JSON.parse(String(out)); } catch (e) { parsed = null; }
            var it = item;
            if (!it || tray.menuRequest !== "tray-menu " + it.key) return;   // another icon was clicked since
            tray.menuRequest = "";
            if (!parsed || !Array.isArray(parsed) || parsed.length === 0) {
                // no usable DBusMenu: let the application show its own menu
                var cache = tray.menuCache;
                delete cache[it.key];
                visible = false;
                if (pendingAnchor) {
                    var p = tray.globalPos(pendingAnchor);
                    exec.run(tray.helper("contextmenu " + tray.q(it.service) + " " + tray.q(it.path) + " " + p.x + " " + p.y), "tray-act");
                }
                return;
            }
            var json = JSON.stringify(parsed);
            var wasCached = tray.menuCache[it.key];
            tray.menuCache[it.key] = parsed;
            if (!visible) {
                if (tray.openMenuKey === it.key) show(parsed);
            } else if (!wasCached || JSON.stringify(wasCached) !== json) {
                // same menu already on screen: swap the data without replaying the entrance
                if (stack.length === 0) rootEntries = parsed;
                else { stack = []; rootEntries = parsed; }
            }
        }

        function trigger(entry) {
            if (!entry || entry.enabled === false || entry.type === "separator") return;
            if (entry.submenu && entry.children && entry.children.length > 0) {
                var s = stack.slice();
                s.push(entry);
                stack = s;
                menuContent.playEnter(1);
                return;
            }
            tray.menuEvent(item, entry.id);
            visible = false;
        }

        function back() {
            if (stack.length === 0) return;
            var s = stack.slice();
            s.pop();
            stack = s;
            menuContent.playEnter(-1);
        }

        onVisibleChanged: if (!visible) { tray.openMenuKey = ""; stack = []; }

        mainItem: TrayMenu {
            id: menuContent
            appItem: trayMenu.item
            entries: trayMenu.entries
            depth: trayMenu.stack.length
            levelTitle: trayMenu.stack.length > 0 ? (trayMenu.stack[trayMenu.stack.length - 1].label || "") : ""
            onActivated: entry => trayMenu.trigger(entry)
            onBackRequested: trayMenu.back()
            onCloseRequested: trayMenu.visible = false
        }
    }
}

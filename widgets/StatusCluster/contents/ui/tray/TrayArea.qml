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
    Behavior on width { NumberAnimation { duration: 350; easing.type: Easing.OutQuart } }

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
    function openMenu(it, item) {
        if (!it.menu) {
            var p = globalPos(item);
            exec.run(helper("contextmenu " + q(it.service) + " " + q(it.path) + " " + p.x + " " + p.y), "tray-act");
            return;
        }
        trayMenu.request(it, item);
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
                NumberAnimation { id: popIn; target: cell; property: "e"; from: 0; to: 1; duration: 420; easing.type: Easing.OutBack }
                opacity: Math.min(1, e * 1.4)
                scale: 0.5 + 0.5 * e

                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width
                    height: parent.height
                    radius: height / 2
                    color: tray.capsuleColor
                    opacity: cell.menuOpen ? 1.0 : (cellMouse.pressed ? 0.4 : 0)
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                }

                Kirigami.Icon {
                    id: icon
                    anchors.centerIn: parent
                    width: tray.iconSize
                    height: tray.iconSize
                    source: cell.modelData.iconFile ? ("file://" + cell.modelData.iconFile)
                          : (cell.modelData.iconName || cell.modelData.appIcon || "application-x-executable")
                    fallback: cell.modelData.appIcon || "application-x-executable"
                    smooth: true
                    // gentle "breathing" when the app asks for attention
                    SequentialAnimation on scale {
                        running: cell.attention
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


                MouseArea {
                    id: cellMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: mouse => {
                        if (tray.appletRoot && typeof tray.appletRoot.closeAllPopups === "function") tray.appletRoot.closeAllPopups();
                        if (mouse.button === Qt.MiddleButton) {
                            tray.secondary(cell.modelData, cell);
                        } else if (mouse.button === Qt.RightButton || (cell.modelData.itemIsMenu && cell.modelData.menu)) {
                            if (cell.menuOpen) trayMenu.visible = false;
                            else tray.openMenu(cell.modelData, cell);
                        } else {
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

    // ───── Material 3 menu (built from the app's DBusMenu) ─────
    PlasmaCore.AppletPopup {
        id: trayMenu
        property var item: null
        property var rootEntries: []
        property var stack: []                  // submenu navigation
        readonly property var entries: stack.length > 0 ? stack[stack.length - 1].children : rootEntries
        readonly property string subTitle: stack.length > 0 ? stack[stack.length - 1].label : ""
        property Item pendingAnchor: null
        property real enterT: 1

        visualParent: pendingAnchor
        // same floating, fully rounded popup as Quick Settings / notifications (a Dialog on the
        // top edge drops its top border → square top corners)
        popupDirection: Qt.BottomEdge
        margin: 1
        removeBorderStrategy: PlasmaCore.AppletPopup.Never
        hideOnWindowDeactivate: true
        backgroundHints: PlasmaCore.AppletPopup.StandardBackground
        width: menuContent.implicitWidth
        height: menuContent.implicitHeight

        function request(it, anchor) {
            item = it;
            pendingAnchor = anchor;
            tray.openMenuKey = it.key;
        }

        function load(out) {
            var parsed;
            try { parsed = JSON.parse(String(out)); } catch (e) { parsed = null; }
            if (!parsed || !Array.isArray(parsed) || parsed.length === 0) {
                // no usable DBusMenu: let the application show its own menu
                if (item && pendingAnchor) {
                    var p = tray.globalPos(pendingAnchor);
                    exec.run(tray.helper("contextmenu " + tray.q(item.service) + " " + tray.q(item.path) + " " + p.x + " " + p.y), "tray-act");
                }
                return;
            }
            stack = [];
            rootEntries = parsed;
            visible = true;
            menuContent.playEnter();
        }

        function trigger(entry) {
            if (!entry.enabled || entry.type === "separator") return;
            if (entry.submenu && entry.children && entry.children.length > 0) {
                var s = stack.slice();
                s.push(entry);
                stack = s;
                menuContent.playEnter();
                return;
            }
            tray.menuEvent(item, entry.id);
            visible = false;
        }

        function back() {
            var s = stack.slice();
            s.pop();
            stack = s;
            menuContent.playEnter();
        }

        onVisibleChanged: if (!visible) tray.openMenuKey = ""

        mainItem: Item {
            id: menuContent
            readonly property color fg: Kirigami.Theme.textColor
            function tint(a) { return Qt.rgba(fg.r, fg.g, fg.b, a); }

            width: Kirigami.Units.gridUnit * 15
            height: menuCol.implicitHeight
            implicitWidth: width
            implicitHeight: height

            // M3 menu motion: content unfolds from the anchor edge, rows follow in cascade
            property real t: 1
            NumberAnimation { id: menuAnim; target: menuContent; property: "t"; from: 0; to: 1; duration: 420 }
            function playEnter() { menuAnim.restart(); }
            function rowEnter(i) {
                var p = Math.max(0, Math.min(1, (t - Math.min(i, 10) * 0.035) / 0.6));
                return 1 - Math.pow(1 - p, 4);
            }

            Column {
                id: menuCol
                width: parent.width
                spacing: 0

                // header: app + back navigation for submenus
                Item {
                    width: parent.width
                    height: Kirigami.Units.gridUnit * 2.2
                    opacity: menuContent.rowEnter(0)

                    Rectangle {
                        id: backBtn
                        visible: trayMenu.stack.length > 0
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: Kirigami.Units.gridUnit * 1.8
                        height: width
                        radius: width / 2
                        color: backMa.containsMouse ? menuContent.tint(0.10) : "transparent"
                        Kirigami.Icon {
                            anchors.centerIn: parent
                            width: Kirigami.Units.iconSizes.small
                            height: width
                            source: "go-previous-symbolic"
                            color: menuContent.fg
                            isMask: true
                        }
                        MouseArea { id: backMa; anchors.fill: parent; hoverEnabled: true; onClicked: trayMenu.back() }
                    }

                    Kirigami.Icon {
                        id: hdrIcon
                        visible: trayMenu.stack.length === 0
                        anchors.left: parent.left
                        anchors.leftMargin: Kirigami.Units.smallSpacing
                        anchors.verticalCenter: parent.verticalCenter
                        width: Kirigami.Units.iconSizes.small
                        height: width
                        source: trayMenu.item ? (trayMenu.item.iconFile ? ("file://" + trayMenu.item.iconFile) : (trayMenu.item.iconName || trayMenu.item.appIcon)) : ""
                        fallback: trayMenu.item ? trayMenu.item.appIcon : ""
                    }

                    Text {
                        anchors.left: trayMenu.stack.length > 0 ? backBtn.right : hdrIcon.right
                        anchors.leftMargin: Kirigami.Units.smallSpacing * 2
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: trayMenu.stack.length > 0 ? trayMenu.subTitle : (trayMenu.item ? trayMenu.item.title : "")
                        font.family: "Google Sans Flex"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        color: menuContent.fg
                        elide: Text.ElideRight
                    }
                }

                Repeater {
                    model: trayMenu.entries
                    delegate: Item {
                        id: entryRow
                        required property var modelData
                        required property int index
                        readonly property bool isSep: modelData.type === "separator"
                        width: menuCol.width
                        height: isSep ? 9 : Kirigami.Units.gridUnit * 2.2
                        opacity: menuContent.rowEnter(index + 1) * (modelData.enabled || isSep ? 1 : 0.38)
                        transform: Translate { y: (1 - menuContent.rowEnter(entryRow.index + 1)) * -8 }

                        Rectangle {
                            visible: entryRow.isSep
                            anchors.centerIn: parent
                            width: parent.width - Kirigami.Units.smallSpacing * 2
                            height: 1
                            color: menuContent.tint(0.12)
                        }

                        // M3 Expressive state layer: inset pill that morphs to a rounded square on press
                        Rectangle {
                            visible: !entryRow.isSep
                            anchors.fill: parent
                            anchors.leftMargin: 4
                            anchors.rightMargin: 4
                            anchors.topMargin: 1
                            anchors.bottomMargin: 1
                            radius: rowMa.pressed ? 8 : height / 2
                            color: menuContent.tint(rowMa.pressed ? 0.16 : (rowMa.containsMouse && entryRow.modelData.enabled ? 0.10 : 0))
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Behavior on radius { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                        }

                        RowLayout {
                            visible: !entryRow.isSep
                            anchors.fill: parent
                            anchors.leftMargin: Kirigami.Units.smallSpacing * 2
                            anchors.rightMargin: Kirigami.Units.smallSpacing * 2
                            spacing: Kirigami.Units.smallSpacing * 2

                            // toggle indicator (checkbox / radio) or icon
                            Item {
                                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                                visible: entryRow.modelData.toggleType !== "" || entryRow.modelData.iconName !== ""

                                Kirigami.Icon {
                                    anchors.fill: parent
                                    visible: entryRow.modelData.toggleType === "" && entryRow.modelData.iconName !== ""
                                    source: entryRow.modelData.iconName
                                }
                                Rectangle {
                                    anchors.centerIn: parent
                                    visible: entryRow.modelData.toggleType !== ""
                                    width: parent.width * 0.85
                                    height: width
                                    radius: entryRow.modelData.toggleType === "radio" ? width / 2 : 4
                                    color: entryRow.modelData.toggleState === 1 ? Kirigami.Theme.highlightColor : "transparent"
                                    border.width: entryRow.modelData.toggleState === 1 ? 0 : 2
                                    border.color: menuContent.tint(0.6)
                                    Kirigami.Icon {
                                        anchors.centerIn: parent
                                        visible: entryRow.modelData.toggleState === 1 && entryRow.modelData.toggleType !== "radio"
                                        width: parent.width * 0.8
                                        height: width
                                        source: "checkmark-symbolic"
                                        isMask: true
                                        color: Kirigami.Theme.highlightedTextColor
                                    }
                                    Rectangle {
                                        anchors.centerIn: parent
                                        visible: entryRow.modelData.toggleState === 1 && entryRow.modelData.toggleType === "radio"
                                        width: parent.width * 0.4
                                        height: width
                                        radius: width / 2
                                        color: Kirigami.Theme.highlightedTextColor
                                    }
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: entryRow.modelData.label
                                font.family: "Google Sans Flex"
                                font.pixelSize: 13
                                color: menuContent.fg
                                elide: Text.ElideRight
                            }

                            Kirigami.Icon {
                                visible: entryRow.modelData.submenu
                                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                                source: "go-next-symbolic"
                                isMask: true
                                color: menuContent.tint(0.7)
                            }
                        }

                        MouseArea {
                            id: rowMa
                            anchors.fill: parent
                            enabled: !entryRow.isSep && entryRow.modelData.enabled
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: trayMenu.trigger(entryRow.modelData)
                        }
                    }
                }
            }
        }
    }
}

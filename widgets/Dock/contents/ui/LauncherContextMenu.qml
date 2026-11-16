/*
 * SPDX-FileCopyrightText: 2024-2026 Maciej Kujawiński <maciek.kujawinski@gmail.com>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

// App context menu (Material 3 Expressive): the app's own actions (jump list) first, then
// pin / dock / folder / desktop / edit / location, info, hide and uninstall.
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import "i18n.js" as I18n

Item {
    id: menu

    function i18n(k, a1, a2) { return I18n.t(k, a1, a2); }

    property var launcherPopup: null
    property var md: ({})
    property var entries: []
    property bool foldersOpen: false
    property int confirmIndex: -1

    readonly property color fg: Kirigami.Theme.textColor
    readonly property color accent: Kirigami.Theme.highlightColor
    readonly property color cBg: Qt.tint(Kirigami.Theme.backgroundColor, Qt.rgba(accent.r, accent.g, accent.b, 0.07))
    readonly property color errorColor: main.isDarkTheme ? "#ffb4ab" : "#ba1a1a"
    function tint(a) { return Qt.rgba(fg.r, fg.g, fg.b, a); }

    visible: false
    z: 99999

    function jumpIcon(a) {
        var id = String(a.actionArgument || a.actionId || "").toLowerCase(), t = String(a.text || "").toLowerCase();
        if (id.indexOf("private") !== -1 || id.indexOf("incognito") !== -1 || t.indexOf("priv") !== -1) return Qt.resolvedUrl("icons/action_incognito.svg");
        if (t.indexOf("onglet") !== -1 || t.indexOf("tab") !== -1) return Qt.resolvedUrl("icons/action_new_tab.svg");
        if (t.indexOf("fenêtre") !== -1 || t.indexOf("window") !== -1) return Qt.resolvedUrl("icons/action_new_window.svg");
        if (t.indexOf("document") !== -1 || t.indexOf("nouveau") !== -1 || t.indexOf("new") !== -1) return Qt.resolvedUrl("icons/action_new_document.svg");
        if (t.indexOf("terminal") !== -1) return Qt.resolvedUrl("icons/action_terminal.svg");
        return Qt.resolvedUrl("icons/action_default.svg");
    }
    function findAction(id) {
        var acts = md.actions || [];
        for (var i = 0; i < acts.length; i++) if (acts[i] && acts[i].actionId === id) return acts[i];
        return null;
    }

    function build() {
        var d = md, items = [], acts = d.actions || [];
        var fav = kicker.globalFavorites;
        // 1. the app's own actions
        var jumps = 0;
        for (var i = 0; i < acts.length && jumps < 6; i++) {
            var a = acts[i];
            if (!a || a.type === "separator" || a.actionId !== "_kicker_jumpListAction") continue;
            (function (act) {
                items.push({ text: act.text, icon: jumpIcon(act), run: function () { d.trigger(act.actionId, act.actionArgument); menu.launched(); } });
            })(a);
            jumps++;
        }
        if (jumps) items.push({ sep: true });

        // 2. organise
        if (d.isPinned) {
            items.push({ text: i18n("Unpin from launcher"), icon: Qt.resolvedUrl("icons/keep_off.svg"), run: function () { fav.removeFavorite(d.launcherUrlStr); } });
            if (d.pinnedIndex >= 0) items.push({ move: true });
        } else {
            items.push({ text: i18n("Pin to launcher"), icon: Qt.resolvedUrl("icons/keep.svg"), run: function () { fav.addFavorite(d.launcherUrlStr); } });
        }
        if (d.isPinnedToDock) {
            items.push({ text: i18n("Unpin from Dock"), icon: Qt.resolvedUrl("icons/dock.svg"), run: function () { kicker.tasksModel.requestRemoveLauncher(menu.dockUrl(d)); } });
        } else {
            items.push({ text: i18n("Pin to Dock"), icon: Qt.resolvedUrl("icons/dock.svg"), run: function () { kicker.tasksModel.requestAddLauncher(d.launcherUrlStr); } });
        }
        if (d.folderId) {
            items.push({ text: i18n("Remove from folder"), icon: Qt.resolvedUrl("icons/remove.svg"), run: function () { appIndex.removeFromFolder(d.folderId, d.appId); } });
        } else if (d.appId) {
            items.push({ text: i18n("Add to folder"), icon: Qt.resolvedUrl("icons/create_new_folder.svg"), folders: true });
        }
        var desk = findAction("addToDesktop");
        items.push({ text: i18n("Add to Desktop"), icon: Qt.resolvedUrl("icons/desktop.svg"), run: function () {
            if (desk) d.trigger(desk.actionId, desk.actionArgument);
            else appIndex.run("desktop " + appIndex.shq(d.appId));
            root.toast(menu.i18n("Added to the desktop"));
        } });
        var edit = findAction("editApplication");
        items.push({ text: i18n("Edit application…"), icon: Qt.resolvedUrl("icons/edit.svg"), run: function () {
            if (edit) d.trigger(edit.actionId, edit.actionArgument);
            else appIndex.sh("kmenuedit");
            menu.launched();
        } });
        items.push({ text: i18n("Open location"), icon: Qt.resolvedUrl("icons/folder_open.svg"), run: function () { appIndex.run("locate " + appIndex.shq(d.appId)); menu.launched(); } });
        items.push({ sep: true });

        // 3. about / remove
        items.push({ text: i18n("App info"), icon: Qt.resolvedUrl("icons/info.svg"), run: function () { root.showInfo(d.appId); } });
        if (!d.folderId) {
            items.push({ text: d.isHidden ? i18n("Un-hide") : i18n("Hide"), icon: Qt.resolvedUrl(d.isHidden ? "icons/visibility.svg" : "icons/visibility_off.svg"), run: function () {
                if (typeof combinedRoot === "undefined" || !combinedRoot) return;
                if (d.isHidden) combinedRoot.unhideApp(d.appId, d.appName);
                else { combinedRoot.hideApp(d.appId, d.appName); root.toast(menu.i18n("%1 hidden", d.appName)); }
            } });
        }
        var e = appIndex.entry(d.appId);
        if (e && String(e.src).indexOf("flatpak") === 0) {
            items.push({ text: i18n("Uninstall"), confirmText: i18n("Confirm uninstall"), icon: Qt.resolvedUrl("icons/delete.svg"), danger: true, run: function () {
                var name = d.appName;
                root.toast(menu.i18n("Uninstalling %1…", name));
                appIndex.run("uninstall " + appIndex.shq(d.appId), function (out) {
                    var r = {};
                    try { r = JSON.parse(out); } catch (err) {}
                    root.toast(r.ok ? menu.i18n("%1 uninstalled", name) : menu.i18n("Could not uninstall %1", name));
                });
            } });
        }
        entries = items;
    }

    function dockUrl(d) {
        var list = kicker.tasksModel.launcherList || [];
        for (var i = 0; i < list.length; i++) if (appIndex.sid(list[i]) === d.appId) return list[i];
        return d.launcherUrlStr;
    }
    function launched() {
        if (launcherPopup) launcherPopup.closeAfterLaunch();
    }

    function open(item, mousePos, d) {
        md = d;
        foldersOpen = false;
        confirmIndex = -1;
        build();
        var pos = item.mapToItem(menu, mousePos.x, mousePos.y);
        visible = true;
        Qt.callLater(function () {
            var tx = pos.x, ty = pos.y;
            menu.flipX = tx + menuCard.width > menu.width - 10;
            menu.flipY = ty + menuCard.height > menu.height - 10;
            if (menu.flipX) tx = Math.max(10, pos.x - menuCard.width);
            if (menu.flipY) ty = Math.max(10, pos.y - menuCard.height);
            menuCard.x = Math.round(Math.min(tx, menu.width - menuCard.width - 10));
            menuCard.y = Math.round(Math.min(ty, menu.height - menuCard.height - 10));
            openAnim.restart();
        });
    }
    property bool flipX: false
    property bool flipY: false

    function close() {
        visible = false;
        confirmIndex = -1;
    }

    Keys.onEscapePressed: close()

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: (mouse) => menu.close()
    }

    property real t: 1
    NumberAnimation { id: openAnim; target: menu; property: "t"; from: 0; to: 1; duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.2 }

    Rectangle {
        id: menuCard
        width: 256
        height: contentCol.implicitHeight + 12
        radius: 20
        color: menu.cBg
        border.color: menu.tint(0.10)
        border.width: 1
        transformOrigin: menu.flipY ? (menu.flipX ? Item.BottomRight : Item.BottomLeft) : (menu.flipX ? Item.TopRight : Item.TopLeft)
        scale: 0.82 + 0.18 * menu.t
        opacity: Math.min(1, menu.t * 1.4)

        layer.enabled: true
        layer.effect: MultiEffect { shadowEnabled: true; shadowBlur: 0.8; shadowOpacity: 0.45; shadowVerticalOffset: 4 }

        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onPressed: (mouse) => mouse.accepted = true }

        Column {
            id: contentCol
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 6
            spacing: 2

            // header: icon + name (+ "new")
            Item {
                width: parent.width
                height: 50
                Kirigami.Icon {
                    id: headIcon
                    anchors.left: parent.left; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter
                    width: 30; height: 30
                    source: menu.md.icon || ""
                }
                Text {
                    anchors.left: headIcon.right; anchors.leftMargin: 12; anchors.right: newPill.left; anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    text: menu.md.appName || ""
                    elide: Text.ElideRight
                    font.family: "Google Sans Flex"; font.pixelSize: 15; font.weight: Font.DemiBold
                    color: menu.fg
                }
                Rectangle {
                    id: newPill
                    visible: menu.md.isNew === true
                    anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                    width: visible ? newText.implicitWidth + 14 : 0; height: 22; radius: 11
                    color: appIndex.tertiary
                    Text { id: newText; anchors.centerIn: parent; text: menu.i18n("New"); font.family: "Google Sans Flex"; font.pixelSize: 11; font.weight: Font.DemiBold; color: appIndex.onTertiary }
                }
            }

            Repeater {
                model: menu.entries.length
                delegate: Loader {
                    id: rowLoader
                    required property int index
                    readonly property var entry: menu.entries[index]
                    width: contentCol.width
                    sourceComponent: entry.sep ? sepComp : (entry.move ? moveComp : actionComp)
                }
            }
        }
    }

    Component {
        id: sepComp
        Item {
            height: 9
            Rectangle { anchors.centerIn: parent; width: parent.width - 24; height: 1; color: menu.tint(0.10) }
        }
    }

    // ◀ ▶ reorder a pinned app
    Component {
        id: moveComp
        Item {
            height: 40
            Row {
                anchors.centerIn: parent
                spacing: 8
                Repeater {
                    model: [-1, 1]
                    delegate: Rectangle {
                        required property int modelData
                        width: 110; height: 34
                        radius: mvMa.pressed ? 10 : 17
                        color: mvMa.containsMouse ? menu.tint(0.12) : menu.tint(0.06)
                        Behavior on radius { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                        Item {
                            anchors.centerIn: parent
                            width: 18; height: 18
                            Image { id: mvImg; anchors.fill: parent; sourceSize: Qt.size(36, 36); visible: false
                                source: Qt.resolvedUrl(parent.parent.modelData < 0 ? "icons/arrow_back.svg" : "icons/arrow_right.svg") }
                            MultiEffect { anchors.fill: mvImg; source: mvImg; colorization: 1.0; colorizationColor: menu.fg }
                        }
                        MouseArea {
                            id: mvMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var from = menu.md.pinnedIndex, to = from + parent.modelData;
                                var fav = kicker.globalFavorites;
                                if (to >= 0 && to < fav.count) fav.moveRow(from, to);
                                menu.close();
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: actionComp
        Column {
            id: actCol
            readonly property var entry: parent ? parent.entry : ({})
            readonly property int entryIndex: parent ? parent.index : -1
            readonly property bool confirming: menu.confirmIndex === entryIndex
            spacing: 2

            Rectangle {
                width: actCol.width
                height: 40
                radius: actMa.pressed ? 10 : 14
                color: actCol.confirming ? menu.errorColor
                     : (actMa.pressed ? menu.tint(0.16) : (actMa.containsMouse ? menu.tint(0.10) : "transparent"))
                Behavior on radius { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
                Behavior on color { ColorAnimation { duration: 140 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 12
                    Item {
                        Layout.preferredWidth: 20
                        Layout.preferredHeight: 20
                        Image { id: actImg; anchors.fill: parent; sourceSize: Qt.size(40, 40); visible: false; source: actCol.entry.icon || "" }
                        MultiEffect {
                            anchors.fill: actImg; source: actImg; colorization: 1.0
                            colorizationColor: actCol.confirming ? (main.isDarkTheme ? "#690005" : "white") : (actCol.entry.danger ? menu.errorColor : menu.fg)
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: actCol.confirming ? actCol.entry.confirmText : (actCol.entry.text || "")
                        font.family: "Google Sans Flex"
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        color: actCol.confirming ? (main.isDarkTheme ? "#690005" : "white") : (actCol.entry.danger ? menu.errorColor : menu.fg)
                        elide: Text.ElideRight
                    }
                    Item {
                        visible: actCol.entry.folders === true
                        Layout.preferredWidth: 18; Layout.preferredHeight: 18
                        rotation: menu.foldersOpen ? 180 : 0
                        Behavior on rotation { NumberAnimation { duration: 240; easing.type: Easing.OutBack } }
                        Image { id: chevImg; anchors.fill: parent; sourceSize: Qt.size(36, 36); visible: false; source: Qt.resolvedUrl("icons/chevron_down.svg") }
                        MultiEffect { anchors.fill: chevImg; source: chevImg; colorization: 1.0; colorizationColor: menu.fg }
                    }
                }

                MouseArea {
                    id: actMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        var e = actCol.entry;
                        if (e.folders) { menu.foldersOpen = !menu.foldersOpen; return; }
                        if (e.confirmText && !actCol.confirming) { menu.confirmIndex = actCol.entryIndex; return; }
                        menu.close();
                        if (e.run) e.run();
                    }
                }
            }

            // "Add to folder" choices
            Column {
                visible: actCol.entry.folders === true && menu.foldersOpen
                width: actCol.width
                spacing: 2
                Repeater {
                    model: actCol.entry.folders === true ? appIndex.folders.length + 1 : 0
                    delegate: Rectangle {
                        required property int index
                        readonly property bool isNew: index === appIndex.folders.length
                        width: actCol.width
                        height: 34
                        radius: 12
                        color: fMa.containsMouse ? menu.tint(0.10) : menu.tint(0.04)
                        Text {
                            anchors.left: parent.left; anchors.leftMargin: 44; anchors.right: parent.right; anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: parent.isNew ? menu.i18n("New folder") : appIndex.folders[parent.index].name
                            elide: Text.ElideRight
                            font.family: "Google Sans Flex"; font.pixelSize: 12; font.weight: parent.isNew ? Font.DemiBold : Font.Normal
                            color: parent.isNew ? menu.accent : menu.fg
                        }
                        MouseArea {
                            id: fMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var d = menu.md;
                                if (d.isPinned) kicker.globalFavorites.removeFavorite(d.launcherUrlStr);
                                if (parent.isNew) appIndex.addToNewFolder(d.appId);
                                else appIndex.addToFolder(appIndex.folders[parent.index].id, d.appId);
                                root.toast(menu.i18n("Added to the folder"));
                                menu.close();
                            }
                        }
                    }
                }
            }
        }
    }
}

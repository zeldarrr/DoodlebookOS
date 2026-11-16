// SPDX-License-Identifier: GPL-3.0-or-later
// Opened folder: card that grows out of the folder tile, editable title, apps grid.
// Drag an app onto the dimmed area to take it out of the folder.
import QtQuick
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import "i18n.js" as I18n

Item {
    id: ov
    function i18n(k, a1, a2) { return I18n.t(k, a1, a2); }

    property string fid: ""
    property bool shown: false
    readonly property var folder: { var r = appIndex.revision; return fid.length ? appIndex.folderById(fid) : null; }
    readonly property var apps: folder ? folder.apps : []
    property point origin: Qt.point(width / 2, height / 2)

    readonly property color fg: Kirigami.Theme.textColor
    readonly property color accent: Kirigami.Theme.highlightColor

    function openFolder(id, item) {
        fid = id;
        if (item) origin = item.mapToItem(ov, item.width / 2, item.height / 2);
        title.text = folder ? folder.name : "";
        shown = true;
        closeAnim.stop();
        openAnim.restart();
        grid.forceActiveFocus();
    }
    function close() {
        if (!shown) return;
        commitTitle();
        shown = false;
        main.searchBar.textField.forceActiveFocus();
    }
    function commitTitle() {
        if (folder && title.text.trim().length && title.text !== folder.name) appIndex.renameFolder(fid, title.text);
    }
    onFolderChanged: if (shown && !folder) shown = false      // dissolved (last app removed)

    property real t: 0
    NumberAnimation { id: openAnim; target: ov; property: "t"; from: 0; to: 1; duration: 380; easing.type: Easing.OutBack; easing.overshoot: 1.0 }
    NumberAnimation { id: closeAnim; target: ov; property: "t"; to: 0; duration: 180; easing.type: Easing.InCubic }
    onShownChanged: if (!shown) closeAnim.restart()
    visible: t > 0.001
    enabled: shown

    // scrim (drop here = remove from folder)
    Rectangle {
        anchors.fill: parent
        radius: 20
        color: Qt.rgba(0, 0, 0, 0.42 * Math.min(1, ov.t))
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onClicked: ov.close() }
        DropArea {
            anchors.fill: parent
            onDropped: (ev) => {
                var src = kicker.dragSource.sourceId;
                if (src && kicker.dragSource.sourceFolder === ov.fid) {
                    ev.accept();
                    appIndex.removeFromFolder(ov.fid, src);
                }
            }
        }
    }

    Rectangle {
        id: card
        readonly property int cols: Math.min(5, Math.max(3, Math.ceil(Math.sqrt(ov.apps.length))))
        readonly property int rows: Math.max(1, Math.ceil(ov.apps.length / cols))
        width: Math.min(ov.width - 48, cols * root.cellSizeWidth + 40)
        height: 76 + rows * root.cellSizeHeight + 48
        radius: 28
        color: Qt.tint(Kirigami.Theme.backgroundColor, Qt.rgba(ov.accent.r, ov.accent.g, ov.accent.b, 0.10))
        border.width: 1
        border.color: Qt.rgba(ov.fg.r, ov.fg.g, ov.fg.b, 0.08)

        // grows from the folder tile to the centre
        readonly property real cx: ov.width / 2
        readonly property real cy: ov.height / 2
        x: (ov.origin.x + (cx - ov.origin.x) * Math.min(1, ov.t)) - width / 2
        y: (ov.origin.y + (cy - ov.origin.y) * Math.min(1, ov.t)) - height / 2
        scale: 0.35 + 0.65 * ov.t
        opacity: Math.min(1, ov.t * 1.6)

        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }    // keep clicks inside

        Row {
            id: titleRow
            anchors.top: parent.top
            anchors.topMargin: 22
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8
            TextInput {
                id: title
                width: Math.min(Math.max(contentWidth + 4, 60), card.width - 120)
                font.family: "Google Sans Flex"
                font.pixelSize: 20
                font.weight: Font.Medium
                color: ov.fg
                selectByMouse: true
                selectionColor: ov.accent
                horizontalAlignment: TextInput.AlignHCenter
                maximumLength: 40
                onAccepted: { ov.commitTitle(); grid.forceActiveFocus(); }
                Keys.onEscapePressed: { text = ov.folder ? ov.folder.name : text; ov.close(); }
                Rectangle {
                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.bottom; anchors.topMargin: 2
                    height: 2; radius: 1
                    color: ov.accent
                    opacity: title.activeFocus ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                }
            }
            Item {
                width: 18; height: 18
                anchors.verticalCenter: title.verticalCenter
                Image { id: pen; anchors.fill: parent; source: Qt.resolvedUrl("icons/edit.svg"); sourceSize: Qt.size(36, 36); visible: false }
                MultiEffect { anchors.fill: pen; source: pen; colorization: 1.0; colorizationColor: ov.fg; opacity: 0.6 }
                MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: { title.forceActiveFocus(); title.selectAll(); } }
            }
        }

        Grid {
            id: grid
            anchors.top: titleRow.bottom
            anchors.topMargin: 18
            anchors.horizontalCenter: parent.horizontalCenter
            columns: card.cols
            focus: true
            property int current: -1
            Keys.onPressed: (event) => {
                var n = ov.apps.length;
                if (event.key === Qt.Key_Escape) { ov.close(); event.accepted = true; return; }
                if (!n) return;
                var c = current < 0 ? 0 : current;
                if (event.key === Qt.Key_Right) c = Math.min(n - 1, c + 1);
                else if (event.key === Qt.Key_Left) c = Math.max(0, c - 1);
                else if (event.key === Qt.Key_Down) c = Math.min(n - 1, c + columns);
                else if (event.key === Qt.Key_Up) c = Math.max(0, c - columns);
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    if (current >= 0) appRepeater.itemAt(current).trigger();
                    event.accepted = true;
                    return;
                } else return;
                current = c;
                event.accepted = true;
            }
            Repeater {
                id: appRepeater
                model: ov.apps
                delegate: FavoriteItem {
                    required property string modelData
                    required property int index
                    forcedId: modelData
                    folderId: ov.fid
                    tileIndex: index
                    forceCurrent: grid.activeFocus && grid.current === index
                }
            }
        }

        // dissolve
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 12
            anchors.horizontalCenter: parent.horizontalCenter
            height: 30
            width: dissolveLabel.implicitWidth + 24
            radius: dissolveMa.pressed ? 8 : 15
            color: dissolveMa.containsMouse ? Qt.rgba(ov.fg.r, ov.fg.g, ov.fg.b, 0.10) : "transparent"
            Behavior on radius { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
            Text {
                id: dissolveLabel
                anchors.centerIn: parent
                text: ov.i18n("Ungroup")
                font.family: "Google Sans Flex"; font.pixelSize: 12; font.weight: Font.Medium
                color: Qt.rgba(ov.fg.r, ov.fg.g, ov.fg.b, 0.7)
            }
            MouseArea {
                id: dissolveMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { appIndex.deleteFolder(ov.fid); ov.close(); }
            }
        }
    }
}

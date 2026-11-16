// SPDX-License-Identifier: GPL-3.0-or-later
// Folder tile: tonal squircle with up to four app icons; opens the folder card, accepts dropped apps.
import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import "i18n.js" as I18n

Item {
    id: tile
    function i18n(k, a1, a2) { return I18n.t(k, a1, a2); }
    property var folder: null           // {id, name, apps}
    property int staggerIndex: 0
    width: root.cellSizeWidth
    height: root.cellSizeHeight

    readonly property color fg: Kirigami.Theme.textColor
    readonly property color accent: Kirigami.Theme.highlightColor
    readonly property var apps: folder ? folder.apps : []


    Rectangle {
        id: box
        anchors.top: parent.top
        anchors.topMargin: Kirigami.Units.smallSpacing * 2 - 3
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.iconSize + 6
        height: width
        radius: drop.containsDrag ? width * 0.5 : (ma.pressed ? width * 0.22 : width * 0.30)
        color: Qt.rgba(tile.accent.r, tile.accent.g, tile.accent.b, drop.containsDrag ? 0.34 : (ma.containsMouse ? 0.24 : 0.16))
        border.width: drop.containsDrag ? 2 : 0
        border.color: tile.accent
        scale: (drop.containsDrag ? 1.12 : (ma.pressed ? 0.9 : (ma.containsMouse ? 1.05 : 1)))
        Behavior on radius { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.5 } }
        Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2 } }
        Behavior on color { ColorAnimation { duration: 140 } }

        SequentialAnimation on rotation {
            running: root.editMode && tile.visible
            loops: Animation.Infinite
            NumberAnimation { to: 2; duration: 150; easing.type: Easing.InOutSine }
            NumberAnimation { to: -2; duration: 150; easing.type: Easing.InOutSine }
            onStopped: box.rotation = 0
        }

        Grid {
            anchors.centerIn: parent
            columns: 2
            spacing: 3
            Repeater {
                model: tile.apps.slice(0, 4)
                delegate: Kirigami.Icon {
                    required property string modelData
                    width: Math.round((box.width - 15) / 2)
                    height: width
                    source: { var r = appIndex.revision; if (appIndex.iconsBlank) return ""; return appIndex.iconFor(modelData); }
                }
            }
        }
    }

    PlasmaComponents.Label {
        anchors.top: box.bottom
        anchors.topMargin: Kirigami.Units.smallSpacing + 4
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Kirigami.Units.smallSpacing
        anchors.rightMargin: Kirigami.Units.smallSpacing
        horizontalAlignment: Text.AlignHCenter
        text: tile.folder ? tile.folder.name : ""
        elide: Text.ElideRight
        maximumLineCount: 1
        font.family: "Google Sans Flex"
        font.pixelSize: root.fullscreen ? 12 : 11
        font.weight: Font.DemiBold
        color: main.textColor
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: root.openFolder(tile.folder.id, box)
    }

    QQC2.ToolTip {
        visible: ma.containsMouse && tile.apps.length > 0
        delay: 600
        text: tile.i18n("%1 apps", tile.apps.length)
    }

    DropArea {
        id: drop
        anchors.fill: parent
        onDropped: (ev) => {
            var src = kicker.dragSource.sourceId;
            if (!src || !tile.folder) return;
            ev.accept();
            if (kicker.dragSource.sourcePinned >= 0) kicker.globalFavorites.removeFavorite("applications:" + src);
            appIndex.addToFolder(tile.folder.id, src);
        }
    }
}

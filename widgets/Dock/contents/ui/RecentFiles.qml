// SPDX-License-Identifier: GPL-3.0-or-later
// Recent files strip (KActivities recent documents): image previews, icons for the rest.
import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

ListView {
    id: strip
    readonly property color fg: Kirigami.Theme.textColor
    readonly property color accent: Kirigami.Theme.highlightColor
    function tint(a) { return Qt.rgba(fg.r, fg.g, fg.b, a); }

    orientation: ListView.Horizontal
    spacing: 8
    clip: true
    height: 64
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentWidth > width
    cacheBuffer: 0

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse
        onWheel: (ev) => {
            strip.contentX = Math.max(0, Math.min(strip.contentWidth - strip.width, strip.contentX - ev.angleDelta.y));
        }
    }

    delegate: Rectangle {
        id: card
        required property var model
        required property int index
        visible: index < 10
        width: visible ? 196 : 0
        height: 64
        radius: ma.pressed ? 14 : 18
        color: ma.containsMouse ? strip.tint(0.12) : strip.tint(0.06)
        Behavior on radius { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
        Behavior on color { ColorAnimation { duration: 120 } }
        scale: ma.pressed ? 0.96 : 1
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: 2 } }

        readonly property string fileUrl: model.url ? String(model.url) : ""
        readonly property bool isImage: /\.(png|jpe?g|webp|gif|bmp|avif)$/i.test(fileUrl)

        Item {
            id: thumbBox
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: 48; height: 48
            Image {
                id: thumb
                anchors.fill: parent
                visible: false                     // drawn through the rounded texture below
                source: card.isImage ? card.fileUrl : ""
                sourceSize: Qt.size(96, 96)
                asynchronous: true
                fillMode: Image.PreserveAspectCrop
                cache: true
            }
            // rounded thumbnail (a plain clip: true keeps square corners)
            Kirigami.ShadowedTexture {
                id: thumbClip
                anchors.fill: parent
                radius: 14
                color: strip.tint(0.08)
                source: thumb
                visible: card.isImage && thumb.status === Image.Ready
            }
            Kirigami.Icon {
                anchors.centerIn: parent
                width: 34; height: 34
                visible: !thumbClip.visible
                source: card.model.decoration
            }
        }

        Column {
            anchors.left: thumbBox.right
            anchors.leftMargin: 10
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Text {
                width: parent.width
                text: card.model.display || ""
                elide: Text.ElideMiddle
                font.family: "Google Sans Flex"; font.pixelSize: 12; font.weight: Font.Medium
                color: strip.fg
            }
            Text {
                width: parent.width
                text: card.model.description || ""
                visible: text.length > 0
                elide: Text.ElideLeft
                font.family: "Google Sans Flex"; font.pixelSize: 10
                color: strip.tint(0.55)
            }
        }

        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                strip.model.trigger(card.index, "", null);
                root.closeAfterLaunch();
            }
        }
        QQC2.ToolTip {
            visible: ma.containsMouse
            delay: 700
            text: card.fileUrl.replace("file://", "")
        }
    }
}

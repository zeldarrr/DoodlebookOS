/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: card
    property var games: []
    signal launch(string id)
    signal openLibrary()
    implicitWidth: 460
    implicitHeight: 250

    M3Colors { id: pal }

    Rectangle {
        anchors.fill: parent
        radius: 32
        color: pal.surface

        Item {
            id: header
            x: 20
            y: 14
            width: parent.width - 32
            height: 36
            Kirigami.Icon {
                id: hIcon
                anchors.verticalCenter: parent.verticalCenter
                width: 20
                height: 20
                source: "input-gaming"
                isMask: true
                color: pal.primary
            }
            Text {
                anchors.left: hIcon.right
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: "Jeux"
                font.family: pal.font
                font.pixelSize: 16
                font.weight: Font.DemiBold
                color: pal.surfaceText
            }
            Rectangle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: libText.implicitWidth + 24
                height: 30
                radius: 15
                color: libMa.pressed ? pal.statePress : (libMa.containsMouse ? pal.stateHover : "transparent")
                border.width: 1
                border.color: pal.outline
                Text {
                    id: libText
                    anchors.centerIn: parent
                    text: "Bibliothèque"
                    font.family: pal.font
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    color: pal.surfaceTextVariant
                }
                MouseArea { id: libMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: card.openLibrary() }
            }
        }

        ListView {
            id: list
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.top: header.bottom
            anchors.topMargin: 10
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 16
            orientation: ListView.Horizontal
            spacing: 12
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            reuseItems: true
            model: card.games
            visible: count > 0

            delegate: Item {
                id: tile
                required property var modelData
                readonly property bool hovered: tileMa.containsMouse
                height: list.height
                width: Math.round(height * 2 / 3)

                Rectangle {
                    id: frame
                    anchors.fill: parent
                    radius: tile.hovered ? 26 : 18
                    color: pal.surfaceHighest
                    clip: true
                    scale: tileMa.pressed ? 0.96 : 1
                    Behavior on radius { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    Behavior on scale { NumberAnimation { duration: 120 } }
                    Image {
                        anchors.fill: parent
                        source: tile.modelData.cover ? "file://" + tile.modelData.cover : ""
                        asynchronous: true
                        fillMode: Image.PreserveAspectCrop
                        sourceSize.height: Math.ceil(tile.height * 1.25)
                        visible: status === Image.Ready
                    }
                    // name over a scrim when there is no portrait cover (or on hover)
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: nameText.implicitHeight + 20
                        visible: !tile.modelData.portrait || tile.hovered
                        gradient: Gradient {
                            GradientStop { position: 0; color: "transparent" }
                            GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.72) }
                        }
                        Text {
                            id: nameText
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: 10
                            text: tile.modelData.name
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            font.family: pal.font
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            color: "white"
                        }
                    }
                    // play badge on hover
                    Rectangle {
                        anchors.centerIn: parent
                        width: 48
                        height: 48
                        radius: 16
                        color: pal.primary
                        opacity: tile.hovered ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 140 } }
                        Kirigami.Icon { anchors.centerIn: parent; width: 22; height: 22; source: "media-playback-start"; isMask: true; color: pal.primaryText }
                    }
                }
                MouseArea { id: tileMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: card.launch(tile.modelData.id) }
            }

            // vertical wheel scrolls the row
            WheelHandler {
                acceptedDevices: PointerDevice.Mouse
                onWheel: ev => {
                    var max = Math.max(0, list.contentWidth - list.width);
                    list.contentX = Math.max(0, Math.min(max, list.contentX - ev.angleDelta.y));
                }
            }
        }

        Text {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: 18
            visible: list.count === 0
            text: "Aucun jeu Steam installé"
            font.family: pal.font
            font.pixelSize: 14
            color: pal.surfaceTextVariant
        }
    }
}

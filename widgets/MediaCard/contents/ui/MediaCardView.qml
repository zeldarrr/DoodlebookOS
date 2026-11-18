/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: card
    property bool hasMedia: false
    property string track: ""
    property string artist: ""
    property string artUrl: ""
    property bool playing: false
    property real position: 0
    property real length: 0
    property bool canNext: false
    property bool canPrev: false
    signal playPause()
    signal next()
    signal prev()
    signal raise()

    implicitWidth: 400
    implicitHeight: 156

    M3Colors { id: pal }

    // tint the card with the cover's colours (computed off the GUI thread, once per cover)
    Kirigami.ImageColors {
        id: artColors
        source: art.status === Image.Ready ? art : null
    }
    readonly property bool tinted: art.status === Image.Ready && artColors.dominant.a > 0
    readonly property color cardColor: tinted ? pal.mix(pal.bg, artColors.dominant, pal.dark ? 0.32 : 0.22) : pal.surface
    // accent = cover hue at a fixed tone so the play button always contrasts with its icon
    readonly property color accent: tinted && artColors.dominant.hslHue >= 0
        ? Qt.hsla(artColors.dominant.hslHue, Math.max(0.45, artColors.dominant.hslSaturation), pal.dark ? 0.74 : 0.40, 1)
        : pal.primary

    Rectangle {
        anchors.fill: parent
        radius: 32
        color: card.cardColor
        Behavior on color { ColorAnimation { duration: Kirigami.Units.longDuration > 1 ? 300 : 0 } }

        // cover
        Rectangle {
            id: artBox
            x: 16
            anchors.verticalCenter: parent.verticalCenter
            width: parent.height - 32
            height: width
            radius: 22
            color: pal.surfaceHighest
            clip: true
            Image {
                id: art
                anchors.fill: parent
                source: card.artUrl
                visible: status === Image.Ready
                asynchronous: true
                cache: true
                fillMode: Image.PreserveAspectCrop
                sourceSize: Qt.size(256, 256)
            }
            Kirigami.Icon {
                anchors.centerIn: parent
                width: parent.width * 0.4
                height: width
                visible: !art.visible
                source: "music-note-16th"
                fallback: "view-media-track"
                isMask: true
                color: pal.surfaceTextVariant
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: card.raise() }
        }

        Item {
            anchors.left: artBox.right
            anchors.leftMargin: 18
            anchors.right: parent.right
            anchors.rightMargin: 20
            anchors.top: artBox.top
            anchors.bottom: artBox.bottom

            Text {
                id: title
                width: parent.width
                text: card.hasMedia ? card.track : "Rien en lecture"
                elide: Text.ElideRight
                font.family: pal.font
                font.pixelSize: 17
                font.weight: Font.DemiBold
                color: pal.surfaceText
            }
            Text {
                anchors.top: title.bottom
                anchors.topMargin: 2
                width: parent.width
                text: card.hasMedia ? card.artist : "Lance une musique ou une vidéo"
                elide: Text.ElideRight
                font.family: pal.font
                font.pixelSize: 13
                color: pal.surfaceTextVariant
            }

            // progress (M3 linear indicator: track + rounded active part)
            Item {
                id: progress
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: controls.top
                anchors.bottomMargin: 10
                height: 6
                visible: card.hasMedia && card.length > 0
                readonly property real frac: card.length > 0 ? Math.max(0, Math.min(1, card.position / card.length)) : 0
                Rectangle { anchors.fill: parent; radius: 3; color: pal.alpha(pal.surfaceText, 0.12) }
                Rectangle {
                    width: Math.max(height, parent.width * progress.frac)
                    height: parent.height
                    radius: 3
                    color: card.accent
                }
            }

            Row {
                id: controls
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                spacing: 10
                opacity: card.hasMedia ? 1 : 0.4
                enabled: card.hasMedia

                component Btn: Rectangle {
                    id: btn
                    property string icon: ""
                    property bool filled: false
                    signal clicked()
                    width: 44
                    height: 44
                    radius: ma.pressed ? 12 : height / 2
                    color: filled ? card.accent : (ma.containsMouse ? pal.stateHover : "transparent")
                    Behavior on radius { NumberAnimation { duration: Kirigami.Units.longDuration > 1 ? 160 : 0; easing.type: Easing.OutCubic } }
                    Kirigami.Icon {
                        anchors.centerIn: parent
                        width: 22
                        height: 22
                        source: btn.icon
                        isMask: true
                        color: btn.filled ? pal.primaryText : pal.surfaceText
                    }
                    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: btn.clicked() }
                }

                Btn { icon: "media-skip-backward"; opacity: card.canPrev ? 1 : 0.4; onClicked: card.prev() }
                // play / pause: pill when paused, rounded square when playing (M3 Expressive morph)
                Rectangle {
                    id: playBtn
                    width: 64
                    height: 44
                    radius: playMa.pressed ? 10 : (card.playing ? 14 : height / 2)
                    color: card.accent
                    Behavior on radius { NumberAnimation { duration: Kirigami.Units.longDuration > 1 ? 220 : 0; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
                    Kirigami.Icon {
                        anchors.centerIn: parent
                        width: 24
                        height: 24
                        source: card.playing ? "media-playback-pause" : "media-playback-start"
                        isMask: true
                        color: pal.primaryText
                    }
                    MouseArea { id: playMa; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: card.playPause() }
                }
                Btn { icon: "media-skip-forward"; opacity: card.canNext ? 1 : 0.4; onClicked: card.next() }
            }
        }
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Material 3 Expressive on-screen indicator (volume / brightness), Android 16 style:
// output-device button + vertical pill on the right edge. Never takes focus.
// Event-driven: show() is called from property-change signals; one single-shot Timer hides it.
import QtQuick
import QtQuick.Effects
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami

PlasmaCore.Dialog {
    id: osd

    property rect screenRect: Qt.rect(0, 0, 1920, 1080)
    property string kind: "volume"      // "volume" | "brightness"
    property real value: 0              // 0..1 (volume may go a bit above 1)
    property bool muted: false
    property string deviceName: ""
    property string deviceType: "speaker"   // "headphones" | "tv" | "speaker"
    readonly property bool showDevice: kind === "volume" && deviceName !== ""

    signal wheelStep(int dir)
    signal deviceClicked()

    type: PlasmaCore.Dialog.OnScreenDisplay
    location: PlasmaCore.Types.Floating
    flags: Qt.WindowDoesNotAcceptFocus | Qt.WindowStaysOnTopHint
    backgroundHints: PlasmaCore.Types.NoBackground
    visible: false
    x: screenRect.x + screenRect.width - width - 4
    y: screenRect.y + Math.round((screenRect.height - height) / 2)

    // Kirigami.Icon.isMask leaves plain local SVGs (fill #e3e3e3) untouched -> colourise them
    component MaskIcon: Item {
        id: mi
        property url source
        property color color
        Image { id: miImg; anchors.fill: parent; source: mi.source; sourceSize: Qt.size(48, 48); visible: false }
        MultiEffect { anchors.fill: parent; source: miImg; colorization: 1.0; colorizationColor: mi.color }
    }

    function show(k, v, m) {
        var wasShown = visible && !leave.running;
        kind = k;
        muted = Boolean(m);
        value = Math.max(0, v);
        if (!hover.hovered) hideTimer.restart();
        if (!wasShown) {
            leave.stop();
            visible = true;
            enter.restart();
        } else {
            pulse.restart();            // expressive "spring" on every step
        }
    }

    mainItem: Item {
        id: root
        // margins leave room for the slide overshoot and the pulse, so nothing gets clipped
        readonly property int pad: 16
        width: 64 + 2 * pad + 16
        height: column.height + 2 * pad

        readonly property color fg: Kirigami.Theme.textColor
        readonly property color accent: Kirigami.Theme.highlightColor
        // pastel Material You accents need a dark "on" colour, not the scheme's white
        readonly property color onAccent: (0.299 * accent.r + 0.587 * accent.g + 0.114 * accent.b) > 0.62 ? "#1d1a2c" : Kirigami.Theme.highlightedTextColor
        function tint(a) { return Qt.rgba(fg.r, fg.g, fg.b, a); }
        Kirigami.Theme.colorSet: Kirigami.Theme.Window
        Kirigami.Theme.inherit: false

        property real slide: 0          // 0 = in place, 1 = out (right)
        Timer { id: hideTimer; interval: 1600; onTriggered: leave.restart() }
        HoverHandler {
            id: hover
            onHoveredChanged: hovered ? hideTimer.stop() : hideTimer.restart()
        }

        Column {
            id: column
            x: root.pad + root.slide * 32
            y: root.pad
            width: 64
            spacing: 8
            opacity: 1 - root.slide

            // output device: tap to switch to the next one
            Rectangle {
                id: devBtn
                visible: osd.showDevice
                anchors.horizontalCenter: parent.horizontalCenter
                width: 52; height: 52
                radius: devMa.pressed ? 16 : 26
                color: devMa.containsMouse ? Qt.tint(Kirigami.Theme.backgroundColor, root.tint(0.08)) : Kirigami.Theme.backgroundColor
                border.width: 1
                border.color: root.tint(0.08)
                Behavior on radius { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                MaskIcon {
                    anchors.centerIn: parent
                    width: 22; height: 22
                    color: root.fg
                    source: osd.deviceType === "headphones" ? Qt.resolvedUrl("../quicksettings/icons/headphones.svg")
                          : osd.deviceType === "tv" ? Qt.resolvedUrl("../quicksettings/icons/monitor.svg")
                          : Qt.resolvedUrl("../quicksettings/icons/speaker.svg")
                }
                MouseArea { id: devMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: osd.deviceClicked() }
            }

            Rectangle {
                id: pill
                width: 64
                height: 232
                radius: 32
                color: Kirigami.Theme.backgroundColor
                border.width: 1
                border.color: root.tint(0.08)

                WheelHandler {
                    property int acc: 0
                    onWheel: (ev) => {
                        acc += ev.angleDelta.y;
                        while (acc >= 120) { osd.wheelStep(1); acc -= 120; }
                        while (acc <= -120) { osd.wheelStep(-1); acc += 120; }
                    }
                }

                Rectangle {
                    id: track
                    anchors.fill: parent
                    anchors.margins: 8
                    radius: 24
                    color: root.tint(0.10)

                    // M3 Expressive stop indicator
                    Rectangle {
                        width: 4; height: 4; radius: 2
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 10
                        color: root.tint(0.45)
                        visible: fill.height < track.height - 22
                    }

                    // active part grows from the bottom; never smaller than the icon circle
                    Rectangle {
                        id: fill
                        anchors.bottom: parent.bottom
                        width: parent.width
                        radius: 24
                        readonly property real ratio: osd.muted ? 0 : Math.min(1, osd.value)
                        height: Math.max(width, ratio * parent.height)
                        color: osd.muted ? root.tint(0.18) : root.accent
                        Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 160 } }
                    }

                    MaskIcon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 12
                        width: 24; height: 24
                        color: osd.muted ? root.fg : root.onAccent
                        source: osd.kind === "brightness" ? Qt.resolvedUrl("../quicksettings/icons/sun.svg")
                              : osd.muted || osd.value <= 0 ? Qt.resolvedUrl("../quicksettings/icons/volume_off.svg")
                              : osd.value < 0.5 ? Qt.resolvedUrl("../quicksettings/icons/volume_down.svg")
                              : Qt.resolvedUrl("../quicksettings/icons/volume_up.svg")
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 24
                    text: osd.muted ? "–" : Math.round(osd.value * 100)
                    font.family: "Google Sans Flex"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                    color: fill.height > track.height - 30 ? root.onAccent : root.fg
                }
            }

            // device name, small caption (2 lines max)
            Text {
                visible: osd.showDevice
                width: 64
                horizontalAlignment: Text.AlignHCenter
                text: osd.deviceName
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                font.family: "Google Sans Flex"
                font.pixelSize: 10
                color: root.fg
                style: Text.Outline
                styleColor: Qt.rgba(0, 0, 0, 0.35)
            }
        }

        // enter: slide + fade with a light overshoot; leave: quick ease-in, then unmap
        NumberAnimation { id: enter; target: root; property: "slide"; from: 1; to: 0; duration: 340; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
        SequentialAnimation {
            id: leave
            NumberAnimation { target: root; property: "slide"; to: 1; duration: 200; easing.type: Easing.InCubic }
            ScriptAction { script: osd.visible = false }
        }
        SequentialAnimation {
            id: pulse
            NumberAnimation { target: pill; property: "scale"; to: 1.035; duration: 70; easing.type: Easing.OutQuad }
            NumberAnimation { target: pill; property: "scale"; to: 1.0; duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2 }
        }
    }
}

/*
    SPDX-License-Identifier: GPL-3.0-or-later

    Android-style charging animation, played when the charger is plugged in: a ripple in the
    accent colour spreads from the middle of the screen while the battery level pops in on a
    spring, then everything fades. ~1.8 s, click-through (the window takes no input), built
    on demand by main.qml and destroyed when done.
*/
import QtQuick
import QtQuick.Window
import org.kde.kirigami as Kirigami
import org.kde.layershell as LayerShell
import "motion.js" as Motion

Window {
    id: win

    signal finished()

    flags: Qt.FramelessWindowHint | Qt.WindowTransparentForInput | Qt.WindowDoesNotAcceptFocus
    color: "transparent"
    visible: false

    LayerShell.Window.scope: "doodlebookos-charging"
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom
                               | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone

    property color accent: Kirigami.Theme.highlightColor
    property int percent: 0
    property real ms: 0

    function play(pct) {
        percent = Math.round(pct || 0);
        visible = true;
        ms = 0;
        driver.restart();
    }

    NumberAnimation {
        id: driver
        target: win; property: "ms"; from: 0; to: 1800; duration: 1800
        onFinished: { win.visible = false; win.finished(); }
    }

    // fade everything out over the last 350 ms
    readonly property real out: ms < 1450 ? 1 : Math.max(0, 1 - (ms - 1450) / 350)

    Rectangle {
        // ripple
        anchors.centerIn: parent
        // decelerating sweep (M3 emphasized-decelerate feel), ~1.1 s
        readonly property real k: 1 - Math.pow(1 - Math.min(1, win.ms / 1100), 3)
        width: Math.max(win.width, win.height) * 0.9 * k
        height: width
        radius: width / 2
        color: "transparent"
        border.width: 3 + 40 * (1 - k)
        border.color: Qt.rgba(win.accent.r, win.accent.g, win.accent.b, 0.55 * (1 - k))
    }

    Rectangle {
        id: badge
        anchors.centerIn: parent
        width: 168
        height: 168
        // Material shape morph: pill → circle as it settles
        radius: 40 + 44 * Motion.defaultSpatial(win.ms - 120)
        color: Qt.tint("#1c1b20", Qt.rgba(win.accent.r, win.accent.g, win.accent.b, 0.18))
        scale: 0.4 + 0.6 * Motion.fastSpatial(win.ms - 60)
        opacity: Motion.effects(win.ms - 40) * win.out

        Column {
            anchors.centerIn: parent
            spacing: 2
            Kirigami.Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 44
                height: 44
                source: Qt.resolvedUrl("quicksettings/icons/bolt.svg")
                isMask: true
                color: win.accent
                rotation: (1 - Motion.fastSpatial(win.ms - 160)) * -40
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: win.percent + " %"
                color: "white"
                font.family: "Google Sans Flex"
                font.pixelSize: 34
                font.variableAxes: { "wght": 420 + 180 * Motion.slowSpatial(win.ms - 200), "ROND": 100 }
            }
        }
    }
}

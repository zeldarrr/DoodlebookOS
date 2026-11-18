/*
    SPDX-License-Identifier: GPL-3.0-or-later

    Material 3 switch for the DoodlebookOS QML style (52×32 dp track scaled to the desktop):
    outlined track with a small grey thumb when off, filled primary track with a larger thumb and a
    check when on, thumb grows while pressed. Same look as the DoodlebookOS Qt widget style.
*/
import QtQuick
import QtQuick.Shapes
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

Item {
    id: indicator

    property T.AbstractButton control

    implicitHeight: Math.round(Kirigami.Units.gridUnit * 1.35)
    implicitWidth: Math.round(implicitHeight * 1.625)
    opacity: control && control.enabled ? 1 : 0.38
    layer.enabled: opacity < 1

    Kirigami.Theme.colorSet: Kirigami.Theme.Window
    Kirigami.Theme.inherit: false

    readonly property color primary: Kirigami.Theme.highlightColor
    readonly property color onPrimary: Kirigami.Theme.highlightedTextColor
    readonly property color outline: Kirigami.ColorUtils.linearInterpolation(Kirigami.Theme.backgroundColor, Kirigami.Theme.textColor, 0.55)
    readonly property color trackOff: Kirigami.ColorUtils.linearInterpolation(Kirigami.Theme.backgroundColor, Kirigami.Theme.textColor, 0.12)

    // 0 = off … 1 = on; follows the finger while dragging, springs otherwise
    property real pos: control ? control.visualPosition : 0
    Behavior on pos {
        enabled: indicator.control && !indicator.control.down && Kirigami.Units.longDuration > 1
        NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
    }

    function mix(a, b, t) { return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t); }
    readonly property real k: Math.max(0, Math.min(1, pos))      // colours don't overshoot

    Rectangle {
        id: track
        anchors.fill: parent
        radius: height / 2
        color: indicator.mix(indicator.trackOff, indicator.primary, indicator.k)
        border.width: 2 * (1 - indicator.k)
        border.color: indicator.mix(indicator.outline, indicator.primary, indicator.k)
    }

    Rectangle {
        id: thumb
        readonly property real base: indicator.height * (0.5 + 0.25 * indicator.k)
        width: indicator.control && indicator.control.down ? indicator.height * 0.875
             : base + (indicator.control && indicator.control.hovered ? indicator.height * 0.06 : 0)
        height: width
        radius: width / 2
        Behavior on width {
            enabled: Kirigami.Units.shortDuration > 1
            NumberAnimation { duration: Kirigami.Units.shortDuration; easing.type: Easing.OutCubic }
        }
        x: indicator.height / 2 + indicator.pos * (indicator.width - indicator.height) - width / 2
        y: (indicator.height - height) / 2
        color: indicator.mix(indicator.outline, indicator.onPrimary, indicator.k)

        Shape {
            anchors.centerIn: parent
            width: parent.width * 0.62
            height: width
            opacity: Math.max(0, (indicator.k - 0.4) / 0.6)
            visible: opacity > 0
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: indicator.primary
                strokeWidth: Math.max(1.6, indicator.height * 0.075)
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathPolyline {
                    readonly property real s: thumb.width * 0.62
                    path: [Qt.point(s * 0.14, s * 0.52), Qt.point(s * 0.40, s * 0.77), Qt.point(s * 0.88, s * 0.25)]
                }
            }
        }
    }
}

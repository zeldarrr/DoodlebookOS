/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
import QtQuick
import org.kde.kirigami as Kirigami
import QtQuick.Shapes

Item {
    id: card
    property real cpu: 0
    property real ram: 0
    property real gpu: 0
    property real cpuTemp: 0
    property real gpuTemp: 0
    property real ramUsedBytes: 0
    implicitWidth: 380
    implicitHeight: 196

    M3Colors { id: pal }

    function gib(b) { return (b / 1073741824).toLocaleString(Qt.locale(), "f", 1) + " Go"; }

    // M3 Expressive gauge: 270° track + value arc with round caps, drawn by the GPU (curve renderer)
    component Gauge: Item {
        id: g
        property real value: 0
        property string label: ""
        property string detail: ""
        property color tint: pal.primary
        readonly property real v: Math.max(0, Math.min(100, value))
        property real shown: v
        Behavior on shown { NumberAnimation { duration: Kirigami.Units.longDuration > 1 ? 280 : 0; easing.type: Easing.OutCubic } }
        width: 96
        height: 132

        Shape {
            id: ring
            anchors.horizontalCenter: parent.horizontalCenter
            width: 88
            height: 88
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: pal.surfaceHighest
                strokeWidth: 10
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc { centerX: 44; centerY: 44; radiusX: 38; radiusY: 38; startAngle: 135; sweepAngle: 270 }
            }
            ShapePath {
                strokeColor: g.v >= 90 ? pal.error : g.tint
                strokeWidth: 10
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc { centerX: 44; centerY: 44; radiusX: 38; radiusY: 38; startAngle: 135; sweepAngle: Math.max(0.5, 270 * g.shown / 100) }
            }
        }
        Text {
            anchors.centerIn: ring
            text: Math.round(g.v) + "%"
            font.family: pal.font
            font.pixelSize: 20
            font.weight: Font.DemiBold
            font.variableAxes: { "ROND": 100 }
            color: pal.surfaceText
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: ring.bottom
            anchors.topMargin: -6
            text: g.label
            font.family: pal.font
            font.pixelSize: 14
            font.weight: Font.Medium
            color: pal.surfaceText
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            text: g.detail
            visible: text.length > 0
            font.family: pal.font
            font.pixelSize: 12
            color: pal.surfaceTextVariant
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 32
        color: pal.surface

        Row {
            anchors.centerIn: parent
            spacing: 18
            Gauge {
                value: card.cpu
                label: "CPU"
                detail: card.cpuTemp > 0 ? Math.round(card.cpuTemp) + " °C" : ""
                tint: pal.primary
            }
            Gauge {
                value: card.ram
                label: "RAM"
                detail: card.ramUsedBytes > 0 ? card.gib(card.ramUsedBytes) : ""
                tint: pal.tertiary
            }
            Gauge {
                value: card.gpu
                label: "GPU"
                detail: card.gpuTemp > 0 ? Math.round(card.gpuTemp) + " °C" : ""
                tint: pal.secondary
            }
        }
    }
}

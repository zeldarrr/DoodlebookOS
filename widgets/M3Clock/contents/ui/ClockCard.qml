/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
import QtQuick

Item {
    id: card
    property var now: new Date()
    implicitWidth: 280
    implicitHeight: 280

    M3Colors { id: pal }
    readonly property real s: Math.min(width, height)
    readonly property string dateText: {
        var t = Qt.locale().toString(card.now, "dddd d MMMM");
        return t.charAt(0).toUpperCase() + t.slice(1);
    }

    Rectangle {
        anchors.centerIn: parent
        width: card.s
        height: card.s
        radius: card.s * 0.24
        color: pal.surface

        // hours on a tonal "cookie" pill, minutes underneath: Material You lock-screen clock
        Rectangle {
            id: hourPill
            anchors.horizontalCenter: parent.horizontalCenter
            y: card.s * 0.09
            width: card.s * 0.62
            height: card.s * 0.40
            radius: height / 2
            color: pal.primaryContainer
            Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: card.s * 0.005
                text: Qt.formatTime(card.now, "HH")
                font.family: pal.font
                font.pixelSize: card.s * 0.34
                font.weight: Font.DemiBold
                font.variableAxes: { "ROND": 100 }
                color: pal.primaryContainerText
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: hourPill.y + hourPill.height - card.s * 0.035
            text: Qt.formatTime(card.now, "mm")
            font.family: pal.font
            font.pixelSize: card.s * 0.34
            font.weight: Font.Normal
            font.variableAxes: { "ROND": 100 }
            color: pal.tertiary
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: card.s * 0.085
            width: parent.width - card.s * 0.16
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: card.dateText
            font.family: pal.font
            font.pixelSize: Math.max(11, card.s * 0.058)
            font.weight: Font.Medium
            color: pal.surfaceTextVariant
        }
    }
}

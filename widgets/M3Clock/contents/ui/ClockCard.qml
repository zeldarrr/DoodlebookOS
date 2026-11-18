/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: card
    property var now: new Date()
    readonly property bool anim: Kirigami.Units.longDuration > 1

    // digits roll up when they change (once a minute, ~450 ms): the old value leaves upwards,
    // the new one rises into place with the M3 "emphasized decelerate" curve
    component RollText: Item {
        id: roll
        property string text: ""
        property font font
        property color color
        property string previous: ""
        property real t: 1
        implicitWidth: cur.implicitWidth
        implicitHeight: cur.implicitHeight
        width: implicitWidth
        height: implicitHeight
        Component.onCompleted: cur.text = text      // initial values don't emit textChanged
        onTextChanged: {
            if (cur.text === "" || !card.anim) { cur.text = text; return; }
            if (cur.text === text) return;
            previous = cur.text;
            cur.text = text;
            rollAnim.restart();
        }
        NumberAnimation {
            id: rollAnim
            target: roll; property: "t"; from: 0; to: 1
            duration: 450
            easing.type: Easing.BezierSpline; easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1, 1]
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: -roll.t * roll.height * 0.22
            visible: roll.t < 1
            opacity: Math.max(0, 1 - roll.t * 2)
            text: roll.previous
            font: roll.font
            color: roll.color
        }
        Text {
            id: cur
            anchors.horizontalCenter: parent.horizontalCenter
            y: (1 - roll.t) * roll.height * 0.22
            opacity: roll.t
            font: roll.font
            color: roll.color
        }
    }
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
            RollText {
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
        RollText {
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

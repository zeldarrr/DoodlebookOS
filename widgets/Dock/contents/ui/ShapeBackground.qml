/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Material 3 Expressive shape behind a button. The outline comes from doodlebookos-m3icons
 * (~/.config/doodlebookos/shape.json, 0..100 box) so buttons and generated icons share it.
 * Drawn once by the curve renderer (GPU, crisp at any scale); hover only animates a rotation.
 */

import QtQuick
import org.kde.kirigami as Kirigami
import QtQuick.Shapes

Item {
    id: root

    property string pathData: ""
    property color color: "transparent"
    property color borderColor: "transparent"
    property real borderWidth: 0
    // one rotational step of the shape: turning by whole steps leaves it identical at rest
    property real turn: 0
    property bool hovered: false

    // whole steps only: the animated angle always lands on notches * turn, whatever the hover rhythm
    property int notches: 0
    onHoveredChanged: if (hovered && turn > 0) notches += 1
    // new outline: start upright, no spin carried over from the previous shape
    onPathDataChanged: reset()
    onTurnChanged: reset()
    function reset() {
        spinBehavior.enabled = false;
        notches = 0;                 // spin follows through its binding, without animation
        spinBehavior.enabled = true;
    }

    property real spin: notches * turn
    Behavior on spin {
        id: spinBehavior
        NumberAnimation { duration: Kirigami.Units.longDuration > 1 ? 420 : 0; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
    }

    readonly property real side: Math.min(width, height)

    Shape {
        anchors.centerIn: parent
        width: 100
        height: 100
        scale: root.side / 100
        rotation: root.spin
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: root.color
            strokeColor: root.borderWidth > 0 ? root.borderColor : "transparent"
            strokeWidth: root.borderWidth > 0 && root.side > 0 ? root.borderWidth * 100 / root.side : -1
            PathSvg { path: root.pathData }
        }
    }
}

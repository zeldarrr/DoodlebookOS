/*
    DoodlebookOS splash screen — Material 3 expressive.
    SPDX-License-Identifier: GPL-3.0-or-later
    Colours come from the active colour scheme (so Material You too). Every looping
    animation runs on the render thread (Animators) or on one tiny item: no CPU cost
    while Plasma is starting.
*/
import QtQuick
import org.kde.kirigami as Kirigami

Rectangle {
    id: root
    color: Kirigami.Theme.backgroundColor
    property int stage

    onStageChanged: {
        if (stage === 2) intro.start();
        else if (stage === 5) outro.start();
    }

    Item {
        id: content
        anchors.centerIn: parent
        width: 160
        height: 220
        opacity: 0
        scale: 0.9

        // logo inside a tonal "squircle" container
        Rectangle {
            id: badge
            anchors.horizontalCenter: parent.horizontalCenter
            width: 128
            height: 128
            radius: 40
            color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.22)
            Kirigami.Icon {
                anchors.centerIn: parent
                width: 72
                height: 72
                source: Qt.resolvedUrl("images/logo.svg")
                isMask: true
                color: Kirigami.Theme.highlightColor
            }
        }

        // M3 expressive loading indicator: a shape that spins and morphs
        Rectangle {
            id: loader
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            width: 40
            height: 40
            color: Kirigami.Theme.highlightColor
            radius: 20
            RotationAnimator on rotation { from: 0; to: 360; duration: 1400; loops: Animation.Infinite; running: root.visible }
            SequentialAnimation on radius {
                loops: Animation.Infinite
                running: root.visible
                NumberAnimation { to: 9; duration: 520; easing.type: Easing.InOutCubic }
                NumberAnimation { to: 20; duration: 520; easing.type: Easing.InOutCubic }
            }
        }
    }

    ParallelAnimation {
        id: intro
        OpacityAnimator { target: content; from: 0; to: 1; duration: 500; easing.type: Easing.OutCubic }
        ScaleAnimator { target: content; from: 0.9; to: 1; duration: 700; easing.type: Easing.OutQuart }
    }
    OpacityAnimator { id: outro; target: content; to: 0; duration: 250; easing.type: Easing.InCubic }
}

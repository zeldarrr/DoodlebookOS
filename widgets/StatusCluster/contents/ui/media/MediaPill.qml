/*
    SPDX-FileCopyrightText: 2026 DoodlebookOS
    SPDX-License-Identifier: GPL-3.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kirigami as Kirigami

Rectangle {
    id: mediaPillButton

    required property var appletRoot
    required property var mediaBackend
    required property bool expanded

    visible: mediaBackend.effectiveVisible && mediaBackend.hasMedia
    height: appletRoot.railHeight
    radius: height / 2

    readonly property bool isPillHovered: mediaMouse.containsMouse || ppMouse.containsMouse
    width: visible ? appletRoot.snap(126.4) : 0
    implicitWidth: width
    implicitHeight: height

    readonly property bool isExpanded: expanded
    readonly property color pillSurfaceColor: isExpanded ? appletRoot.effectiveAccentColor : "#000000"

    color: pillSurfaceColor

    border.color: isExpanded ? "transparent" : "#42494f"
    border.width: appletRoot.snap(1.6)

    Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }
    Behavior on border.color { ColorAnimation { duration: Kirigami.Units.shortDuration } }

    property bool mediaWasOpen: false

    MouseArea {
        id: mediaMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

        onPressed: mouse => {
            mediaPillButton.mediaWasOpen = mediaPillButton.isExpanded;
        }

        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton) {
                mediaPillButton.mediaBackend.togglePlaying();
            } else if (mouse.button === Qt.LeftButton) {
                if (mediaPillButton.mediaWasOpen) {
                    mediaPillButton.appletRoot.closeAllPopups();
                } else {
                    mediaPillButton.appletRoot.requestTogglePopup("media");
                }
            }
        }

        onWheel: wheel => {
            var delta = (wheel.inverted ? -1 : 1) * (wheel.angleDelta.y ? wheel.angleDelta.y : -wheel.angleDelta.x);
            if (delta > 0) mediaPillButton.mediaBackend.changeVolume(0.05);
            else if (delta < 0) mediaPillButton.mediaBackend.changeVolume(-0.05);
        }
    }

    // Left play/pause circular button
    Rectangle {
        id: playPauseCircle
        anchors.left: parent.left
        anchors.leftMargin: mediaPillButton.appletRoot.snap(4.8)
        anchors.verticalCenter: parent.verticalCenter
        readonly property real baseTargetSize: mediaPillButton.appletRoot.snap(mediaPillButton.appletRoot.effectiveHeight * 0.45)
        width: baseTargetSize
        height: width
        radius: width / 2
        color: mediaPillButton.isExpanded
            ? mediaPillButton.appletRoot.highlightedContentColor
            : (mediaPillButton.isPillHovered ? (mediaPillButton.appletRoot.isLightContent ? "#ffffff" : "#18181c") : "transparent")
        Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }

        scale: ppMouse.pressed ? 0.92 : (ppMouse.containsMouse ? 1.08 : 1.0)
        Behavior on scale { NumberAnimation { duration: Kirigami.Units.shortDuration; easing.type: Easing.OutQuad } }

        // App Logo (stan spoczynku: widoczny, gdy NIE najechano i NIE jest otwarte okno)
        Kirigami.Icon {
            id: appLogoIcon
            anchors.fill: parent
            source: mediaPillButton.mediaBackend.appIcon
            opacity: (mediaPillButton.isPillHovered || mediaPillButton.isExpanded) ? 0.0 : 1.0
            visible: opacity > 0.0
            Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }
        }

        // Play/Pause Icon (widoczny, gdy najechano LUB otwarte jest okno dialogowe)
        PlayPauseIcon {
            id: playPauseSymbol
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: mediaPillButton.mediaBackend.isPlaying ? 0 : mediaPillButton.appletRoot.snap(0.8)
            isPlaying: mediaPillButton.mediaBackend.isPlaying
            iconSize: mediaPillButton.appletRoot.snap(playPauseCircle.baseTargetSize * 0.5)
            color: mediaPillButton.isExpanded
                ? mediaPillButton.appletRoot.effectiveAccentColor
                : (mediaPillButton.appletRoot.isLightContent ? "#18181c" : "#ffffff")
            opacity: (mediaPillButton.isPillHovered || mediaPillButton.isExpanded) ? 1.0 : 0.0
            visible: opacity > 0.0
            Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }
        }

        MouseArea {
            id: ppMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: {
                mediaPillButton.mediaBackend.togglePlaying();
            }
        }
    }

    // Scrolling Title Text
    MarqueeText {
        id: marqueeTitle
        anchors.left: playPauseCircle.right
        anchors.leftMargin: mediaPillButton.appletRoot.snap(5.6)
        anchors.right: parent.right
        anchors.rightMargin: mediaPillButton.appletRoot.snap(7.2)
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: mediaPillButton.appletRoot.snap(0.8)
        height: parent.height

        text: mediaPillButton.mediaBackend.track
        font.family: "Google Sans Flex"
        font.weight: Font.DemiBold
        font.pixelSize: mediaPillButton.appletRoot.snap(mediaPillButton.appletRoot.effectiveHeight * 0.40)
        color: mediaPillButton.isExpanded
            ? mediaPillButton.appletRoot.highlightedContentColor
            : "#e0e6ee"
        scrollOnClickOnly: false
        scrollOnHoverOnly: true
        hovered: mediaPillButton.isPillHovered
    }

    // Left fade overlay (visible when text is scrolled to the left)
    Rectangle {
        anchors.left: marqueeTitle.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.topMargin: mediaPillButton.border.width
        anchors.bottomMargin: mediaPillButton.border.width
        width: mediaPillButton.appletRoot.snap(14.4)
        z: 5
        opacity: (marqueeTitle.textOffset < -1.0) ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }

        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: mediaPillButton.pillSurfaceColor }
            GradientStop { position: 1.0; color: "#00000000" }
        }
    }

    // Right fade overlay (visible when text overflows the right boundary)
    Rectangle {
        anchors.right: parent.right
        anchors.rightMargin: mediaPillButton.border.width
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.topMargin: mediaPillButton.border.width
        anchors.bottomMargin: mediaPillButton.border.width
        width: mediaPillButton.appletRoot.snap(14.4)
        radius: height / 2
        z: 5
        opacity: marqueeTitle.overflowing ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }

        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "#00000000" }
            GradientStop { position: 0.85; color: mediaPillButton.pillSurfaceColor }
            GradientStop { position: 1.0; color: mediaPillButton.pillSurfaceColor }
        }
    }
}

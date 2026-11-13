/*
    SPDX-FileCopyrightText: 2026 DoodlebookOS
    SPDX-License-Identifier: GPL-3.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: buttonRoot

    property url iconSource
    property real railHeight: 21.6
    property real iconSize: 12.8
    property real dpr: 1.0
    property color highlightCapsuleColor: Kirigami.Theme.highlightColor
    property color contentColor: "#ffffff"
    property color highlightedContentColor: Kirigami.Theme.highlightedTextColor
    property bool expanded: false

    signal clicked(bool wasExpanded)

    function snapPx(val) {
        return Math.round(val * dpr) / dpr;
    }

    readonly property bool isActive: buttonMouse.pressed || expanded
    readonly property bool isHovered: buttonMouse.containsMouse && !isActive

    height: railHeight
    width: height
    implicitWidth: width
    implicitHeight: height

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: buttonRoot.highlightCapsuleColor
        opacity: buttonRoot.isActive ? 1.0 : (buttonRoot.isHovered ? 0.25 : 0.0)
        Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }
    }

    StatusIcon {
        id: buttonIcon
        x: buttonRoot.snapPx((buttonRoot.width - width) / 2)
        y: buttonRoot.snapPx((buttonRoot.height - height) / 2)
        source: buttonRoot.iconSource
        dpr: buttonRoot.dpr
        iconHeight: buttonRoot.iconSize
        color: buttonRoot.isActive ? buttonRoot.highlightedContentColor : buttonRoot.contentColor
    }

    property bool _wasExpandedOnPress: false

    MouseArea {
        id: buttonMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton

        onPressed: {
            buttonRoot._wasExpandedOnPress = buttonRoot.expanded;
        }

        onClicked: {
            buttonRoot.clicked(buttonRoot._wasExpandedOnPress);
        }
    }
}

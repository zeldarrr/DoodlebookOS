/*
    SPDX-FileCopyrightText: 2026 DoodlebookOS
    SPDX-License-Identifier: GPL-3.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kirigami as Kirigami
import "../components" as Components

Item {
    id: notifBellButton

    required property var appletRoot
    required property bool expanded

    height: appletRoot.railHeight
    width: height
    implicitWidth: width
    implicitHeight: height

    readonly property bool isActive: notifMouse.pressed || expanded
    readonly property bool isHovered: notifMouse.containsMouse && !isActive

    // Background highlight capsule
    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: notifBellButton.appletRoot.highlightCapsuleColor
        opacity: notifBellButton.isActive ? 1.0 : (notifBellButton.isHovered ? 0.25 : 0.0)
        Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }
    }

    Components.StatusIcon {
        id: bellIcon
        x: notifBellButton.appletRoot.snap((notifBellButton.width - width) / 2)
        y: notifBellButton.appletRoot.snap((notifBellButton.height - height) / 2)
        dpr: notifBellButton.appletRoot.dpr
        iconHeight: notifBellButton.appletRoot.barPx(13.0, 36.0)
        preserveSvgAspect: true
        source: (notifBellButton.appletRoot.unreadNotifCount > 0)
            ? (notifBellButton.appletRoot.isLightContent
                ? Qt.resolvedUrl("icons/notifications_unread.svg")
                : Qt.resolvedUrl("icons/notifications_unread_dark.svg"))
            : Qt.resolvedUrl("icons/notifications.svg")
        colorize: notifBellButton.isActive || notifBellButton.appletRoot.unreadNotifCount === 0
        color: notifBellButton.isActive
            ? notifBellButton.appletRoot.highlightedContentColor
            : notifBellButton.appletRoot.topBarContentColor
    }

    property bool notifWasOpen: false

    MouseArea {
        id: notifMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

        onPressed: mouse => {
            notifBellButton.notifWasOpen = notifBellButton.expanded;
        }

        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton) {
                notifBellButton.appletRoot.toggleDoNotDisturbMode();
            } else if (mouse.button === Qt.LeftButton) {
                if (notifBellButton.notifWasOpen) {
                    notifBellButton.appletRoot.closeAllPopups();
                } else {
                    notifBellButton.appletRoot.requestTogglePopup("notif");
                }
            }
        }
    }
}

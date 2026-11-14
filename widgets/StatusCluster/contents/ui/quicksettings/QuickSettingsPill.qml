/*
    SPDX-FileCopyrightText: 2026 DoodlebookOS
    SPDX-License-Identifier: GPL-3.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kirigami as Kirigami
import "../components" as Components

Item {
    id: qsPillButton

    required property var appletRoot
    required property bool expanded

    readonly property real qsPadding: appletRoot.snap(appletRoot.effectiveHeight * 0.175) // 7 px on each side and between icons
    readonly property real qsIconH: appletRoot.qsIconHeight // 16 px box -> 14x15 BT, 15x15 DND, 20x15 Wi-Fi & 15 px Battery centered on y=13..27

    height: appletRoot.railHeight // Normalized Quick Settings pill height
    width: qsPadding + qsIconsRow.implicitWidth + qsPadding
    implicitWidth: width
    implicitHeight: height

    readonly property bool isActive: qsMouse.pressed || expanded
    readonly property bool isHovered: qsMouse.containsMouse && !isActive

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: qsPillButton.appletRoot.highlightCapsuleColor
        opacity: qsPillButton.isActive ? 1.0 : (qsPillButton.isHovered ? 0.25 : 0.0)
        Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }
    }

    Row {
        id: qsIconsRow
        x: qsPillButton.appletRoot.snap((qsPillButton.width - width) / 2)
        y: qsPillButton.appletRoot.snap((qsPillButton.height - height) / 2)
        spacing: qsPillButton.appletRoot.qsIconSpacing

        Components.StatusIcon {
            visible: qsPillButton.appletRoot.hasConnectedBluetoothDevice
            source: Qt.resolvedUrl("icons/bluetooth_connected_tray.svg")
            dpr: qsPillButton.appletRoot.dpr
            iconHeight: qsPillButton.qsIconH
            preserveSvgAspect: true
            color: qsPillButton.isActive
                ? qsPillButton.appletRoot.highlightedContentColor
                : qsPillButton.appletRoot.topBarContentColor
        }

        Components.StatusIcon {
            visible: qsPillButton.appletRoot.isDndActive
            source: Qt.resolvedUrl("icons/dnd_tray.svg")
            dpr: qsPillButton.appletRoot.dpr
            iconHeight: qsPillButton.qsIconH
            preserveSvgAspect: true
            color: qsPillButton.isActive
                ? qsPillButton.appletRoot.highlightedContentColor
                : qsPillButton.appletRoot.topBarContentColor
        }

        Components.StatusIcon {
            source: qsPillButton.appletRoot.currentWifiIcon
            dpr: qsPillButton.appletRoot.dpr
            iconHeight: qsPillButton.qsIconH
            preserveSvgAspect: true
            color: qsPillButton.isActive
                ? qsPillButton.appletRoot.highlightedContentColor
                : qsPillButton.appletRoot.topBarContentColor
        }

        Item {
            id: batteryTrayWrapper
            readonly property real tightLeftOffset: Math.max(1.0 / qsPillButton.appletRoot.dpr, qsPillButton.appletRoot.snap(qsPillButton.appletRoot.effectiveHeight * 0.025))
            width: batteryTrayIcon.width - batteryTrayWrapper.tightLeftOffset
            height: batteryTrayIcon.height

            Components.StatusIcon {
                id: batteryTrayIcon
                x: -batteryTrayWrapper.tightLeftOffset
                source: qsPillButton.appletRoot.currentBatteryIcon
                dpr: qsPillButton.appletRoot.dpr
                iconHeight: qsPillButton.qsIconH
                preserveSvgAspect: true
                color: qsPillButton.isActive
                    ? qsPillButton.appletRoot.highlightedContentColor
                    : qsPillButton.appletRoot.topBarContentColor
            }
        }
    }

    property bool qsWasOpen: false

    MouseArea {
        id: qsMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        onPressed: mouse => {
            qsPillButton.qsWasOpen = qsPillButton.expanded;
        }

        onClicked: mouse => {
            if (mouse.button === Qt.LeftButton) {
                if (qsPillButton.qsWasOpen) {
                    qsPillButton.appletRoot.closeAllPopups();
                } else {
                    qsPillButton.appletRoot.requestTogglePopup("qs");
                }
            }
        }
    }
}

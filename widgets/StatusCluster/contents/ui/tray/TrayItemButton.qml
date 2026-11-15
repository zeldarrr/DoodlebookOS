/*
    SPDX-FileCopyrightText: 2026 Maciej Kujawiński <maciek.kujawinski@gmail.com>
    SPDX-License-Identifier: GPL-3.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

Item {
    id: buttonRoot

    required property var appletRoot
    required property var trayBackend
    required property var itemData
    property bool expanded: false

    readonly property real iconSize: appletRoot.qsIconHeight
    readonly property bool isActive: itemMouse.pressed || expanded
    readonly property bool isHovered: itemMouse.containsMouse && !isActive
    readonly property bool needsAttention: String(itemData ? itemData.status : "") === "NeedsAttention"

    height: appletRoot.railHeight
    width: height
    implicitWidth: width
    implicitHeight: height

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: buttonRoot.appletRoot.highlightCapsuleColor
        opacity: buttonRoot.isActive ? 1.0 : (buttonRoot.isHovered ? 0.25 : 0.0)
        Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }
    }

    Item {
        id: iconHolder
        x: buttonRoot.appletRoot.snap((buttonRoot.width - width) / 2)
        y: buttonRoot.appletRoot.snap((buttonRoot.height - height) / 2)
        width: buttonRoot.appletRoot.snap(buttonRoot.iconSize)
        height: width

        readonly property url resolvedIconPath: (buttonRoot.itemData && buttonRoot.itemData.iconPath)
            ? buttonRoot.itemData.iconPath
            : ""

        Image {
            id: appImage
            anchors.fill: parent
            visible: iconHolder.resolvedIconPath.toString().length > 0 && status === Image.Ready
            source: iconHolder.resolvedIconPath
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
            asynchronous: true
            sourceSize: Qt.size(
                Math.max(16, Math.round(iconHolder.width * buttonRoot.appletRoot.dpr)),
                Math.max(16, Math.round(iconHolder.height * buttonRoot.appletRoot.dpr))
            )
        }

        Kirigami.Icon {
            id: fallbackIcon
            anchors.fill: parent
            visible: !appImage.visible
            isMask: false
            source: (buttonRoot.itemData && buttonRoot.itemData.iconName)
                ? buttonRoot.itemData.iconName
                : "application-x-executable"
        }
    }

    Rectangle {
        id: attentionDot
        visible: buttonRoot.needsAttention
        width: buttonRoot.appletRoot.legacyDp(4.8)
        height: width
        radius: width / 2
        x: buttonRoot.appletRoot.snap(iconHolder.x + iconHolder.width - width + buttonRoot.appletRoot.legacyDp(1.6))
        y: buttonRoot.appletRoot.snap(iconHolder.y + iconHolder.height - height + buttonRoot.appletRoot.legacyDp(1.6))
        color: buttonRoot.appletRoot.effectiveAccentColor
        border.width: 1
        border.color: buttonRoot.appletRoot.isLightContent ? Qt.rgba(0, 0, 0, 0.35) : Qt.rgba(255, 255, 255, 0.45)
    }

    property bool _wasExpandedOnPress: false

    PlasmaCore.ToolTipArea {
        id: tooltipArea
        anchors.fill: parent
        active: !buttonRoot.expanded && !itemMouse.pressed
        interactive: false
        location: Plasmoid.location
        mainText: (buttonRoot.itemData && buttonRoot.itemData.tooltipTitle)
            ? buttonRoot.itemData.tooltipTitle
            : ((buttonRoot.itemData && buttonRoot.itemData.displayTitle) ? buttonRoot.itemData.displayTitle : "")
        subText: (buttonRoot.itemData && buttonRoot.itemData.tooltipSubtitle) ? buttonRoot.itemData.tooltipSubtitle : ""

        MouseArea {
            id: itemMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

            onPressed: _mouse => {
                buttonRoot._wasExpandedOnPress = buttonRoot.expanded;
            }

            onClicked: mouse => {
                if (!buttonRoot.itemData) {
                    return;
                }
                var globalPt = buttonRoot.mapToGlobal(mouse.x, mouse.y);
                var gx = Math.round(globalPt.x);
                var gy = Math.round(globalPt.y);

                if (mouse.button === Qt.MiddleButton) {
                    buttonRoot.trayBackend.secondaryActivateItem(buttonRoot.itemData.key, gx, gy);
                    return;
                }

                if (mouse.button === Qt.RightButton) {
                    if (buttonRoot.itemData.hasMenu) {
                        buttonRoot.appletRoot.requestOpenTrayMenu(buttonRoot.itemData, buttonRoot, buttonRoot._wasExpandedOnPress);
                    } else {
                        buttonRoot.appletRoot.closeAllPopups();
                        buttonRoot.trayBackend.contextMenuItem(buttonRoot.itemData.key, gx, gy);
                    }
                    return;
                }

                if (mouse.button === Qt.LeftButton) {
                    if (buttonRoot.itemData.itemIsMenu && buttonRoot.itemData.hasMenu) {
                        buttonRoot.appletRoot.requestOpenTrayMenu(buttonRoot.itemData, buttonRoot, buttonRoot._wasExpandedOnPress);
                    } else if (buttonRoot.itemData.itemIsMenu) {
                        buttonRoot.appletRoot.closeAllPopups();
                        buttonRoot.trayBackend.contextMenuItem(buttonRoot.itemData.key, gx, gy);
                    } else {
                        buttonRoot.appletRoot.closeAllPopups();
                        buttonRoot.trayBackend.activateItem(buttonRoot.itemData.key, gx, gy);
                    }
                }
            }
        }
    }

    WheelHandler {
        id: itemWheel
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            if (!buttonRoot.itemData) {
                return;
            }
            if (event.angleDelta.y !== 0) {
                buttonRoot.trayBackend.scrollItem(buttonRoot.itemData.key, event.angleDelta.y, "vertical");
            } else if (event.angleDelta.x !== 0) {
                buttonRoot.trayBackend.scrollItem(buttonRoot.itemData.key, event.angleDelta.x, "horizontal");
            }
        }
    }
}

/*
 * SPDX-FileCopyrightText: 2024-2026 Maciej Kujawiński <maciek.kujawinski@gmail.com>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

Item {
    id: launcherBtn

    property bool active: false
    property real buttonHeight: 52
    property bool isVertical: false
    property string customIcon: (typeof Plasmoid !== "undefined" && Plasmoid.configuration && Plasmoid.configuration.launcherIcon) ? Plasmoid.configuration.launcherIcon : ""
    signal clicked()
    signal rightClicked(var mouse)

    readonly property real dpr: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1.0
    readonly property real effectiveBase: launcherBtn.isVertical ? launcherBtn.width : launcherBtn.buttonHeight
    function snap(val) {
        return Math.round(val * dpr) / dpr;
    }

    readonly property real capsuleHeight: snap(effectiveBase * 0.73)
    readonly property real capsuleWidth: snap(effectiveBase * 1.20)
    readonly property real capsuleTopMargin: snap(effectiveBase * 0.12)
    readonly property real iconSize: snap(effectiveBase * 0.37)

    readonly property bool shaped: appIndex.shapeName !== "circle" && appIndex.shapePath.length > 0
    implicitWidth: launcherBtn.isVertical ? launcherBtn.buttonHeight : (launcherBtn.shaped ? launcherBtn.buttonHeight * 0.92 : launcherBtn.capsuleWidth)
    implicitHeight: launcherBtn.isVertical ? (launcherBtn.shaped ? launcherBtn.buttonHeight * 0.92 : launcherBtn.capsuleWidth) : launcherBtn.buttonHeight
    width: launcherBtn.implicitWidth
    height: launcherBtn.implicitHeight
    Layout.preferredWidth: launcherBtn.implicitWidth
    Layout.preferredHeight: launcherBtn.implicitHeight
    Layout.alignment: Qt.AlignVCenter

    readonly property bool isDarkTheme: Kirigami.Theme.textColor.r > 0.5 || Kirigami.Theme.textColor.g > 0.5 || Kirigami.Theme.textColor.b > 0.5

    Rectangle {
        id: capsuleBg
        y: launcherBtn.shaped ? (launcherBtn.height - height) / 2 : launcherBtn.capsuleTopMargin
        anchors.horizontalCenter: parent.horizontalCenter
        width: launcherBtn.shaped ? launcherBtn.capsuleHeight * 1.08 : (launcherBtn.isVertical ? launcherBtn.capsuleHeight : launcherBtn.capsuleWidth)
        height: launcherBtn.shaped ? launcherBtn.capsuleHeight * 1.08 : (launcherBtn.isVertical ? launcherBtn.capsuleWidth : launcherBtn.capsuleHeight)
        radius: (launcherBtn.isVertical ? launcherBtn.capsuleWidth : launcherBtn.capsuleHeight) / 2

        Kirigami.Theme.colorSet: Kirigami.Theme.Header
        Kirigami.Theme.inherit: false
        // same tonal colours as the Material You app icons when they are generated
        readonly property color baseColor: appIndex.hasIconColors ? appIndex.iconBg : Kirigami.Theme.backgroundColor
        readonly property color baseIconColor: appIndex.hasIconColors ? appIndex.iconFg : Kirigami.Theme.textColor
        readonly property color activeColor: Kirigami.Theme.highlightColor
        readonly property color activeIconColor: Kirigami.Theme.highlightedTextColor

        property color fillColor: {
            if (launcherBtn.active) {
                return mouseArea.pressed ? Qt.darker(activeColor, 1.1) : activeColor;
            }
            if (mouseArea.pressed) {
                return Qt.lighter(baseColor, 1.35);
            }
            if (mouseArea.containsMouse) {
                return Qt.lighter(baseColor, 1.15);
            }
            return baseColor;
        }

        color: launcherBtn.shaped ? "transparent" : fillColor
        border.color: {
            if (launcherBtn.active) {
                return activeColor;
            }
            return launcherBtn.isDarkTheme ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.04);
        }
        border.width: launcherBtn.shaped ? 0 : 1

        Behavior on fillColor {
            ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
        }

        ShapeBackground {
            anchors.fill: parent
            visible: launcherBtn.shaped
            pathData: appIndex.shapePath
            turn: appIndex.shapeTurn
            color: capsuleBg.fillColor
            hovered: mouseArea.containsMouse
            scale: mouseArea.pressed ? 0.9 : 1
            Behavior on scale { SpringAnimation { spring: 4; damping: 0.3; epsilon: 0.005 } }
        }

        Kirigami.Icon {
            id: coloredIcon
            anchors.centerIn: parent
            width: launcherBtn.iconSize
            height: launcherBtn.iconSize
            source: launcherBtn.customIcon && launcherBtn.customIcon.length > 0 ? launcherBtn.customIcon : Qt.resolvedUrl("icons/launcher_d.svg")
            isMask: true
            color: launcherBtn.active ? capsuleBg.activeIconColor : capsuleBg.baseIconColor
            roundToIconSize: false

            Behavior on scale {
                NumberAnimation { duration: 100; easing.type: Easing.OutQuad }
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: mouse => {
            if (mouse.button === Qt.RightButton) {
                mouse.accepted = true;
            }
        }
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                launcherBtn.rightClicked(mouse);
            } else {
                launcherBtn.clicked();
            }
        }
    }
}

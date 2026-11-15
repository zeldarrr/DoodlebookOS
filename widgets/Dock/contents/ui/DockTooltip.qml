/*
 * SPDX-FileCopyrightText: 2024-2026 Maciej Kujawiński <maciek.kujawinski@gmail.com>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import QtQuick
import QtQuick.Shapes
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import "metrics" as LocalMetrics

PlasmaCore.Dialog {
    id: tooltipDialog

    type: PlasmaCore.Dialog.Tooltip
    flags: Qt.ToolTip | Qt.WindowStaysOnTopHint | Qt.WindowDoesNotAcceptFocus
    backgroundHints: PlasmaCore.Types.NoBackground
    location: PlasmaCore.Types.Floating
    visualParent: targetItem
    floating: LocalMetrics.Metrics.px(5.0)

    property Item targetItem: null
    property string text: ""
    property real dockHeight: LocalMetrics.Metrics.px(56.0)
    property color panelBgColor: Kirigami.Theme.backgroundColor
    property color panelTextColor: Kirigami.Theme.textColor

    width: mainItem.implicitWidth
    height: mainItem.implicitHeight

    readonly property bool isDarkTheme: Kirigami.Theme.textColor.r > 0.5 || Kirigami.Theme.textColor.g > 0.5 || Kirigami.Theme.textColor.b > 0.5
    readonly property color bubbleColor: {
        if (panelBgColor && panelBgColor.a > 0 && panelBgColor !== "#00000000") {
            return panelBgColor;
        }
        return isDarkTheme ? "#2A2E32" : "#F4F4F8";
    }
    readonly property color textColor: {
        if (panelTextColor && panelTextColor.a > 0 && panelTextColor !== "#00000000") {
            return panelTextColor;
        }
        return isDarkTheme ? "#F4F4F8" : "#1F1F24";
    }

    function requestShow(item, tooltipText) {
        if (!item || !tooltipText || tooltipText.length === 0) {
            requestHideImmediately();
            return;
        }

        if (hideGraceTimer && hideGraceTimer.running) {
            hideGraceTimer.stop();
        }

        targetItem = item;
        tooltipDialog.visualParent = item;
        text = tooltipText;
        if (mainItem) {
            mainItem.opacity = 1;
        }
        tooltipDialog.visible = true;
    }

    function requestHide(item) {
        if (!item) {
            requestHideImmediately();
            return;
        }
        if (targetItem === item) {
            if (hideGraceTimer) {
                hideGraceTimer.restart();
            } else {
                requestHideImmediately();
            }
        }
    }

    function requestHideImmediately() {
        if (hideGraceTimer && hideGraceTimer.running) {
            hideGraceTimer.stop();
        }
        if (mainItem) {
            mainItem.opacity = 0;
        }
        tooltipDialog.visible = false;
        targetItem = null;
        tooltipDialog.visualParent = null;
    }

    mainItem: Item {
        id: mainItem
        implicitWidth: Math.max(LocalMetrics.Metrics.px(48.0), label.implicitWidth + LocalMetrics.Metrics.px(32.0))
        implicitHeight: LocalMetrics.Metrics.px(43.0)
        opacity: 1

        Timer {
            id: hideGraceTimer
            interval: 60
            repeat: false
            onTriggered: {
                tooltipDialog.requestHideImmediately();
            }
        }

        // Main rounded pill body - flat, borderless
        Rectangle {
            id: bubbleBody
            x: 0
            y: 0
            width: parent.width
            height: LocalMetrics.Metrics.px(36.0)
            radius: height / 2
            color: tooltipDialog.bubbleColor
            border.width: 0

            Text {
                id: label
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -LocalMetrics.Metrics.px(1.0)
                text: tooltipDialog.text
                color: tooltipDialog.textColor
                font.family: "Google Sans Flex"
                font.pixelSize: LocalMetrics.Metrics.px(15.0)
                font.weight: Font.Medium
                renderType: Text.NativeRendering
            }
        }

        // Downward triangular pointer / arrow pointing at the icon (7 px arrow)
        Shape {
            id: arrowShape
            anchors.fill: parent
            containsMode: Shape.FillContains
            readonly property real midX: Math.round(width / 2)
            readonly property real arrowHalfW: LocalMetrics.Metrics.px(7.0)
            readonly property real arrowStartY: Math.max(0, bubbleBody.height - LocalMetrics.Metrics.px(1.0))
            readonly property real arrowTipY: bubbleBody.height + LocalMetrics.Metrics.px(7.0)

            ShapePath {
                strokeWidth: 0
                fillColor: tooltipDialog.bubbleColor

                startX: arrowShape.midX - arrowShape.arrowHalfW
                startY: arrowShape.arrowStartY

                PathLine { x: arrowShape.midX; y: arrowShape.arrowTipY }
                PathLine { x: arrowShape.midX + arrowShape.arrowHalfW; y: arrowShape.arrowStartY }
                PathLine { x: arrowShape.midX - arrowShape.arrowHalfW; y: arrowShape.arrowStartY }
            }
        }
    }
}

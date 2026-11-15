/*
    SPDX-FileCopyrightText: 2026 DoodlebookOS
    SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
*/

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Effects
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support
import "i18n.js" as I18n
import "metrics" as LocalMetrics

PlasmaCore.Dialog {
    id: taskbarMenuDialog

    function i18n(k, a1, a2) { return I18n.t(k, a1, a2); }

    flags: Qt.WindowStaysOnTopHint
    backgroundHints: PlasmaCore.Types.NoBackground
    location: PlasmaCore.Types.Floating
    visualParent: targetItem
    floating: LocalMetrics.Metrics.legacyDp(10)
    hideOnWindowDeactivate: true

    property Item targetItem: null
    property bool alwaysShow: true

    readonly property bool isDark: {
        var bg = Kirigami.Theme.backgroundColor;
        var lum = bg.r * 0.299 + bg.g * 0.587 + bg.b * 0.114;
        return lum < 0.5 || Kirigami.Theme.colorSet === Kirigami.Theme.Complementary;
    }
    readonly property color cBg: mainItem ? mainItem.Kirigami.Theme.backgroundColor : "#19191f"
    readonly property color cBorder: isDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08)
    readonly property color cText: isDark ? "#E3E3E3" : "#1F1F1F"

    width: mainItem.implicitWidth
    height: mainItem.implicitHeight

    function queryHidingStatus() {
        var cmd = '$(command -v qdbus-qt6 || command -v qdbus6 || command -v qdbus) org.kde.plasmashell /PlasmaShell evaluateScript \'
for (var i = 0; i < panels().length; i++) {
    if (panels()[i].location === "bottom") {
        print(panels()[i].hiding);
        break;
    }
}
\'';
        mainItem.runCmd(cmd);
    }

    function setHiding(enableAlwaysShow) {
        alwaysShow = enableAlwaysShow;
        var val = enableAlwaysShow ? "none" : "dodgewindows";
        var cmd = '$(command -v qdbus-qt6 || command -v qdbus6 || command -v qdbus) org.kde.plasmashell /PlasmaShell evaluateScript \'
for (var i = 0; i < panels().length; i++) {
    if (panels()[i].location === "bottom") {
        panels()[i].hiding = "' + val + '";
        break;
    }
}
\'';
        mainItem.runCmd(cmd);
    }

    function requestShow(parentItem) {
        if (taskbarMenuDialog.visible) {
            taskbarMenuDialog.visible = false;
        }
        targetItem = parentItem;
        taskbarMenuDialog.visualParent = parentItem;
        queryHidingStatus();
        taskbarMenuDialog.visible = true;
        taskbarMenuDialog.requestActivate();
    }

    function close() {
        taskbarMenuDialog.visible = false;
        targetItem = null;
    }

    onActiveChanged: {
        if (!active && visible) {
            close();
        }
    }

    onVisibleChanged: {
        if (!visible) {
            targetItem = null;
        }
    }

    mainItem: Item {
        id: mainItem
        Kirigami.Theme.colorSet: Kirigami.Theme.Tooltip
        Kirigami.Theme.inherit: false
        implicitWidth: LocalMetrics.Metrics.legacyDp(260)
        implicitHeight: LocalMetrics.Metrics.legacyDp(46)

        function runCmd(cmd) {
            dbusRunner.connectSource(cmd + " # " + Date.now());
        }

        Plasma5Support.DataSource {
            id: dbusRunner
            engine: "executable"
            connectedSources: []
            onNewData: (sourceName, data) => {
                var stdout = (data["stdout"] || "").toString().trim();
                if (stdout.indexOf("autohide") !== -1 || stdout.indexOf("dodgewindows") !== -1) {
                    alwaysShow = false;
                } else if (stdout.indexOf("none") !== -1) {
                    alwaysShow = true;
                }
                disconnectSource(sourceName);
            }
        }

        scale: taskbarMenuDialog.visible ? 1.0 : 0.88
        opacity: taskbarMenuDialog.visible ? 1.0 : 0.0
        transformOrigin: Item.Bottom

        Behavior on scale {
            NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
        }
        Behavior on opacity {
            NumberAnimation { duration: 140; easing.type: Easing.OutQuad }
        }

        // Soft drop shadow
        Rectangle {
            x: pillBody.x
            y: pillBody.y + 1
            width: pillBody.width
            height: pillBody.height
            radius: pillBody.radius
            color: Qt.rgba(0, 0, 0, 0.18)
            z: -1
        }

        // Main pill body
        Rectangle {
            id: pillBody
            x: 0
            y: 0
            width: parent.width
            height: LocalMetrics.Metrics.legacyDp(38)
            radius: LocalMetrics.Metrics.legacyDp(19)
            color: taskbarMenuDialog.cBg
            border.color: taskbarMenuDialog.cBorder
            border.width: Math.max(1.0 / LocalMetrics.Metrics.dpr, LocalMetrics.Metrics.snap(1))

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    taskbarMenuDialog.setHiding(!taskbarMenuDialog.alwaysShow);
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: LocalMetrics.Metrics.legacyDp(16)
                anchors.rightMargin: LocalMetrics.Metrics.legacyDp(12)
                spacing: LocalMetrics.Metrics.legacyDp(12)

                // Visibility Icon
                Item {
                    Layout.preferredWidth: LocalMetrics.Metrics.legacyDp(20)
                    Layout.preferredHeight: LocalMetrics.Metrics.legacyDp(20)

                    Image {
                        id: visIconImg
                        anchors.fill: parent
                        source: Qt.resolvedUrl("icons/visibility.svg")
                        sourceSize: Qt.size(Math.round(LocalMetrics.Metrics.legacyDp(20) * 2), Math.round(LocalMetrics.Metrics.legacyDp(20) * 2))
                        visible: false
                    }

                    MultiEffect {
                        anchors.fill: visIconImg
                        source: visIconImg
                        colorization: 1.0
                        colorizationColor: taskbarMenuDialog.cText
                    }
                }

                // Label Text
                Text {
                    Layout.fillWidth: true
                    text: i18n("Always show Taskbar")
                    font.family: "Google Sans Flex"
                    font.pixelSize: LocalMetrics.Metrics.legacyDp(13)
                    font.weight: Font.Medium
                    color: taskbarMenuDialog.cText
                    elide: Text.ElideRight
                }

                // Material Design Switch Toggle
                Item {
                    id: switchItem
                    Layout.preferredWidth: LocalMetrics.Metrics.legacyDp(44)
                    Layout.preferredHeight: LocalMetrics.Metrics.legacyDp(24)

                    Rectangle {
                        id: switchTrack
                        anchors.fill: parent
                        radius: LocalMetrics.Metrics.legacyDp(12)
                        color: taskbarMenuDialog.alwaysShow ? Kirigami.Theme.highlightColor : (taskbarMenuDialog.isDark ? "#484C52" : "#74777F")
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }

                    Rectangle {
                        id: switchThumb
                        readonly property real thumbInset: LocalMetrics.Metrics.legacyDp(3)
                        width: LocalMetrics.Metrics.legacyDp(18)
                        height: LocalMetrics.Metrics.legacyDp(18)
                        radius: LocalMetrics.Metrics.legacyDp(9)
                        y: thumbInset
                        x: taskbarMenuDialog.alwaysShow ? (switchItem.width - width - thumbInset) : thumbInset
                        color: taskbarMenuDialog.alwaysShow ? Kirigami.Theme.highlightedTextColor : "#FFFFFF"
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                    }
                }
            }
        }

        // Downward pointer arrow pointing at the taskbar (centered)
        Shape {
            id: pointerArrow
            anchors.fill: parent
            readonly property real arrowX: Math.round(pillBody.width / 2)
            readonly property real arrowHalfW: LocalMetrics.Metrics.legacyDp(6)
            readonly property real arrowStartY: Math.max(0, pillBody.height - LocalMetrics.Metrics.legacyDp(1))
            readonly property real arrowTipY: LocalMetrics.Metrics.legacyDp(44)

            ShapePath {
                strokeWidth: 0
                fillColor: taskbarMenuDialog.cBg
                startX: pointerArrow.arrowX - pointerArrow.arrowHalfW
                startY: pointerArrow.arrowStartY
                PathLine { x: pointerArrow.arrowX; y: pointerArrow.arrowTipY }
                PathLine { x: pointerArrow.arrowX + pointerArrow.arrowHalfW; y: pointerArrow.arrowStartY }
                PathLine { x: pointerArrow.arrowX - pointerArrow.arrowHalfW; y: pointerArrow.arrowStartY }
            }
        }
    }
}

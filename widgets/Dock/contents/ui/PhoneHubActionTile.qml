/*
 * SPDX-FileCopyrightText: 2024-2026 Maciej Kujawiński <maciek.kujawinski@gmail.com>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import "metrics" as LocalMetrics

Item {
    id: root

    property string title: ""
    property string iconSource: ""
    property bool isActive: false
    property color activeColor: Kirigami.Theme.highlightColor

    signal clicked()

    implicitWidth: LocalMetrics.Metrics.legacyDp(200)
    implicitHeight: LocalMetrics.Metrics.legacyDp(64)

    readonly property color cBg: isActive
        ? activeColor
        : (ma.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.07))
    readonly property color cText: isActive ? "#FFFFFF" : "#E3E3E3"
    readonly property color cIcon: isActive ? "#FFFFFF" : "#D0D0D8"

    Rectangle {
        id: bgRect
        anchors.fill: parent
        radius: LocalMetrics.Metrics.legacyDp(18)
        color: root.cBg
        border.color: root.isActive ? "transparent" : Qt.rgba(1, 1, 1, 0.08)
        border.width: 1

        scale: ma.pressed ? 0.97 : (ma.containsMouse ? 1.02 : 1.0)
        Behavior on scale { NumberAnimation { duration: 100 } }
        Behavior on color { ColorAnimation { duration: 150 } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: LocalMetrics.Metrics.legacyDp(16)
            anchors.rightMargin: LocalMetrics.Metrics.legacyDp(16)
            spacing: LocalMetrics.Metrics.legacyDp(12)

            Item {
                Layout.preferredWidth: LocalMetrics.Metrics.legacyDp(24)
                Layout.preferredHeight: LocalMetrics.Metrics.legacyDp(24)
                Layout.alignment: Qt.AlignVCenter

                Image {
                    id: iconImg
                    anchors.centerIn: parent
                    width: LocalMetrics.Metrics.legacyDp(24)
                    height: LocalMetrics.Metrics.legacyDp(24)
                    sourceSize: Qt.size(Math.round(LocalMetrics.Metrics.legacyDp(24) * 2), Math.round(LocalMetrics.Metrics.legacyDp(24) * 2))
                    fillMode: Image.PreserveAspectFit
                    source: root.iconSource
                    visible: false
                }

                MultiEffect {
                    anchors.fill: iconImg
                    source: iconImg
                    colorization: 1.0
                    colorizationColor: root.cIcon
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                text: root.title
                font.family: "Google Sans Flex"
                font.pixelSize: LocalMetrics.Metrics.legacyDp(13)
                font.weight: root.isActive ? Font.DemiBold : Font.Medium
                color: root.cText
                elide: Text.ElideRight
            }
        }

        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.clicked()
        }
    }
}

/*
 * SPDX-FileCopyrightText: 2024-2026 Maciej Kujawiński <maciek.kujawinski@gmail.com>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Material 3 expressive action tile, theme-aware (was hard-coded white-on-dark,
// unreadable with DoodlebookOS Light).
Item {
    id: root

    property string title: ""
    property string subtitle: ""
    property string iconSource: ""
    property bool isActive: false
    property bool available: true
    property bool editMode: false
    property color activeColor: Kirigami.Theme.highlightColor
    property real enter: 1.0 // entrance progress driven by the popup (0..1)

    signal clicked()
    signal removeRequested()

    implicitWidth: 200
    implicitHeight: 64

    opacity: (available || editMode ? 1.0 : 0.45) * enter
    scale: 0.86 + 0.14 * enter

    readonly property color fg: isActive ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
    readonly property real hoverAlpha: (ma.containsMouse && available && !editMode) ? 0.13 : 0.07

    Rectangle {
        id: bgRect
        anchors.fill: parent
        // Shape morph: pill at rest, rounded square when active (M3 expressive)
        radius: root.isActive ? 20 : height / 2
        color: root.isActive
               ? root.activeColor
               : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, root.hoverAlpha)
        border.width: 1
        border.color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, root.editMode ? 0.6 : 0)
        Behavior on border.color { ColorAnimation { duration: Kirigami.Units.longDuration > 1 ? 400 : 0 } }
        scale: ma.pressed ? 0.96 : 1.0

        Behavior on radius { NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }
        Behavior on scale { NumberAnimation { duration: Kirigami.Units.shortDuration; easing.type: Easing.OutCubic } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 18
            anchors.rightMargin: 14
            spacing: 12

            Kirigami.Icon {
                Layout.preferredWidth: 22
                Layout.preferredHeight: 22
                Layout.alignment: Qt.AlignVCenter
                source: root.iconSource
                isMask: true
                color: root.fg
                Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 0

                Text {
                    Layout.fillWidth: true
                    text: root.title
                    font.family: "Google Sans Flex"
                    font.pixelSize: 13
                    font.weight: root.isActive ? Font.DemiBold : Font.Medium
                    color: root.fg
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: root.subtitle
                    font.family: "Google Sans Flex"
                    font.pixelSize: 11
                    color: root.fg
                    opacity: 0.7
                    elide: Text.ElideRight
                }
            }
        }

        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            enabled: root.available && !root.editMode
            cursorShape: Qt.PointingHandCursor
            onClicked: root.clicked()
        }
    }

    // Edit mode: Android-style "–" badge, pops in with a slight overshoot
    Rectangle {
        property real pop: root.editMode ? 1 : 0
        Behavior on pop { NumberAnimation { duration: Kirigami.Units.longDuration > 1 ? 420 : 0; easing.type: Easing.OutBack } }
        visible: pop > 0.01
        scale: pop
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: -4
        anchors.leftMargin: -2
        width: 22
        height: 22
        radius: 11
        color: removeMa.containsMouse ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.highlightColor
        Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }

        Kirigami.Icon {
            anchors.centerIn: parent
            width: 14
            height: 14
            source: Qt.resolvedUrl("icons/remove.svg")
            isMask: true
            color: removeMa.containsMouse ? "#ffffff" : Kirigami.Theme.highlightedTextColor
        }

        MouseArea {
            id: removeMa
            anchors.fill: parent
            anchors.margins: -3
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.removeRequested()
        }
    }
}

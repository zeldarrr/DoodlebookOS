/*
    SPDX-FileCopyrightText: 2026 DoodlebookOS
    SPDX-License-Identifier: GPL-3.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: highlightRoot

    property bool active: false
    property bool hovered: false
    property color activeColor: Kirigami.Theme.highlightColor
    property color hoverColor: "#ffffff"
    property real hoverOpacity: 0.282

    anchors.fill: parent

    // Separate hover and active layers prevent a color flash when transitioning out of active state.
    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: highlightRoot.hoverColor
        opacity: highlightRoot.hovered ? highlightRoot.hoverOpacity : 0.0
        Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }
    }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: highlightRoot.activeColor
        opacity: highlightRoot.active ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }
    }
}

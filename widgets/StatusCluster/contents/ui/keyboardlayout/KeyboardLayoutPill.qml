/*
    SPDX-FileCopyrightText: 2026 DoodlebookOS
    SPDX-License-Identifier: GPL-3.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: keyboardLayoutButton

    required property var appletRoot
    required property bool expanded

    visible: appletRoot.hasMultipleKeyboardLayouts && appletRoot.activeKeyboardLayoutCode.length > 0
    height: appletRoot.railHeight
    readonly property real sidePadding: appletRoot.snap(appletRoot.effectiveHeight * 0.125)
    width: visible ? Math.max(appletRoot.railHeight, appletRoot.snap(keyboardLayoutLabel.paintedWidth + sidePadding * 2)) : 0
    implicitWidth: width
    implicitHeight: height

    readonly property bool isActive: keyboardLayoutMouse.pressed || expanded
    readonly property bool isHovered: keyboardLayoutMouse.containsMouse && !isActive

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: keyboardLayoutButton.appletRoot.highlightCapsuleColor
        opacity: keyboardLayoutButton.isActive ? 1.0 : (keyboardLayoutButton.isHovered ? 0.25 : 0.0)
        Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }
    }

    Text {
        id: keyboardLayoutLabel
        x: keyboardLayoutButton.appletRoot.snap((parent.width - width) / 2)
        y: keyboardLayoutButton.appletRoot.snap((parent.height - height) / 2) + keyboardLayoutButton.appletRoot.legacyDp(0.4)
        text: keyboardLayoutButton.appletRoot.activeKeyboardLayoutCode
        font {
            family: "Google Sans"
            weight: 700
            pointSize: keyboardLayoutButton.appletRoot.keyboardLayoutFontSize * 0.75
            letterSpacing: 0.4
        }
        renderType: Text.CurveRendering
        color: keyboardLayoutButton.isActive
            ? keyboardLayoutButton.appletRoot.highlightedContentColor
            : keyboardLayoutButton.appletRoot.topBarContentColor
        Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }
    }

    property bool layoutWasOpen: false

    MouseArea {
        id: keyboardLayoutMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        onPressed: mouse => {
            keyboardLayoutButton.layoutWasOpen = keyboardLayoutButton.expanded;
        }

        onClicked: mouse => {
            if (mouse.button === Qt.LeftButton) {
                if (keyboardLayoutButton.layoutWasOpen) {
                    keyboardLayoutButton.appletRoot.closeAllPopups();
                } else {
                    keyboardLayoutButton.appletRoot.requestTogglePopup("keyboardlayout");
                }
            }
        }
    }
}

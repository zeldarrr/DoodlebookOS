// SPDX-License-Identifier: GPL-3.0-or-later
// M3 snackbar used for launcher feedback (copied result, folder created, uninstall…).
import QtQuick
import org.kde.kirigami as Kirigami

Rectangle {
    id: toast
    property string text: ""
    function show(t) {
        text = t;
        hideTimer.restart();
        shown = true;
    }
    property bool shown: false

    width: Math.min(label.implicitWidth + 40, 460)
    height: 44
    radius: 14
    color: Kirigami.Theme.textColor
    opacity: shown ? 1 : 0
    visible: opacity > 0
    scale: shown ? 1 : 0.85
    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }

    Timer { id: hideTimer; interval: 2800; onTriggered: toast.shown = false }

    Text {
        id: label
        anchors.centerIn: parent
        width: Math.min(implicitWidth, 420)
        text: toast.text
        elide: Text.ElideRight
        font.family: "Google Sans Flex"
        font.pixelSize: 13
        font.weight: Font.Medium
        color: Kirigami.Theme.backgroundColor
    }
}

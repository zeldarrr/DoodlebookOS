// SPDX-License-Identifier: GPL-3.0-or-later
// M3 Expressive filter chips (one per non-empty category). The selected chip turns into a
// filled squircle with a check that grows in; the row scrolls with the mouse wheel.
import QtQuick
import QtQuick.Effects
import org.kde.kirigami as Kirigami

ListView {
    id: chips
    property string current: "all"
    signal picked(string key)

    readonly property color fg: Kirigami.Theme.textColor
    readonly property color accent: Kirigami.Theme.highlightColor
    readonly property color onAccent: (0.299 * accent.r + 0.587 * accent.g + 0.114 * accent.b) > 0.62 ? "#1d1a2c" : Kirigami.Theme.highlightedTextColor
    function tint(a) { return Qt.rgba(fg.r, fg.g, fg.b, a); }

    orientation: ListView.Horizontal
    spacing: 8
    implicitHeight: 36
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    activeFocusOnTab: false
    highlightMoveDuration: 220
    currentIndex: Math.max(0, keys.indexOf(current))
    onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

    model: keys
    readonly property var keys: {
        var rev = appIndex.revision;     // dependency
        var out = [];
        for (var i = 0; i < appIndex.categoryKeys.length; i++) {
            var k = appIndex.categoryKeys[i];
            if (k === "all" || (appIndex.counts[k] || 0) > 0) out.push(k);
        }
        return out;
    }

    function step(d) {
        var list = keys;
        var i = list.indexOf(current);
        var n = list[Math.max(0, Math.min(list.length - 1, i + d))];
        if (n && n !== current) picked(n);
    }

    Keys.onLeftPressed: step(-1)
    Keys.onRightPressed: step(1)
    Keys.onUpPressed: main.searchBar.textField.forceActiveFocus(Qt.BacktabFocusReason)
    Keys.onDownPressed: {
        var v = main.stackItem ? main.stackItem.viewItem : null;
        if (v) { v.forceActiveFocus(Qt.TabFocusReason); if (v.currentIndex < 0 && v.count > 0) v.currentIndex = 0; v.movedWithKeyboard = true; }
    }

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse
        onWheel: (ev) => {
            chips.contentX = Math.max(0, Math.min(chips.contentWidth - chips.width, chips.contentX - ev.angleDelta.y));
        }
    }

    delegate: Rectangle {
        id: chip
        required property string modelData
        required property int index
        readonly property bool sel: chips.current === modelData
        readonly property bool focused: chips.activeFocus && chips.currentIndex === index

        height: 36
        width: row.implicitWidth + 28
        radius: chipMa.pressed ? 10 : (sel ? 12 : 18)
        color: sel ? chips.accent : (chipMa.containsMouse ? chips.tint(0.10) : "transparent")
        border.width: sel ? 0 : 1
        border.color: focused ? chips.accent : chips.tint(0.22)
        Behavior on radius { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
        Behavior on color { ColorAnimation { duration: 160 } }
        Behavior on width { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

        Row {
            id: row
            anchors.centerIn: parent
            spacing: 6
            Item {
                width: chip.sel ? 16 : 0
                height: 16
                anchors.verticalCenter: parent.verticalCenter
                clip: true
                Behavior on width { NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
                Image { id: checkImg; width: 16; height: 16; source: Qt.resolvedUrl("icons/check.svg"); sourceSize: Qt.size(32, 32); visible: false }
                MultiEffect { anchors.fill: checkImg; source: checkImg; colorization: 1.0; colorizationColor: chips.onAccent; opacity: chip.sel ? 1 : 0 }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: appIndex.categoryLabel(chip.modelData)
                font.family: "Google Sans Flex"
                font.pixelSize: 13
                font.weight: chip.sel ? Font.DemiBold : Font.Medium
                color: chip.sel ? chips.onAccent : chips.fg
            }
        }

        MouseArea {
            id: chipMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chips.picked(chip.modelData)
        }
    }
}

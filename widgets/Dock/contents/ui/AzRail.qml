// SPDX-License-Identifier: GPL-3.0-or-later
// A–Z fast scroller (Android style): letters present in the list, the current one highlighted;
// press or drag on it to jump, with a big expressive letter bubble.
import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: rail
    property var view: null          // GridView
    property var proxy: null         // its model
    property var letters: []         // [{l, row}]
    property string active: ""
    readonly property bool dragging: ma.pressed
    width: root.railWidth

    readonly property color fg: Kirigami.Theme.textColor
    readonly property color accent: Kirigami.Theme.highlightColor
    readonly property color onAccent: (0.299 * accent.r + 0.587 * accent.g + 0.114 * accent.b) > 0.62 ? "#1d1a2c" : Kirigami.Theme.highlightedTextColor

    function letterOf(name) {
        var c = appIndex.fold(name).charAt(0).toUpperCase();
        return (c >= "A" && c <= "Z") ? c : "#";
    }
    function rebuild() {
        var out = [], seen = {};
        if (proxy) {
            for (var r = 0; r < proxy.count; r++) {
                var l = letterOf(proxy.data(proxy.index(r, 0), Qt.DisplayRole) || "");
                if (!seen[l]) { seen[l] = true; out.push({ l: l, row: r }); }
            }
        }
        letters = out;
        syncActive();
    }
    Timer { id: rebuildTimer; interval: 30; onTriggered: rail.rebuild() }
    function scheduleRebuild() { rebuildTimer.restart(); }
    Connections {
        target: rail.proxy
        function onRowCountChanged() { rail.scheduleRebuild(); }
        function onModelReset() { rail.scheduleRebuild(); }
        function onLayoutChanged() { rail.scheduleRebuild(); }
    }
    onProxyChanged: scheduleRebuild()

    // letter of the first visible row while scrolling
    function syncActive() {
        if (!view || dragging) return;
        var idx = view.indexAt(view.cellWidth / 2, view.contentY + view.cellHeight / 2);
        if (idx < 0) { active = ""; return; }
        var a = "";
        for (var i = 0; i < letters.length && letters[i].row <= idx; i++) a = letters[i].l;
        active = a;
    }
    Connections {
        target: rail.view
        function onContentYChanged() { rail.syncActive(); }
    }

    function jumpAt(y) {
        if (!letters.length) return;
        var i = Math.max(0, Math.min(letters.length - 1, Math.floor((y - column.y) / slot)));
        var it = letters[i];
        if (active !== it.l) {
            active = it.l;
            view.positionViewAtIndex(it.row, GridView.Beginning);
        }
        bubble.y = Math.max(0, Math.min(height - bubble.height, column.y + i * slot + slot / 2 - bubble.height / 2));
    }

    readonly property real slot: letters.length ? Math.min(20, height / letters.length) : 20

    Rectangle {
        anchors.horizontalCenter: column.horizontalCenter
        y: column.y - 4
        width: 22
        height: column.height + 8
        radius: 11
        color: Qt.rgba(rail.fg.r, rail.fg.g, rail.fg.b, rail.dragging ? 0.10 : (ma.containsMouse ? 0.06 : 0))
        Behavior on color { ColorAnimation { duration: Kirigami.Units.longDuration > 1 ? 150 : 0 } }
    }

    Column {
        id: column
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        Repeater {
            model: rail.letters
            delegate: Item {
                required property var modelData
                width: rail.width
                height: rail.slot
                readonly property bool on: rail.active === modelData.l
                Rectangle {
                    anchors.centerIn: parent
                    width: 18; height: 18; radius: 9
                    color: rail.accent
                    scale: parent.on ? 1 : 0
                    Behavior on scale { NumberAnimation { duration: Kirigami.Units.longDuration > 1 ? 220 : 0; easing.type: Easing.OutBack; easing.overshoot: 2 } }
                }
                Text {
                    anchors.centerIn: parent
                    text: modelData.l
                    font.family: "Google Sans Flex"
                    font.pixelSize: 10
                    font.weight: parent.on ? Font.Bold : Font.Medium
                    color: parent.on ? rail.onAccent : Qt.rgba(rail.fg.r, rail.fg.g, rail.fg.b, 0.6)
                }
            }
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        preventStealing: true
        onPressed: (m) => rail.jumpAt(m.y)
        onPositionChanged: (m) => { if (pressed) rail.jumpAt(m.y); }
    }

    // expressive bubble next to the rail while dragging
    Rectangle {
        id: bubble
        x: -width - 10
        width: 56; height: 56
        radius: rail.dragging ? 18 : 28
        color: rail.accent
        scale: rail.dragging && rail.active.length ? 1 : 0
        visible: scale > 0.01
        transformOrigin: Item.Right
        Behavior on scale { NumberAnimation { duration: Kirigami.Units.longDuration > 1 ? 240 : 0; easing.type: Easing.OutBack; easing.overshoot: 1.8 } }
        Behavior on radius { NumberAnimation { duration: Kirigami.Units.longDuration > 1 ? 260 : 0; easing.type: Easing.OutBack } }
        Behavior on y { NumberAnimation { duration: Kirigami.Units.longDuration > 1 ? 90 : 0; easing.type: Easing.OutCubic } }
        Text {
            anchors.centerIn: parent
            text: rail.active
            font.family: "Google Sans Flex"
            font.pixelSize: 26
            font.weight: Font.Bold
            color: rail.onAccent
        }
    }
}

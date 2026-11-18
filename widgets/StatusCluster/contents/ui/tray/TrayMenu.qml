/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Material 3 Expressive menu for a background app (built from its DBusMenu).
 * Pure view: TrayArea feeds it the entries and handles the D-Bus side.
 *
 *  - entries split at separators into tonal groups with small gaps (M3 Expressive "gap" menu)
 *  - selected toggles get a filled container + check, rows morph pill → rounded square on press
 *  - motion: KWin unfolds the popup from the icon; inside, the header and the groups settle on
 *    M3 Expressive springs, submenus use the shared X axis (spring slide + fade)
 *  - keyboard: ↑/↓ (Tab), Entrée/Espace, → opens a submenu, ←/Retour arrière goes back, Échap
 * Everything stops (durations 0) when Plasma animations are disabled.
 */

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../motion.js" as Motion

FocusScope {
    id: menu

    property var appItem: null                 // tray item: title, tooltip, icons
    property var entries: []                   // current level
    property int depth: 0                      // 0 = root, > 0 = inside a submenu
    property string levelTitle: ""

    signal activated(var entry)
    signal backRequested()
    signal closeRequested()

    readonly property bool anim: Kirigami.Units.longDuration > 1
    readonly property color fg: Kirigami.Theme.textColor
    readonly property color accent: Kirigami.Theme.highlightColor
    readonly property color onAccent: Kirigami.Theme.highlightedTextColor
    readonly property string appFont: "Google Sans Flex"
    function tint(c, a) { return Qt.rgba(c.r, c.g, c.b, a); }

    readonly property real rowHeight: 40
    readonly property real groupPad: 4
    readonly property real groupGap: 4

    width: Kirigami.Units.gridUnit * 16
    implicitWidth: width
    implicitHeight: col.implicitHeight + 12
    height: implicitHeight

    // groups of rows (separators become gaps) + flat index for keyboard navigation
    readonly property var groups: {
        var out = [], cur = [], flat = 0;
        for (var i = 0; i < entries.length; i++) {
            var e = entries[i];
            if (!e || e.visible === false) continue;
            if (e.type === "separator") {
                if (cur.length) out.push(cur);
                cur = [];
                continue;
            }
            cur.push({ entry: e, flat: flat++ });
        }
        if (cur.length) out.push(cur);
        return out;
    }
    readonly property int rowCount: {
        var n = 0;
        for (var g = 0; g < groups.length; g++) n += groups[g].length;
        return n;
    }
    function entryAt(flat) {
        for (var g = 0; g < groups.length; g++)
            for (var r = 0; r < groups[g].length; r++)
                if (groups[g][r].flat === flat) return groups[g][r].entry;
        return null;
    }
    function selectable(e) { return e && e.enabled !== false && e.type !== "separator"; }

    property int current: -1                   // keyboard highlight (-1 = none)
    property bool keyboardNav: false
    function step(dir) {
        if (rowCount === 0) return;
        keyboardNav = true;
        // nothing highlighted yet: ↓ starts at the first row, ↑ at the last one
        var i = current < 0 || current >= rowCount ? (dir > 0 ? -1 : rowCount) : current;
        for (var n = 0; n < rowCount; n++) {
            i = (i + dir + rowCount) % rowCount;
            if (selectable(entryAt(i))) { current = i; return; }
        }
    }

    // ───── motion (springs: ../motion.js; one linear driver each, time in nominal ms) ─────
    property real enterMs: 100000              // since the popup opened
    property real slideMs: 100000              // since entering / leaving a submenu
    property int slideDir: 0                   // 1 = into a submenu, -1 = back
    readonly property real slide: slideDir * (1 - Motion.defaultSpatial(slideMs))   // ±1 → 0
    NumberAnimation {
        id: enterAnim
        target: menu; property: "enterMs"; from: 0; to: 600
        duration: 600 * Motion.speed(Kirigami.Units.longDuration)
    }
    NumberAnimation {
        id: slideAnim
        target: menu; property: "slideMs"; from: 0; to: 600
        duration: 600 * Motion.speed(Kirigami.Units.longDuration)
    }
    // dir: 0 = popup opened, 1 = into a submenu, -1 = back to the parent level
    function playEnter(dir) {
        current = -1;
        keyboardNav = false;
        enterAnim.stop();
        slideAnim.stop();
        if (!anim) {
            enterMs = slideMs = 100000;
        } else if (dir === 0) {
            slideMs = 100000;
            enterMs = 0;
            enterAnim.start();
        } else {
            enterMs = 100000;
            slideDir = dir;
            slideMs = 0;
            slideAnim.start();
        }
        forceActiveFocus();
    }
    // header (0) and groups (1, 2…) settle from the top, 24 ms apart
    function enterOpacity(order) { return Motion.effects(enterMs - 20 - Math.min(order, 6) * 24); }
    function enterShift(order) { return (1 - Motion.defaultSpatial(enterMs - Math.min(order, 6) * 24)) * -10; }

    Keys.onPressed: event => {
        switch (event.key) {
        case Qt.Key_Down: case Qt.Key_Tab:
            step(1); break;
        case Qt.Key_Up: case Qt.Key_Backtab:
            step(-1); break;
        case Qt.Key_Home:
            current = -1; step(1); break;
        case Qt.Key_End:
            current = rowCount; step(-1); break;
        case Qt.Key_Return: case Qt.Key_Enter: case Qt.Key_Space: {
            var e = entryAt(current);
            if (selectable(e)) menu.activated(e);
            break;
        }
        case Qt.Key_Right: {
            var s = entryAt(current);
            if (selectable(s) && s.submenu) menu.activated(s);
            break;
        }
        case Qt.Key_Left: case Qt.Key_Backspace:
            if (depth > 0) menu.backRequested();
            break;
        case Qt.Key_Escape:
            if (depth > 0) menu.backRequested(); else menu.closeRequested();
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    // KWin unfolds the popup out of the icon; the content settles on springs just behind it
    Item {
        id: content
        width: parent.width
        height: menu.height

        Column {
            id: col
            x: 0
            y: 6
            width: menu.width
            spacing: menu.groupGap
            opacity: Motion.effects(menu.slideMs - 10)
            transform: Translate { x: menu.slide * 32 }

            // ───── header: app (root) or submenu title with a back button ─────
            Item {
                width: parent.width
                height: 50
                opacity: menu.enterOpacity(0)

                Rectangle {
                    id: lead
                    anchors.left: parent.left
                    anchors.leftMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    width: 40
                    height: 40
                    radius: menu.depth > 0 && backMa.pressed ? 12 : 20
                    color: menu.depth > 0
                        ? menu.tint(menu.fg, backMa.pressed ? 0.12 : (backMa.containsMouse ? 0.08 : 0))
                        : menu.tint(menu.accent, 0.18)
                    Behavior on radius { NumberAnimation { duration: menu.anim ? 200 : 0; easing.type: Easing.OutBack } }
                    Behavior on color { ColorAnimation { duration: menu.anim ? 150 : 0 } }

                    Kirigami.Icon {
                        anchors.centerIn: parent
                        visible: menu.depth === 0
                        width: 24
                        height: 24
                        source: menu.appItem ? (menu.appItem.iconFile ? ("file://" + menu.appItem.iconFile)
                                                : (menu.appItem.iconName || menu.appItem.appIcon || "application-x-executable")) : ""
                        fallback: menu.appItem ? (menu.appItem.appIcon || "application-x-executable") : ""
                    }
                    Kirigami.Icon {
                        anchors.centerIn: parent
                        visible: menu.depth > 0
                        width: 20
                        height: 20
                        source: Qt.resolvedUrl("../quicksettings/icons/arrow_back.svg")
                        isMask: true
                        color: menu.fg
                    }
                    MouseArea {
                        id: backMa
                        anchors.fill: parent
                        enabled: menu.depth > 0
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: menu.backRequested()
                    }
                }

                Column {
                    anchors.left: lead.right
                    anchors.leftMargin: 12
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1
                    Text {
                        width: parent.width
                        text: menu.depth > 0 ? menu.levelTitle : (menu.appItem ? menu.appItem.title : "")
                        font.family: menu.appFont
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                        color: menu.fg
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        visible: text.length > 0
                        text: menu.depth > 0 ? "" : (menu.appItem && menu.appItem.tooltip ? menu.appItem.tooltip.replace(/<[^>]*>/g, "").replace(/\s+/g, " ").trim()
                                                                                            : (menu.appItem && menu.appItem.status === "NeedsAttention" ? "Demande votre attention" : "En arrière-plan"))
                        font.family: menu.appFont
                        font.pixelSize: 12
                        color: menu.tint(menu.fg, 0.66)
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                }
            }

            Text {
                visible: menu.rowCount === 0
                width: parent.width
                height: menu.rowHeight
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
                text: "Aucune action"
                font.family: menu.appFont
                font.pixelSize: 13
                color: menu.tint(menu.fg, 0.6)
            }

            // ───── groups ─────
            Repeater {
                model: menu.groups
                delegate: Rectangle {
                    id: group
                    required property var modelData
                    required property int index
                    width: col.width
                    height: groupCol.implicitHeight + menu.groupPad * 2
                    radius: 18
                    color: menu.tint(menu.fg, 0.05)
                    opacity: menu.enterOpacity(group.index + 1)
                    transform: Translate { y: menu.enterShift(group.index + 1) }

                    Column {
                        id: groupCol
                        x: menu.groupPad
                        y: menu.groupPad
                        width: parent.width - menu.groupPad * 2
                        spacing: 2

                        Repeater {
                            model: group.modelData
                            delegate: Item {
                                id: row
                                required property var modelData
                                readonly property var e: modelData.entry
                                readonly property bool enabledRow: e.enabled !== false
                                readonly property bool isToggle: (e.toggleType || "") !== ""
                                readonly property bool checked: isToggle && e.toggleState === 1
                                readonly property bool kbCurrent: menu.keyboardNav && menu.current === modelData.flat
                                width: groupCol.width
                                height: menu.rowHeight
                                opacity: enabledRow ? 1 : 0.38

                                // selected container (checked toggles) — M3 Expressive filled selection
                                Rectangle {
                                    anchors.fill: parent
                                    radius: rowMa.pressed ? 8 : 14
                                    color: row.checked ? menu.tint(menu.accent, 0.24) : "transparent"
                                    Behavior on color { ColorAnimation { duration: menu.anim ? 200 : 0 } }
                                    Behavior on radius { NumberAnimation { duration: menu.anim ? 220 : 0; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
                                }
                                // state layer: hover 8 %, focus 10 %, pressed 12 %
                                Rectangle {
                                    anchors.fill: parent
                                    radius: rowMa.pressed ? 8 : 14
                                    color: menu.tint(row.checked ? menu.accent : menu.fg,
                                                     rowMa.pressed ? 0.12 : (row.kbCurrent ? 0.10 : (rowMa.containsMouse && row.enabledRow ? 0.08 : 0)))
                                    border.width: row.kbCurrent ? 2 : 0
                                    border.color: menu.accent
                                    Behavior on color { ColorAnimation { duration: menu.anim ? 120 : 0 } }
                                    Behavior on radius { NumberAnimation { duration: menu.anim ? 220 : 0; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 10
                                    spacing: 12

                                    // leading: check (selected toggle) or the entry's icon
                                    Item {
                                        Layout.preferredWidth: 20
                                        Layout.preferredHeight: 20
                                        visible: row.isToggle || (row.e.iconName || "") !== ""

                                        Kirigami.Icon {
                                            anchors.fill: parent
                                            visible: !row.isToggle
                                            source: row.e.iconName || ""
                                        }
                                        // unchecked toggle: quiet outline (round for radio)
                                        Rectangle {
                                            anchors.centerIn: parent
                                            visible: row.isToggle
                                            width: 18
                                            height: 18
                                            radius: row.e.toggleType === "radio" ? 9 : 5
                                            color: row.checked ? menu.accent : "transparent"
                                            border.width: row.checked ? 0 : 2
                                            border.color: menu.tint(menu.fg, 0.55)
                                            Behavior on color { ColorAnimation { duration: menu.anim ? 150 : 0 } }
                                            Kirigami.Icon {
                                                anchors.centerIn: parent
                                                width: 14
                                                height: 14
                                                visible: row.e.toggleType !== "radio"
                                                source: Qt.resolvedUrl("../quicksettings/icons/check.svg")
                                                isMask: true
                                                color: menu.onAccent
                                                scale: row.checked ? 1 : 0
                                                Behavior on scale { NumberAnimation { duration: menu.anim ? 260 : 0; easing.type: Easing.OutBack; easing.overshoot: 2 } }
                                            }
                                            Rectangle {
                                                anchors.centerIn: parent
                                                visible: row.e.toggleType === "radio"
                                                width: 8
                                                height: 8
                                                radius: 4
                                                color: menu.onAccent
                                                scale: row.checked ? 1 : 0
                                                Behavior on scale { NumberAnimation { duration: menu.anim ? 260 : 0; easing.type: Easing.OutBack; easing.overshoot: 2 } }
                                            }
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: row.e.label || ""
                                        font.family: menu.appFont
                                        font.pixelSize: 14
                                        font.weight: row.checked ? Font.DemiBold : Font.Normal
                                        color: menu.fg
                                        elide: Text.ElideRight
                                    }

                                    Kirigami.Icon {
                                        visible: row.e.submenu === true
                                        Layout.preferredWidth: 18
                                        Layout.preferredHeight: 18
                                        source: "go-next-symbolic"
                                        isMask: true
                                        color: menu.tint(menu.fg, 0.7)
                                        // nudges toward the submenu on hover
                                        transform: Translate {
                                            x: rowMa.containsMouse ? 2 : 0
                                            Behavior on x { NumberAnimation { duration: menu.anim ? 200 : 0; easing.type: Easing.OutBack } }
                                        }
                                    }
                                }

                                MouseArea {
                                    id: rowMa
                                    anchors.fill: parent
                                    enabled: row.enabledRow
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onEntered: if (menu.keyboardNav) menu.keyboardNav = false
                                    onClicked: menu.activated(row.e)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

}

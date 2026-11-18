// SPDX-License-Identifier: GPL-3.0-or-later
// Do not disturb (Android 15 style): quick durations + nightly schedule.
// Pure bindings on the applet state; the only timer lives in main.qml and is armed on the next deadline.
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import "i18n.js" as I18n

Item {
    id: dv
    function i18n(k, a1, a2) { return I18n.t(k, a1, a2); }
    signal closeRequested()
    property var applet: null
    property color tertiary: accent
    property color onTertiary: onAccent

    readonly property string appFont: "Google Sans Flex"
    readonly property color fg: Kirigami.Theme.textColor
    readonly property color accent: Kirigami.Theme.highlightColor
    readonly property color onAccent: Kirigami.Theme.highlightedTextColor
    function tint(a) { return Qt.rgba(fg.r, fg.g, fg.b, a); }
    function hhmm(min) { return ("0" + Math.floor(min / 60)).slice(-2) + ":" + ("0" + (min % 60)).slice(-2); }

    readonly property bool active: Boolean(applet && applet.isDndActive)
    readonly property bool schedule: Boolean(Plasmoid.configuration.dndSchedule)
    readonly property string statusText: !active ? i18n("Off")
        : (applet.dndUntil - new Date() < 86400000 ? i18n("Until %1", Qt.formatTime(applet.dndUntil, "HH:mm")) : i18n("Until you turn it off"))

    function inFor(ms) { var d = new Date(Date.now() + ms); applet.setDndUntil(d); }
    function untilMorning() { applet.setDndUntil(applet.dndNext(Plasmoid.configuration.dndEndMinutes)); }
    function forever() { var d = new Date(); d.setFullYear(d.getFullYear() + 1); applet.setDndUntil(d); }

    component Chip: Rectangle {
        id: chip
        property string label: ""
        property bool selected: false
        signal clicked()
        height: 36
        width: chipLabel.implicitWidth + 28
        radius: chipMa.pressed ? 10 : (selected ? 12 : 18)
        color: selected ? dv.accent : (chipMa.containsMouse ? dv.tint(0.10) : "transparent")
        border.width: selected ? 0 : 1
        border.color: dv.tint(0.25)
        Behavior on radius { NumberAnimation { duration: Kirigami.Units.longDuration > 1 ? 220 : 0; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: Kirigami.Units.longDuration > 1 ? 150 : 0 } }
        Text {
            id: chipLabel
            anchors.centerIn: parent
            text: chip.label
            font.family: dv.appFont; font.pixelSize: 12; font.weight: Font.Medium
            color: chip.selected ? dv.onAccent : dv.fg
        }
        MouseArea { id: chipMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: chip.clicked() }
    }

    component Row2: Rectangle {
        id: row
        property string label: ""
        property string sub: ""
        signal clicked()
        Layout.fillWidth: true
        Layout.preferredHeight: 52
        radius: rowMa.pressed ? 12 : 16
        color: rowMa.containsMouse ? dv.tint(0.10) : dv.tint(0.05)
        Behavior on radius { NumberAnimation { duration: Kirigami.Units.longDuration > 1 ? 200 : 0; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: Kirigami.Units.longDuration > 1 ? 120 : 0 } }
        ColumnLayout {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left; anchors.leftMargin: 16; anchors.right: parent.right; anchors.rightMargin: 16
            spacing: 0
            Text { text: row.label; font.family: dv.appFont; font.pixelSize: 14; color: dv.fg }
            Text { visible: row.sub.length > 0; text: row.sub; font.family: dv.appFont; font.pixelSize: 11; color: dv.tint(0.6) }
        }
        MouseArea { id: rowMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: row.clicked() }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Rectangle {
                Layout.preferredWidth: 40; Layout.preferredHeight: 40; radius: 20
                color: backMa.containsMouse ? dv.tint(0.10) : "transparent"
                Kirigami.Icon { anchors.centerIn: parent; width: 22; height: 22; source: Qt.resolvedUrl("icons/arrow_back.svg"); isMask: true; color: dv.fg }
                MouseArea { id: backMa; anchors.fill: parent; hoverEnabled: true; onClicked: dv.closeRequested() }
            }
            Text { Layout.fillWidth: true; text: dv.i18n("Do not disturb"); font.family: dv.appFont; font.pixelSize: 20; color: dv.fg }
        }

        // Big M3 toggle card
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 72
            radius: mainMa.pressed ? 18 : 28
            color: dv.active ? dv.accent : dv.tint(0.08)
            Behavior on color { ColorAnimation { duration: Kirigami.Units.longDuration > 1 ? 220 : 0 } }
            Behavior on radius { NumberAnimation { duration: Kirigami.Units.longDuration > 1 ? 260 : 0; easing.type: Easing.OutCubic } }
            Kirigami.Icon {
                id: mainIcon
                anchors.left: parent.left; anchors.leftMargin: 22; anchors.verticalCenter: parent.verticalCenter
                width: 26; height: 26
                source: Qt.resolvedUrl("icons/modes.svg"); isMask: true; color: dv.active ? dv.onAccent : dv.fg
            }
            Column {
                anchors.left: mainIcon.right; anchors.leftMargin: 16; anchors.right: parent.right; anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Text { text: dv.active ? dv.i18n("On") : dv.i18n("Off"); font.family: dv.appFont; font.pixelSize: 16; font.weight: Font.Medium; color: dv.active ? dv.onAccent : dv.fg }
                Text { text: dv.statusText; visible: dv.active; font.family: dv.appFont; font.pixelSize: 12; color: dv.active ? dv.onAccent : dv.tint(0.6) }
            }
            MouseArea { id: mainMa; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: dv.applet.toggleDoNotDisturbMode() }
        }

        Text { text: dv.i18n("Duration"); font.family: dv.appFont; font.pixelSize: 12; color: dv.tint(0.7) }
        Row2 { label: dv.i18n("For 1 hour"); sub: dv.i18n("Until %1", Qt.formatTime(new Date(Date.now() + 3600000), "HH:mm")); onClicked: dv.inFor(3600000) }
        Row2 { label: dv.i18n("For 3 hours"); sub: dv.i18n("Until %1", Qt.formatTime(new Date(Date.now() + 3 * 3600000), "HH:mm")); onClicked: dv.inFor(3 * 3600000) }
        Row2 { label: dv.i18n("Until tomorrow morning"); sub: dv.i18n("Until %1", dv.hhmm(Plasmoid.configuration.dndEndMinutes)); onClicked: dv.untilMorning() }
        Row2 { label: dv.i18n("Until you turn it off"); onClicked: dv.forever() }

        // Nightly schedule
        Item {
            Layout.fillWidth: true
            Layout.topMargin: 4
            Layout.preferredHeight: 44
            Column {
                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                spacing: 0
                Text { text: dv.i18n("Every night"); font.family: dv.appFont; font.pixelSize: 14; color: dv.fg }
                Text { text: dv.hhmm(Plasmoid.configuration.dndStartMinutes) + " – " + dv.hhmm(Plasmoid.configuration.dndEndMinutes); font.family: dv.appFont; font.pixelSize: 11; color: dv.tint(0.6) }
            }
            Rectangle {
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                width: 52; height: 32; radius: 16
                color: dv.schedule ? dv.tertiary : dv.tint(0.2)
                Behavior on color { ColorAnimation { duration: Kirigami.Units.longDuration > 1 ? 180 : 0 } }
                Rectangle {
                    width: dv.schedule ? 24 : 16; height: width; radius: width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    x: dv.schedule ? parent.width - width - 4 : 8
                    color: dv.schedule ? dv.onTertiary : dv.tint(0.7)
                    Behavior on x { NumberAnimation { duration: Kirigami.Units.longDuration > 1 ? 220 : 0; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
                    Behavior on width { NumberAnimation { duration: Kirigami.Units.longDuration > 1 ? 180 : 0 } }
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Plasmoid.configuration.dndSchedule = !dv.schedule }
            }
        }
        Flow {
            visible: dv.schedule
            Layout.fillWidth: true
            spacing: 8
            Repeater {
                model: [1260, 1320, 1380, 0]
                delegate: Chip {
                    required property int modelData
                    label: dv.hhmm(modelData)
                    selected: Plasmoid.configuration.dndStartMinutes === modelData
                    onClicked: Plasmoid.configuration.dndStartMinutes = modelData
                }
            }
            Text { text: "→"; color: dv.tint(0.5); font.pixelSize: 14; height: 36; verticalAlignment: Text.AlignVCenter }
            Repeater {
                model: [360, 420, 480, 540]
                delegate: Chip {
                    required property int modelData
                    label: dv.hhmm(modelData)
                    selected: Plasmoid.configuration.dndEndMinutes === modelData
                    onClicked: Plasmoid.configuration.dndEndMinutes = modelData
                }
            }
        }
        Item { Layout.fillHeight: true }
    }
}

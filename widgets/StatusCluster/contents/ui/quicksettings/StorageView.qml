// SPDX-License-Identifier: GPL-3.0-or-later
// Removable storage (USB keys, SD cards…): open / eject. Read when opened, never polled.
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support
import "i18n.js" as I18n

Item {
    id: sv
    function i18n(k, a1, a2) { return I18n.t(k, a1, a2); }
    signal closeRequested()
    signal opened()

    readonly property string appFont: "Google Sans Flex"
    readonly property color fg: Kirigami.Theme.textColor
    readonly property color accent: Kirigami.Theme.highlightColor
    function tint(a) { return Qt.rgba(fg.r, fg.g, fg.b, a); }
    readonly property string helper: decodeURIComponent(String(Qt.resolvedUrl("../../code/disks.py")).replace("file://", ""))
    function shq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'"; }
    function run(args, tag) { ds.connectSource("python3 " + shq(helper) + " " + args + " # " + tag + "-" + Date.now()); }
    function human(b) {
        var u = ["o", "Ko", "Mo", "Go", "To"], i = 0;
        while (b >= 1000 && i < u.length - 1) { b /= 1000; i++; }
        return (b >= 10 || i === 0 ? Math.round(b) : b.toFixed(1)) + " " + u[i];
    }

    property var parts: []
    property bool loaded: false
    property string busy: ""

    Component.onCompleted: run("list", "list")

    Plasma5Support.DataSource {
        id: ds
        engine: "executable"
        connectedSources: []
        onNewData: (src, data) => {
            disconnectSource(src);
            if (src.indexOf("# list") !== -1) {
                try { sv.parts = JSON.parse(data["stdout"] || "[]"); } catch (e) { sv.parts = []; }
                sv.loaded = true;
                sv.busy = "";
            } else if (src.indexOf("# eject") !== -1) {
                sv.run("list", "list");
            } else if (src.indexOf("# open") !== -1) {
                sv.busy = "";
                sv.opened();
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Rectangle {
                Layout.preferredWidth: 40; Layout.preferredHeight: 40; radius: 20
                color: backMa.containsMouse ? sv.tint(0.10) : "transparent"
                Kirigami.Icon { anchors.centerIn: parent; width: 22; height: 22; source: Qt.resolvedUrl("icons/arrow_back.svg"); isMask: true; color: sv.fg }
                MouseArea { id: backMa; anchors.fill: parent; hoverEnabled: true; onClicked: sv.closeRequested() }
            }
            Text { Layout.fillWidth: true; text: sv.i18n("Storage"); font.family: sv.appFont; font.pixelSize: 20; color: sv.fg }
        }

        Repeater {
            model: sv.parts
            delegate: Rectangle {
                id: card
                required property var modelData
                required property int index
                Layout.fillWidth: true
                Layout.preferredHeight: 88
                radius: 20
                color: sv.tint(0.06)
                opacity: 0
                Component.onCompleted: fade.start()
                NumberAnimation { id: fade; target: card; property: "opacity"; to: 1; duration: 280; easing.type: Easing.OutCubic }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 12

                    Rectangle {
                        Layout.preferredWidth: 44; Layout.preferredHeight: 44; radius: 14
                        color: Qt.rgba(sv.accent.r, sv.accent.g, sv.accent.b, 0.18)
                        Kirigami.Icon { anchors.centerIn: parent; width: 22; height: 22; source: Qt.resolvedUrl("icons/usb.svg"); isMask: true; color: sv.accent }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        Text { Layout.fillWidth: true; text: card.modelData.label; elide: Text.ElideRight; font.family: sv.appFont; font.pixelSize: 14; font.weight: Font.Medium; color: sv.fg }
                        Text {
                            Layout.fillWidth: true
                            text: sv.human(card.modelData.size) + " · " + card.modelData.fstype
                                  + (card.modelData.used >= 0 ? " · " + sv.i18n("%1% used", Math.round(card.modelData.used * 100)) : "")
                            elide: Text.ElideRight; font.family: sv.appFont; font.pixelSize: 11; color: sv.tint(0.65)
                        }
                        // M3 linear progress (used space)
                        Rectangle {
                            visible: card.modelData.used >= 0
                            Layout.fillWidth: true; Layout.preferredHeight: 6; radius: 3
                            color: sv.tint(0.12)
                            Rectangle { width: parent.width * Math.max(0, card.modelData.used); height: parent.height; radius: 3; color: sv.accent }
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 40; Layout.preferredHeight: 40; radius: openMa.pressed ? 12 : 20
                        color: sv.accent
                        Behavior on radius { NumberAnimation { duration: 180 } }
                        Kirigami.Icon { anchors.centerIn: parent; width: 20; height: 20; source: Qt.resolvedUrl("icons/folder_open.svg"); isMask: true; color: Kirigami.Theme.highlightedTextColor }
                        MouseArea { id: openMa; anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: { sv.busy = card.modelData.path; sv.run("open " + sv.shq(card.modelData.path), "open"); } }
                    }
                    Rectangle {
                        Layout.preferredWidth: 40; Layout.preferredHeight: 40; radius: ejectMa.pressed ? 12 : 20
                        color: ejectMa.containsMouse ? sv.tint(0.14) : sv.tint(0.08)
                        Behavior on radius { NumberAnimation { duration: 180 } }
                        Kirigami.Icon { anchors.centerIn: parent; width: 20; height: 20; source: Qt.resolvedUrl("icons/eject.svg"); isMask: true; color: sv.fg }
                        MouseArea { id: ejectMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { sv.busy = card.modelData.disk; sv.run("eject " + sv.shq(card.modelData.disk), "eject"); } }
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: sv.loaded && sv.parts.length === 0
            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            text: sv.i18n("No USB key or removable disk")
            font.family: sv.appFont; font.pixelSize: 13; color: sv.tint(0.6)
        }
        Item { Layout.fillHeight: true; visible: sv.parts.length > 0 }
    }
}

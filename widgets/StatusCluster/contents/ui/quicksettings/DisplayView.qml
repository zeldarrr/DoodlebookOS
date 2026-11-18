// SPDX-License-Identifier: GPL-3.0-or-later
// Display panel: scale and refresh rate chips per screen, on/off when several screens.
// Read when opened (kscreen-doctor), never polled.
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCMUtils
import org.kde.plasma.plasma5support as Plasma5Support
import "i18n.js" as I18n

Item {
    id: dv
    function i18n(k, a1, a2) { return I18n.t(k, a1, a2); }
    signal closeRequested()

    readonly property string appFont: "Google Sans Flex"
    readonly property color fg: Kirigami.Theme.textColor
    readonly property color accent: Kirigami.Theme.highlightColor
    function tint(a) { return Qt.rgba(fg.r, fg.g, fg.b, a); }
    readonly property string helper: decodeURIComponent(String(Qt.resolvedUrl("../../code/display.py")).replace("file://", ""))
    function shq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'"; }
    function run(args, tag) { ds.connectSource("python3 " + shq(helper) + " " + args + " # " + tag + "-" + Date.now()); }

    property var outputs: []
    readonly property var scales: [1, 1.25, 1.5, 1.75, 2]

    Component.onCompleted: run("list", "list")

    Plasma5Support.DataSource {
        id: ds
        engine: "executable"
        connectedSources: []
        onNewData: (src, data) => {
            disconnectSource(src);
            if (src.indexOf("# list") !== -1) {
                try { dv.outputs = JSON.parse(data["stdout"] || "[]"); } catch (e) { dv.outputs = []; }
            } else {
                dv.run("list", "list"); // re-read after a change
            }
        }
    }

    component Chip: Rectangle {
        id: chip
        property string label: ""
        property bool selected: false
        signal clicked()
        height: 36
        width: chipLabel.implicitWidth + 28
        radius: selected ? 12 : 18
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
            color: chip.selected ? Kirigami.Theme.highlightedTextColor : dv.fg
        }
        MouseArea { id: chipMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: chip.clicked() }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 14

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Rectangle {
                Layout.preferredWidth: 40; Layout.preferredHeight: 40; radius: 20
                color: backMa.containsMouse ? dv.tint(0.10) : "transparent"
                Kirigami.Icon { anchors.centerIn: parent; width: 22; height: 22; source: Qt.resolvedUrl("icons/arrow_back.svg"); isMask: true; color: dv.fg }
                MouseArea { id: backMa; anchors.fill: parent; hoverEnabled: true; onClicked: dv.closeRequested() }
            }
            Text { Layout.fillWidth: true; text: dv.i18n("Display"); font.family: dv.appFont; font.pixelSize: 20; color: dv.fg }
            Rectangle {
                Layout.preferredWidth: 40; Layout.preferredHeight: 40; radius: 20
                color: setMa.containsMouse ? dv.tint(0.10) : "transparent"
                Kirigami.Icon { anchors.centerIn: parent; width: 20; height: 20; source: Qt.resolvedUrl("icons/settings.svg"); isMask: true; color: dv.fg }
                MouseArea { id: setMa; anchors.fill: parent; hoverEnabled: true; onClicked: KCMUtils.KCMLauncher.openSystemSettings("kcm_kscreen") }
            }
        }

        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: col.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: col
                width: parent.width
                spacing: 12

                Repeater {
                    model: dv.outputs
                    delegate: Rectangle {
                        id: card
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: inner.implicitHeight + 28
                        radius: 24
                        color: dv.tint(0.06)

                        ColumnLayout {
                            id: inner
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 10

                            RowLayout {
                                Layout.fillWidth: true
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Text { text: card.modelData.name; font.family: dv.appFont; font.pixelSize: 15; font.weight: Font.Medium; color: dv.fg }
                                    Text {
                                        text: card.modelData.w + " × " + card.modelData.h + " · " + card.modelData.hz + " Hz"
                                        font.family: dv.appFont; font.pixelSize: 12; color: dv.tint(0.65)
                                    }
                                }
                                // on/off only makes sense with several screens
                                Rectangle {
                                    visible: dv.outputs.length > 1
                                    width: 52; height: 32; radius: 16
                                    color: card.modelData.enabled ? dv.accent : dv.tint(0.2)
                                    Rectangle {
                                        width: 24; height: 24; radius: 12; y: 4
                                        x: card.modelData.enabled ? parent.width - width - 4 : 4
                                        color: card.modelData.enabled ? Kirigami.Theme.highlightedTextColor : "white"
                                        Behavior on x { NumberAnimation { duration: Kirigami.Units.longDuration > 1 ? 180 : 0; easing.type: Easing.OutCubic } }
                                    }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: dv.run((card.modelData.enabled ? "disable " : "enable ") + dv.shq(card.modelData.name), "set") }
                                }
                            }

                            Text { visible: card.modelData.enabled; text: dv.i18n("Scale"); font.family: dv.appFont; font.pixelSize: 12; color: dv.tint(0.7) }
                            Flow {
                                visible: card.modelData.enabled
                                Layout.fillWidth: true
                                spacing: 8
                                Repeater {
                                    model: dv.scales
                                    delegate: Chip {
                                        required property var modelData
                                        label: Math.round(modelData * 100) + " %"
                                        selected: Math.abs(card.modelData.scale - modelData) < 0.01
                                        onClicked: dv.run("scale " + dv.shq(card.modelData.name) + " " + modelData, "set")
                                    }
                                }
                            }

                            Text { visible: card.modelData.enabled && card.modelData.rates.length > 1; text: dv.i18n("Refresh rate"); font.family: dv.appFont; font.pixelSize: 12; color: dv.tint(0.7) }
                            Flow {
                                visible: card.modelData.enabled && card.modelData.rates.length > 1
                                Layout.fillWidth: true
                                spacing: 8
                                Repeater {
                                    model: card.modelData.rates
                                    delegate: Chip {
                                        required property var modelData
                                        label: modelData.hz + " Hz"
                                        selected: modelData.hz === card.modelData.hz
                                        onClicked: dv.run("mode " + dv.shq(card.modelData.name) + " " + dv.shq(modelData.id), "set")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

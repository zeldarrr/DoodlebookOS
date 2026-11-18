// SPDX-License-Identifier: GPL-3.0-or-later
// Clipboard history (Material cards). Read once when opened; nothing runs in the background.
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support
import "i18n.js" as I18n

Item {
    id: clipView
    function i18n(k, a1, a2) { return I18n.t(k, a1, a2); }
    signal closeRequested()
    signal pasted()

    readonly property string appFont: "Google Sans Flex"
    readonly property color fg: Kirigami.Theme.textColor
    readonly property color accent: Kirigami.Theme.highlightColor
    function tint(a) { return Qt.rgba(fg.r, fg.g, fg.b, a); }
    readonly property string helper: decodeURIComponent(String(Qt.resolvedUrl("../../code/clipboard.py")).replace("file://", ""))
    function shq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'"; }
    function run(args, tag) { ds.connectSource("python3 " + shq(helper) + " " + args + " # " + tag + "-" + Date.now()); }

    property var items: []
    property bool loaded: false
    property int copiedIndex: -1

    Component.onCompleted: run("list 30", "list")

    Plasma5Support.DataSource {
        id: ds
        engine: "executable"
        connectedSources: []
        onNewData: (src, data) => {
            disconnectSource(src);
            if (src.indexOf("# list") !== -1) {
                try { clipView.items = JSON.parse(data["stdout"] || "[]"); } catch (e) { clipView.items = []; }
                clipView.loaded = true;
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
                color: backMa.containsMouse ? clipView.tint(0.10) : "transparent"
                Kirigami.Icon { anchors.centerIn: parent; width: 22; height: 22; source: Qt.resolvedUrl("icons/arrow_back.svg"); isMask: true; color: clipView.fg }
                MouseArea { id: backMa; anchors.fill: parent; hoverEnabled: true; onClicked: clipView.closeRequested() }
            }
            Text {
                Layout.fillWidth: true
                text: clipView.i18n("Clipboard")
                font.family: clipView.appFont; font.pixelSize: 20; color: clipView.fg
            }
            Rectangle {
                visible: clipView.items.length > 0
                Layout.preferredHeight: 34
                Layout.preferredWidth: clearTxt.implicitWidth + 28
                radius: 17
                color: clearMa.containsMouse ? clipView.tint(0.10) : "transparent"
                border.width: 1; border.color: clipView.tint(0.25)
                Text { id: clearTxt; anchors.centerIn: parent; text: clipView.i18n("Clear all"); font.family: clipView.appFont; font.pixelSize: 12; font.weight: Font.Medium; color: clipView.fg }
                MouseArea { id: clearMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: { clipView.run("clear", "clear"); clipView.items = []; } }
            }
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 8
            boundsBehavior: Flickable.StopAtBounds
            model: clipView.items
            cacheBuffer: 0

            delegate: Rectangle {
                id: card
                required property var modelData
                required property int index
                width: list.width
                height: body.implicitHeight + 24
                radius: copied ? 24 : 16
                readonly property bool copied: clipView.copiedIndex === modelData.i
                color: copied ? clipView.accent : (cardMa.containsMouse ? clipView.tint(0.11) : clipView.tint(0.06))
                Behavior on color { ColorAnimation { duration: Kirigami.Units.longDuration > 1 ? 150 : 0 } }
                Behavior on radius { NumberAnimation { duration: Kirigami.Units.longDuration > 1 ? 260 : 0; easing.type: Easing.OutCubic } }
                // staggered entrance, only for the first visible cards
                opacity: 0
                transform: Translate { id: tr; y: 14 }
                Component.onCompleted: enter.start()
                ParallelAnimation {
                    id: enter
                    PauseAnimation { duration: Math.min(card.index, 8) * 35 }
                    NumberAnimation { target: card; property: "opacity"; to: 1; duration: Kirigami.Units.longDuration > 1 ? 260 : 0; easing.type: Easing.OutCubic }
                    NumberAnimation { target: tr; property: "y"; to: 0; duration: Kirigami.Units.longDuration > 1 ? 380 : 0; easing.type: Easing.OutQuart }
                }

                Text {
                    id: body
                    anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 16; anchors.rightMargin: 16
                    text: card.copied ? clipView.i18n("Copied") : card.modelData.text.trim()
                    maximumLineCount: 3
                    wrapMode: Text.Wrap
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    font.family: clipView.appFont; font.pixelSize: 13
                    color: card.copied ? Kirigami.Theme.highlightedTextColor : clipView.fg
                }
                MouseArea {
                    id: cardMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        clipView.run("set " + card.modelData.i, "set");
                        clipView.copiedIndex = card.modelData.i;
                        closeTimer.restart();
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: clipView.loaded && clipView.items.length === 0
            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            text: clipView.i18n("Clipboard is empty")
            font.family: clipView.appFont; font.pixelSize: 13; color: clipView.tint(0.6)
        }
    }

    Timer { id: closeTimer; interval: 600; onTriggered: clipView.pasted() }
}

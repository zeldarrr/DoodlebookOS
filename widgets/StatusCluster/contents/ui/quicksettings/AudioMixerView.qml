// SPDX-License-Identifier: GPL-3.0-or-later
// Per-app volume (Android 15 style): one M3 pill slider per playing application.
// Event-driven: rows come from plasma-pa's live SinkInputModel, nothing polls.
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCMUtils
import org.kde.plasma.private.volume as Volume
import "i18n.js" as I18n

Item {
    id: mixer
    function i18n(k, a1, a2) { return I18n.t(k, a1, a2); }
    signal closeRequested()

    readonly property string appFont: "Google Sans Flex"
    readonly property real normalVolume: 65536
    readonly property color fg: Kirigami.Theme.textColor
    readonly property color accent: Kirigami.Theme.highlightColor
    function tint(a) { return Qt.rgba(fg.r, fg.g, fg.b, a); }

    Volume.SinkInputModel { id: streams }

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Rectangle {
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                radius: 20
                color: backMa.containsMouse ? mixer.tint(0.10) : "transparent"
                Kirigami.Icon {
                    anchors.centerIn: parent
                    width: 22; height: 22
                    source: Qt.resolvedUrl("icons/arrow_back.svg")
                    isMask: true
                    color: mixer.fg
                }
                MouseArea { id: backMa; anchors.fill: parent; hoverEnabled: true; onClicked: mixer.closeRequested() }
            }

            Text {
                Layout.fillWidth: true
                text: mixer.i18n("App volume")
                font.family: mixer.appFont
                font.pixelSize: 20
                color: mixer.fg
            }

            Rectangle {
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                radius: 20
                color: setMa.containsMouse ? mixer.tint(0.10) : "transparent"
                Kirigami.Icon {
                    anchors.centerIn: parent
                    width: 20; height: 20
                    source: Qt.resolvedUrl("icons/settings.svg")
                    isMask: true
                    color: mixer.fg
                }
                MouseArea { id: setMa; anchors.fill: parent; hoverEnabled: true; onClicked: KCMUtils.KCMLauncher.openSystemSettings("kcm_pulseaudio") }
            }
        }

        // Output device chips (headphones / speakers…): click = make it the default sink
        Flow {
            Layout.fillWidth: true
            spacing: 8
            visible: sinkRep.count > 1
            Repeater {
                id: sinkRep
                model: Volume.SinkModel {}
                delegate: Rectangle {
                    required property var model
                    readonly property var sink: model.PulseObject
                    readonly property bool isDefault: sink ? Boolean(sink["default"]) : false
                    height: 36
                    width: Math.min(chipText.implicitWidth + 44, mixer.width)
                    radius: isDefault ? 12 : 18
                    color: isDefault ? mixer.accent : (chipMa.containsMouse ? mixer.tint(0.10) : "transparent")
                    border.width: isDefault ? 0 : 1
                    border.color: mixer.tint(0.25)
                    Behavior on radius { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Kirigami.Icon {
                        id: chipIcon
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: 16; height: 16
                        source: (sink && sink.properties && String(sink.properties["device.form_factor"] || "").indexOf("head") >= 0) ? "audio-headphones" : "audio-speakers"
                        isMask: true
                        color: parent.isDefault ? Kirigami.Theme.highlightedTextColor : mixer.fg
                    }
                    Text {
                        id: chipText
                        anchors.left: chipIcon.right
                        anchors.leftMargin: 8
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: sink ? (sink.description || sink.name) : ""
                        elide: Text.ElideRight
                        font.family: mixer.appFont
                        font.pixelSize: 12
                        font.weight: Font.Medium
                        color: parent.isDefault ? Kirigami.Theme.highlightedTextColor : mixer.fg
                    }
                    MouseArea { id: chipMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: if (parent.sink) parent.sink["default"] = true }
                }
            }
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 10
            boundsBehavior: Flickable.StopAtBounds
            model: streams
            reuseItems: true

            add: Transition { NumberAnimation { properties: "opacity,scale"; from: 0; to: 1; duration: 320; easing.type: Easing.OutQuart } }
            remove: Transition { NumberAnimation { properties: "opacity"; to: 0; duration: 180 } }
            displaced: Transition { NumberAnimation { properties: "y"; duration: 320; easing.type: Easing.OutQuart } }

            delegate: Item {
                id: row
                required property var model
                required property int index
                readonly property var obj: model.PulseObject
                readonly property var props: obj && obj.properties ? obj.properties : ({})
                readonly property bool hidden: !obj || props["media.role"] === "event" || Boolean(obj.virtualStream)
                readonly property string appName: (obj && obj.client && obj.client.name) ? obj.client.name
                                                 : (props["application.name"] || (obj ? obj.name : ""))
                readonly property string iconName: props["application.icon_name"] || props["application.process.binary"] || "audio-volume-high"
                readonly property bool muted: obj ? Boolean(obj.muted) : false
                readonly property real level: obj ? Math.min(1.5, obj.volume / mixer.normalVolume) : 0
                width: list.width
                height: hidden ? 0 : 56
                visible: !hidden

                RowLayout {
                    anchors.fill: parent
                    spacing: 10

                    // icon = mute toggle (shape morphs circle -> rounded square when muted)
                    Rectangle {
                        Layout.preferredWidth: 48
                        Layout.preferredHeight: 48
                        radius: row.muted ? 14 : 24
                        color: row.muted ? mixer.tint(0.10) : Qt.rgba(mixer.accent.r, mixer.accent.g, mixer.accent.b, 0.18)
                        Behavior on radius { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                        Kirigami.Icon {
                            anchors.centerIn: parent
                            width: 28; height: 28
                            source: row.iconName
                            fallback: "audio-volume-high"
                            opacity: row.muted ? 0.45 : 1
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (row.obj) row.obj.muted = !row.obj.muted
                        }
                    }

                    // M3 thick pill slider (fill + handle), drag or click to set
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 48

                        Rectangle {
                            id: track
                            anchors.fill: parent
                            radius: height / 2
                            color: mixer.tint(0.08)
                            clip: true

                            Rectangle {
                                // 0 % = no fill at all (the pill minimum only applies once there is sound)
                                width: row.level <= 0.004 ? 0 : Math.max(track.height, track.width * Math.min(1, row.level))
                                visible: width > 0.5
                                height: parent.height
                                radius: parent.radius
                                color: row.muted ? mixer.tint(0.25) : mixer.accent
                                Behavior on width { enabled: !dragMa.pressed; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.leftMargin: 18
                                anchors.right: pct.left
                                anchors.rightMargin: 8
                                text: row.appName
                                elide: Text.ElideRight
                                font.family: mixer.appFont
                                font.pixelSize: 13
                                font.weight: Font.Medium
                                color: row.level > 0.35 && !row.muted ? Kirigami.Theme.highlightedTextColor : mixer.fg
                            }

                            Text {
                                id: pct
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.right: parent.right
                                anchors.rightMargin: 16
                                text: Math.round(row.level * 100) + " %"
                                font.family: mixer.appFont
                                font.pixelSize: 12
                                color: row.level > 0.92 && !row.muted ? Kirigami.Theme.highlightedTextColor : mixer.tint(0.7)
                            }
                        }

                        MouseArea {
                            id: dragMa
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            function setFrom(x) {
                                if (!row.obj) return;
                                var v = Math.max(0, Math.min(1, x / width));
                                row.obj.volume = Math.round(v * mixer.normalVolume);
                                if (row.obj.muted && v > 0) row.obj.muted = false;
                            }
                            onPressed: (mouse) => setFrom(mouse.x)
                            onPositionChanged: (mouse) => { if (pressed) setFrom(mouse.x); }
                            onWheel: (wheel) => {
                                if (!row.obj) return;
                                var step = (wheel.angleDelta.y > 0 ? 0.05 : -0.05);
                                setFrom((Math.min(1, row.level) + step) * width);
                            }
                        }
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: list.count === 0
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: mixer.i18n("No app is playing sound")
            font.family: mixer.appFont
            font.pixelSize: 13
            color: mixer.tint(0.6)
        }
    }
}

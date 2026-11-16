/*
 * SPDX-FileCopyrightText: 2024-2026 Maciej Kujawiński <maciek.kujawinski@gmail.com>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "i18n.js" as I18n

// Phone notification card — follows the Plasma colour scheme (light & dark).
Rectangle {
    id: root

    function i18n(k, a1, a2) { return I18n.t(k, a1, a2); }

    property var notifModel: null
    property bool isReplying: false
    property real enter: 1.0

    readonly property color fg: Kirigami.Theme.textColor
    function tint(a) { return Qt.rgba(fg.r, fg.g, fg.b, a); }

    width: parent ? parent.width : 0
    implicitHeight: mainCol.implicitHeight + 24
    radius: 20
    color: tint(0.06)
    opacity: enter
    transform: Translate { y: (1 - root.enter) * 14 }

    function dismiss() {
        if (!notifModel) return;
        if (notifModel.dbusInterface && typeof notifModel.dbusInterface.dismiss === "function")
            notifModel.dbusInterface.dismiss();
    }

    function send() {
        var msg = replyInput.text.trim();
        if (!msg || !notifModel) return;
        if (notifModel.dbusInterface && typeof notifModel.dbusInterface.sendReply === "function")
            notifModel.dbusInterface.sendReply(msg);
        replyInput.text = "";
        isReplying = false;
    }

    ColumnLayout {
        id: mainCol
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 12
        anchors.leftMargin: 14
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Kirigami.Icon {
                Layout.preferredWidth: 16
                Layout.preferredHeight: 16
                source: (root.notifModel && root.notifModel.appIcon) ? root.notifModel.appIcon : "notifications"
            }

            Text {
                Layout.fillWidth: true
                text: (root.notifModel && root.notifModel.appName) ? root.notifModel.appName : ""
                font.family: "Google Sans Flex"
                font.pixelSize: 11
                color: root.tint(0.65)
                elide: Text.ElideRight
            }

            Rectangle {
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                radius: 12
                visible: Boolean(root.notifModel && root.notifModel.dismissable)
                color: closeMa.containsMouse ? root.tint(0.12) : "transparent"
                Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }

                Kirigami.Icon {
                    anchors.centerIn: parent
                    width: 14
                    height: 14
                    source: "window-close-symbolic"
                    color: root.tint(0.75)
                    isMask: true
                }

                MouseArea {
                    id: closeMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.dismiss()
                }
            }
        }

        Text {
            Layout.fillWidth: true
            text: (root.notifModel && root.notifModel.title) ? root.notifModel.title : ""
            visible: text.length > 0
            font.family: "Google Sans Flex"
            font.pixelSize: 13
            font.weight: Font.DemiBold
            color: root.fg
            elide: Text.ElideRight
        }

        Text {
            Layout.fillWidth: true
            text: (root.notifModel && root.notifModel.notitext) ? root.notifModel.notitext : ""
            visible: text.length > 0
            font.family: "Google Sans Flex"
            font.pixelSize: 12
            color: root.tint(0.85)
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
        }

        // Quick reply (M3 tonal button → inline text field)
        Item {
            Layout.fillWidth: true
            Layout.topMargin: 4
            Layout.preferredHeight: root.isReplying ? 36 : 28
            visible: Boolean(root.notifModel && root.notifModel.repliable)
            Behavior on Layout.preferredHeight { NumberAnimation { duration: Kirigami.Units.shortDuration; easing.type: Easing.OutCubic } }

            Rectangle {
                visible: !root.isReplying
                height: 28
                width: replyLabel.implicitWidth + 28
                radius: 14
                color: replyBtnMa.containsMouse
                       ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.30)
                       : Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.18)
                Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }

                Text {
                    id: replyLabel
                    anchors.centerIn: parent
                    text: root.i18n("Reply")
                    font.family: "Google Sans Flex"
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    color: root.fg
                }

                MouseArea {
                    id: replyBtnMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.isReplying = true;
                        replyInput.forceActiveFocus();
                    }
                }
            }

            RowLayout {
                anchors.fill: parent
                visible: root.isReplying
                spacing: 6

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    radius: 18
                    color: root.tint(0.08)
                    border.color: replyInput.activeFocus ? Kirigami.Theme.highlightColor : root.tint(0.18)
                    border.width: 1

                    TextInput {
                        id: replyInput
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        verticalAlignment: TextInput.AlignVCenter
                        font.family: "Google Sans Flex"
                        font.pixelSize: 12
                        color: root.fg
                        selectionColor: Kirigami.Theme.highlightColor
                        selectedTextColor: Kirigami.Theme.highlightedTextColor
                        clip: true
                        onAccepted: root.send()
                        Keys.onEscapePressed: { text = ""; root.isReplying = false; }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: replyInput.text.length === 0
                            text: root.i18n("Reply…")
                            font: replyInput.font
                            color: root.tint(0.45)
                        }
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    radius: 18
                    color: Kirigami.Theme.highlightColor
                    opacity: replyInput.text.trim().length > 0 ? 1.0 : 0.5

                    Kirigami.Icon {
                        anchors.centerIn: parent
                        width: 18
                        height: 18
                        source: Qt.resolvedUrl("icons/send_to.svg")
                        isMask: true
                        color: Kirigami.Theme.highlightedTextColor
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.send()
                    }
                }
            }
        }
    }
}

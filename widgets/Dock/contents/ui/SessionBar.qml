// SPDX-License-Identifier: GPL-3.0-or-later
// Bottom bar: user, Edit, and session buttons (lock / sleep / restart / shut down / log out).
// In edit mode it morphs into the edit toolbar (full screen, hidden apps, done).
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.coreaddons as KCoreAddons
import org.kde.plasma.private.sessions as Sessions
import org.kde.plasma.plasmoid
import "i18n.js" as I18n

FocusScope {
    id: bar
    function i18n(k, a1, a2) { return I18n.t(k, a1, a2); }

    readonly property color fg: Kirigami.Theme.textColor
    readonly property color accent: Kirigami.Theme.highlightColor
    readonly property color onAccent: (0.299 * accent.r + 0.587 * accent.g + 0.114 * accent.b) > 0.62 ? "#1d1a2c" : Kirigami.Theme.highlightedTextColor
    function tint(a) { return Qt.rgba(fg.r, fg.g, fg.b, a); }

    property bool showHidden: false
    function focusFirst() { (root.editMode ? doneBtn : editBtn).forceActiveFocus(Qt.TabFocusReason); }

    KCoreAddons.KUser { id: kuser }
    Sessions.SessionManagement { id: sm }

    // ── icon button with M3 Expressive shape morph (circle -> squircle while pressed) ──
    component IconBtn: Rectangle {
        id: btn
        property url icon
        property string tip: ""
        property bool danger: false
        signal activated()
        width: 40; height: 40
        radius: btnMa.pressed ? 12 : (activeFocus ? 14 : 20)
        color: activeFocus ? bar.tint(0.16) : (btnMa.containsMouse ? (danger ? Qt.rgba(1, 0.35, 0.3, 0.18) : bar.tint(0.10)) : "transparent")
        border.width: activeFocus ? 1.5 : 0
        border.color: bar.accent
        activeFocusOnTab: true
        Behavior on radius { NumberAnimation { duration: Kirigami.Units.longDuration > 1 ? 240 : 0; easing.type: Easing.OutBack; easing.overshoot: 1.5 } }
        Behavior on color { ColorAnimation { duration: Kirigami.Units.longDuration > 1 ? 120 : 0 } }
        scale: btnMa.pressed ? 0.92 : 1
        Behavior on scale { NumberAnimation { duration: Kirigami.Units.longDuration > 1 ? 160 : 0; easing.type: Easing.OutBack; easing.overshoot: 2 } }
        Keys.onReturnPressed: activated()
        Keys.onEnterPressed: activated()
        Keys.onSpacePressed: activated()
        Image { id: bi; anchors.centerIn: parent; width: 20; height: 20; source: btn.icon; sourceSize: Qt.size(40, 40); visible: false }
        MultiEffect { anchors.fill: bi; source: bi; colorization: 1.0; colorizationColor: bar.fg }
        MouseArea { id: btnMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: btn.activated() }
        QQC2.ToolTip.visible: btnMa.containsMouse && tip.length > 0
        QQC2.ToolTip.delay: 450
        QQC2.ToolTip.text: tip
    }

    // ───────── normal mode ─────────
    RowLayout {
        anchors.fill: parent
        spacing: 4
        visible: opacity > 0
        opacity: root.editMode ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: Kirigami.Units.longDuration > 1 ? 160 : 0 } }

        // avatar + name
        Rectangle {
            Layout.preferredWidth: 36; Layout.preferredHeight: 36
            radius: 18
            color: bar.accent
            clip: true
            Text {
                anchors.centerIn: parent
                visible: avatar.status !== Image.Ready
                text: (kuser.fullName || kuser.loginName || "?").charAt(0).toUpperCase()
                font.family: "Google Sans Flex"; font.pixelSize: 16; font.weight: Font.DemiBold
                color: bar.onAccent
            }
            Image {
                id: avatar
                anchors.fill: parent
                source: kuser.faceIconUrl
                sourceSize: Qt.size(72, 72)
                fillMode: Image.PreserveAspectCrop
                visible: false
            }
            Rectangle { id: avatarMask; anchors.fill: parent; radius: 18; visible: false; layer.enabled: true }
            MultiEffect {
                anchors.fill: parent
                source: avatar
                visible: avatar.status === Image.Ready
                maskEnabled: true
                maskSource: avatarMask
            }
        }
        Text {
            Layout.leftMargin: 8
            Layout.fillWidth: true
            text: kuser.fullName || kuser.loginName
            elide: Text.ElideRight
            font.family: "Google Sans Flex"; font.pixelSize: 14; font.weight: Font.Medium
            color: bar.fg
        }

        IconBtn { id: editBtn; icon: Qt.resolvedUrl("icons/edit.svg"); tip: bar.i18n("Edit"); onActivated: root.editMode = true }
        Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 22; Layout.leftMargin: 4; Layout.rightMargin: 4; color: bar.tint(0.18) }
        IconBtn { icon: Qt.resolvedUrl("icons/lock.svg"); tip: bar.i18n("Lock"); visible: sm.canLock
            onActivated: { root.close(); sm.lock(); } }
        IconBtn { icon: Qt.resolvedUrl("icons/sleep.svg"); tip: bar.i18n("Sleep"); visible: sm.canSuspend
            onActivated: { root.close(); sm.suspend(); } }
        IconBtn { icon: Qt.resolvedUrl("icons/restart.svg"); tip: bar.i18n("Restart"); visible: sm.canReboot
            onActivated: { root.close(); sm.requestReboot(); } }
        IconBtn { icon: Qt.resolvedUrl("icons/power.svg"); tip: bar.i18n("Shut down"); danger: true; visible: sm.canShutdown
            onActivated: { root.close(); sm.requestShutdown(); } }
        IconBtn { icon: Qt.resolvedUrl("icons/logout.svg"); tip: bar.i18n("Log out"); visible: sm.canLogout
            onActivated: { root.close(); sm.requestLogout(); } }
    }

    // ───────── edit mode toolbar ─────────
    RowLayout {
        anchors.fill: parent
        spacing: 10
        visible: opacity > 0
        opacity: root.editMode ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Kirigami.Units.longDuration > 1 ? 160 : 0 } }

        Text {
            Layout.fillWidth: true
            text: bar.i18n("Drag an app onto another to make a folder")
            elide: Text.ElideRight
            font.family: "Google Sans Flex"; font.pixelSize: 12
            color: bar.tint(0.65)
        }

        // full-screen switch
        Row {
            spacing: 8
            Text { anchors.verticalCenter: parent.verticalCenter; text: bar.i18n("Full screen"); font.family: "Google Sans Flex"; font.pixelSize: 13; color: bar.fg }
            Rectangle {
                id: fsSwitch
                readonly property bool on: Plasmoid.configuration.launcherFullscreen === true
                width: 52; height: 32; radius: 16
                color: on ? bar.accent : bar.tint(0.2)
                activeFocusOnTab: true
                border.width: activeFocus ? 2 : 0
                border.color: bar.fg
                Behavior on color { ColorAnimation { duration: Kirigami.Units.longDuration > 1 ? 180 : 0 } }
                function toggle() { Plasmoid.configuration.launcherFullscreen = !on; }
                Keys.onSpacePressed: toggle()
                Keys.onReturnPressed: toggle()
                Rectangle {
                    width: fsSwitch.on ? 24 : 16; height: width; radius: width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    x: fsSwitch.on ? parent.width - width - 4 : 8
                    color: fsSwitch.on ? bar.onAccent : bar.tint(0.7)
                    Behavior on x { NumberAnimation { duration: Kirigami.Units.longDuration > 1 ? 240 : 0; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
                    Behavior on width { NumberAnimation { duration: Kirigami.Units.longDuration > 1 ? 180 : 0 } }
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: fsSwitch.toggle() }
            }
        }

        IconBtn {
            icon: Qt.resolvedUrl(bar.showHidden ? "icons/visibility.svg" : "icons/visibility_off.svg")
            tip: bar.i18n("Hidden apps")
            onActivated: bar.showHidden = !bar.showHidden
        }

        Rectangle {
            id: doneBtn
            Layout.preferredHeight: 40
            Layout.preferredWidth: doneLabel.implicitWidth + 36
            radius: doneMa.pressed ? 12 : 20
            color: bar.accent
            activeFocusOnTab: true
            border.width: activeFocus ? 2 : 0
            border.color: bar.fg
            Behavior on radius { NumberAnimation { duration: Kirigami.Units.longDuration > 1 ? 240 : 0; easing.type: Easing.OutBack; easing.overshoot: 1.5 } }
            Keys.onReturnPressed: root.editMode = false
            Keys.onSpacePressed: root.editMode = false
            Text { id: doneLabel; anchors.centerIn: parent; text: bar.i18n("Done"); font.family: "Google Sans Flex"; font.pixelSize: 14; font.weight: Font.DemiBold; color: bar.onAccent }
            MouseArea { id: doneMa; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.editMode = false }
        }
    }

    Connections {
        target: root
        function onEditModeChanged() { if (!root.editMode) bar.showHidden = false; }
    }
}

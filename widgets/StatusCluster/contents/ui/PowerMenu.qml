/*
    SPDX-License-Identifier: GPL-3.0-or-later

    Material 3 Expressive power menu (Android 12+ style): the screen dims and a row of large
    tonal buttons springs up — Lock, Sleep, Sign out, Restart, Power off. A click acts at once
    (this screen is the confirmation, like on Android); Esc or a click on the scrim cancels.
    Arrows/Tab move the focus, Enter acts.

    A layer-shell overlay, created on first use only (Loader in main.qml). One timer drives the
    entrance on the shared M3 springs (motion.js); nothing runs while it is closed.
*/
import QtQuick
import QtQuick.Window
import org.kde.kirigami as Kirigami
import org.kde.layershell as LayerShell
import org.kde.plasma.private.sessions as Sessions
import "motion.js" as Motion

Window {
    id: menu

    flags: Qt.FramelessWindowHint
    color: "transparent"
    visible: false

    LayerShell.Window.scope: "doodlebookos-power"
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom
                               | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityExclusive

    property bool dark: true
    property color accent: Kirigami.Theme.highlightColor
    property string fontFamily: "Google Sans Flex"
    property var labels: ({})          // optional translations: {lock, sleep, logout, restart, shutdown, hint}
    function label(k, fallback) { return labels[k] || fallback; }

    Sessions.SessionManagement { id: sm }

    readonly property var actions: {
        var a = [];
        if (sm.canLock) a.push({ id: "lock", icon: "quicksettings/icons/custom_lock.svg", text: label("lock", "Verrouiller") });
        if (sm.canSuspend) a.push({ id: "sleep", icon: "quicksettings/icons/moon.svg", text: label("sleep", "Veille") });
        if (sm.canLogout) a.push({ id: "logout", icon: "quicksettings/icons/logout.svg", text: label("logout", "Se déconnecter") });
        if (sm.canReboot) a.push({ id: "restart", icon: "quicksettings/icons/restart.svg", text: label("restart", "Redémarrer") });
        if (sm.canShutdown) a.push({ id: "shutdown", icon: "quicksettings/icons/power_btn.svg", text: label("shutdown", "Éteindre"), primary: true });
        return a;
    }
    property int focusIndex: -1

    // ── motion ───────────────────────────────────────────────────────────────────────────────
    readonly property bool animate: Kirigami.Units.longDuration > 1
    property real revealMs: 100000
    property real hideT: 0                       // 0 → 1 while closing
    NumberAnimation {
        id: openAnim
        target: menu; property: "revealMs"; from: 0; to: 900
        duration: menu.animate ? 900 * Motion.speed(Kirigami.Units.longDuration) : 0
    }
    NumberAnimation {
        id: closeAnim
        target: menu; property: "hideT"; from: 0; to: 1
        duration: menu.animate ? 160 : 0
        easing.type: Easing.InCubic
        onFinished: { menu.visible = false; if (menu.pending) { var f = menu.pending; menu.pending = null; f(); } }
    }
    property var pending: null

    function open() {
        closeAnim.stop();
        hideT = 0;
        focusIndex = -1;
        visible = true;
        requestActivate();
        content.forceActiveFocus();
        revealMs = 0;
        openAnim.restart();
    }
    function close(then) {
        if (!visible || closeAnim.running) return;
        pending = then || null;
        openAnim.stop();
        closeAnim.restart();
    }
    function act(id) {
        // the overlay goes first, so it isn't in the way of the logout screen / lock screen
        close(function () {
            switch (id) {
            case "lock": sm.lock(); break;
            case "sleep": sm.suspend(); break;
            case "logout": sm.requestLogout(Sessions.SessionManagement.ConfirmationMode.Skip); break;
            case "restart": sm.requestReboot(Sessions.SessionManagement.ConfirmationMode.Skip); break;
            case "shutdown": sm.requestShutdown(Sessions.SessionManagement.ConfirmationMode.Skip); break;
            }
        });
    }

    // ── scrim ────────────────────────────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: 0.68 * Motion.effects(menu.revealMs) * (1 - menu.hideT)
        MouseArea { anchors.fill: parent; onClicked: menu.close() }
    }

    FocusScope {
        id: content
        anchors.fill: parent
        focus: true
        opacity: 1 - menu.hideT
        scale: 1 - 0.04 * menu.hideT

        Keys.onPressed: event => {
            var n = menu.actions.length;
            if (event.key === Qt.Key_Escape) { menu.close(); event.accepted = true; }
            else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab || event.key === Qt.Key_Down) {
                menu.focusIndex = (menu.focusIndex + 1) % n; event.accepted = true;
            } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Backtab || event.key === Qt.Key_Up) {
                menu.focusIndex = menu.focusIndex <= 0 ? n - 1 : menu.focusIndex - 1; event.accepted = true;
            } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)
                       && menu.focusIndex >= 0) {
                menu.act(menu.actions[menu.focusIndex].id); event.accepted = true;
            }
        }

        Row {
            id: row
            anchors.centerIn: parent
            spacing: 20

            Repeater {
                model: menu.actions
                delegate: Item {
                    id: cell
                    required property var modelData
                    required property int index
                    readonly property real enter: Motion.defaultSpatial(menu.revealMs - 40 - index * 38)
                    readonly property bool focused: menu.focusIndex === index
                    width: 128
                    height: 172
                    opacity: Motion.effects(menu.revealMs - 60 - index * 38)
                    transform: Translate { y: (1 - cell.enter) * 48 }

                    Rectangle {
                        id: tile
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 128
                        height: 128
                        // M3 Expressive shape morph: square-ish at rest, rounder on hover, tight on press
                        radius: ma.pressed ? 22 : (ma.containsMouse || cell.focused ? 64 : 36)
                        Behavior on radius { NumberAnimation { duration: menu.animate ? 320 : 0; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
                        scale: ma.pressed ? 0.94 : 1
                        Behavior on scale { NumberAnimation { duration: menu.animate ? 220 : 0; easing.type: Easing.OutBack } }
                        // tonal containers (M3 surface-container-high / primary)
                        color: cell.modelData.primary
                               ? (ma.containsMouse ? Qt.lighter(menu.accent, 1.08) : menu.accent)
                               : Qt.tint(menu.dark ? (ma.containsMouse ? "#3a3740" : "#2d2b33") : (ma.containsMouse ? "#ffffff" : "#f1ecf4"),
                                         Qt.rgba(menu.accent.r, menu.accent.g, menu.accent.b, 0.14))
                        Behavior on color { ColorAnimation { duration: menu.animate ? 150 : 0 } }

                        // keyboard focus ring (M3: 3 px, offset 2 px)
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: -5
                            radius: parent.radius + 5
                            color: "transparent"
                            border.width: 3
                            border.color: menu.accent
                            visible: cell.focused
                        }

                        Kirigami.Icon {
                            anchors.centerIn: parent
                            width: 44
                            height: 44
                            source: Qt.resolvedUrl(cell.modelData.icon)
                            isMask: true
                            color: cell.modelData.primary ? (menu.dark ? "#1b1b1f" : "white")
                                                          : (menu.dark ? "white" : "#1b1b1f")
                            // a small spin/settle as the tile arrives
                            rotation: (1 - cell.enter) * -30
                        }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: tile.bottom
                        anchors.topMargin: 14
                        text: cell.modelData.text
                        color: "white"
                        font.family: menu.fontFamily
                        font.pixelSize: 16
                        font.weight: Font.Medium
                    }
                    MouseArea {
                        id: ma
                        anchors.fill: tile
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: menu.focusIndex = -1
                        onClicked: menu.act(cell.modelData.id)
                    }
                }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: row.bottom
            anchors.topMargin: 36
            text: menu.label("hint", "Échap pour annuler")
            color: Qt.rgba(1, 1, 1, 0.6)
            font.family: menu.fontFamily
            font.pixelSize: 13
            opacity: Motion.effects(menu.revealMs - 260)
        }
    }
}

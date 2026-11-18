/*
    SPDX-License-Identifier: GPL-3.0-or-later

    DoodlebookOS login screen (SDDM, Qt 6) — Material 3 Expressive, matching the lock screen:
    the wallpaper, a big two-line clock in Google Sans Flex that "breathes" in, the date, then
    the user's avatar and a pill password field with a round go button. Session and power
    actions are tonal icon buttons at the bottom. Motion uses the M3 Expressive springs of the
    rest of DoodlebookOS; one timer, nothing runs once settled.

    Colours and wallpaper come from theme.conf, written by the installer from Material You.
*/
import QtQuick
import QtQuick.Controls
import QtQml.Models

Item {
    id: root
    width: 1920
    height: 1080

    readonly property color accent: config.accent || "#d0bcff"
    readonly property color onAccent: config.onAccent || "#381e72"
    readonly property color clockColor: Qt.tint("#ffffff", Qt.rgba(accent.r, accent.g, accent.b, 0.32))
    readonly property color surface: Qt.tint("#2b2930", Qt.rgba(accent.r, accent.g, accent.b, 0.12))
    readonly property string fontFamily: sans.status === FontLoader.Ready ? sans.font.family : "sans-serif"

    FontLoader { id: sans; source: "fonts/GoogleSansFlex.ttf" }

    // ── springs (motion.js) ─────────────────────────────────────────────────────────────────
    function spring(ms, damping, stiffness) {
        if (ms <= 0) return 0;
        var t = ms / 1000, w = Math.sqrt(stiffness), v;
        if (damping >= 1) {
            v = 1 - Math.exp(-w * t) * (1 + w * t);
        } else {
            var wd = w * Math.sqrt(1 - damping * damping), e = Math.exp(-damping * w * t);
            v = 1 - e * (Math.cos(wd * t) + (damping * w / wd) * Math.sin(wd * t));
        }
        return Math.abs(1 - v) < 0.0005 ? 1 : v;
    }
    function spatial(ms) { return spring(ms, 0.8, 380); }
    function slowSpatial(ms) { return spring(ms, 0.8, 200); }
    function fastSpatial(ms) { return spring(ms, 0.6, 800); }
    function effects(ms) { return spring(ms, 1, 1600); }

    property real revealMs: 0
    NumberAnimation on revealMs { from: 0; to: 1500; duration: 1500; running: true }
    function rise(i) { return (1 - spatial(revealMs - 40 - i * 70)) * 56; }
    function fade(i) { return effects(revealMs - 80 - i * 70); }

    // shake on a wrong password (M3 error feedback)
    property real shakeMs: 100000
    NumberAnimation on shakeMs { id: shake; from: 0; to: 600; duration: 600; running: false }
    readonly property real shakeX: shakeMs < 600 ? Math.sin(shakeMs / 1000 * 2 * Math.PI * 9) * 14 * Math.exp(-shakeMs / 140) : 0

    // ── state ───────────────────────────────────────────────────────────────────────────────
    property int userIndex: 0
    // the last user who logged in, by name (lastIndex isn't always set)
    function pickLastUser() {
        for (var i = 0; i < users.count; i++) {
            var u = users.objectAt(i);
            if (u && u.name === userModel.lastUser) { userIndex = i; return; }
        }
        // else the first real account (a home under /home), not a service user
        for (var j = 0; j < users.count; j++) {
            var h = users.objectAt(j);
            if (h && h.homeDir.indexOf("/home/") === 0) { userIndex = j; return; }
        }
        userIndex = 0;
    }
    property int sessionIndex: sessionModel.lastIndex >= 0 ? sessionModel.lastIndex : 0
    property bool busy: false
    property string message: ""

    function userData(role) {
        // ListView-free access to the user model
        if (users.count === 0) return "";       // re-evaluated once the model is filled
        var u = users.objectAt(Math.min(userIndex, users.count - 1));
        return u ? u[role] : "";
    }
    Instantiator {
        id: users
        model: userModel
        onCountChanged: root.pickLastUser()
        delegate: QtObject {
            required property string name
            required property string realName
            required property string icon
            required property string homeDir
        }
    }
    Instantiator {
        id: sessions
        model: sessionModel
        delegate: QtObject { required property string name }
    }

    function login() {
        if (busy) return;
        busy = true;
        message = "";
        sddm.login(userData("name"), password.text, sessionIndex);
    }
    Connections {
        target: sddm
        function onLoginFailed() {
            root.busy = false;
            root.message = "Mot de passe incorrect";
            password.selectAll();
            password.forceActiveFocus();
            shake.restart();
        }
        function onLoginSucceeded() { root.message = ""; }
        function onInformationMessage(m) { root.message = m; }
    }

    property date now: new Date()
    Timer { interval: 1000; running: true; repeat: true; onTriggered: root.now = new Date() }

    // ── wallpaper ───────────────────────────────────────────────────────────────────────────
    Rectangle { anchors.fill: parent; color: "#141218" }
    Image {
        anchors.fill: parent
        source: config.background || ""
        fillMode: Image.PreserveAspectCrop
        sourceSize: Qt.size(root.width, root.height)
        scale: 1.06 - 0.06 * root.slowSpatial(root.revealMs)
    }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.42) }
            GradientStop { position: 0.5; color: Qt.rgba(0, 0, 0, 0.2) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.5) }
        }
    }

    // ── clock ───────────────────────────────────────────────────────────────────────────────
    Column {
        id: clock
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(root.height * 0.09)
        spacing: -Math.round(size * 0.08)
        readonly property real size: Math.round(Math.min(root.height * 0.17, root.width * 0.14))
        readonly property real weight: 300 + 260 * root.slowSpatial(root.revealMs - 120)

        Repeater {
            model: [Qt.formatTime(root.now, "HH"), Qt.formatTime(root.now, "mm")]
            Text {
                required property string modelData
                required property int index
                anchors.horizontalCenter: parent.horizontalCenter
                text: modelData
                color: root.clockColor
                font.family: root.fontFamily
                font.pixelSize: clock.size
                font.variableAxes: { "wght": clock.weight, "ROND": 100 }
                height: clock.size * 0.86
                verticalAlignment: Text.AlignVCenter
                opacity: root.fade(index)
                transform: Translate { y: root.rise(index) }
            }
        }
        Item { width: 1; height: clock.size * 0.16 }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: {
                var s = root.now.toLocaleDateString(Qt.locale(), "dddd d MMMM");
                return s.charAt(0).toUpperCase() + s.slice(1);
            }
            color: Qt.rgba(1, 1, 1, 0.86)
            font.family: root.fontFamily
            font.pixelSize: Math.round(clock.size * 0.13)
            font.variableAxes: { "wght": 500, "ROND": 100 }
            opacity: root.fade(2)
            transform: Translate { y: root.rise(2) }
        }
    }

    // ── login card ──────────────────────────────────────────────────────────────────────────
    Column {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Math.round(root.height * 0.17)
        spacing: 14
        opacity: root.fade(4)
        transform: Translate { y: root.rise(4); x: root.shakeX }

        // avatar: click cycles through users when there are several
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 96; height: 96
            Rectangle {
                id: avatarBg
                anchors.fill: parent
                radius: avatarMa.pressed ? 28 : 48
                Behavior on radius { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                color: root.surface
                clip: true
                Image {
                    anchors.fill: parent
                    source: root.userData("icon") ? "file://" + root.userData("icon") : ""
                    fillMode: Image.PreserveAspectCrop
                    sourceSize: Qt.size(192, 192)
                    visible: status === Image.Ready
                }
                Text {
                    anchors.centerIn: parent
                    visible: !parent.children[0].visible
                    text: (root.userData("realName") || root.userData("name") || "?").charAt(0).toUpperCase()
                    color: root.accent
                    font.family: root.fontFamily
                    font.pixelSize: 40
                    font.weight: Font.DemiBold
                }
            }
            MouseArea {
                id: avatarMa
                anchors.fill: parent
                enabled: userModel.count > 1
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: { root.userIndex = (root.userIndex + 1) % userModel.count; password.forceActiveFocus(); }
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.userData("realName") || root.userData("name")
            color: "white"
            font.family: root.fontFamily
            font.pixelSize: 20
            font.variableAxes: { "wght": 550, "ROND": 100 }
        }

        // pill password field + round go button
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8
            Rectangle {
                width: 300; height: 56
                radius: 28
                color: root.surface
                border.width: password.activeFocus ? 2 : 0
                border.color: root.accent
                TextField {
                    id: password
                    anchors.fill: parent
                    anchors.leftMargin: 22
                    anchors.rightMargin: 16
                    echoMode: TextInput.Password
                    passwordCharacter: "●"
                    placeholderText: "Mot de passe"
                    placeholderTextColor: Qt.rgba(1, 1, 1, 0.5)
                    color: "white"
                    font.family: root.fontFamily
                    font.pixelSize: 17
                    verticalAlignment: TextInput.AlignVCenter
                    background: Item {}
                    focus: true
                    enabled: !root.busy
                    Keys.onReturnPressed: root.login()
                    Keys.onEnterPressed: root.login()
                    Component.onCompleted: forceActiveFocus()
                }
            }
            Rectangle {
                id: go
                width: 56; height: 56
                radius: goMa.pressed ? 16 : 28
                Behavior on radius { NumberAnimation { duration: 240; easing.type: Easing.OutBack } }
                scale: goMa.pressed ? 0.92 : 1
                Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                color: root.accent
                Text {
                    anchors.centerIn: parent
                    text: "→"
                    visible: !root.busy
                    color: root.onAccent
                    font.family: root.fontFamily
                    font.pixelSize: 26
                    font.weight: Font.DemiBold
                }
                // busy: a small spinning dot ring
                Rectangle {
                    anchors.centerIn: parent
                    width: 22; height: 22; radius: 11
                    color: "transparent"
                    border.width: 3
                    border.color: root.onAccent
                    visible: root.busy
                    Rectangle { width: 7; height: 7; radius: 3.5; color: root.accent; x: 7.5; y: -2 }
                    RotationAnimator on rotation { from: 0; to: 360; duration: 900; loops: Animation.Infinite; running: root.busy }
                }
                MouseArea { id: goMa; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.login() }
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.message !== "" ? root.message : (keyboard.capsLock ? "Verr. Maj activé" : " ")
            color: root.message !== "" ? "#ffb4ab" : Qt.rgba(1, 1, 1, 0.7)
            font.family: root.fontFamily
            font.pixelSize: 14
        }
    }

    // ── bottom bar: session chip + power buttons ────────────────────────────────────────────
    component Chip: Rectangle {
        id: chip
        property string label
        signal clicked()
        height: 48
        width: row.implicitWidth + 36
        radius: chipMa.pressed ? 14 : 24
        Behavior on radius { NumberAnimation { duration: 240; easing.type: Easing.OutBack } }
        color: chipMa.containsMouse ? Qt.lighter(root.surface, 1.25) : root.surface
        Row {
            id: row
            anchors.centerIn: parent
            spacing: 8
            Text {
                visible: chip.label !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: chip.label
                color: "white"
                font.family: root.fontFamily
                font.pixelSize: 15
                font.weight: Font.Medium
            }
        }
        MouseArea { id: chipMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: chip.clicked() }
    }

    Row {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 28
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 10
        opacity: root.fade(6)
        transform: Translate { y: root.rise(6) }

        Chip {
            label: sessions.count > 0 && sessions.objectAt(root.sessionIndex) ? sessions.objectAt(root.sessionIndex).name : ""
            visible: sessions.count > 1
            onClicked: root.sessionIndex = (root.sessionIndex + 1) % sessions.count
        }
        Chip { label: "Veille"; visible: sddm.canSuspend; onClicked: sddm.suspend() }
        Chip { label: "Redémarrer"; visible: sddm.canReboot; onClicked: sddm.reboot() }
        Chip { label: "Éteindre"; visible: sddm.canPowerOff; onClicked: sddm.powerOff() }
    }
}

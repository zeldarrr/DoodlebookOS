// SPDX-License-Identifier: GPL-3.0-or-later
// App info sheet: version, source (Flatpak / rpm), size, install date, plus Bazaar, permissions,
// location and uninstall. Data comes from code/apps.py on demand.
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import "i18n.js" as I18n

Item {
    id: card
    function i18n(k, a1, a2) { return I18n.t(k, a1, a2); }

    property string appId: ""
    property var info: ({})
    property bool shown: false
    property bool loading: false
    property bool confirmUninstall: false

    readonly property color fg: Kirigami.Theme.textColor
    readonly property color accent: Kirigami.Theme.highlightColor
    readonly property color errorColor: main.isDarkTheme ? "#ffb4ab" : "#ba1a1a"
    readonly property color onError: main.isDarkTheme ? "#690005" : "#ffffff"
    function tint(a) { return Qt.rgba(fg.r, fg.g, fg.b, a); }
    readonly property bool isFlatpak: String(info.source || "").indexOf("flatpak") === 0

    function openFor(id) {
        appId = id;
        info = ({ name: appIndex.nameFor(id) });
        confirmUninstall = false;
        loading = true;
        shown = true;
        appIndex.run("info " + appIndex.shq(id), function (out) {
            card.loading = false;
            try { card.info = JSON.parse(out); } catch (e) {}
        });
    }
    function close() { shown = false; confirmUninstall = false; }

    function sourceLabel(s) {
        if (s === "flatpak-system") return i18n("Flatpak (system)");
        if (s === "flatpak-user") return i18n("Flatpak (user)");
        if (s === "rpm") return i18n("System package (rpm)");
        if (s === "pacman") return i18n("System package (pacman)");
        return i18n("Local");
    }

    function uninstall() {
        if (!confirmUninstall) { confirmUninstall = true; confirmReset.restart(); return; }
        confirmUninstall = false;
        var name = info.name || appId;
        root.toast(i18n("Uninstalling %1…", name));
        appIndex.run("uninstall " + appIndex.shq(appId), function (out) {
            var r = {};
            try { r = JSON.parse(out); } catch (e) {}
            root.toast(r.ok ? i18n("%1 uninstalled", name) : i18n("Could not uninstall %1", name));
        });
        close();
    }
    Timer { id: confirmReset; interval: 4000; onTriggered: card.confirmUninstall = false }

    component SheetBtn: Rectangle {
        id: sb
        property string label
        property url icon
        property bool filled: false
        property color fill: card.accent
        property color onFill: Kirigami.Theme.highlightedTextColor
        signal activated()
        Layout.preferredHeight: 40
        Layout.preferredWidth: sbRow.implicitWidth + 32
        radius: sbMa.pressed ? 12 : 20
        color: filled ? fill : (sbMa.containsMouse ? card.tint(0.10) : "transparent")
        border.width: filled ? 0 : 1
        border.color: card.tint(0.22)
        Behavior on radius { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
        Behavior on color { ColorAnimation { duration: 160 } }
        Row {
            id: sbRow
            anchors.centerIn: parent
            spacing: 8
            Item {
                width: 18; height: 18
                anchors.verticalCenter: parent.verticalCenter
                Image { id: sbImg; anchors.fill: parent; source: sb.icon; sourceSize: Qt.size(36, 36); visible: false }
                MultiEffect { anchors.fill: sbImg; source: sbImg; colorization: 1.0; colorizationColor: sb.filled ? sb.onFill : card.fg }
            }
            Text { anchors.verticalCenter: parent.verticalCenter; text: sb.label
                font.family: "Google Sans Flex"; font.pixelSize: 13; font.weight: Font.Medium; color: sb.filled ? sb.onFill : card.fg }
        }
        MouseArea { id: sbMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: sb.activated() }
    }

    property real t: shown ? 1 : 0
    Behavior on t { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
    visible: t > 0.001
    enabled: shown

    Rectangle {
        anchors.fill: parent
        radius: 20
        color: Qt.rgba(0, 0, 0, 0.42 * card.t)
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onClicked: card.close() }
    }

    Rectangle {
        id: sheet
        width: Math.min(parent.width - 48, 440)
        height: col.implicitHeight + 48
        anchors.centerIn: parent
        radius: 28
        color: Qt.tint(Kirigami.Theme.backgroundColor, Qt.rgba(card.accent.r, card.accent.g, card.accent.b, 0.08))
        border.width: 1
        border.color: card.tint(0.08)
        scale: 0.86 + 0.14 * card.t
        opacity: card.t
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

        ColumnLayout {
            id: col
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 24
            spacing: 14

            RowLayout {
                spacing: 16
                Kirigami.Icon {
                    Layout.preferredWidth: 64; Layout.preferredHeight: 64
                    source: { var r = appIndex.revision; return appIndex.iconFor(card.appId); }
                }
                ColumnLayout {
                    spacing: 2
                    Layout.fillWidth: true
                    Text { Layout.fillWidth: true; text: card.info.name || ""; elide: Text.ElideRight
                        font.family: "Google Sans Flex"; font.pixelSize: 22; font.weight: Font.Medium; color: card.fg }
                    Text { Layout.fillWidth: true; text: card.info.generic || ""; visible: text.length > 0; elide: Text.ElideRight
                        font.family: "Google Sans Flex"; font.pixelSize: 13; color: card.tint(0.65) }
                }
            }

            Text {
                Layout.fillWidth: true
                visible: text.length > 0
                text: card.info.comment || ""
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
                font.family: "Google Sans Flex"; font.pixelSize: 13
                color: card.tint(0.8)
            }

            // facts as tonal chips
            Flow {
                Layout.fillWidth: true
                spacing: 8
                Repeater {
                    model: {
                        var i = card.info, out = [];
                        if (card.loading) return [card.i18n("Loading…")];
                        if (i.version) out.push(card.i18n("Version %1", i.version));
                        out.push(card.sourceLabel(i.source));
                        if (i.size) out.push(i.size);
                        if (i.installed) out.push(card.i18n("Installed %1", i.installed));
                        return out;
                    }
                    delegate: Rectangle {
                        required property string modelData
                        height: 30
                        width: factText.implicitWidth + 22
                        radius: 10
                        color: card.tint(0.07)
                        Text { id: factText; anchors.centerIn: parent; text: parent.modelData
                            font.family: "Google Sans Flex"; font.pixelSize: 12; font.weight: Font.Medium; color: card.fg }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: card.info.flatpak || card.info.id || ""
                elide: Text.ElideMiddle
                font.family: "monospace"; font.pixelSize: 11
                color: card.tint(0.5)
            }

            Flow {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 8
                SheetBtn {
                    visible: card.isFlatpak
                    label: "Bazaar"
                    icon: Qt.resolvedUrl("icons/store.svg")
                    onActivated: { appIndex.sh("xdg-open " + appIndex.shq("appstream://" + card.info.flatpak)); root.close(); }
                }
                SheetBtn {
                    visible: card.isFlatpak
                    label: card.i18n("Permissions")
                    icon: Qt.resolvedUrl("icons/shield.svg")
                    onActivated: { appIndex.sh("kcmshell6 kcm_app-permissions"); root.close(); }
                }
                SheetBtn {
                    label: card.i18n("Open location")
                    icon: Qt.resolvedUrl("icons/folder_open.svg")
                    onActivated: { appIndex.run("locate " + appIndex.shq(card.appId)); root.close(); }
                }
                SheetBtn {
                    visible: card.isFlatpak
                    filled: card.confirmUninstall
                    fill: card.errorColor
                    onFill: card.onError
                    label: card.confirmUninstall ? card.i18n("Confirm uninstall") : card.i18n("Uninstall")
                    icon: Qt.resolvedUrl("icons/delete.svg")
                    onActivated: card.uninstall()
                }
            }

            Text {
                Layout.fillWidth: true
                visible: card.info.source === "rpm"
                text: card.i18n("Part of the system image: remove it with rpm-ostree.")
                wrapMode: Text.Wrap
                font.family: "Google Sans Flex"; font.pixelSize: 11
                color: card.tint(0.55)
            }
        }
    }
}

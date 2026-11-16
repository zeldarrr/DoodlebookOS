// SPDX-License-Identifier: GPL-3.0-or-later
//
// DoodlebookOS Devices: battery chips for wireless peripherals (UPower / Solid: mouse, keyboard,
// headset, gamepad…) and reachable KDE Connect phones, for the top bar. Takes no space when no
// device reports a battery. Fully event-driven: Solid and KDE Connect push every change, nothing
// is polled here.
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kirigami as Kirigami
import org.kde.taskmanager as TaskManager

PlasmoidItem {
    id: root

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    preferredRepresentation: fullRepresentation
    toolTipMainText: ""
    toolTipSubText: ""

    // ───────── strings ─────────
    readonly property bool fr: Qt.locale().name.indexOf("fr") === 0
    function t(en, frs) { return fr ? frs : en; }

    // ───────── metrics (same rail maths as the other top bar widgets) ─────────
    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property real dpr: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1.0
    function snap(v) { return Math.round(v * dpr) / dpr; }
    readonly property real thickness: {
        var v = vertical ? root.width : root.height;
        return v > 0 ? Math.min(v, 96) : 32;
    }
    readonly property real pillHeight: snap(thickness * 0.675)
    readonly property real fontPx: snap(pillHeight * 0.46)
    readonly property real iconPx: snap(pillHeight * 0.56)
    readonly property real gap: snap(pillHeight * 0.24)

    // ───────── colours ─────────
    readonly property bool isTop: Plasmoid.location === PlasmaCore.Types.TopEdge
    Instantiator {           // the maximised-window watcher only exists while chips are shown
        id: maxWatch
        active: root.isTop && root.devices.length > 0
        model: 1
        delegate: TaskManager.TasksModel {
            activity: activityInfo.currentActivity
            filterByActivity: true
            screenGeometry: Plasmoid.containment ? Plasmoid.containment.screenGeometry : Qt.rect(0, 0, 0, 0)
            filterByScreen: true
            filterMinimized: true
            filterNotMaximized: true
            virtualDesktop: vdi.currentDesktop
            filterByVirtualDesktop: true
        }
    }
    TaskManager.VirtualDesktopInfo { id: vdi }
    TaskManager.ActivityInfo { id: activityInfo }
    readonly property bool hasMaximizedWindow: maxWatch.object ? maxWatch.object.count > 0 : false
    readonly property color fg: hasMaximizedWindow ? "#ffffff"
        : (Plasmoid.configuration.contentColor ? Plasmoid.configuration.contentColor : Kirigami.Theme.textColor)
    readonly property color accent: Kirigami.Theme.highlightColor
    readonly property color low: "#f2b8b5"
    function tint(a) { return Qt.rgba(fg.r, fg.g, fg.b, a); }

    // ───────── data ─────────
    // [{ key, name, kind, percent, charging, deviceId }]
    property var peripherals: []
    property var phones: []
    readonly property var devices: peripherals.concat(phones)

    function kindOf(type) {
        var s = String(type || "").toLowerCase();
        if (s.indexOf("mouse") >= 0 || s.indexOf("touchpad") >= 0) return "mouse";
        if (s.indexOf("keyboard") >= 0) return "keyboard";
        if (s.indexOf("head") >= 0 || s.indexOf("audio") >= 0) return "headphones";
        if (s.indexOf("gaming") >= 0 || s.indexOf("joystick") >= 0) return "gamepad";
        if (s.indexOf("phone") >= 0 || s.indexOf("pda") >= 0) return "smartphone";
        if (s.indexOf("tablet") >= 0 || s.indexOf("pen") >= 0) return "tablet";
        return "battery";
    }
    function same(a, b) { return JSON.stringify(a) === JSON.stringify(b); }

    function rebuildPeripherals() {
        var out = [], src = pm.connectedSources;
        for (var i = 0; i < src.length; i++) {
            var d = pm.data[src[i]];
            if (!d || d["Is Power Supply"] === true || d["Percent"] === undefined) continue;
            if (d["Plugged in"] === false) continue;            // "Plugged in" = battery present
            out.push({ key: src[i], name: String(d["Pretty Name"] || d["Product"] || src[i]),
                       kind: kindOf(d["Type"]), percent: Number(d["Percent"]),
                       charging: d["State"] === "Charging", deviceId: "" });
        }
        if (!same(out, peripherals)) peripherals = out;
    }
    Plasma5Support.DataSource {
        id: pm
        engine: "powermanagement"
        connectedSources: []
        function want(s) { return /^Battery\d+$/.test(s); }
        onSourceAdded: (s) => { if (want(s)) connectSource(s); }
        onSourceRemoved: (s) => { disconnectSource(s); Qt.callLater(root.rebuildPeripherals); }
        onNewData: (s, d) => Qt.callLater(root.rebuildPeripherals)
        Component.onCompleted: {
            for (var i = 0; i < sources.length; i++) if (want(sources[i])) connectSource(sources[i]);
        }
    }

    // KDE Connect phones, loaded apart: without KDE Connect the peripherals still show
    Loader {
        id: phoneLoader
        active: Plasmoid.configuration.showPhones !== false
        source: "PhoneSource.qml"
        onActiveChanged: if (!active) root.phones = []
    }
    Connections {
        target: phoneLoader.item
        function onPhonesChanged() { root.phones = phoneLoader.item.phones; }
    }

    Plasma5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (s) => disconnectSource(s)
    }
    property int serial: 0
    function open(dev) {
        var id = String(dev.deviceId || "").replace(/[^A-Za-z0-9_]/g, "");
        exec.connectSource((id ? "kdeconnect-app --device '" + id + "'" : "kcmshell6 kcm_bluetooth") + " # " + (++serial));
    }

    // local SVG tinted with a colour (Kirigami.Icon isMask does not recolour plain SVG files)
    component MaskIcon: Item {
        id: mi
        property url source
        property color color
        Image { id: miImg; anchors.fill: parent; source: mi.source; sourceSize: Qt.size(48, 48); visible: false }
        MultiEffect { anchors.fill: parent; source: miImg; colorization: 1.0; colorizationColor: mi.color }
    }

    // ───────── chips ─────────
    fullRepresentation: Item {
        id: bar
        readonly property real w: row.implicitWidth > 0 ? row.implicitWidth + root.gap : 0
        implicitWidth: w
        implicitHeight: root.pillHeight
        Layout.minimumWidth: w
        Layout.preferredWidth: w
        Layout.maximumWidth: w
        Layout.fillHeight: true
        visible: root.devices.length > 0

        Row {
            id: row
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.gap
            Repeater {
                model: root.devices
                delegate: Item {
                    id: chip
                    required property var modelData
                    readonly property bool isLow: modelData.percent <= 20 && !modelData.charging
                    readonly property color ink: isLow ? root.low : root.fg
                    width: content.implicitWidth + root.pillHeight * 0.62
                    height: root.pillHeight
                    scale: ma.pressed ? 0.9 : 1
                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 2 } }

                    Rectangle {
                        anchors.fill: parent
                        radius: ma.pressed ? height * 0.3 : height / 2
                        color: chip.isLow ? Qt.rgba(0.95, 0.72, 0.71, ma.containsMouse ? 0.30 : 0.18)
                                          : root.tint(ma.containsMouse ? 0.22 : 0.10)
                        Behavior on color { ColorAnimation { duration: 180 } }
                        Behavior on radius { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
                    }
                    Row {
                        id: content
                        anchors.centerIn: parent
                        spacing: root.snap(root.pillHeight * 0.12)
                        MaskIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            width: root.iconPx; height: root.iconPx
                            source: Qt.resolvedUrl("icons/" + chip.modelData.kind + ".svg")
                            color: chip.ink
                        }
                        Text {
                            visible: Plasmoid.configuration.showPercent !== false
                            anchors.verticalCenter: parent.verticalCenter
                            text: Math.round(chip.modelData.percent) + "%"
                            font.family: "Google Sans Flex"
                            font.weight: 600
                            font.pixelSize: root.fontPx
                            font.features: { "tnum": 1 }
                            renderType: Text.QtRendering
                            color: chip.ink
                        }
                        MaskIcon {
                            visible: chip.modelData.charging
                            anchors.verticalCenter: parent.verticalCenter
                            width: root.snap(root.iconPx * 0.8); height: width
                            source: Qt.resolvedUrl("icons/bolt.svg")
                            color: root.accent
                        }
                    }
                    PlasmaCore.ToolTipArea {
                        anchors.fill: parent
                        mainText: chip.modelData.name
                        subText: Math.round(chip.modelData.percent) + " %"
                            + (chip.modelData.charging ? " · " + root.t("charging", "en charge") : "")
                            + "\n" + (chip.modelData.deviceId ? root.t("Click: open KDE Connect", "Clic : ouvrir KDE Connect")
                                                              : root.t("Click: Bluetooth settings", "Clic : réglages Bluetooth"))
                        MouseArea {
                            id: ma
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.open(chip.modelData)
                        }
                    }
                }
            }
        }
    }
}

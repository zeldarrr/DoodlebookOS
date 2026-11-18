/*
    SPDX-License-Identifier: GPL-3.0-or-later

    DoodlebookOS "Fond d'écran et style" — Android's "Wallpaper & style" for KDE Plasma.

    One page: a live preview, the wallpaper, Material You on/off, the palette style (Android's
    scheme variants), contrast, light/dark and the Material 3 Expressive icon shape. Every
    choice runs the matching DoodlebookOS command (doodlebookos-materialyou, dostheme,
    doodlebookos-icons, plasma-apply-wallpaperimage); the page then re-reads the state.

    Launched by `doodlebookos-style` (qml runtime). Nothing runs in the background.
*/
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Shapes
import QtQuick.Effects
import Qt.labs.folderlistmodel
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support

Kirigami.ApplicationWindow {
    id: app
    title: "Fond d'écran et style"
    width: 760
    height: 900
    minimumWidth: 520
    minimumHeight: 600
    pageStack.initialPage: page

    property string homeUrl: ""

    // ── state from `doodlebookos-materialyou swatches` ───────────────────────────────────────
    property var st: ({ enabled: true, mode: "dark", variant: "tonal_spot", contrast: "standard", wallpaper: "", variants: {} })
    property string shape: "circle"
    property var shapes: []
    property int busy: 0
    readonly property color accent: Kirigami.Theme.highlightColor
    readonly property bool dark: st.mode === "dark"

    readonly property var variantLabels: ({
        tonal_spot: "Tonal", vibrant: "Vibrant", expressive: "Expressif", fruit_salad: "Salade de fruits",
        rainbow: "Arc-en-ciel", content: "Contenu", neutral: "Neutre", monochrome: "Monochrome"
    })
    readonly property var variantOrder: ["tonal_spot", "vibrant", "expressive", "fruit_salad", "rainbow", "content", "neutral", "monochrome"]

    function q(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'"; }
    function run(cmd, then) {
        busy++;
        var id = "sh -c " + q("export PATH=\"$HOME/.local/bin:$PATH\"; " + cmd) + " #" + Date.now() + Math.random();
        callbacks[id] = then || null;
        exec.connectSource(id);
    }
    property var callbacks: ({})
    function refresh() {
        run("doodlebookos-materialyou swatches", function (out) {
            try { app.st = JSON.parse(out); } catch (e) {}
        });
        run("cat \"${XDG_CONFIG_HOME:-$HOME/.config}/doodlebookos/shape.json\"", function (out) {
            try {
                var d = JSON.parse(out);
                app.shape = d.name || "circle";
                app.shapes = d.shapes || [];
            } catch (e) {}
        });
        run("printf %s \"$HOME\"", function (out) { app.homeUrl = "file://" + out.trim(); });
    }

    P5Support.DataSource {
        id: exec
        engine: "executable"
        onNewData: (source, data) => {
            disconnectSource(source);
            var cb = app.callbacks[source];
            delete app.callbacks[source];
            app.busy = Math.max(0, app.busy - 1);
            if (cb) cb(data["stdout"] || "");
        }
    }

    Component.onCompleted: refresh()

    // ── M3 Expressive springs (motion.js) ───────────────────────────────────────────────────
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
    readonly property bool animate: Kirigami.Units.longDuration > 1
    property real revealMs: 0
    NumberAnimation on revealMs { from: 0; to: 1200; duration: app.animate ? 1200 : 0; running: true }
    function sectionOpacity(i) { return spring(revealMs - 60 - i * 45, 1, 1600); }
    function sectionShift(i) { return (1 - spring(revealMs - i * 45, 0.8, 380)) * 28; }

    FileDialog {
        id: pickImage
        title: "Choisir un fond d'écran"
        nameFilters: ["Images (*.jpg *.jpeg *.png *.webp *.avif *.jxl)"]
        onAccepted: app.setWallpaper(String(selectedFile).replace(/^file:\/\//, ""))
    }
    function setWallpaper(path) {
        app.st = Object.assign({}, app.st, { wallpaper: decodeURIComponent(path) });
        run("plasma-apply-wallpaperimage " + q(decodeURIComponent(path)) + " >/dev/null 2>&1; sleep 1; doodlebookos-materialyou auto", refresh);
    }

    // ── building blocks ─────────────────────────────────────────────────────────────────────
    // content clipped to a rounded rectangle (clip: true only cuts square corners)
    component Rounded: Item {
        id: rc
        property real radius: 0
        default property alias content: inner.data
        Item {
            id: inner
            anchors.fill: parent
            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: maskItem
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }
        }
        Rectangle {
            id: maskItem
            anchors.fill: parent
            radius: rc.radius
            visible: false
            layer.enabled: true
            layer.smooth: true
        }
    }
    component SectionTitle: QQC2.Label {
        font.pixelSize: 15
        font.weight: Font.DemiBold
        color: app.accent
        Layout.topMargin: 10
    }
    component Segmented: Row {
        id: seg
        property var options: []        // [{value, label}]
        property string current
        signal picked(string value)
        spacing: 0
        Repeater {
            model: seg.options
            delegate: Rectangle {
                id: segBtn
                required property var modelData
                required property int index
                readonly property bool on: seg.current === modelData.value
                width: Math.max(110, segLabel.implicitWidth + (on ? 52 : 32))
                height: 44
                Behavior on width { NumberAnimation { duration: app.animate ? 260 : 0; easing.type: Easing.OutBack } }
                // M3 connected button group: outer corners round, inner corners small; the
                // selected one becomes a full pill
                radius: on ? 22 : 8
                Behavior on radius { NumberAnimation { duration: app.animate ? 260 : 0; easing.type: Easing.OutBack } }
                color: on ? app.accent : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, segMa.containsMouse ? 0.12 : 0.07)
                Behavior on color { ColorAnimation { duration: app.animate ? 160 : 0 } }
                Row {
                    anchors.centerIn: parent
                    spacing: 6
                    Kirigami.Icon {
                        width: 18; height: 18
                        visible: segBtn.on
                        source: "checkmark"
                        color: Kirigami.Theme.highlightedTextColor
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    QQC2.Label {
                        id: segLabel
                        text: segBtn.modelData.label
                        color: segBtn.on ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                        font.weight: Font.Medium
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                MouseArea { id: segMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: seg.picked(segBtn.modelData.value) }
            }
        }
    }

    Kirigami.ScrollablePage {
        id: page
        title: "Fond d'écran et style"
        actions: [
            Kirigami.Action {
                displayComponent: Item {
                    implicitWidth: 28; implicitHeight: 28
                    visible: app.busy > 0
                    M3LoadingIndicator { anchors.fill: parent; running: app.busy > 0; color: app.accent }
                }
            }
        ]

        ColumnLayout {
            spacing: 14

            // ── preview ────────────────────────────────────────────────────────────────────
            Rounded {
                Layout.fillWidth: true
                Layout.preferredHeight: 260
                radius: 28
                opacity: app.sectionOpacity(0)
                transform: Translate { y: app.sectionShift(0) }
                Rectangle { anchors.fill: parent; color: "black" }
                Image {
                    anchors.fill: parent
                    source: app.st.wallpaper ? "file://" + app.st.wallpaper : ""
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: 900
                    asynchronous: true
                    Behavior on source { enabled: false }
                }
                Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.25) }
                Column {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.margins: 24
                    spacing: 8
                    QQC2.Label {
                        text: Qt.formatTime(new Date(), "HH:mm")
                        color: "white"
                        font.pixelSize: 54
                        font.family: "Google Sans Flex"
                        font.weight: Font.Medium
                    }
                    Row {
                        spacing: 8
                        Repeater {
                            model: app.st.variants && app.st.variants[app.st.variant] ? app.st.variants[app.st.variant] : []
                            Rectangle {
                                required property string modelData
                                required property int index
                                width: index === 0 ? 72 : 36
                                height: 36
                                radius: 18
                                color: modelData
                                Behavior on color { ColorAnimation { duration: app.animate ? 300 : 0 } }
                            }
                        }
                    }
                }
            }

            // ── wallpaper ──────────────────────────────────────────────────────────────────
            SectionTitle { text: "Fond d'écran"; opacity: app.sectionOpacity(1) }
            ListView {
                id: wallList
                Layout.fillWidth: true
                Layout.preferredHeight: 128
                orientation: ListView.Horizontal
                spacing: 12
                clip: true
                opacity: app.sectionOpacity(1)
                transform: Translate { y: app.sectionShift(1) }
                model: FolderListModel {
                    folder: app.homeUrl ? app.homeUrl + "/.local/share/wallpapers/DoodlebookOS" : ""
                    nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp"]
                    showDirs: false
                }
                footer: Item {
                    width: 112; height: 128
                    Rectangle {
                        x: 12
                        width: 100; height: 128
                        radius: addMa.pressed ? 16 : 24
                        Behavior on radius { NumberAnimation { duration: 240; easing.type: Easing.OutBack } }
                        color: Qt.rgba(app.accent.r, app.accent.g, app.accent.b, addMa.containsMouse ? 0.24 : 0.14)
                        Kirigami.Icon { anchors.centerIn: parent; width: 32; height: 32; source: "list-add"; color: app.accent }
                        MouseArea { id: addMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pickImage.open() }
                    }
                }
                delegate: Item {
                    id: wp
                    required property string filePath
                    readonly property bool current: app.st.wallpaper === filePath
                    width: 100; height: 128
                    Rectangle {
                        anchors.fill: parent
                        radius: wp.current ? 32 : (wpMa.pressed ? 14 : 20)
                        Behavior on radius { NumberAnimation { duration: app.animate ? 280 : 0; easing.type: Easing.OutBack } }
                        color: "transparent"
                        border.width: wp.current ? 3 : 0
                        border.color: app.accent
                        Rounded {
                            id: wpClip
                            anchors.fill: parent
                            anchors.margins: wp.current ? 6 : 0
                            radius: parent.radius - (wp.current ? 6 : 0)
                            Rectangle { anchors.fill: parent; color: "#222" }
                            Image {
                                anchors.fill: parent
                                source: "file://" + wp.filePath
                                sourceSize.width: 240
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                            }
                        }
                    }
                    MouseArea { id: wpMa; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: app.setWallpaper(wp.filePath) }
                }
            }

            // ── colours ────────────────────────────────────────────────────────────────────
            SectionTitle { text: "Couleurs"; opacity: app.sectionOpacity(2) }
            RowLayout {
                Layout.fillWidth: true
                opacity: app.sectionOpacity(2)
                transform: Translate { y: app.sectionShift(2) }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    QQC2.Label { text: "Couleurs du fond d'écran"; font.weight: Font.Medium }
                    QQC2.Label {
                        text: "Material You : le thème, les icônes et les applis prennent les couleurs du fond."
                        opacity: 0.7; wrapMode: Text.WordWrap; Layout.fillWidth: true
                    }
                }
                QQC2.Switch {
                    checked: app.st.enabled
                    onToggled: app.run("doodlebookos-materialyou " + (checked ? "on" : "off"), app.refresh)
                }
            }
            GridLayout {
                Layout.fillWidth: true
                columns: Math.max(4, Math.floor(width / 150))
                rowSpacing: 12
                columnSpacing: 12
                enabled: app.st.enabled
                opacity: (app.st.enabled ? 1 : 0.45) * app.sectionOpacity(3)
                transform: Translate { y: app.sectionShift(3) }
                Repeater {
                    model: app.variantOrder
                    delegate: ColumnLayout {
                        id: vc
                        required property string modelData
                        readonly property bool on: app.st.variant === modelData
                        readonly property var cols: app.st.variants && app.st.variants[modelData] ? app.st.variants[modelData] : ["#888", "#777", "#666", "#333"]
                        spacing: 6
                        Layout.alignment: Qt.AlignHCenter
                        Item {
                            Layout.alignment: Qt.AlignHCenter
                            width: 72; height: 72
                            // Android colour option: a disc split in primary / secondary / tertiary,
                            // morphing to a rounded square when selected
                            Rounded {
                                id: disc
                                anchors.centerIn: parent
                                width: 64; height: 64
                                radius: vc.on ? 20 : 32
                                Behavior on radius { NumberAnimation { duration: app.animate ? 320 : 0; easing.type: Easing.OutBack; easing.overshoot: 1.8 } }
                                Rectangle { anchors.fill: parent; color: vc.cols[3] }
                                Rectangle { x: 0; y: 0; width: 64; height: 32; color: vc.cols[0] }
                                Rectangle { x: 0; y: 32; width: 32; height: 32; color: vc.cols[1] }
                                Rectangle { x: 32; y: 32; width: 32; height: 32; color: vc.cols[2] }
                                scale: vcMa.pressed ? 0.92 : 1
                                Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                            }
                            Rectangle {
                                visible: vc.on
                                anchors.centerIn: parent
                                width: 28; height: 28; radius: 14
                                color: vc.cols[3]
                                Kirigami.Icon { anchors.centerIn: parent; width: 18; height: 18; source: "checkmark"; color: vc.cols[0] }
                            }
                            MouseArea { id: vcMa; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: app.run("doodlebookos-materialyou variant " + vc.modelData, app.refresh) }
                        }
                        QQC2.Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: app.variantLabels[vc.modelData]
                            font.weight: vc.on ? Font.DemiBold : Font.Normal
                        }
                    }
                }
            }

            // ── contrast + light/dark ─────────────────────────────────────────────────────
            SectionTitle { text: "Contraste"; opacity: app.sectionOpacity(4) }
            Segmented {
                opacity: (app.st.enabled ? 1 : 0.45) * app.sectionOpacity(4)
                enabled: app.st.enabled
                options: [{ value: "standard", label: "Standard" }, { value: "medium", label: "Moyen" }, { value: "high", label: "Élevé" }]
                current: app.st.contrast
                onPicked: value => app.run("doodlebookos-materialyou contrast " + value, app.refresh)
            }
            SectionTitle { text: "Thème"; opacity: app.sectionOpacity(5) }
            Segmented {
                opacity: app.sectionOpacity(5)
                options: [{ value: "light", label: "Clair" }, { value: "dark", label: "Sombre" }]
                current: app.st.mode
                onPicked: value => app.run("dostheme " + value + " >/dev/null 2>&1", app.refresh)
            }

            // ── icon shape ─────────────────────────────────────────────────────────────────
            SectionTitle { text: "Forme des icônes"; visible: app.shapes.length > 0; opacity: app.sectionOpacity(6) }
            Flow {
                Layout.fillWidth: true
                spacing: 10
                visible: app.shapes.length > 0
                opacity: app.sectionOpacity(6)
                transform: Translate { y: app.sectionShift(6) }
                Repeater {
                    model: app.shapes
                    delegate: Item {
                        id: sh
                        required property var modelData
                        readonly property bool on: app.shape === modelData.name
                        width: 64; height: 64
                        Rectangle {
                            anchors.fill: parent
                            radius: sh.on ? 18 : 32
                            Behavior on radius { NumberAnimation { duration: app.animate ? 280 : 0; easing.type: Easing.OutBack } }
                            color: sh.on ? Qt.rgba(app.accent.r, app.accent.g, app.accent.b, 0.22)
                                         : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, shMa.containsMouse ? 0.1 : 0.05)
                        }
                        Shape {
                            anchors.centerIn: parent
                            width: 40; height: 40
                            preferredRendererType: Shape.CurveRenderer
                            rotation: shMa.containsMouse ? sh.modelData.turn / 2 : 0
                            Behavior on rotation { NumberAnimation { duration: app.animate ? 420 : 0; easing.type: Easing.OutBack } }
                            ShapePath {
                                strokeWidth: -1
                                fillColor: sh.on ? app.accent : Kirigami.Theme.textColor
                                scale: Qt.size(0.4, 0.4)
                                PathSvg { path: sh.modelData.path }
                            }
                        }
                        QQC2.ToolTip.visible: shMa.containsMouse
                        QQC2.ToolTip.text: sh.modelData.label
                        QQC2.ToolTip.delay: 400
                        MouseArea {
                            id: shMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { app.shape = sh.modelData.name; app.run("doodlebookos-icons shape " + sh.modelData.name + " >/dev/null 2>&1", app.refresh); }
                        }
                    }
                }
            }
            Item { Layout.preferredHeight: 24 }
        }
    }
}

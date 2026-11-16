// SPDX-License-Identifier: GPL-3.0-or-later
//
// DoodlebookOS Workspaces: one Material 3 chip per virtual desktop (number + icons of the apps open
// on it), for the top bar.
//   click a chip            → go to that desktop (the active pill moves at once, KWin confirms)
//   click the current chip  → Overview          middle click → desktop grid
//   wheel                   → previous / next desktop
//   "+"                     → add a desktop and go to it
//   right click             → Overview, grid, add / remove, virtual desktop settings
//   drop an app dragged up out of the DoodlebookOS dock on a chip → its windows move there
// Everything follows VirtualDesktopInfo / TasksModel signals; D-Bus calls only run on user input.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
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
    readonly property string lang: Qt.locale().name.split(/[_-]/)[0]
    readonly property var frDict: ({
        "Desktop %1": "Bureau %1",
        "Overview": "Vue d'ensemble",
        "Desktop grid": "Grille des bureaux",
        "Add a desktop": "Ajouter un bureau",
        "Remove “%1”": "Supprimer « %1 »",
        "Configure virtual desktops…": "Configurer les bureaux virtuels…",
        "No windows": "Aucune fenêtre",
        "Click: Overview": "Clic : vue d'ensemble",
        "Click: go to this desktop": "Clic : aller sur ce bureau",
        "Wheel: switch desktop": "Molette : changer de bureau"
    })
    function t(k, a1) {
        var s = (lang === "fr" && frDict[k] !== undefined) ? frDict[k] : k;
        return a1 === undefined ? s : s.replace("%1", a1);
    }

    // ───────── metrics (same rail maths as the DoodlebookOS clock) ─────────
    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property real dpr: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1.0
    function snap(v) { return Math.round(v * dpr) / dpr; }
    readonly property real thickness: {
        var v = vertical ? root.width : root.height;
        return v > 0 ? Math.min(v, 96) : 32;
    }
    readonly property real pillHeight: snap(thickness * 0.675)
    readonly property real edgeMargin: Math.max(0, snap(thickness * 0.62) - 4)
    readonly property real fontPx: snap(pillHeight * 0.54)
    readonly property real iconPx: snap(pillHeight * 0.68)
    readonly property real gap: snap(pillHeight * 0.24)
    readonly property bool showIcons: Plasmoid.configuration.showIcons !== false
    readonly property int maxIcons: Math.max(1, Plasmoid.configuration.maxIcons || 3)

    // ───────── colours (white over a maximised window, like the clock) ─────────
    readonly property bool isTop: Plasmoid.location === PlasmaCore.Types.TopEdge
    readonly property bool hasMaximizedWindow: isTop && maximizedTasks.count > 0
    readonly property color fg: hasMaximizedWindow ? "#ffffff"
        : (Plasmoid.configuration.contentColor ? Plasmoid.configuration.contentColor : Kirigami.Theme.textColor)
    readonly property color accent: Kirigami.Theme.highlightColor
    readonly property color onAccent: (0.299 * accent.r + 0.587 * accent.g + 0.114 * accent.b) > 0.62 ? "#1d1a2c" : Kirigami.Theme.highlightedTextColor
    function tint(a) { return Qt.rgba(fg.r, fg.g, fg.b, a); }

    // ───────── desktops ─────────
    TaskManager.VirtualDesktopInfo { id: vdi }
    TaskManager.ActivityInfo { id: activityInfo }

    TaskManager.TasksModel {
        id: maximizedTasks
        activity: activityInfo.currentActivity
        filterByActivity: true
        screenGeometry: Plasmoid.containment ? Plasmoid.containment.screenGeometry : Qt.rect(0, 0, 0, 0)
        filterByScreen: true
        filterMinimized: true
        filterNotMaximized: true
        virtualDesktop: vdi.currentDesktop
        filterByVirtualDesktop: true
    }

    readonly property var ids: vdi.desktopIds
    // optimistic: the pill moves on click, KWin's answer then confirms it
    property string pending: ""
    readonly property string current: pending.length ? pending : String(vdi.currentDesktop)
    Timer { id: pendingReset; interval: 800; onTriggered: root.pending = "" }
    property bool goToNewDesktop: false
    property int lastHovered: -1

    Connections {
        target: vdi
        function onCurrentDesktopChanged() { root.pending = ""; }
        function onDesktopIdsChanged() {
            if (root.goToNewDesktop && root.ids.length) {
                root.goToNewDesktop = false;
                root.switchTo(String(root.ids[root.ids.length - 1]));
            }
        }
    }

    function indexOfId(id) {
        for (var i = 0; i < ids.length; i++) if (String(ids[i]) === id) return i;
        return -1;
    }
    function nameAt(i) {
        var n = vdi.desktopNames;
        return (n && n[i]) ? String(n[i]) : t("Desktop %1", i + 1);
    }

    // ───────── actions (D-Bus, only on input) ─────────
    Plasma5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (source) => disconnectSource(source)
    }
    property int serial: 0
    function run(cmd) { exec.connectSource(cmd + " # " + (++serial)); }
    readonly property string qdbus: "$(command -v qdbus-qt6 || command -v qdbus6 || command -v qdbus)"
    function clean(s) { return String(s).replace(/[^A-Za-z0-9_-]/g, ""); }

    function shortcut(name) {
        run(qdbus + " org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.invokeShortcut '" + name + "'");
    }
    function switchTo(id) {
        id = clean(id);
        if (!id.length) return;
        if (id === current) { shortcut("Overview"); return; }
        pending = id;
        pendingReset.restart();
        run("gdbus call --session --dest org.kde.KWin --object-path /VirtualDesktopManager"
            + " --method org.freedesktop.DBus.Properties.Set org.kde.KWin.VirtualDesktopManager current \"<'" + id + "'>\"");
    }
    function step(d) {
        var n = ids.length, i = indexOfId(current);
        if (n < 2 || i < 0) return;
        var j = i + d;
        if (vdi.navigationWrappingAround) j = (j + n) % n;
        else j = Math.max(0, Math.min(n - 1, j));
        if (j !== i) switchTo(String(ids[j]));
    }
    function addDesktop() {
        var n = ids.length;
        if (n >= 20) return;
        goToNewDesktop = true;
        run(qdbus + " org.kde.KWin /VirtualDesktopManager org.kde.KWin.VirtualDesktopManager.createDesktop " + n + " '" + t("Desktop %1", n + 1) + "'");
    }
    function removeDesktop(i) {
        if (ids.length < 2 || i < 0 || i >= ids.length) return;
        run(qdbus + " org.kde.KWin /VirtualDesktopManager org.kde.KWin.VirtualDesktopManager.removeDesktop '" + clean(ids[i]) + "'");
    }
    readonly property int menuTarget: (lastHovered >= 0 && lastHovered < ids.length) ? lastHovered : indexOfId(current)

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: root.t("Overview")
            icon.name: "view-app-grid-symbolic"
            onTriggered: root.shortcut("Overview")
        },
        PlasmaCore.Action {
            text: root.t("Desktop grid")
            icon.name: "view-grid"
            onTriggered: root.shortcut("Grid View")
        },
        PlasmaCore.Action { isSeparator: true },
        PlasmaCore.Action {
            text: root.t("Add a desktop")
            icon.name: "list-add"
            enabled: root.ids.length < 20
            onTriggered: root.addDesktop()
        },
        PlasmaCore.Action {
            text: root.t("Remove “%1”", root.nameAt(root.menuTarget))
            icon.name: "list-remove"
            enabled: root.ids.length > 1
            onTriggered: root.removeDesktop(root.menuTarget)
        },
        PlasmaCore.Action {
            text: root.t("Configure virtual desktops…")
            icon.name: "configure"
            onTriggered: root.run("kcmshell6 kcm_kwin_virtualdesktops")
        }
    ]

    // ───────── one chip per desktop ─────────
    component Chip: Item {
        id: chip
        required property var modelData
        required property int index
        readonly property string desktopId: String(modelData)
        readonly property bool active: desktopId === root.current
        readonly property int appCount: rows.length
        readonly property bool occupied: appCount > 0
        readonly property bool hovered: ma.containsMouse || dropHover
        readonly property alias taskModel: tasks
        property bool dropHover: false

        // windows dragged from the dock: find them in the other chips' models and move them here
        function takeWindows(text) {
            var want = String(text || "").split("\n").filter(function (s) { return s.length > 0; });
            if (!want.length || !chip.parent) return;
            var sibs = chip.parent.children;
            for (var c = 0; c < sibs.length; c++) {
                var other = sibs[c];
                if (other === chip || !other.taskModel) continue;
                var m = other.taskModel;
                for (var r = m.count - 1; r >= 0; r--) {
                    var idx = m.makeModelIndex(r);
                    var wl = m.data(idx, TaskManager.AbstractTasksModel.WinIdList) || [];
                    for (var k = 0; k < wl.length; k++) {
                        if (want.indexOf(String(wl[k])) >= 0) { m.requestVirtualDesktops(idx, [chip.desktopId]); break; }
                    }
                }
            }
        }

        width: Math.max(active ? root.pillHeight * 1.9 : root.pillHeight, content.implicitWidth + root.pillHeight * 0.72)
        height: root.pillHeight
        Behavior on width { NumberAnimation { duration: 340; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
        scale: ma.pressed ? 0.9 : (dropHover ? 1.12 : 1)
        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 2 } }

        DropArea {
            anchors.fill: parent
            anchors.margins: -root.gap / 2
            keys: ["application/x-doodlebookos-window"]
            onEntered: (drag) => { chip.dropHover = true; drag.accept(Qt.MoveAction); }
            onExited: chip.dropHover = false
            onDropped: (drop) => {
                chip.dropHover = false;
                chip.takeWindows(drop.getDataAsString("application/x-doodlebookos-window"));
                drop.accept(Qt.MoveAction);
            }
        }

        TaskManager.TasksModel {
            id: tasks
            activity: activityInfo.currentActivity
            filterByActivity: true
            virtualDesktop: chip.desktopId
            filterByVirtualDesktop: true
            filterByScreen: false
            groupMode: TaskManager.TasksModel.GroupApplications
            groupInline: false
            sortMode: TaskManager.TasksModel.SortLastActivated
        }

        // TasksModel lets two kinds of rows through the desktop filter: app launches in progress
        // (no desktop yet) and windows demanding attention (e.g. Discord on a new message).
        // Keep only rows really on this desktop. Rebuilt on structural changes only; a title
        // change leaves the key identical, so the icons are not recreated.
        property var rows: []          // [{ row, key }]
        property string rowsKey: ""
        function rebuild() {
            var A = TaskManager.AbstractTasksModel, out = [], keys = [];
            for (var r = 0; r < tasks.count; r++) {
                var idx = tasks.makeModelIndex(r);
                if (tasks.data(idx, A.IsStartup)) continue;
                if (!tasks.data(idx, A.IsOnAllVirtualDesktops)) {
                    var d = tasks.data(idx, A.VirtualDesktops) || [], here = false;
                    for (var k = 0; k < d.length; k++) if (String(d[k]) === chip.desktopId) { here = true; break; }
                    if (!here) continue;
                }
                var key = String(tasks.data(idx, A.AppId) || tasks.data(idx, A.AppName) || ("#" + r));
                out.push({ row: r, key: key });
                keys.push(r + ":" + key);
            }
            var joined = keys.join("|");
            if (joined !== rowsKey) { rowsKey = joined; rows = out; }
        }
        Connections {
            target: tasks
            function onCountChanged() { Qt.callLater(chip.rebuild); }
            function onDataChanged() { Qt.callLater(chip.rebuild); }
            function onRowsMoved() { Qt.callLater(chip.rebuild); }
            function onLayoutChanged() { Qt.callLater(chip.rebuild); }
            function onModelReset() { Qt.callLater(chip.rebuild); }
        }
        Component.onCompleted: rebuild()

        Rectangle {
            anchors.fill: parent
            radius: ma.pressed ? height * 0.3 : height / 2
            color: chip.active || chip.dropHover ? root.accent : root.tint(chip.hovered ? 0.24 : (chip.occupied ? 0.14 : 0.07))
            Behavior on color { ColorAnimation { duration: 220 } }
            Behavior on radius { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
        }

        Row {
            id: content
            anchors.centerIn: parent
            spacing: root.snap(root.pillHeight * 0.18)
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: chip.index + 1
                font.family: "Google Sans Flex"
                font.weight: 600
                font.pixelSize: root.fontPx
                font.features: { "tnum": 1 }
                renderType: Text.QtRendering
                color: chip.active || chip.dropHover ? root.onAccent : root.tint(chip.occupied ? 1 : 0.62)
                Behavior on color { ColorAnimation { duration: 220 } }
            }
            Repeater {
                model: root.showIcons ? chip.rows : null
                delegate: Kirigami.Icon {
                    required property var modelData
                    required property int index
                    visible: index < root.maxIcons
                    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                    width: root.iconPx
                    height: root.iconPx
                    source: tasks.data(tasks.makeModelIndex(modelData.row), Qt.DecorationRole)
                    roundToIconSize: false
                    opacity: chip.active || chip.hovered ? 1 : 0.85
                }
            }
            Text {
                visible: root.showIcons && chip.appCount > root.maxIcons
                anchors.verticalCenter: parent.verticalCenter
                text: "+" + (chip.appCount - root.maxIcons)
                font.family: "Google Sans Flex"
                font.weight: 600
                font.pixelSize: Math.round(root.fontPx * 0.8)
                color: chip.active || chip.dropHover ? root.onAccent : root.tint(0.75)
            }
        }

        PlasmaCore.ToolTipArea {
            anchors.fill: parent
            mainText: root.nameAt(chip.index)
            subText: {
                var n = chip.appCount, names = [];
                for (var i = 0; i < n && i < 6; i++) names.push(String(tasks.data(tasks.makeModelIndex(chip.rows[i].row), Qt.DisplayRole) || ""));
                var apps = n ? names.join(", ") + (n > 6 ? "…" : "") : root.t("No windows");
                return apps + "\n" + (chip.active ? root.t("Click: Overview") : root.t("Click: go to this desktop")) + " · " + root.t("Wheel: switch desktop");
            }
            MouseArea {
                id: ma
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                cursorShape: Qt.PointingHandCursor
                onEntered: root.lastHovered = chip.index
                onClicked: (m) => {
                    if (m.button === Qt.MiddleButton) root.shortcut("Grid View");
                    else root.switchTo(chip.desktopId);
                }
            }
        }
    }

    fullRepresentation: Item {
        id: bar
        implicitWidth: root.edgeMargin + row.implicitWidth
        implicitHeight: root.pillHeight
        Layout.minimumWidth: implicitWidth
        Layout.preferredWidth: implicitWidth
        Layout.maximumWidth: implicitWidth
        Layout.fillHeight: true

        HoverHandler { id: barHover }

        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            property real acc: 0
            onWheel: (ev) => {
                acc += ev.angleDelta.y !== 0 ? ev.angleDelta.y : -ev.angleDelta.x;
                if (acc >= 120) { acc = 0; root.step(-1); }
                else if (acc <= -120) { acc = 0; root.step(1); }
            }
        }

        Row {
            id: row
            x: root.edgeMargin
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.gap

            Repeater {
                model: root.ids
                delegate: Chip {}
            }

            // "+": always takes its slot (no layout jump), comes forward on hover
            Item {
                id: addChip
                visible: root.ids.length < 20
                width: root.pillHeight
                height: root.pillHeight
                readonly property bool lit: addMa.containsMouse
                scale: addMa.pressed ? 0.88 : 1
                Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 2 } }
                Rectangle {
                    anchors.fill: parent
                    radius: addMa.pressed ? height * 0.3 : height / 2
                    color: root.tint(addChip.lit ? 0.24 : 0.07)
                    opacity: barHover.hovered ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 180 } }
                    Behavior on color { ColorAnimation { duration: 160 } }
                    Behavior on radius { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
                }
                // plus sign drawn with two bars (no icon theme dependency)
                Item {
                    anchors.centerIn: parent
                    width: root.snap(root.pillHeight * 0.46)
                    height: width
                    opacity: barHover.hovered ? 1 : 0.4
                    rotation: addChip.lit ? 90 : 0
                    Behavior on opacity { NumberAnimation { duration: 180 } }
                    Behavior on rotation { NumberAnimation { duration: 320; easing.type: Easing.OutBack } }
                    Rectangle { anchors.centerIn: parent; width: parent.width; height: Math.max(1.5, root.snap(parent.width * 0.16)); radius: height / 2; color: root.fg }
                    Rectangle { anchors.centerIn: parent; height: parent.height; width: Math.max(1.5, root.snap(parent.height * 0.16)); radius: width / 2; color: root.fg }
                }
                PlasmaCore.ToolTipArea {
                    anchors.fill: parent
                    mainText: root.t("Add a desktop")
                    MouseArea {
                        id: addMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.addDesktop()
                    }
                }
            }
        }
    }
}

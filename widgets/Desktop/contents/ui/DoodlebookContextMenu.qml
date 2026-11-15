/*
 * SPDX-FileCopyrightText: 2026 Maciej Kujawiński <maciek.kujawinski@gmail.com>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support
import "i18n.js" as I18n
import "metrics" as LocalMetrics

QQC2.Popup {
    id: rootMenu

    Binding {
        when: rootMenu.effectivePlasmoid !== null
        target: LocalMetrics.Metrics
        property: "uiScale"
        value: (rootMenu.effectivePlasmoid && rootMenu.effectivePlasmoid.configuration
                && typeof rootMenu.effectivePlasmoid.configuration.shellScale === "number"
                && rootMenu.effectivePlasmoid.configuration.shellScale > 0)
            ? rootMenu.effectivePlasmoid.configuration.shellScale
            : 1.0
    }
    Binding {
        target: LocalMetrics.Metrics
        property: "hostDpr"
        value: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1.0
    }

    // Embed in containment or overlay with high z-order so it floats above all applets
    parent: QQC2.Overlay.overlay ? QQC2.Overlay.overlay : (containment ? containment : null)
    z: 999999

    padding: 0
    margins: 0
    modal: false
    dim: false
    focus: true
    closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutside | QQC2.Popup.CloseOnPressOutsideParent

    onOpened: {
        rootMenu.forceActiveFocus();
    }

    onActiveFocusChanged: {
        if (!activeFocus && opened) {
            Qt.callLater(() => {
                if (!rootMenu.activeFocus && opened) {
                    rootMenu.close();
                }
            });
        }
    }

    Connections {
        target: rootMenu.parent ? rootMenu.parent.Window.window : null
        function onActiveChanged() {
            var w = rootMenu.parent ? rootMenu.parent.Window.window : null;
            if (w && !w.active && rootMenu.opened) {
                rootMenu.close();
            }
        }
    }

    Connections {
        target: Qt.application
        function onStateChanged() {
            if (Qt.application.state !== Qt.ApplicationActive && rootMenu.opened) {
                rootMenu.close();
            }
        }
    }

    // Mode: "desktop" or "file" or "widget"
    property string menuMode: "desktop"
    property var targetItem: null
    property var folderModel: null
    property var folderView: null
    property var containment: null
    property var plasmoid: null
    readonly property var effectivePlasmoid: plasmoid || (containment && containment.Plasmoid ? containment.Plasmoid : null)

    // State for wallpaper selection
    property string activeWallpaperPath: ""
    property var wallpaperList: [
        { name: "DoodlebookOS_Wallpaper_DARK", path: "" },
        { name: "DoodlebookOS_Wallpaper_LIGHT", path: "" },
        { name: "Next", path: "" },
        { name: "Altai", path: "" },
        { name: "Flow", path: "" }
    ]

    // Accordion state for more settings
    property bool settingsExpanded: false

    onSettingsExpandedChanged: {
        if (settingsExpanded && rootMenu.menuMode === "desktop") {
            var container = rootMenu.parent || containment || (Window.window ? Window.window.contentItem : null);
            var pH = container ? container.height : 1080;
            var margin = LocalMetrics.Metrics.px(16.0);
            var expandedEstH = LocalMetrics.Metrics.px(524.0);
            if (rootMenu.y + expandedEstH > pH - margin) {
                rootMenu.y = Math.max(margin, pH - expandedEstH - margin);
            }
        }
    }

    function createNewFolder() {
        var baseName = I18n.t("New folder");
        var shCmd = "D=$(xdg-user-dir DESKTOP 2>/dev/null); "
            + "if [ -z \"$D\" ] || [ ! -d \"$D\" ]; then "
            + "  if [ -d \"$HOME/Pulpit\" ]; then D=\"$HOME/Pulpit\"; else D=\"$HOME/Desktop\"; fi; "
            + "fi; "
            + "mkdir -p \"$D\"; "
            + "BASE=\"" + baseName + "\"; "
            + "TARGET=\"$D/$BASE\"; "
            + "I=2; "
            + "while [ -e \"$TARGET\" ]; do TARGET=\"$D/$BASE $I\"; I=$((I+1)); done; "
            + "mkdir -p \"$TARGET\"; "
            + "touch \"$D\" 2>/dev/null || true";
        executor.connectSource(shCmd + " # " + Date.now());
    }

    Item {
        id: menuThemeScope
        Kirigami.Theme.colorSet: Kirigami.Theme.Tooltip
        Kirigami.Theme.inherit: false
    }

    // Color definitions (100% solid, fully opaque, bound to Tooltip token)
    readonly property bool isDark: Kirigami.Theme.colorSet === Kirigami.Theme.Complementary || Kirigami.Theme.backgroundColor.r < 0.5
    readonly property color cAccent: Kirigami.Theme.highlightColor
    readonly property color cBg: menuThemeScope ? menuThemeScope.Kirigami.Theme.backgroundColor : "#19191f"
    readonly property bool isLightBg: (cBg.r * 0.299 + cBg.g * 0.587 + cBg.b * 0.114) > 0.5
    readonly property color cCardBorder: isLightBg ? Qt.rgba(0, 0, 0, 0.12) : Qt.rgba(1, 1, 1, 0.15)
    readonly property color cText: isLightBg ? "#18181C" : "#FFFFFF"
    readonly property color cSub: isLightBg ? Qt.rgba(0.1, 0.1, 0.15, 0.75) : Qt.rgba(1, 1, 1, 0.75)
    readonly property color cHover: isLightBg ? Qt.rgba(0, 0, 0, 0.10) : Qt.rgba(1, 1, 1, 0.12)
    readonly property color cPress: isLightBg ? Qt.rgba(0, 0, 0, 0.18) : Qt.rgba(1, 1, 1, 0.22)

    // Background is completely transparent because we render two independent floating cards
    background: Item {}

    // Shell runner for system commands
    Plasma5Support.DataSource {
        id: executor
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName);
            if (rootMenu.folderModel && typeof rootMenu.folderModel.reload === "function") {
                rootMenu.folderModel.reload();
            }
        }
        function exec(cmd) {
            var fullCmd = "nohup sh -c " + JSON.stringify(cmd) + " </dev/null >/dev/null 2>&1 & # " + Date.now();
            connectSource(fullCmd);
        }
    }

    // Wallpaper scanner
    Plasma5Support.DataSource {
        id: wpScanner
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            var stdout = data["stdout"] || "";
            if (stdout.length > 0) {
                var lines = stdout.trim().split("\n");
                var list = [];
                var activePath = "";
                for (var i = 0; i < lines.length; i++) {
                    var l = lines[i].trim();
                    if (l.startsWith("CURR:")) {
                        activePath = l.substring(5).trim();
                        continue;
                    }
                    if (l.length > 0) {
                        var base = l.split("/").pop();
                        list.push({ name: base, path: l });
                    }
                }
                if (list.length > 0) {
                    rootMenu.wallpaperList = list.slice(0, 5);
                    if (activePath.length > 0) {
                        rootMenu.activeWallpaperPath = activePath;
                    } else if (rootMenu.activeWallpaperPath === "") {
                        rootMenu.activeWallpaperPath = list[0].path;
                    }
                }
            }
            disconnectSource(sourceName);
        }
    }

    function scanWallpapers() {
        var cmd = `python3 -c '
import os

curr = ""
try:
    with open(os.path.expanduser("~/.config/plasma-org.kde.plasma.desktop-appletsrc")) as f:
        for line in f:
            if line.startswith("Image="):
                curr = line.strip().split("=", 1)[1].replace("file://", "")
                break
except Exception:
    pass

def find_db_wp(fname):
    base, _ = os.path.splitext(fname)
    dirs = [
        os.path.expanduser("~/.local/share/wallpapers/DoodlebookOS"),
        os.path.expanduser("~/antigravity/DoodlebookOS-alphaRC/extras/wallpapers"),
        os.path.expanduser("~/Pobrane")
    ]
    exts = [".jpeg", ".jpg", ".png", ".webp", ""]
    for d in dirs:
        for ext in exts:
            p = os.path.join(d, base + ext)
            if os.path.isfile(p):
                return p
    return ""

def get_best_kde_wp(wp_name):
    img_dir = os.path.join("/usr/share/wallpapers", wp_name, "contents", "images")
    if not os.path.isdir(img_dir):
        return ""
    candidates = [os.path.join(img_dir, f) for f in os.listdir(img_dir) if f.endswith((".png", ".jpg", ".jpeg", ".webp"))]
    if not candidates:
        return ""
    for pat in ["5120x2880", "3840x2160", "7680x2160", "2560x1440", "1920x1080"]:
        for c in candidates:
            if pat in c:
                return c
    candidates.sort(key=lambda x: os.path.getsize(x), reverse=True)
    return candidates[0]

res = []
w_dark = find_db_wp("DoodlebookOS_Wallpaper_DARK.png")
if w_dark: res.append(w_dark)
w_light = find_db_wp("DoodlebookOS_Wallpaper_LIGHT.png")
if w_light: res.append(w_light)

kde_favs = ["Next", "Altai", "Flow", "MilkyWay", "ScarletTree", "Autumn", "Canopee"]
for k in kde_favs:
    if len(res) >= 5:
        break
    img = get_best_kde_wp(k)
    if img and img not in res:
        res.append(img)

if curr and os.path.isfile(curr):
    res = [curr] + [r for r in res if r != curr]

if curr:
    print("CURR:" + curr)
for r in res[:5]:
    print(r)
'`;
        wpScanner.connectSource(cmd + " # " + Date.now());
    }

    // Open API
    function openDesktopMenu(posX, posY, fModel, fView) {
        rootMenu.menuMode = "desktop";
        rootMenu.targetItem = null;
        rootMenu.folderModel = fModel;
        rootMenu.folderView = fView;
        rootMenu.settingsExpanded = false;
        positionAndOpen(posX, posY);
        scanWallpapers();
    }

    function openFileMenu(posX, posY, item, fModel, fView) {
        rootMenu.menuMode = "file";
        rootMenu.targetItem = item;
        rootMenu.folderModel = fModel;
        rootMenu.folderView = fView;
        rootMenu.settingsExpanded = false;
        positionAndOpen(posX, posY);
    }

    function positionAndOpen(targetX, targetY) {
        var container = rootMenu.parent || containment || (Window.window ? Window.window.contentItem : null);
        var pW = container ? container.width : 1920;
        var pH = container ? container.height : 1080;

        var menuW = LocalMetrics.Metrics.px(355.0);
        var menuH = rootMenu.menuMode === "desktop"
            ? (settingsExpanded ? LocalMetrics.Metrics.px(524.0) : LocalMetrics.Metrics.px(315.0))
            : LocalMetrics.Metrics.px(270.0);
        var edgePad = LocalMetrics.Metrics.px(16.0);

        // Ensure popup doesn't overflow screen borders
        var finalX = targetX;
        var finalY = targetY;

        if (finalX + menuW > pW - edgePad) {
            finalX = Math.max(edgePad, targetX - menuW);
        }
        if (finalY + menuH > pH - edgePad) {
            finalY = Math.max(edgePad, targetY - menuH);
        }

        rootMenu.x = finalX;
        rootMenu.y = finalY;
        rootMenu.open();
    }

    // Apply Wallpaper Action
    function applyWallpaper(path) {
        if (!path) return;
        rootMenu.activeWallpaperPath = path;
        executor.exec("plasma-apply-wallpaperimage \"" + path + "\" && (~/.local/bin/doodlebookos-topbar-color \"" + path + "\" || true)");
    }

    // Content container with Spring Scale & Fade In
    contentItem: Item {
        implicitWidth: LocalMetrics.Metrics.px(355.0)
        implicitHeight: mainColumn.implicitHeight

        scale: rootMenu.opened ? 1.0 : 0.88
        opacity: rootMenu.opened ? 1.0 : 0.0
        transformOrigin: Item.TopLeft

        Behavior on scale {
            NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.15 }
        }
        Behavior on opacity {
            NumberAnimation { duration: 160; easing.type: Easing.OutQuad }
        }

        Column {
            id: mainColumn
            width: parent.width
            spacing: LocalMetrics.Metrics.px(2.0)

            // ================================================================
            // TOP CARD: Main Actions & Wallpaper Carousel (Desktop Mode)
            // ================================================================
            Rectangle {
                id: topCard
                width: parent.width
                implicitHeight: topCardColumn.implicitHeight + LocalMetrics.Metrics.px(8.0)
                radius: LocalMetrics.Metrics.px(24.0)
                color: rootMenu.cBg
                border.color: "transparent"
                border.width: 0

                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowHorizontalOffset: 0
                    shadowVerticalOffset: LocalMetrics.Metrics.px(6.0)
                    shadowBlur: 0.5
                    shadowColor: Qt.rgba(0, 0, 0, 0.32)
                }

                Column {
                    id: topCardColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.topMargin: LocalMetrics.Metrics.px(4.0)
                    anchors.leftMargin: LocalMetrics.Metrics.px(7.0)
                    anchors.rightMargin: LocalMetrics.Metrics.px(7.0)
                    spacing: 0

                    // --------------------------------------------------------
                    // DESKTOP MODE
                    // --------------------------------------------------------
                    Loader {
                        width: parent.width
                        active: rootMenu.menuMode === "desktop"
                        visible: active
                        sourceComponent: Column {
                            width: parent.width
                            spacing: LocalMetrics.Metrics.px(2.0)

                            // 1. New folder
                            ActionRow {
                                iconSource: Qt.resolvedUrl("icons/create_new_folder.svg")
                                text: I18n.t("New folder")
                                onClicked: {
                                    rootMenu.close();
                                    rootMenu.createNewFolder();
                                }
                            }

                            // 2. Widgets
                            ActionRow {
                                iconSource: Qt.resolvedUrl("icons/widgets.svg")
                                text: I18n.t("Widgets")
                                onClicked: {
                                    rootMenu.close();
                                    var act = null;
                                    if (rootMenu.effectivePlasmoid && typeof rootMenu.effectivePlasmoid.internalAction === "function") {
                                        act = rootMenu.effectivePlasmoid.internalAction("add widgets");
                                    } else if (rootMenu.effectivePlasmoid && typeof rootMenu.effectivePlasmoid.action === "function") {
                                        act = rootMenu.effectivePlasmoid.action("add widgets");
                                    }
                                    if (act) {
                                        act.trigger();
                                    } else {
                                        executor.exec("$(command -v qdbus-qt6 || command -v qdbus6 || command -v qdbus) org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.toggleWidgetExplorer");
                                    }
                                }
                            }

                            // 3. Wallpaper
                            ActionRow {
                                iconSource: Qt.resolvedUrl("icons/palette.svg")
                                text: I18n.t("Wallpaper")
                                onClicked: {
                                    rootMenu.close();
                                    var act = null;
                                    if (rootMenu.effectivePlasmoid && typeof rootMenu.effectivePlasmoid.internalAction === "function") {
                                        act = rootMenu.effectivePlasmoid.internalAction("configure");
                                    } else if (rootMenu.effectivePlasmoid && typeof rootMenu.effectivePlasmoid.action === "function") {
                                        act = rootMenu.effectivePlasmoid.action("configure");
                                    }
                                    if (act) {
                                        act.trigger();
                                    } else if (rootMenu.effectivePlasmoid && rootMenu.effectivePlasmoid.containment && typeof rootMenu.effectivePlasmoid.containment.configureRequested === "function") {
                                        rootMenu.effectivePlasmoid.containment.configureRequested(rootMenu.effectivePlasmoid);
                                    } else {
                                        executor.exec("kcmshell6 kcm_wallpaper || systemsettings || true");
                                    }
                                }
                            }

                            // 4. Horizontal Wallpaper Thumbnails Carousel
                            Item {
                                width: parent.width
                                height: LocalMetrics.Metrics.px(97.0)

                                ListView {
                                    id: wpView
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    height: LocalMetrics.Metrics.px(88.0)
                                    orientation: ListView.Horizontal
                                    spacing: LocalMetrics.Metrics.px(8.0)
                                    clip: true
                                    model: rootMenu.wallpaperList

                                    delegate: Item {
                                        id: wpDelegate
                                        required property int index
                                        required property var modelData

                                        readonly property bool isSelected: {
                                            if (!rootMenu.activeWallpaperPath) return wpDelegate.index === 0;
                                            if (rootMenu.activeWallpaperPath === wpDelegate.modelData.path) return true;
                                            var aBase = rootMenu.activeWallpaperPath.split("/").pop();
                                            var mBase = wpDelegate.modelData.name || (wpDelegate.modelData.path ? wpDelegate.modelData.path.split("/").pop() : "");
                                            return Boolean(aBase && mBase && (aBase === mBase || aBase.replace(/\.[^/.]+$/, "") === mBase.replace(/\.[^/.]+$/, "")));
                                        }
                                        
                                        width: wpDelegate.isSelected ? LocalMetrics.Metrics.px(234.0) : LocalMetrics.Metrics.px(99.0)
                                        height: LocalMetrics.Metrics.px(88.0)

                                        Behavior on width {
                                            NumberAnimation { duration: 250; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
                                        }

                                        Rectangle {
                                            id: wpBox
                                            anchors.fill: parent
                                            radius: LocalMetrics.Metrics.px(18.0)
                                            color: rootMenu.isDark ? "#28292E" : "#E2E4E8"
                                            border.color: wpDelegate.isSelected ? rootMenu.cAccent : rootMenu.cCardBorder
                                            border.width: wpDelegate.isSelected ? Math.max(1, LocalMetrics.Metrics.px(2.0)) : Math.max(1.0 / LocalMetrics.Metrics.dpr, LocalMetrics.Metrics.px(1.0))

                                            Rectangle {
                                                id: wpMask
                                                width: wpImageMaskedContainer.width
                                                height: wpImageMaskedContainer.height
                                                radius: LocalMetrics.Metrics.px(16.0)
                                                color: "black"
                                                visible: false
                                                layer.enabled: true
                                            }

                                            Item {
                                                id: wpImageMaskedContainer
                                                anchors.fill: parent
                                                anchors.margins: wpDelegate.isSelected ? LocalMetrics.Metrics.px(2.0) : LocalMetrics.Metrics.px(1.0)
                                                layer.enabled: true
                                                layer.effect: MultiEffect {
                                                    maskEnabled: true
                                                    maskSource: wpMask
                                                }

                                                // Wallpaper image preview
                                                Image {
                                                    anchors.fill: parent
                                                    source: (wpDelegate.modelData && wpDelegate.modelData.path) ? ("file://" + wpDelegate.modelData.path) : ""
                                                    fillMode: Image.PreserveAspectCrop
                                                    smooth: true
                                                    asynchronous: true
                                                }

                                                // Subtle dark overlay for inactive items
                                                Rectangle {
                                                    anchors.fill: parent
                                                    color: Qt.rgba(0, 0, 0, wpDelegate.isSelected ? 0.05 : 0.25)
                                                }
                                            }

                                            // Central Checkmark Badge for Selected Wallpaper
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: LocalMetrics.Metrics.px(36.0)
                                                height: LocalMetrics.Metrics.px(36.0)
                                                radius: LocalMetrics.Metrics.px(18.0)

                                                // Circle background: linkColor
                                                color: Kirigami.Theme.linkColor

                                                visible: wpDelegate.isSelected
                                                scale: wpDelegate.isSelected ? 1.0 : 0.4
                                                opacity: wpDelegate.isSelected ? 1.0 : 0.0

                                                Behavior on scale {
                                                    NumberAnimation { duration: 220; easing.type: Easing.OutBack }
                                                }
                                                Behavior on opacity {
                                                    NumberAnimation { duration: 180; easing.type: Easing.OutQuad }
                                                }

                                                Kirigami.Icon {
                                                    anchors.centerIn: parent
                                                    width: LocalMetrics.Metrics.px(20.0)
                                                    height: LocalMetrics.Metrics.px(20.0)
                                                    source: Qt.resolvedUrl("icons/check.svg")

                                                    // Icon color: backgroundColor
                                                    color: Kirigami.Theme.backgroundColor
                                                }
                                            }

                                            // Hover indicator
                                            Rectangle {
                                                anchors.fill: parent
                                                color: wpMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
                                                radius: parent.radius
                                            }

                                            MouseArea {
                                                id: wpMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (wpDelegate.modelData) rootMenu.applyWallpaper(wpDelegate.modelData.path);
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // --------------------------------------------------------
                    // FILE / FOLDER MODE (When right-clicking on desktop icons)
                    // --------------------------------------------------------
                    Loader {
                        width: parent.width
                        active: rootMenu.menuMode === "file"
                        visible: active
                        sourceComponent: Column {
                            width: parent.width
                            spacing: LocalMetrics.Metrics.px(2.0)

                            ActionRow {
                                iconSource: Qt.resolvedUrl("icons/open_in_new.svg")
                                text: I18n.t("Open")
                                onClicked: {
                                    rootMenu.close();
                                    if (rootMenu.folderModel) rootMenu.folderModel.runSelected();
                                }
                            }

                            ActionRow {
                                iconSource: Qt.resolvedUrl("icons/content_copy.svg")
                                text: I18n.t("Copy")
                                onClicked: {
                                    rootMenu.close();
                                    if (rootMenu.folderModel) rootMenu.folderModel.copy();
                                }
                            }

                            ActionRow {
                                iconSource: Qt.resolvedUrl("icons/edit.svg")
                                text: I18n.t("Rename")
                                onClicked: {
                                    rootMenu.close();
                                    if (rootMenu.folderView) rootMenu.folderView.rename();
                                }
                            }

                            ActionRow {
                                iconSource: Qt.resolvedUrl("icons/delete.svg")
                                text: I18n.t("Move to Trash")
                                isDestructive: true
                                onClicked: {
                                    rootMenu.close();
                                    if (rootMenu.folderModel) {
                                        var trashAction = rootMenu.folderModel.action("trash");
                                        if (trashAction && trashAction.enabled) {
                                            trashAction.trigger();
                                        } else if (typeof rootMenu.folderModel.moveSelectedToTrash === "function") {
                                            rootMenu.folderModel.moveSelectedToTrash();
                                        } else if (typeof rootMenu.folderModel.deleteSelected === "function") {
                                            rootMenu.folderModel.deleteSelected();
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ================================================================
            // BOTTOM CARD: "More settings" (Desktop Mode)
            // or "More system options..." (File Mode)
            // ================================================================
            Rectangle {
                id: bottomCard
                width: parent.width
                implicitHeight: bottomCardColumn.implicitHeight
                radius: LocalMetrics.Metrics.px(24.0)
                color: rootMenu.cBg
                border.color: "transparent"
                border.width: 0
                clip: true

                Behavior on implicitHeight {
                    NumberAnimation { duration: 220; easing.type: Easing.OutQuad }
                }

                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowHorizontalOffset: 0
                    shadowVerticalOffset: LocalMetrics.Metrics.px(6.0)
                    shadowBlur: 0.5
                    shadowColor: Qt.rgba(0, 0, 0, 0.32)
                }

                Column {
                    id: bottomCardColumn
                    width: parent.width

                    // Pill Main Header Button
                    Item {
                        width: parent.width
                        height: LocalMetrics.Metrics.px(52.0)

                        Rectangle {
                            anchors.fill: parent
                            color: bottomMouse.containsMouse ? rootMenu.cHover : "transparent"
                            radius: LocalMetrics.Metrics.px(24.0)
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: LocalMetrics.Metrics.px(14.0)
                            anchors.rightMargin: LocalMetrics.Metrics.px(12.0)
                            spacing: LocalMetrics.Metrics.px(12.0)

                            // Left Icon: Settings Gear
                            Kirigami.Icon {
                                Layout.preferredWidth: LocalMetrics.Metrics.px(20.0)
                                Layout.preferredHeight: LocalMetrics.Metrics.px(20.0)
                                source: Qt.resolvedUrl("icons/settings.svg")
                                isMask: true
                                color: rootMenu.cText
                            }

                            // Text Label
                            Text {
                                Layout.fillWidth: true
                                text: rootMenu.menuMode === "desktop" ? I18n.t("More settings") : I18n.t("More system options…")
                                font.family: "Google Sans Flex"
                                font.pixelSize: LocalMetrics.Metrics.px(15.0)
                                font.weight: Font.Medium
                                color: rootMenu.cText
                            }

                            // Right Chevron Pill
                            Rectangle {
                                Layout.preferredWidth: LocalMetrics.Metrics.px(36.0)
                                Layout.preferredHeight: LocalMetrics.Metrics.px(26.0)
                                radius: LocalMetrics.Metrics.px(13.0)
                                color: rootMenu.isDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.07)

                                Kirigami.Icon {
                                    anchors.centerIn: parent
                                    width: LocalMetrics.Metrics.px(18.0)
                                    height: LocalMetrics.Metrics.px(18.0)
                                    source: Qt.resolvedUrl("icons/keyboard_arrow_down.svg")
                                    isMask: true
                                    color: rootMenu.cSub

                                    // Icon rotation depending on mode and expansion state:
                                    // - Desktop mode collapsed: 0° (down)
                                    // - Desktop mode expanded: 180° (up)
                                    // - Other mode (e.g. file): -90° (right)
                                    rotation: {
                                        if (rootMenu.menuMode === "desktop") {
                                            return rootMenu.settingsExpanded ? 180 : 0;
                                        }
                                        return -90;
                                    }

                                    Behavior on rotation {
                                        NumberAnimation { duration: 200; easing.type: Easing.OutQuad }
                                    }
                                }
                            }
                        }

                        MouseArea {
                            id: bottomMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (rootMenu.menuMode === "desktop") {
                                    rootMenu.settingsExpanded = !rootMenu.settingsExpanded;
                                } else {
                                    rootMenu.close();
                                    if (rootMenu.folderModel && rootMenu.targetItem) {
                                        rootMenu.folderModel.openContextMenu(rootMenu.targetItem);
                                    }
                                }
                            }
                        }
                    }

                    // Expandable Accordion Drawer for More Desktop & System Options
                    Column {
                        width: parent.width - LocalMetrics.Metrics.px(14.0)
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: rootMenu.settingsExpanded && rootMenu.menuMode === "desktop"
                        spacing: LocalMetrics.Metrics.px(2.0)
                        topPadding: LocalMetrics.Metrics.px(4.0)
                        bottomPadding: LocalMetrics.Metrics.px(12.0)

                        Rectangle {
                            width: parent.width
                            anchors.horizontalCenter: parent.horizontalCenter
                            height: Math.max(1.0 / LocalMetrics.Metrics.dpr, LocalMetrics.Metrics.px(1.0))
                            color: rootMenu.cCardBorder
                            Item { height: LocalMetrics.Metrics.px(4.0); width: 1 }
                        }

                        // 1. Terminal
                        ActionRow {
                            iconSource: Qt.resolvedUrl("icons/terminal.svg")
                            text: I18n.t("Open in terminal")
                            onClicked: {
                                rootMenu.close();
                                executor.exec("konsole || x-terminal-emulator || gnome-terminal");
                            }
                        }

                        // 2. Display Settings
                        ActionRow {
                            iconSource: Qt.resolvedUrl("icons/display_settings.svg")
                            text: I18n.t("Display settings")
                            onClicked: {
                                rootMenu.close();
                                executor.exec("kcmshell6 kcm_kscreen");
                            }
                        }

                        // Separator line
                        Item {
                            width: parent.width
                            height: LocalMetrics.Metrics.px(7.0)
                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width - LocalMetrics.Metrics.px(16.0)
                                height: Math.max(1.0 / LocalMetrics.Metrics.dpr, LocalMetrics.Metrics.px(1.0))
                                color: rootMenu.cCardBorder
                            }
                        }

                        // 5. Lock Screen
                        ActionRow {
                            iconSource: Qt.resolvedUrl("icons/lock.svg")
                            text: I18n.t("Lock screen")
                            onClicked: {
                                rootMenu.close();
                                executor.exec("loginctl lock-session");
                            }
                        }

                        // 6. Full System Settings
                        ActionRow {
                            iconSource: Qt.resolvedUrl("icons/settings.svg")
                            text: I18n.t("All settings…")
                            onClicked: {
                                rootMenu.close();
                                executor.exec("systemsettings");
                            }
                        }
                    }
                }
            }
        }
    }

    // ========================================================================
    // HELPER COMPONENT: Action Row with Google-style icons & hover ripple
    // ========================================================================
    component ActionRow: Rectangle {
        id: rowRoot
        property string iconSource: ""
        property string text: ""
        property bool isDestructive: false
        signal clicked()

        width: parent ? parent.width : LocalMetrics.Metrics.px(341.0)
        height: LocalMetrics.Metrics.px(50.0)
        radius: LocalMetrics.Metrics.px(14.0)
        color: rowMouse.pressed ? rootMenu.cPress : (rowMouse.containsMouse ? rootMenu.cHover : "transparent")

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: LocalMetrics.Metrics.px(7.0)
            anchors.rightMargin: LocalMetrics.Metrics.px(5.0)
            spacing: LocalMetrics.Metrics.px(12.0)

            Item {
                Layout.preferredWidth: LocalMetrics.Metrics.px(20.0)
                Layout.preferredHeight: LocalMetrics.Metrics.px(20.0)

                Kirigami.Icon {
                    anchors.centerIn: parent
                    width: LocalMetrics.Metrics.px(20.0)
                    height: LocalMetrics.Metrics.px(20.0)
                    visible: rowRoot.iconSource.length > 0
                    source: rowRoot.iconSource
                    isMask: true
                    color: rowRoot.isDestructive && rowMouse.containsMouse ? "#EA4335" : rootMenu.cText
                }
            }

            Text {
                Layout.fillWidth: true
                text: rowRoot.text
                font.family: "Google Sans Flex"
                font.pixelSize: LocalMetrics.Metrics.px(15.0)
                font.weight: Font.Medium
                color: rowRoot.isDestructive && rowMouse.containsMouse ? "#EA4335" : rootMenu.cText
                elide: Text.ElideRight
            }
        }

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: rowRoot.clicked()
        }
    }
}

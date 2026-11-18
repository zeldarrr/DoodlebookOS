/*
 * SPDX-FileCopyrightText: 2024-2026 Maciej Kujawiński <maciek.kujawinski@gmail.com>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import QtQuick
import org.kde.plasma.plasmoid
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore

PlasmaCore.Dialog {
    id: root

    property var rootModel: null
    property var plasmoidConfiguration: null
    property Item visualParentItem: null
    property var dimOverlayItem: null
    readonly property bool shouldDimBackground: Boolean((root.plasmoidConfiguration && root.plasmoidConfiguration.dimBackground !== false) || (typeof Plasmoid !== "undefined" && Plasmoid.configuration && Plasmoid.configuration.dimBackground !== false))

    objectName: "popupWindow"
    flags: Qt.WindowStaysOnTopHint
    visualParent: visualParentItem
    // Floating: KWin's "sliding popups" animation is skipped (it delayed the launcher on Super);
    // the dialog is still placed above the dock and our own 130 ms fade plays instead
    location: PlasmaCore.Types.Floating
    floating: 12
    hideOnWindowDeactivate: true
    backgroundHints: PlasmaCore.Types.StandardBackground

    property bool fullscreen: false
    property bool editMode: false
    property int openSerial: 0                 // bumped on every open: drives the staggered entrance
    property int popupWidth: 680
    property int popupHeight: Math.round(Screen.height * Math.max(40, Math.min(95, Plasmoid.configuration.launcherHeight || 62)) / 100)
    property real panelHeight: 52

    width: popupWidth
    height: popupHeight

    readonly property real containerInnerPadding: fullscreen ? 28 : (Plasmoid.configuration.launcherPadding || 16)
    readonly property real railWidth: 0          // A–Z rail removed
    readonly property int columns: fullscreen
        ? Math.max(6, Math.floor((popupWidth - containerInnerPadding * 2 - railWidth) / 132))
        : ((root.plasmoidConfiguration && root.plasmoidConfiguration.numberColumns) || 6)
    property int iconSize: fullscreen ? 60 : (Plasmoid.configuration.launcherIconSize || 44)
    readonly property real cellSizeWidth: Math.floor((popupWidth - (containerInnerPadding * 2) - railWidth) / columns)
    readonly property real cellSizeHeight: fullscreen ? 120 : Math.max(iconSize + 34, Plasmoid.configuration.launcherRowHeight || 90)

    property alias launcherContainer: launcherBox.card
    property alias launcherContextMenu: launcherContextMenu
    property alias folderOverlay: folderOverlay
    property alias infoCard: infoCard

    function closeAnimated() {
        close();
    }
    // launch first, then close once the tile's launch animation has played
    function closeAfterLaunch() {
        closeTimer.restart();
    }

    function toast(text) { toastItem.show(text); }
    function openFolder(fid, item) { folderOverlay.openFolder(fid, item); }
    function showInfo(appId) { infoCard.openFor(appId); }

    // Escape: innermost layer first
    function handleEscape() {
        if (launcherContextMenu.visible) { launcherContextMenu.close(); return true; }
        if (infoCard.shown) { infoCard.close(); return true; }
        if (folderOverlay.shown) { folderOverlay.close(); return true; }
        if (editMode) { editMode = false; return true; }
        return false;
    }

    function updatePosition() {
        if (!visualParent) {
            var scrHeight = Screen.height;
            var scrX = Screen.virtualX;
            var scrY = Screen.virtualY;
            var effPanelHeight = root.panelHeight;
            if (visualParentItem && visualParentItem.Window && visualParentItem.Window.window && visualParentItem.Window.window.height > 0) {
                effPanelHeight = visualParentItem.Window.window.height;
            }
            var bottomGap = 12;
            var panelTop = scrY + scrHeight - effPanelHeight;
            var targetX = scrX + Math.round((Screen.width - popupWidth) / 2);
            var targetY = Math.max(24, Math.round(panelTop - popupHeight - bottomGap));
            if (root.x !== targetX) root.x = targetX;
            if (root.y !== targetY) root.y = targetY;
        }
    }

    property bool skipResetOnOpen: false

    function openWithQuery(term) {
        skipResetOnOpen = true;
        if (shouldDimBackground && dimOverlayItem && typeof dimOverlayItem.showOverlay === "function") {
            dimOverlayItem.showOverlay();
        }
        updatePosition();
        root.visible = true;
        updatePosition();
        root.requestActivate();
        if (main && typeof main.setQuery === "function") {
            main.setQuery(term);
        }
        skipResetOnOpen = false;
    }

    function toggle() {
        if (root.visible) {
            close();
        } else {
            open();
        }
    }

    function open() {
        if (shouldDimBackground && dimOverlayItem && typeof dimOverlayItem.showOverlay === "function") {
            dimOverlayItem.showOverlay();
        }
        updatePosition();
        root.visible = true;
        updatePosition();
        root.requestActivate();
    }

    function close() {
        closeTimer.stop();
        if (launcherContextMenu && launcherContextMenu.visible) launcherContextMenu.close();
        folderOverlay.close();
        infoCard.close();
        if (dimOverlayItem && typeof dimOverlayItem.hideOverlay === "function") {
            dimOverlayItem.hideOverlay();
        }
        root.visible = false;
        root.editMode = false;
        if (main && typeof main.reset === "function") {
            main.reset();
        }
    }

    onVisibleChanged: {
        if (launcherContextMenu && launcherContextMenu.visible) {
            launcherContextMenu.close();
        }
        if (typeof Plasmoid !== "undefined") {
            Plasmoid.expanded = visible;
        }
        if (visible) {
            updatePosition();
            openSerial++;
            launcherRevealAnim.restart();
            // no rootModel.refresh() here: Kicker refreshes itself on KSycoca changes
            if (!skipResetOnOpen && main && typeof main.reset === "function") {
                main.reset();
            }
        } else {
            editMode = false;
            if (dimOverlayItem && typeof dimOverlayItem.hideOverlay === "function") {
                dimOverlayItem.hideOverlay();
            }
        }
    }

    onWidthChanged: if (visible) updatePosition()
    onHeightChanged: if (visible) updatePosition()

    mainItem: Item {
        id: launcherBox
        implicitWidth: root.popupWidth
        implicitHeight: root.popupHeight
        Layout.preferredWidth: root.popupWidth
        Layout.preferredHeight: root.popupHeight
        Layout.minimumWidth: root.popupWidth
        Layout.minimumHeight: root.popupHeight
        Layout.maximumWidth: root.popupWidth
        Layout.maximumHeight: root.popupHeight

        property alias card: launcherCard

        Timer { id: closeTimer; interval: 170; onTriggered: root.close() }

        // M3 entrance, kept short so Super still feels instant: the page rises out of the dock and
        // settles with the "emphasized decelerate" curve (most of the travel happens in the first
        // frames). Cheap: opacity + one transform on a single item, no layer, no re-layout.
        property real revealT: 1.0
        NumberAnimation {
            id: launcherRevealAnim
            target: launcherBox; property: "revealT"; from: 0; to: 1
            duration: Kirigami.Units.longDuration > 1 ? 280 : 0
            easing.type: Easing.BezierSpline; easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1, 1]
        }

        Rectangle {
            id: launcherCard
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            height: parent.height
            radius: 0
            color: "transparent"
            border.width: 0
            clip: false

            Item {
                id: cardContent
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width
                height: root.popupHeight

                MainView {
                    id: main
                    anchors.fill: parent
                    anchors.margins: root.containerInnerPadding
                    anchors.bottomMargin: Math.round(root.containerInnerPadding * 0.6)
                    opacity: 0.35 + 0.65 * launcherBox.revealT
                    transform: [
                        Scale {
                            origin.x: main.width / 2
                            origin.y: main.height
                            xScale: 0.97 + 0.03 * launcherBox.revealT
                            yScale: xScale
                        },
                        Translate { y: (1 - launcherBox.revealT) * 28 }
                    ]
                }

                FolderOverlay {
                    id: folderOverlay
                    anchors.fill: parent
                    z: 50
                }

                AppInfoCard {
                    id: infoCard
                    anchors.fill: parent
                    z: 60
                }

                LauncherToast {
                    id: toastItem
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 76
                    z: 70
                }

                LauncherContextMenu {
                    id: launcherContextMenu
                    anchors.fill: parent
                    launcherPopup: root
                }
            }
        }
    }

    Component.onCompleted: {
        updatePosition();
        if (root.rootModel) {
            root.rootModel.refreshed.connect(function() {
                if (main && typeof main.reset === "function" && !root.visible) {
                    main.reset();
                }
            });
        }
    }
}

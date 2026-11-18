/*
 * SPDX-FileCopyrightText: 2024-2026 Maciej Kujawiński <maciek.kujawinski@gmail.com>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

// Apps page: pinned apps + folders, recent files, then every app A–Z.
// Full-screen mode shows the apps as swipeable pages.
import QtQuick
import org.kde.plasma.plasmoid
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import org.kde.kitemmodels as KItemModels
import "i18n.js" as I18n

Item {
    id: combinedRoot
    function i18n(k, a1, a2) { return I18n.t(k, a1, a2); }
    width: parent ? parent.width : 0
    height: parent ? parent.height : 0

    readonly property bool isCombinedAppsView: true
    readonly property Item viewItem: root.fullscreen ? (pagedLoader.item ? pagedLoader.item.keyTarget : null) : mainGrid
    property QtObject rawRecentAppsModel: null
    property QtObject rawMainAppsModel: null
    property QtObject rawRecentDocsModel: null
    property bool showHiddenLocal: false
    readonly property bool showHiddenApps: showHiddenLocal || (main.bottomBar && main.bottomBar.showHidden)
    readonly property bool showHeader: true

    property var hiddenApps: []
    property var hiddenSet: ({})

    function cfg() {
        return (typeof root !== "undefined" && root && root.plasmoidConfiguration) ? root.plasmoidConfiguration : (typeof Plasmoid !== "undefined" ? Plasmoid.configuration : null);
    }
    function refreshHiddenApps() {
        var c = cfg();
        var raw = (c && c.hiddenApps) ? Array.from(c.hiddenApps) : [];
        var set = {};
        for (var i = 0; i < raw.length; i++) {
            var h = String(raw[i] || "").trim();
            if (!h) continue;
            set[appIndex.sid(h)] = true;
            set["name:" + h.toLowerCase()] = true;
        }
        hiddenApps = raw;
        hiddenSet = set;
        invalidateAll();
    }
    function isHidden(id, name) {
        return Boolean((id && hiddenSet[id]) || (name && hiddenSet["name:" + String(name).toLowerCase()]));
    }
    function writeHidden(list) {
        var c = cfg();
        if (c) {
            c.hiddenApps = list;
            if (typeof c.writeConfig === "function") c.writeConfig();
        }
        refreshHiddenApps();
    }
    function hideApp(appId, appName) {
        var id = appIndex.sid(appId || appName);
        var list = hiddenApps.slice();
        if (id && list.indexOf(id) === -1) list.push(id);
        writeHidden(list);
    }
    function unhideApp(appId, appName) {
        var id = appIndex.sid(appId), nm = String(appName || "").toLowerCase();
        writeHidden(hiddenApps.filter(function (h) {
            var s = String(h || "").trim();
            return appIndex.sid(s) !== id && s.toLowerCase() !== nm;
        }));
    }
    function invalidateAll() {
        filteredMainModel.invalidateFilter();
        hiddenAppsModel.invalidateFilter();
    }

    // full-screen pages read rows straight from the filtered model (no per-page proxies)
    property int filterRev: 0
    function idAt(row) {
        var src = filteredMainModel.mapToSource(filteredMainModel.index(row, 0));
        return src.row >= 0 ? (appIndex.rowIds[src.row] || "") : "";
    }
    Connections {
        target: filteredMainModel
        enabled: root.fullscreen
        function onRowCountChanged() { combinedRoot.filterRev++; }
        function onModelReset() { combinedRoot.filterRev++; }
        function onLayoutChanged() { combinedRoot.filterRev++; }
    }

    Connections {
        target: (typeof root !== "undefined" && root) ? root : null
        function onPlasmoidConfigurationChanged() { combinedRoot.refreshHiddenApps(); }
    }
    Connections {
        target: appIndex
        function onRevisionChanged() { combinedRoot.invalidateAll(); }
    }

    function syncModels() {
        rawRecentAppsModel = rootModel.modelForRow(0);
        rawRecentDocsModel = rootModel.modelForRow(1);
        rawMainAppsModel = rootModel.modelForRow(2);
    }
    Component.onCompleted: {
        syncModels();
        refreshHiddenApps();
    }
    Connections {
        target: rootModel
        function onCountChanged() { combinedRoot.syncModels(); combinedRoot.refreshHiddenApps(); }
        function onRefreshed() { combinedRoot.syncModels(); combinedRoot.refreshHiddenApps(); }
    }

    component TriggerProxy: KItemModels.KSortFilterProxyModel {
        function trigger(row, actionId, actionArgument) {
            if (!sourceModel) return false;
            var srcIdx = mapToSource(index(row, 0));
            if (srcIdx.row >= 0 && typeof sourceModel.trigger === "function") {
                return sourceModel.trigger(srcIdx.row, actionId || "", actionArgument || null);
            }
            return false;
        }
    }

    TriggerProxy {
        id: filteredMainModel
        sourceModel: combinedRoot.rawMainAppsModel
        filterRowCallback: function (sourceRow, sourceParent) {
            if (!sourceModel) return true;
            var id = appIndex.rowIds[sourceRow] || "";
            var name = combinedRoot.hiddenApps.length ? sourceModel.data(sourceModel.index(sourceRow, 0, sourceParent), Qt.DisplayRole) : "";
            if (combinedRoot.isHidden(id, name)) return false;
            return !appIndex.folderOfId[id];          // apps living in a folder are shown in it
        }
    }

    TriggerProxy {
        id: hiddenAppsModel
        sourceModel: combinedRoot.rawMainAppsModel
        filterRowCallback: function (sourceRow, sourceParent) {
            if (!sourceModel || !combinedRoot.hiddenApps.length) return false;
            var id = appIndex.rowIds[sourceRow] || "";
            var name = sourceModel.data(sourceModel.index(sourceRow, 0, sourceParent), Qt.DisplayRole);
            return combinedRoot.isHidden(id, name);
        }
    }

    // ───────── section title ─────────
    component SectionTitle: Text {
        width: parent ? parent.width : 0
        leftPadding: 8
        topPadding: 6
        bottomPadding: 4
        font.family: "Google Sans Flex"
        font.pixelSize: 12
        font.weight: Font.DemiBold
        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.6)
    }

    // ───────── pinned apps + folders (drop an app on the empty area to pin it) ─────────
    component PinnedArea: Item {
        id: pinned
        property bool singleRow: false
        readonly property int pinCount: kicker.globalFavorites ? kicker.globalFavorites.count : 0
        readonly property int folderCount: appIndex.folders.length
        readonly property bool hasContent: pinCount + folderCount > 0
        visible: hasContent || root.editMode || pinDrop.containsDrag
        height: visible ? Math.max(flow.implicitHeight, root.cellSizeHeight) : 0
        width: parent ? parent.width : 0

        Rectangle {
            anchors.fill: parent
            radius: 24
            visible: !pinned.hasContent || pinDrop.containsDrag
            color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, pinDrop.containsDrag ? 0.16 : 0.06)
            border.width: 1.5
            border.color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.5)
            Text {
                anchors.centerIn: parent
                visible: !pinned.hasContent
                text: combinedRoot.i18n("Drop apps here to pin them")
                font.family: "Google Sans Flex"; font.pixelSize: 13
                color: Kirigami.Theme.textColor
                opacity: 0.7
            }
        }
        DropArea {
            id: pinDrop
            anchors.fill: parent
            onDropped: (ev) => {
                var src = kicker.dragSource.sourceId;
                if (!src || kicker.dragSource.sourcePinned >= 0) return;
                ev.accept();
                if (kicker.dragSource.sourceFolder) appIndex.removeFromFolder(kicker.dragSource.sourceFolder, src);
                kicker.globalFavorites.addFavorite("applications:" + src);
            }
        }
        Flow {
            id: flow
            width: pinned.singleRow ? Math.min(implicitWidthHint, parent.width) : parent.width
            anchors.horizontalCenter: parent.horizontalCenter
            readonly property real implicitWidthHint: (pinned.pinCount + pinned.folderCount) * root.cellSizeWidth
            Repeater {
                model: kicker.globalFavorites
                delegate: FavoriteItem {
                    required property var model
                    required property int index
                    tileModel: model
                    tileIndex: index
                    triggerModel: kicker.globalFavorites
                    isPinned: true
                }
            }
            Repeater {
                model: appIndex.folders
                delegate: FolderTile {
                    required property var modelData
                    required property int index
                    folder: modelData
                    staggerIndex: pinned.pinCount + index
                }
            }
        }
    }

    // ───────── list mode ─────────
    AppGridView {
        id: mainGrid
        visible: !root.fullscreen
        anchors.fill: parent
        model: filteredMainModel
        showScrollBar: false
        move: null
        moveDisplaced: null

        onContentYChanged: {
            if (root.launcherContextMenu && root.launcherContextMenu.visible) root.launcherContextMenu.close();
        }

        header: Component {
            Column {
                id: headerCol
                width: mainGrid.width
                visible: combinedRoot.showHeader
                height: combinedRoot.showHeader ? implicitHeight : 0
                spacing: 2
                // the header fills in after creation (models load): while the user is still looking
                // at it (contentY <= 0, grid rows start at y = 0), keep the view pinned to the top
                onHeightChanged: if (mainGrid.contentY <= 0) Qt.callLater(mainGrid.positionViewAtBeginning)

                SectionTitle {
                    text: combinedRoot.i18n("Pinned")
                    visible: pinArea.visible
                }
                PinnedArea { id: pinArea }

                SectionTitle {
                    text: combinedRoot.i18n("Recent files")
                    visible: recentFiles.visible
                }
                RecentFiles {
                    id: recentFiles
                    width: parent.width
                    visible: count > 0 && Plasmoid.configuration.showRecentFiles !== false
                    height: visible ? 64 : 0
                    model: combinedRoot.rawRecentDocsModel
                }

                SectionTitle {
                    topPadding: 12
                    text: combinedRoot.i18n("All apps")
                }
            }
        }

        footer: Component {
            Item {
                id: footerContainer
                width: mainGrid.width
                visible: hiddenAppsModel.count > 0
                height: visible ? (hiddenAppsSection.implicitHeight + 24) : 0

                Column {
                    id: hiddenAppsSection
                    anchors.top: parent.top
                    anchors.topMargin: 12
                    anchors.left: parent.left
                    anchors.right: parent.right
                    spacing: 12

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.round(root.cellSizeWidth * 1.6)
                        height: 3
                        radius: 2
                        color: Kirigami.Theme.textColor
                        opacity: 0.22
                    }

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: eyeRow.implicitWidth + 28
                        height: 36
                        radius: toggleMouse.pressed ? 12 : 18
                        color: combinedRoot.showHiddenApps ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.22)
                                                           : (toggleMouse.containsMouse ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.10) : "transparent")
                        Behavior on radius { NumberAnimation { duration: Kirigami.Units.longDuration > 1 ? 200 : 0; easing.type: Easing.OutBack } }
                        Row {
                            id: eyeRow
                            anchors.centerIn: parent
                            spacing: 8
                            Item {
                                width: 20; height: 20
                                anchors.verticalCenter: parent.verticalCenter
                                Image { id: eyeIcon; anchors.fill: parent; sourceSize: Qt.size(40, 40); source: Qt.resolvedUrl("icons/visibility.svg"); visible: false }
                                MultiEffect { anchors.fill: eyeIcon; source: eyeIcon; colorization: 1.0
                                    colorizationColor: combinedRoot.showHiddenApps ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: combinedRoot.i18n("Hidden apps (%1)", hiddenAppsModel.count)
                                font.family: "Google Sans Flex"; font.pixelSize: 12; font.weight: Font.Medium
                                color: Kirigami.Theme.textColor
                            }
                        }
                        MouseArea {
                            id: toggleMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: combinedRoot.showHiddenLocal = !combinedRoot.showHiddenLocal
                        }
                    }

                    Flow {
                        width: parent.width
                        visible: combinedRoot.showHiddenApps
                        Repeater {
                            model: combinedRoot.showHiddenApps ? hiddenAppsModel : null
                            delegate: FavoriteItem {
                                required property var model
                                required property int index
                                tileModel: model
                                tileIndex: index
                                triggerModel: hiddenAppsModel
                                isHiddenApp: true
                            }
                        }
                    }
                }
            }
        }
    }

    // ───────── full-screen mode: pages ─────────
    Loader {
        id: pagedLoader
        anchors.fill: parent
        active: root.fullscreen
        sourceComponent: Item {
            id: paged
            property alias keyTarget: pager
            readonly property int rowsPerPage: Math.max(1, Math.floor(pager.height / root.cellSizeHeight))
            readonly property int perPage: Math.max(1, rowsPerPage * root.columns)
            readonly property int pageCount: Math.max(1, Math.ceil(filteredMainModel.count / perPage))
            property int current: -1

            ColumnLayout {
                anchors.fill: parent
                spacing: 6
                PinnedArea {
                    Layout.fillWidth: true
                    Layout.preferredHeight: height
                    singleRow: true
                    visible: combinedRoot.showHeader && (hasContent || root.editMode)
                }
                ListView {
                    id: pager
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    orientation: ListView.Horizontal
                    snapMode: ListView.SnapOneItem
                    highlightRangeMode: ListView.StrictlyEnforceRange
                    highlightMoveDuration: 380
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true
                    focus: true
                    model: paged.pageCount
                    property bool movedWithKeyboard: false

                    function selectIndex(i) {
                        var n = filteredMainModel.count;
                        if (!n) return;
                        paged.current = Math.max(0, Math.min(n - 1, i));
                        currentIndex = Math.floor(paged.current / paged.perPage);
                    }
                    Keys.onPressed: (event) => {
                        var c = paged.current < 0 ? 0 : paged.current, cols = root.columns;
                        var ctrl = event.modifiers & Qt.ControlModifier;
                        if (event.key === Qt.Key_Right && !ctrl) selectIndex(paged.current < 0 ? 0 : c + 1);
                        else if (event.key === Qt.Key_Left && !ctrl) selectIndex(c - 1);
                        else if (event.key === Qt.Key_Down) selectIndex(paged.current < 0 ? 0 : c + cols);
                        else if (event.key === Qt.Key_Up) {
                            if (c % paged.perPage < cols) { main.searchBar.textField.forceActiveFocus(); paged.current = -1; }
                            else selectIndex(c - cols);
                        }
                        else if (event.key === Qt.Key_PageDown) selectIndex((currentIndex + 1) * paged.perPage);
                        else if (event.key === Qt.Key_PageUp) selectIndex((currentIndex - 1) * paged.perPage);
                        else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && paged.current >= 0) {
                            filteredMainModel.trigger(paged.current, "", null);
                            root.closeAfterLaunch();
                        } else if (event.text && event.text.charCodeAt(0) >= 32 && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
                            main.searchBar.textField.forceActiveFocus();
                            main.searchBar.textField.text += event.text;
                        } else return;
                        event.accepted = true;
                    }
                    onActiveFocusChanged: if (activeFocus && paged.current < 0 && filteredMainModel.count) paged.current = currentIndex * paged.perPage

                    // wheel flips pages
                    WheelHandler {
                        property int acc: 0
                        onWheel: (ev) => {
                            acc += ev.angleDelta.y || ev.angleDelta.x;
                            if (acc <= -120) { pager.incrementCurrentIndex(); acc = 0; }
                            else if (acc >= 120) { pager.decrementCurrentIndex(); acc = 0; }
                        }
                    }

                    delegate: Item {
                        id: page
                        required property int index
                        width: pager.width
                        height: pager.height
                        readonly property int start: index * paged.perPage
                        Grid {
                            anchors.top: parent.top
                            anchors.horizontalCenter: parent.horizontalCenter
                            columns: root.columns
                            Repeater {
                                model: Math.max(0, Math.min(paged.perPage, filteredMainModel.count - page.start))
                                delegate: FavoriteItem {
                                    required property int index
                                    forcedId: { var r = combinedRoot.filterRev; return combinedRoot.idAt(page.start + index); }
                                    staggerIndex: index
                                    forceCurrent: pager.activeFocus && paged.current === page.start + index
                                }
                            }
                        }
                    }
                }

                // page dots (expressive: the current one stretches into a pill)
                Row {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.bottomMargin: 2
                    spacing: 6
                    visible: paged.pageCount > 1
                    Repeater {
                        model: paged.pageCount
                        delegate: Rectangle {
                            required property int index
                            readonly property bool on: pager.currentIndex === index
                            width: on ? 24 : 8
                            height: 8
                            radius: 4
                            color: on ? Kirigami.Theme.highlightColor : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.3)
                            Behavior on width { NumberAnimation { duration: Kirigami.Units.longDuration > 1 ? 280 : 0; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
                            Behavior on color { ColorAnimation { duration: Kirigami.Units.longDuration > 1 ? 180 : 0 } }
                            MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: pager.currentIndex = parent.index }
                        }
                    }
                }
            }
        }
    }
}

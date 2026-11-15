/*
 * SPDX-FileCopyrightText: 2024-2026 Maciej Kujawiński <maciek.kujawinski@gmail.com>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import org.kde.kitemmodels as KItemModels
import "metrics" as LocalMetrics

Item {
    id: combinedRoot
    width: parent ? parent.width : 0
    height: parent ? parent.height : 0

    readonly property bool isCombinedAppsView: true
    property alias viewItem: mainGrid
    property QtObject rawRecentAppsModel: null
    property QtObject rawMainAppsModel: null
    property bool showHiddenApps: false

    property var hiddenApps: []
    property var hiddenLookup: ({})

    function buildHiddenLookup(appsList) {
        var map = Object.create(null);
        if (!appsList || appsList.length === 0) return map;
        for (var i = 0; i < appsList.length; ++i) {
            var raw = (appsList[i] || "").toString().toLowerCase().trim();
            if (!raw) continue;
            map[raw] = true;

            var base = raw.replace("applications:", "").replace(".desktop", "").replace("file://", "");
            if (base.length > 0) {
                map[base] = true;
                if (base.indexOf("/") !== -1) {
                    var slashSub = base.substring(base.lastIndexOf("/") + 1);
                    map[slashSub] = true;
                    base = slashSub;
                }
                var dotParts = base.split(".");
                if (dotParts.length > 1) {
                    for (var d = 1; d < dotParts.length; d++) {
                        map[dotParts.slice(d).join(".")] = true;
                    }
                }
            }
        }
        return map;
    }

    function refreshHiddenApps() {
        var cfg = (typeof root !== "undefined" && root && root.plasmoidConfiguration) ? root.plasmoidConfiguration : (typeof Plasmoid !== "undefined" ? Plasmoid.configuration : null);
        var raw = (cfg && cfg.hiddenApps) ? Array.from(cfg.hiddenApps) : [];
        hiddenLookup = buildHiddenLookup(raw);
        hiddenApps = raw;
        filteredMainModel.invalidateFilter();
        filteredRecentModel.invalidateFilter();
        hiddenAppsModel.invalidateFilter();
    }

    function hideApp(appId, appName) {
        var cfg = (typeof root !== "undefined" && root && root.plasmoidConfiguration) ? root.plasmoidConfiguration : (typeof Plasmoid !== "undefined" ? Plasmoid.configuration : null);
        var list = hiddenApps.slice();
        var idStr = (appId || appName || "").toString().trim();
        if (idStr && list.indexOf(idStr) === -1) {
            list.push(idStr);
        }
        hiddenLookup = buildHiddenLookup(list);
        hiddenApps = list;
        if (cfg) {
            cfg.hiddenApps = list;
            if (typeof cfg.writeConfig === "function") {
                cfg.writeConfig();
            }
        }
        filteredMainModel.invalidateFilter();
        filteredRecentModel.invalidateFilter();
        hiddenAppsModel.invalidateFilter();
    }

    function unhideApp(appId, appName) {
        var cfg = (typeof root !== "undefined" && root && root.plasmoidConfiguration) ? root.plasmoidConfiguration : (typeof Plasmoid !== "undefined" ? Plasmoid.configuration : null);
        var idStr = (appId || "").toString().toLowerCase().trim();
        var nameStr = (appName || "").toString().toLowerCase().trim();
        var list = hiddenApps.filter(function(item) {
            var it = (item || "").toString().toLowerCase().trim();
            if (idStr && (it === idStr || it.indexOf(idStr) !== -1 || idStr.indexOf(it) !== -1)) return false;
            if (nameStr && (it === nameStr || it.indexOf(nameStr) !== -1 || nameStr.indexOf(it) !== -1)) return false;
            return true;
        });
        hiddenLookup = buildHiddenLookup(list);
        hiddenApps = list;
        if (cfg) {
            cfg.hiddenApps = list;
            if (typeof cfg.writeConfig === "function") {
                cfg.writeConfig();
            }
        }
        filteredMainModel.invalidateFilter();
        filteredRecentModel.invalidateFilter();
        hiddenAppsModel.invalidateFilter();
    }

    Connections {
        target: (typeof root !== "undefined" && root) ? root : null
        function onPlasmoidConfigurationChanged() {
            combinedRoot.refreshHiddenApps();
        }
    }

    function isRowHidden(srcModel, row, parentIdx) {
        if (!srcModel || !hiddenApps || hiddenApps.length === 0) return false;
        if (!hiddenLookup) return false;
        var idx = srcModel.index(row, 0, parentIdx);

        var rolesToCheck = [0, 257, 258, 259, 266, 270];
        for (var r = 0; r < rolesToCheck.length; r++) {
            var d = srcModel.data(idx, rolesToCheck[r]);
            if (d === undefined || d === null) continue;
            var c = d.toString().toLowerCase().trim();
            if (c.length === 0) continue;

            if (hiddenLookup[c] === true) return true;

            var base = c.replace("applications:", "").replace(".desktop", "").replace("file://", "");
            if (base.length > 0) {
                if (hiddenLookup[base] === true) return true;
                if (base.indexOf("/") !== -1) {
                    var slashSub = base.substring(base.lastIndexOf("/") + 1);
                    if (hiddenLookup[slashSub] === true) return true;
                    base = slashSub;
                }
                var dotParts = base.split(".");
                if (dotParts.length > 1) {
                    for (var i = 1; i < dotParts.length; i++) {
                        if (hiddenLookup[dotParts.slice(i).join(".")] === true) return true;
                    }
                }
            }
        }
        return false;
    }

    Component.onCompleted: {
        rawRecentAppsModel = rootModel.modelForRow(0);
        rawMainAppsModel = rootModel.modelForRow(2);
        refreshHiddenApps();
    }

    Connections {
        target: rootModel
        function onCountChanged() {
            combinedRoot.rawRecentAppsModel = rootModel.modelForRow(0);
            combinedRoot.rawMainAppsModel = rootModel.modelForRow(2);
            combinedRoot.refreshHiddenApps();
        }
        function onRefreshed() {
            combinedRoot.rawRecentAppsModel = rootModel.modelForRow(0);
            combinedRoot.rawMainAppsModel = rootModel.modelForRow(2);
            combinedRoot.refreshHiddenApps();
            if (filteredMainModel && typeof filteredMainModel.invalidate === "function") {
                filteredMainModel.invalidate();
            }
            if (filteredRecentModel && typeof filteredRecentModel.invalidate === "function") {
                filteredRecentModel.invalidate();
            }
        }
    }

    KItemModels.KSortFilterProxyModel {
        id: filteredMainModel
        sourceModel: combinedRoot.rawMainAppsModel
        filterRowCallback: function(sourceRow, sourceParent) {
            if (!sourceModel) return true;
            if (!combinedRoot.hiddenApps || combinedRoot.hiddenApps.length === 0) return true;
            return !combinedRoot.isRowHidden(sourceModel, sourceRow, sourceParent);
        }

        function trigger(row, actionId, actionArgument) {
            if (!sourceModel) return false;
            var pIdx = index(row, 0);
            var srcIdx = mapToSource(pIdx);
            if (srcIdx.row >= 0 && typeof sourceModel.trigger === "function") {
                return sourceModel.trigger(srcIdx.row, actionId || "", actionArgument || null);
            }
            return false;
        }
    }

    KItemModels.KSortFilterProxyModel {
        id: filteredRecentModel
        sourceModel: combinedRoot.rawRecentAppsModel
        filterRowCallback: function(sourceRow, sourceParent) {
            if (!sourceModel) return true;
            if (combinedRoot.hiddenApps && combinedRoot.hiddenApps.length > 0) {
                if (combinedRoot.isRowHidden(sourceModel, sourceRow, sourceParent)) return false;
            }
            return sourceRow < 6;
        }

        function trigger(row, actionId, actionArgument) {
            if (!sourceModel) return false;
            var pIdx = index(row, 0);
            var srcIdx = mapToSource(pIdx);
            if (srcIdx.row >= 0 && typeof sourceModel.trigger === "function") {
                return sourceModel.trigger(srcIdx.row, actionId || "", actionArgument || null);
            }
            return false;
        }
    }

    KItemModels.KSortFilterProxyModel {
        id: hiddenAppsModel
        sourceModel: combinedRoot.rawMainAppsModel
        filterRowCallback: function(sourceRow, sourceParent) {
            if (!sourceModel) return false;
            if (!combinedRoot.hiddenApps || combinedRoot.hiddenApps.length === 0) return false;
            return combinedRoot.isRowHidden(sourceModel, sourceRow, sourceParent);
        }

        function trigger(row, actionId, actionArgument) {
            if (!sourceModel) return false;
            var pIdx = index(row, 0);
            var srcIdx = mapToSource(pIdx);
            if (srcIdx.row >= 0 && typeof sourceModel.trigger === "function") {
                return sourceModel.trigger(srcIdx.row, actionId || "", actionArgument || null);
            }
            return false;
        }
    }

    onHiddenAppsChanged: {
        hiddenLookup = buildHiddenLookup(hiddenApps);
        filteredMainModel.invalidateFilter();
        filteredRecentModel.invalidateFilter();
        hiddenAppsModel.invalidateFilter();
    }

    AppGridView {
        id: mainGrid
        anchors.fill: parent
        model: filteredMainModel
        move: null
        moveDisplaced: null

        onContentYChanged: {
            if (typeof root !== "undefined" && root && root.launcherContextMenu && root.launcherContextMenu.visible) {
                root.launcherContextMenu.close();
            }
        }

        header: Component {
            Item {
                id: headerContainer
                width: mainGrid.width
                readonly property real separatorTopSpacing: LocalMetrics.Metrics.legacyDp(10)
                readonly property real separatorBottomSpacing: LocalMetrics.Metrics.legacyDp(22)
                readonly property real separatorThick: LocalMetrics.Metrics.legacyDp(3)

                height: root.cellSizeHeight + separatorTopSpacing + separatorThick + separatorBottomSpacing

                GridView {
                    id: recentSubGrid
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: root.cellSizeHeight

                    cellWidth: root.cellSizeWidth
                    cellHeight: root.cellSizeHeight
                    interactive: false
                    boundsBehavior: Flickable.StopAtBounds
                    move: null
                    moveDisplaced: null

                    model: filteredRecentModel

                    delegate: FavoriteItem {
                        id: recentFavItem
                        triggerModel: filteredRecentModel
                        visible: index < 6
                        width: root.cellSizeWidth
                        height: root.cellSizeHeight
                    }
                }

                // Rounded separator line
                Rectangle {
                    anchors.top: recentSubGrid.bottom
                    anchors.topMargin: headerContainer.separatorTopSpacing
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.round(root.cellSizeWidth * 1.6)
                    height: headerContainer.separatorThick
                    radius: headerContainer.separatorThick / 2
                    color: Kirigami.Theme.textColor
                    opacity: 0.22
                }
            }
        }

        footer: Component {
            Item {
                id: footerContainer
                width: mainGrid.width
                visible: hiddenAppsModel.count > 0
                height: visible ? (hiddenAppsSection.implicitHeight + LocalMetrics.Metrics.legacyDp(24)) : 0

                Column {
                    id: hiddenAppsSection
                    anchors.top: parent.top
                    anchors.topMargin: LocalMetrics.Metrics.legacyDp(12)
                    anchors.left: parent.left
                    anchors.right: parent.right
                    spacing: LocalMetrics.Metrics.legacyDp(12)

                    // Separator
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.round(root.cellSizeWidth * 1.6)
                        height: LocalMetrics.Metrics.legacyDp(3)
                        radius: LocalMetrics.Metrics.legacyDp(2)
                        color: Kirigami.Theme.textColor
                        opacity: 0.22
                    }

                    // Centered visibility.svg button
                    Item {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: LocalMetrics.Metrics.legacyDp(36)
                        height: LocalMetrics.Metrics.legacyDp(36)

                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: toggleMouse.pressed ? Qt.rgba(1, 1, 1, 0.18) : (toggleMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : "transparent")
                        }

                        Item {
                            anchors.centerIn: parent
                            width: LocalMetrics.Metrics.legacyDp(22)
                            height: LocalMetrics.Metrics.legacyDp(22)

                            Image {
                                id: eyeIcon
                                anchors.fill: parent
                                sourceSize: Qt.size(Math.round(width * 2), Math.round(height * 2))
                                fillMode: Image.PreserveAspectFit
                                source: Qt.resolvedUrl("icons/visibility.svg")
                                visible: false
                            }

                            MultiEffect {
                                anchors.fill: eyeIcon
                                source: eyeIcon
                                colorization: 1.0
                                colorizationColor: combinedRoot.showHiddenApps ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
                            }
                        }

                        MouseArea {
                            id: toggleMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                combinedRoot.showHiddenApps = !combinedRoot.showHiddenApps;
                            }
                        }
                    }

                    // Hidden apps list
                    Item {
                        width: parent.width
                        visible: combinedRoot.showHiddenApps
                        height: visible ? (Math.ceil(hiddenAppsModel.count / ((typeof root !== "undefined" && root.plasmoidConfiguration && root.plasmoidConfiguration.numberColumns) || 6)) * root.cellSizeHeight) : 0
                        implicitHeight: height

                        GridView {
                            id: hiddenGrid
                            anchors.fill: parent
                            cellWidth: root.cellSizeWidth
                            cellHeight: root.cellSizeHeight
                            interactive: false
                            boundsBehavior: Flickable.StopAtBounds
                            model: hiddenAppsModel

                            delegate: FavoriteItem {
                                id: hiddenFavItem
                                triggerModel: hiddenAppsModel
                                isHiddenApp: true
                                width: root.cellSizeWidth
                                height: root.cellSizeHeight
                            }
                        }
                    }
                }
            }
        }
    }
}

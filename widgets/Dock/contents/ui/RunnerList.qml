/*
 * SPDX-FileCopyrightText: 2024-2026 Maciej Kujawiński <maciek.kujawinski@gmail.com>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kitemmodels as KItemModels
import org.kde.plasma.plasma5support as Plasma5Support
import "i18n.js" as I18n
import "metrics" as LocalMetrics

Item {
    id: searchListRoot
    function i18n(k, a1, a2) { return I18n.t(k, a1, a2); }
    width: parent ? parent.width : 0
    height: parent ? parent.height : 0

    property alias viewItem: searchListView
    property var rawModel: null
    property alias model: searchListRoot.rawModel
    property alias count: searchListView.count
    property alias currentIndex: searchListView.currentIndex
    property string topResultName: ""
    property bool footerSelected: false

    function isDirectUrl(text) {
        if (!text) return false;
        var t = text.trim();
        if (t.startsWith("http://") || t.startsWith("https://") || t.startsWith("file://") || t.startsWith("localhost")) {
            return true;
        }
        if (!t.includes(" ") && /^[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)+(\/.*)?$/.test(t)) {
            return true;
        }
        return false;
    }

    function formatUrl(text) {
        var t = (text || "").trim();
        if (t.startsWith("http://") || t.startsWith("https://") || t.startsWith("file://")) {
            return t;
        }
        if (t.startsWith("localhost")) {
            return "http://" + t;
        }
        return "https://" + t;
    }

    function openWebOrUrl(text) {
        var t = (text || "").trim();
        if (t.length === 0) return;
        if (isDirectUrl(t)) {
            Qt.openUrlExternally(formatUrl(t));
        } else {
            Qt.openUrlExternally("https://www.google.com/search?q=" + encodeURIComponent(t));
        }
        if (typeof root !== "undefined" && root && typeof root.closeAnimated === "function") {
            root.closeAnimated();
        }
    }

    Plasma5Support.DataSource {
        id: osdExec
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName);
        }
        function showOsd(icon, text) {
            var safeText = (text || "").replace(/'/g, "'\\''");
            connectSource("$(command -v qdbus-qt6 || command -v qdbus6 || command -v qdbus) org.kde.plasmashell /org/kde/osdService org.kde.osdService.showText '" + icon + "' '" + safeText + "'");
        }
    }

    function showOsdNotification(icon, text) {
        osdExec.showOsd(icon, text);
    }

    function updateTopResult() {
        if (filteredSearchModel && filteredSearchModel.count > 0) {
            var targetIdx = (searchListView.currentIndex >= 0 && searchListView.currentIndex < filteredSearchModel.count) ? searchListView.currentIndex : 0;
            var idx = filteredSearchModel.index(targetIdx, 0);
            topResultName = (filteredSearchModel.data(idx, Qt.DisplayRole) || "").toString();
        } else {
            topResultName = "";
        }
    }

    KItemModels.KSortFilterProxyModel {
        id: filteredSearchModel
        sourceModel: searchListRoot.rawModel

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

    ListView {
        id: searchListView
        anchors.fill: parent
        anchors.topMargin: LocalMetrics.Metrics.legacyDp(4)
        anchors.bottomMargin: LocalMetrics.Metrics.legacyDp(8)
        anchors.leftMargin: LocalMetrics.Metrics.legacyDp(8)
        anchors.rightMargin: LocalMetrics.Metrics.legacyDp(8)
        clip: true
        focus: true

        model: filteredSearchModel
        boundsBehavior: Flickable.StopAtBounds
        keyNavigationEnabled: false
        keyNavigationWraps: false
        highlightMoveDuration: 0
        spacing: LocalMetrics.Metrics.legacyDp(2)

        section.property: "group"
        section.criteria: ViewSection.FullString
        section.delegate: Component {
            id: sectionHeaderComponent
            Item {
                id: sectionHeader
                required property string section
                width: ListView.view ? ListView.view.width : 0
                height: LocalMetrics.Metrics.legacyDp(28)

                QQC2.Label {
                    anchors.left: parent.left
                    anchors.leftMargin: LocalMetrics.Metrics.legacyDp(12)
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: LocalMetrics.Metrics.legacyDp(4)
                    text: sectionHeader.section
                    font.family: (typeof main !== "undefined" && main) ? main.textFont : Kirigami.Theme.defaultFont.family
                    font.pointSize: 9 * (8.0 / 9.0) * LocalMetrics.Metrics.clampedScale
                    font.weight: Font.DemiBold
                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.45)
                    elide: Text.ElideRight
                }
            }
        }

        delegate: RunnerDelegate {
            id: runnerDelegateItem
        }

        footer: Component {
            id: footerComponent
            Item {
                id: footerRoot
                width: ListView.view ? ListView.view.width : 0
                height: (typeof runnerModel !== "undefined" && runnerModel && runnerModel.query && runnerModel.query.trim().length > 0) ? LocalMetrics.Metrics.legacyDp(46) : 0
                visible: height > 0

                readonly property bool isSelected: searchListRoot.footerSelected
                readonly property bool isHovered: footerMouseArea.containsMouse

                Rectangle {
                    anchors.fill: parent
                    anchors.leftMargin: LocalMetrics.Metrics.legacyDp(6)
                    anchors.rightMargin: LocalMetrics.Metrics.legacyDp(6)
                    anchors.topMargin: LocalMetrics.Metrics.legacyDp(2)
                    anchors.bottomMargin: LocalMetrics.Metrics.legacyDp(2)
                    radius: LocalMetrics.Metrics.legacyDp(8)
                    color: footerRoot.isSelected ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.22)
                                                 : (footerRoot.isHovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent")
                    border.width: footerRoot.isSelected ? 1 : 0
                    border.color: footerRoot.isSelected ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.5) : "transparent"

                    Behavior on color { ColorAnimation { duration: 100 } }
                }

                MouseArea {
                    id: footerMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        searchListRoot.openWebOrUrl(runnerModel.query);
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: LocalMetrics.Metrics.legacyDp(16)
                    anchors.rightMargin: LocalMetrics.Metrics.legacyDp(16)
                    spacing: LocalMetrics.Metrics.legacyDp(12)

                    Image {
                        Layout.preferredWidth: LocalMetrics.Metrics.legacyDp(20)
                        Layout.preferredHeight: LocalMetrics.Metrics.legacyDp(20)
                        Layout.alignment: Qt.AlignVCenter
                        source: (typeof runnerModel !== "undefined" && runnerModel && searchListRoot.isDirectUrl(runnerModel.query)) ? "internet-web-browser" : Qt.resolvedUrl("icons/google_g.svg")
                        sourceSize.width: Math.round(LocalMetrics.Metrics.legacyDp(20) * 2)
                        sourceSize.height: Math.round(LocalMetrics.Metrics.legacyDp(20) * 2)
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: LocalMetrics.Metrics.legacyDp(1)

                        QQC2.Label {
                            Layout.fillWidth: true
                            text: {
                                var q = (typeof runnerModel !== "undefined" && runnerModel) ? (runnerModel.query || "") : "";
                                if (searchListRoot.isDirectUrl(q)) {
                                    return searchListRoot.i18n("Open website: ") + searchListRoot.formatUrl(q);
                                }
                                return searchListRoot.i18n("Search Google for: ") + "\"" + q + "\"";
                            }
                            font.family: (typeof main !== "undefined" && main) ? main.textFont : Kirigami.Theme.defaultFont.family
                            font.pointSize: (typeof main !== "undefined" && main) ? (main.textSize + (1 * (8.0 / 9.0) * LocalMetrics.Metrics.clampedScale)) : (11 * (8.0 / 9.0) * LocalMetrics.Metrics.clampedScale)
                            font.weight: Font.DemiBold
                            color: footerRoot.isSelected ? Kirigami.Theme.highlightColor : ((typeof main !== "undefined" && main) ? main.textColor : Kirigami.Theme.textColor)
                            elide: Text.ElideRight
                        }

                        QQC2.Label {
                            Layout.fillWidth: true
                            text: (typeof runnerModel !== "undefined" && runnerModel && searchListRoot.isDirectUrl(runnerModel.query)) ? searchListRoot.i18n("Open in browser") : searchListRoot.i18n("Web search")
                            font.family: (typeof main !== "undefined" && main) ? main.textFont : Kirigami.Theme.defaultFont.family
                            font.pointSize: (typeof main !== "undefined" && main) ? Math.max(7 * LocalMetrics.Metrics.clampedScale, main.textSize - (1 * (8.0 / 9.0) * LocalMetrics.Metrics.clampedScale)) : (9 * (8.0 / 9.0) * LocalMetrics.Metrics.clampedScale)
                            color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.6)
                            elide: Text.ElideRight
                        }
                    }

                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        radius: LocalMetrics.Metrics.legacyDp(4)
                        color: Qt.rgba(1, 1, 1, 0.08)
                        implicitWidth: footerBadge.implicitWidth + LocalMetrics.Metrics.legacyDp(12)
                        implicitHeight: footerBadge.implicitHeight + LocalMetrics.Metrics.legacyDp(6)

                        QQC2.Label {
                            id: footerBadge
                            anchors.centerIn: parent
                            text: (typeof runnerModel !== "undefined" && runnerModel && searchListRoot.isDirectUrl(runnerModel.query)) ? "WWW" : "Google"
                            font.pointSize: 8 * (8.0 / 9.0) * LocalMetrics.Metrics.clampedScale
                            font.weight: Font.Normal
                            color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.5)
                        }
                    }
                }
            }
        }

        onCountChanged: {
            if (count > 0 && currentIndex < 0 && !searchListRoot.footerSelected) {
                currentIndex = 0;
            }
            updateTopResult();
        }
        onCurrentIndexChanged: {
            if (currentIndex >= 0) {
                searchListRoot.footerSelected = false;
            }
            updateTopResult();
        }

        Keys.onUpPressed: event => {
            if (searchListRoot.footerSelected) {
                event.accepted = true;
                searchListRoot.footerSelected = false;
                if (count > 0) {
                    currentIndex = count - 1;
                    positionViewAtIndex(currentIndex, ListView.Contain);
                }
            } else if (currentIndex > 0) {
                event.accepted = true;
                currentIndex--;
                positionViewAtIndex(currentIndex, ListView.Contain);
            }
        }

        Keys.onDownPressed: event => {
            if (currentIndex < count - 1) {
                event.accepted = true;
                currentIndex++;
                positionViewAtIndex(currentIndex, ListView.Contain);
            } else if (currentIndex === count - 1) {
                event.accepted = true;
                currentIndex = -1;
                searchListRoot.footerSelected = true;
            }
        }

        Keys.onReturnPressed: event => {
            if (searchListRoot.footerSelected) {
                event.accepted = true;
                searchListRoot.openWebOrUrl(runnerModel.query);
                return;
            }
            if (currentItem && typeof currentItem.runPrimary === "function") {
                event.accepted = true;
                if (event.modifiers & Qt.ShiftModifier) {
                    currentItem.runFirstAction();
                } else {
                    currentItem.runPrimary();
                }
            }
        }
        Keys.onEnterPressed: event => {
            if (searchListRoot.footerSelected) {
                event.accepted = true;
                searchListRoot.openWebOrUrl(runnerModel.query);
                return;
            }
            if (currentItem && typeof currentItem.runPrimary === "function") {
                event.accepted = true;
                if (event.modifiers & Qt.ShiftModifier) {
                    currentItem.runFirstAction();
                } else {
                    currentItem.runPrimary();
                }
            }
        }
    }

    Connections {
        target: runnerModel
        function onQueryChanged() {
            searchListRoot.footerSelected = false;
            searchListView.currentIndex = 0;
            searchListView.positionViewAtBeginning();
            updateTopResult();
        }
        function onQueryFinished() {
            if (searchListView.count > 0 && searchListView.currentIndex < 0 && !searchListRoot.footerSelected) {
                searchListView.currentIndex = 0;
            }
            updateTopResult();
        }
        function onCountChanged() {
            updateTopResult();
        }
    }

    Connections {
        target: filteredSearchModel
        function onRowsInserted() { updateTopResult(); }
        function onRowsRemoved() { updateTopResult(); }
        function onModelReset() { updateTopResult(); }
        function onLayoutChanged() { updateTopResult(); }
    }
}

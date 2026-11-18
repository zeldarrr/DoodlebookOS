/*
 * SPDX-FileCopyrightText: 2024-2026 Maciej Kujawiński <maciek.kujawinski@gmail.com>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

// Search results: an instant answer card (calculator / unit conversion from KRunner), typo-tolerant
// app tiles (AppIndex), the remaining KRunner matches (files, settings, commands…) and a
// DuckDuckGo search opened in Zen. One flat selection (`sel`) runs across all of them so the
// arrow keys work while the focus stays in the search field.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import org.kde.kitemmodels as KItemModels
import "i18n.js" as I18n

Item {
    id: searchListRoot
    function i18n(k, a1, a2) { return I18n.t(k, a1, a2); }
    width: parent ? parent.width : 0
    height: parent ? parent.height : 0

    property alias viewItem: searchListView
    property var rawModel: null
    property alias model: searchListRoot.rawModel
    property string topResultName: ""

    readonly property string query: (typeof main !== "undefined" && main) ? String(main.searchText || "") : ""
    readonly property bool hasQuery: query.trim().length > 0
    // default web browser (desktop id without ".desktop"), read once; "" = plain xdg-open
    property string browserId: ""

    // ───────── flat selection: [answer] [app tiles] [KRunner rows] [web] ─────────
    property int sel: 0
    property var apps: []                 // AppIndex entries
    property Repeater tileRepeater: null  // app tiles (lives in the list header)
    // hover only selects after a real pointer move, so a still cursor doesn't steal the keyboard
    // selection when results re-flow under it
    property bool mouseActive: false
    function hoverSelect(i) { if (mouseActive) sel = i; }
    HoverHandler {
        property point last: Qt.point(-1, -1)
        onPointChanged: {
            var p = searchListRoot.mapToGlobal(point.position.x, point.position.y);
            if (last.x < 0) { last = p; return; }
            if (Math.abs(p.x - last.x) + Math.abs(p.y - last.y) > 3) { last = p; searchListRoot.mouseActive = true; }
        }
    }
    property var appIdSet: ({})
    property int answerRow: -1            // source row of the calculator / converter match
    property string answerText: ""
    property var answerIcon: ""
    readonly property int answerN: answerRow >= 0 ? 1 : 0
    readonly property int appsN: apps.length
    readonly property int rowsN: searchListView.count
    readonly property int rowsStart: answerN + appsN
    readonly property int footerIdx: rowsStart + rowsN
    readonly property int total: footerIdx + (hasQuery ? 1 : 0)
    readonly property int maxApps: root.fullscreen ? root.columns : Math.min(6, root.columns)

    function moveSel(d) {
        if (!total) return false;
        var n = Math.max(0, Math.min(total - 1, sel + d));
        if (n === sel) return false;
        sel = n;
        ensureVisible();
        return true;
    }
    function ensureVisible() {
        if (sel < rowsStart) searchListView.positionViewAtBeginning();
        else if (sel < footerIdx) searchListView.positionViewAtIndex(sel - rowsStart, ListView.Contain);
        else searchListView.positionViewAtEnd();
    }
    function activateSelection(shift) {
        if (!total) return;
        if (sel < answerN) { copyAnswer(); return; }
        if (sel < rowsStart) {
            var tile = tileRepeater ? tileRepeater.itemAt(sel - answerN) : null;
            if (tile) tile.trigger();
            else { appIndex.launch(apps[sel - answerN].id); root.closeAfterLaunch(); }
            return;
        }
        if (sel < footerIdx) {
            var row = sel - rowsStart;
            var item = searchListView.itemAtIndex(row);
            if (item) {
                if (shift) item.runFirstAction(); else item.runPrimary();
            } else {
                filteredSearchModel.trigger(row, "", null);
                root.closeAnimated();
            }
            return;
        }
        openWeb(query);
    }

    // ───────── clipboard (works without a KRunner round trip) ─────────
    TextEdit { id: clip; visible: false }
    function copyText(t) {
        clip.text = String(t || "");
        clip.selectAll();
        clip.copy();
        clip.text = "";
        root.toast(i18n("Copied: %1", t));
    }
    function copyAnswer() { if (answerText) copyText(answerText); }

    // ───────── web: DuckDuckGo in Zen ─────────
    function isDirectUrl(text) {
        var t = (text || "").trim();
        if (!t) return false;
        if (/^(https?|file):\/\//.test(t) || t.indexOf("localhost") === 0) return true;
        return t.indexOf(" ") < 0 && /^[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)+(:\d+)?(\/.*)?$/.test(t);
    }
    function formatUrl(text) {
        var t = (text || "").trim();
        if (/^(https?|file):\/\//.test(t)) return t;
        return (t.indexOf("localhost") === 0 ? "http://" : "https://") + t;
    }
    function openWeb(text) {
        var t = (text || "").trim();
        if (!t) return;
        var url = isDirectUrl(t) ? formatUrl(t) : "https://duckduckgo.com/?q=" + encodeURIComponent(t);
        appIndex.sh((browserId ? "gtk-launch " + appIndex.shq(browserId) + " " + appIndex.shq(url) + " || " : "") + "xdg-open " + appIndex.shq(url));
        root.closeAnimated();
    }
    // kept for SearchBar compatibility
    function openWebOrUrl(text) { openWeb(text); }

    // ───────── data ─────────
    property string appKey: ""
    function refreshApps() {
        // read the text itself: hasQuery may still hold the previous value inside onQueryChanged
        var q = query.trim();
        var list = q.length ? appIndex.search(q, maxApps) : [];
        var set = {}, ids = [];
        for (var i = 0; i < list.length; i++) { set[list[i].id] = true; ids.push(list[i].id); }
        apps = list;
        var key = ids.join("|");
        if (key !== appKey) {          // only re-filter the KRunner rows when the app set changed
            appKey = key;
            appIdSet = set;
            filteredSearchModel.invalidateFilter();
        }
        updateTopResult();
    }
    function foldGroup(g) { return appIndex.fold(String(g || "")).trim(); }
    function isAnswerGroup(g) {
        var f = foldGroup(g);
        return /^(calcul|kalkul|convers|convert|unit)/.test(f);
    }
    function findAnswer() {
        var m = rawModel, row = -1, text = "", icon = "";
        if (m && hasQuery) {
            var gRole = filteredSearchModel.roleOf("group", 258);
            for (var r = 0; r < m.rowCount() && r < 40; r++) {
                var idx = m.index(r, 0);
                if (isAnswerGroup(m.data(idx, gRole))) {
                    row = r;
                    text = String(m.data(idx, Qt.DisplayRole) || "");
                    icon = m.data(idx, Qt.DecorationRole) || "accessories-calculator";
                    break;
                }
            }
        }
        var changed = row !== answerRow;
        answerRow = row;
        answerText = text;
        answerIcon = icon;
        if (changed) filteredSearchModel.invalidateFilter();
        updateTopResult();
        if (sel >= total) sel = Math.max(0, total - 1);
    }
    Timer { id: answerTimer; interval: 1; onTriggered: searchListRoot.findAnswer() }
    Connections {
        target: searchListRoot.rawModel
        function onModelReset() { answerTimer.restart(); }
        function onRowsInserted() { answerTimer.restart(); }
        function onRowsRemoved() { answerTimer.restart(); }
        function onDataChanged() { answerTimer.restart(); }
        function onLayoutChanged() { answerTimer.restart(); }
    }
    onRawModelChanged: answerTimer.restart()

    function updateTopResult() {
        if (apps.length) { topResultName = apps[0].name; return; }
        if (filteredSearchModel.count > 0) {
            topResultName = String(filteredSearchModel.data(filteredSearchModel.index(0, 0), Qt.DisplayRole) || "");
            return;
        }
        topResultName = "";
    }

    onQueryChanged: {
        sel = 0;
        mouseActive = false;
        refreshApps();
        searchListView.positionViewAtBeginning();
    }
    Connections {
        target: appIndex
        function onRevisionChanged() { searchListRoot.refreshApps(); }
    }
    Component.onCompleted: {
        refreshApps(); findAnswer();
        appIndex.sh("xdg-settings get default-web-browser", function (out) {
            searchListRoot.browserId = String(out).trim().replace(/\.desktop$/, "");
        });
    }

    KItemModels.KSortFilterProxyModel {
        id: filteredSearchModel
        sourceModel: searchListRoot.rawModel

        function roleOf(name, fallback) {
            var r = KItemModels.KRoleNames.role(name);
            return r >= 0 ? r : fallback;
        }
        function trigger(row, actionId, actionArgument) {
            if (!sourceModel) return false;
            var srcIdx = mapToSource(index(row, 0));
            if (srcIdx.row >= 0 && typeof sourceModel.trigger === "function") {
                return sourceModel.trigger(srcIdx.row, actionId || "", actionArgument || null);
            }
            return false;
        }
        // the answer card and the app tiles already show these matches
        filterRowCallback: function (row, parent) {
            if (row === searchListRoot.answerRow) return false;
            if (!searchListRoot.appsN) return true;
            var fav = String(sourceModel.data(sourceModel.index(row, 0, parent), roleOf("favoriteId", 259)) || "");
            return !(fav.length && searchListRoot.appIdSet[appIndex.sid(fav)]);
        }
    }

    component SectionTitle: Text {
        leftPadding: 12
        topPadding: 8
        bottomPadding: 4
        font.family: "Google Sans Flex"
        font.pixelSize: 12
        font.weight: Font.DemiBold
        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.55)
    }

    ListView {
        id: searchListView
        anchors.fill: parent
        anchors.topMargin: 4
        anchors.bottomMargin: 8
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        clip: true
        focus: true
        currentIndex: -1
        model: filteredSearchModel
        boundsBehavior: Flickable.StopAtBounds
        keyNavigationEnabled: false
        highlightMoveDuration: 0
        reuseItems: true             // KRunner resets its model often: recycle the rows
        cacheBuffer: 400
        spacing: 2

        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Up) {
                if (!searchListRoot.moveSel(-1)) main.searchBar.textField.forceActiveFocus();
                event.accepted = true;
            } else if (event.key === Qt.Key_Down) {
                searchListRoot.moveSel(1);
                event.accepted = true;
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                searchListRoot.activateSelection(Boolean(event.modifiers & Qt.ShiftModifier));
                event.accepted = true;
            }
        }

        // ── answer card + app tiles ──
        header: Component {
            Column {
                width: searchListView.width
                spacing: 4
                // keep the top visible while the header fills in (rows start at y = 0)
                onHeightChanged: if (searchListView.contentY <= 0) Qt.callLater(searchListView.positionViewAtBeginning)

                // instant answer (calculator / unit converter)
                Item {
                    id: answerBox
                    width: parent.width
                    height: searchListRoot.answerN ? 96 : 0
                    visible: height > 0
                    readonly property bool selected: searchListRoot.sel === 0 && searchListRoot.answerN > 0

                    Rectangle {
                        id: answerCard
                        anchors.fill: parent
                        anchors.margins: 4
                        radius: answerMa.pressed ? 18 : 28
                        color: Qt.tint(Kirigami.Theme.backgroundColor, Qt.rgba(appIndex.tertiary.r, appIndex.tertiary.g, appIndex.tertiary.b, answerMa.containsMouse ? 0.30 : 0.22))
                        border.width: answerBox.selected ? 2 : 0
                        border.color: appIndex.tertiary
                        Behavior on radius { NumberAnimation { duration: Kirigami.Units.longDuration > 1 ? 240 : 0; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
                        Behavior on color { ColorAnimation { duration: Kirigami.Units.longDuration > 1 ? 140 : 0 } }
                        scale: answerBox.visible ? 1 : 0.9
                        Behavior on scale { NumberAnimation { duration: Kirigami.Units.longDuration > 1 ? 320 : 0; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 20
                            anchors.rightMargin: 16
                            spacing: 16
                            Rectangle {
                                Layout.preferredWidth: 48; Layout.preferredHeight: 48
                                radius: 16
                                color: appIndex.tertiary
                                Kirigami.Icon {
                                    anchors.centerIn: parent
                                    width: 28; height: 28
                                    source: searchListRoot.answerIcon || "accessories-calculator"
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text {
                                    Layout.fillWidth: true
                                    text: searchListRoot.query.trim() + " ="
                                    elide: Text.ElideRight
                                    font.family: "Google Sans Flex"; font.pixelSize: 13
                                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.65)
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: searchListRoot.answerText
                                    elide: Text.ElideRight
                                    font.family: "Google Sans Flex"; font.pixelSize: 30; font.weight: Font.Medium
                                    color: Kirigami.Theme.textColor
                                }
                            }
                            Rectangle {
                                Layout.preferredWidth: copyRow.implicitWidth + 24
                                Layout.preferredHeight: 36
                                radius: 18
                                color: answerBox.selected ? appIndex.tertiary : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08)
                                Behavior on color { ColorAnimation { duration: Kirigami.Units.longDuration > 1 ? 140 : 0 } }
                                Row {
                                    id: copyRow
                                    anchors.centerIn: parent
                                    spacing: 6
                                    Item {
                                        width: 16; height: 16
                                        anchors.verticalCenter: parent.verticalCenter
                                        Image { id: copyImg; anchors.fill: parent; source: Qt.resolvedUrl("icons/action_copy.svg"); sourceSize: Qt.size(32, 32); visible: false }
                                        MultiEffect { anchors.fill: copyImg; source: copyImg; colorization: 1.0
                                            colorizationColor: answerBox.selected ? appIndex.onTertiary : Kirigami.Theme.textColor }
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: searchListRoot.i18n("Copy")
                                        font.family: "Google Sans Flex"; font.pixelSize: 12; font.weight: Font.Medium
                                        color: answerBox.selected ? appIndex.onTertiary : Kirigami.Theme.textColor
                                    }
                                }
                            }
                        }
                        MouseArea {
                            id: answerMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: searchListRoot.hoverSelect(0)
                            onClicked: searchListRoot.copyAnswer()
                        }
                    }
                }

                SectionTitle {
                    visible: searchListRoot.appsN > 0
                    text: searchListRoot.i18n("Apps")
                }
                Row {
                    visible: searchListRoot.appsN > 0
                    anchors.horizontalCenter: root.fullscreen ? parent.horizontalCenter : undefined
                    // a fixed set of tiles whose app changes in place (no delegate re-creation per keystroke)
                    Repeater {
                        id: appRepeater
                        model: searchListRoot.maxApps
                        Component.onCompleted: searchListRoot.tileRepeater = appRepeater
                        delegate: FavoriteItem {
                            required property int index
                            forcedId: index < searchListRoot.apps.length ? searchListRoot.apps[index].id : ""
                            visible: forcedId.length > 0
                            staggerIndex: index
                            forceCurrent: searchListRoot.sel === searchListRoot.answerN + index
                            onIsHoveredChanged: if (isHovered) searchListRoot.hoverSelect(searchListRoot.answerN + index)
                        }
                    }
                }
                SectionTitle {
                    visible: searchListRoot.rowsN > 0 && (searchListRoot.appsN > 0 || searchListRoot.answerN > 0)
                    text: searchListRoot.i18n("More results")
                }
            }
        }

        section.property: "group"
        section.criteria: ViewSection.FullString
        section.delegate: Component {
            Item {
                id: sectionHeader
                required property string section
                width: ListView.view ? ListView.view.width : 0
                height: 28
                QQC2.Label {
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 4
                    text: sectionHeader.section
                    font.family: main.textFont
                    font.pointSize: 9
                    font.weight: Font.DemiBold
                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.45)
                    elide: Text.ElideRight
                }
            }
        }

        delegate: RunnerDelegate {
            listRoot: searchListRoot
        }

        // ── web search (DuckDuckGo in Zen) ──
        footer: Component {
            Item {
                id: footerRoot
                width: ListView.view ? ListView.view.width : 0
                height: searchListRoot.hasQuery ? 54 : 0
                visible: height > 0
                readonly property bool isSelected: searchListRoot.sel === searchListRoot.footerIdx
                readonly property bool direct: searchListRoot.isDirectUrl(searchListRoot.query)

                Rectangle {
                    anchors.fill: parent
                    anchors.leftMargin: 6
                    anchors.rightMargin: 6
                    anchors.topMargin: 6
                    radius: footerMouseArea.pressed ? 14 : 22
                    color: footerRoot.isSelected ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.22)
                                                 : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, footerMouseArea.containsMouse ? 0.10 : 0.05)
                    border.width: footerRoot.isSelected ? 1 : 0
                    border.color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.5)
                    Behavior on color { ColorAnimation { duration: Kirigami.Units.longDuration > 1 ? 100 : 0 } }
                    Behavior on radius { NumberAnimation { duration: Kirigami.Units.longDuration > 1 ? 220 : 0; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 12
                        Kirigami.Icon {
                            Layout.preferredWidth: 26
                            Layout.preferredHeight: 26
                            source: searchListRoot.browserId || "internet-web-browser"
                            fallback: "internet-web-browser"
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            QQC2.Label {
                                Layout.fillWidth: true
                                text: footerRoot.direct ? searchListRoot.i18n("Open website: ") + searchListRoot.formatUrl(searchListRoot.query)
                                                        : searchListRoot.i18n("Search DuckDuckGo for “%1”", searchListRoot.query.trim())
                                font.family: main.textFont
                                font.pointSize: main.textSize + 1
                                font.weight: Font.DemiBold
                                color: footerRoot.isSelected ? Kirigami.Theme.highlightColor : main.textColor
                                elide: Text.ElideRight
                            }
                            QQC2.Label {
                                Layout.fillWidth: true
                                text: footerRoot.direct ? "Zen Browser" : "Zen Browser · DuckDuckGo"
                                font.family: main.textFont
                                font.pointSize: Math.max(8, main.textSize - 1)
                                color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.6)
                                elide: Text.ElideRight
                            }
                        }
                        Rectangle {
                            visible: footerRoot.isSelected
                            radius: 6
                            color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08)
                            implicitWidth: kbd.implicitWidth + 12
                            implicitHeight: kbd.implicitHeight + 6
                            QQC2.Label {
                                id: kbd
                                anchors.centerIn: parent
                                text: "↵"
                                font.pointSize: 9
                                color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.6)
                            }
                        }
                    }
                }
                MouseArea {
                    id: footerMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: searchListRoot.hoverSelect(searchListRoot.footerIdx)
                    onClicked: searchListRoot.openWeb(searchListRoot.query)
                }
            }
        }

        onCountChanged: {
            searchListRoot.updateTopResult();
            if (searchListRoot.sel >= searchListRoot.total) searchListRoot.sel = Math.max(0, searchListRoot.total - 1);
        }
    }
}

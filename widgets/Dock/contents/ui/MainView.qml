/*
 * SPDX-FileCopyrightText: 2024-2026 Maciej Kujawiński <maciek.kujawinski@gmail.com>
 * SPDX-FileCopyrightText: 2022 Friedrich Schriewer <friedrich.schriewer@gmx.net>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import QtQuick
import org.kde.plasma.plasmoid
import QtQuick.Layouts
import QtQuick.Controls
import org.kde.kirigami as Kirigami

Item {
  id: main
  property bool searching: (searchBar.textField.text != "")
  // typed text, immediately (KRunner gets it debounced, see SearchBar)
  readonly property string searchText: searchBar.textField.text

  readonly property var plasmoidConfig: (typeof root !== "undefined" && root && root.plasmoidConfiguration) ? root.plasmoidConfiguration : (typeof Plasmoid !== "undefined" ? Plasmoid.configuration : null)
  readonly property bool usePlasmaTheme: Boolean(!plasmoidConfig || plasmoidConfig.usePlasmaTheme !== false)

  readonly property color baseBgColor: Kirigami.Theme.backgroundColor
  readonly property color currentBgColor: Qt.rgba(baseBgColor.r, baseBgColor.g, baseBgColor.b, 0.85)
  readonly property bool isDarkTheme: Kirigami.Theme.textColor.r > 0.5 || Kirigami.Theme.textColor.g > 0.5 || Kirigami.Theme.textColor.b > 0.5
  readonly property color textColor: Kirigami.Theme.textColor
  readonly property string textFont: (usePlasmaTheme || (plasmoidConfig && plasmoidConfig.useSystemFontSettings)) ? (Kirigami.Theme.defaultFont.family || Kirigami.Theme.defaultFont) : ((plasmoidConfig && plasmoidConfig.fontFamily) || "Google Sans Flex")
  readonly property real textSize: (usePlasmaTheme || (plasmoidConfig && plasmoidConfig.useSystemFontSettings)) ? (Kirigami.Theme.defaultFont.pointSize || 10) : ((plasmoidConfig && plasmoidConfig.fontSize) || 11)
  readonly property color bgColor: currentBgColor

  property color contrastBgColor: isDarkTheme ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.06)

  property alias searchBar: searchBar
  property alias bottomBar: bottomBar
  readonly property Item stackItem: stack.currentItem
  property int itemSpacing: 6

  function reset(){
    if (searchBar.textField.text !== "") {
      searchBar.textField.clear();
    }
    searchBar.textField.forceActiveFocus();
    if (appsPage.viewItem) appsPage.viewItem.positionViewAtBeginning();
  }

  function setQuery(queryText) {
    var q = queryText || "";
    searchBar.textField.text = q;
    searchBar.textField.cursorPosition = q.length;
    searchBar.textField.forceActiveFocus(Qt.ShortcutFocusReason);
  }

  function findAppByNamePrefix(prefix) {
    var res = appIndex.search(prefix, 1);
    return res.length && res[0].key.indexOf(appIndex.fold(prefix).trim()) === 0 ? res[0].name : "";
  }

  // Tab / Shift+Tab: search -> apps -> bottom bar
  function focusZone(dir) {
    var zones = [searchBar.textField];
    if (stack.currentItem && stack.currentItem.viewItem) zones.push(stack.currentItem.viewItem);
    zones.push(bottomBar);
    var cur = 0;
    for (var i = 0; i < zones.length; i++) if (zones[i].activeFocus) cur = i;
    var next = zones[(cur + dir + zones.length) % zones.length];
    if (next === bottomBar) bottomBar.focusFirst();
    else next.forceActiveFocus(dir > 0 ? Qt.TabFocusReason : Qt.BacktabFocusReason);
  }

  function launchPinned(n) {
    var fav = kicker.globalFavorites;
    if (fav && n < fav.count) {
      fav.trigger(n, "", null);
      root.closeAfterLaunch();
    }
  }

  Keys.onPressed: event => {
    var ctrl = event.modifiers & Qt.ControlModifier;
    if (ctrl && event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
      launchPinned(event.key - Qt.Key_1);
      event.accepted = true;
    } else if (ctrl && event.key === Qt.Key_E) {
      root.editMode = !root.editMode;
      event.accepted = true;
    } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      focusZone(event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier) ? -1 : 1);
      event.accepted = true;
    } else if (event.key === Qt.Key_Escape) {
      if (!root.handleEscape()) root.closeAnimated();
      event.accepted = true;
    }
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: itemSpacing

    SearchBar {
      id: searchBar
      Layout.fillWidth: !root.fullscreen
      Layout.preferredWidth: root.fullscreen ? Math.min(720, main.width) : -1
      Layout.preferredHeight: 50
      Layout.maximumHeight: Layout.preferredHeight
      Layout.alignment: Qt.AlignTop | Qt.AlignHCenter
      Layout.topMargin: root.fullscreen ? 8 : 4
      Layout.bottomMargin: 2
      Keys.priority: Keys.AfterItem
      Keys.forwardTo: stack.currentItem ? stack.currentItem.viewItem : null
    }

    // Both pages stay alive: switching between apps and results no longer rebuilds the whole
    // app grid (or the results list) on the first / last keystroke.
    Item {
      id: stack
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.minimumHeight: 100
      readonly property Item currentItem: main.searching ? searchLoader.item : appsPage
      Keys.priority: Keys.AfterItem
      Keys.forwardTo: searchBar.textField

      CombinedAppsView {
        id: appsPage
        visible: !main.searching
      }
      Loader {
        id: searchLoader
        anchors.fill: parent
        active: true             // built once in the background at startup, then kept
        asynchronous: true
        visible: main.searching
        sourceComponent: RunnerList {
          model: runnerModel.count ? runnerModel.modelForRow(0) : null
        }
      }
      NumberAnimation { id: pageFade; property: "opacity"; from: 0.35; to: 1; duration: Kirigami.Units.longDuration > 1 ? 110 : 0; easing.type: Easing.OutCubic }
    }

    SessionBar {
      id: bottomBar
      Layout.fillWidth: true
      Layout.preferredHeight: 52
    }
  }

  onSearchingChanged: {
    if (typeof root !== "undefined" && root && root.launcherContextMenu && root.launcherContextMenu.visible) {
      root.launcherContextMenu.close();
    }
    if (searching) searchLoader.active = true;
    pageFade.target = searching ? searchLoader : appsPage;
    pageFade.restart();
  }
}

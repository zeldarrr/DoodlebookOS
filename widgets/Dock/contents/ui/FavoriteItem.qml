/*
 * SPDX-FileCopyrightText: 2024-2026 Maciej Kujawiński <maciek.kujawinski@gmail.com>
 * SPDX-FileCopyrightText: 2022 Friedrich Schriewer <friedrich.schriewer@gmx.net>
 * SPDX-FileCopyrightText: 2021 Prateek SU <pankajsunal123@gmail.com>
 * SPDX-FileCopyrightText: 2015 Eike Hein <hein@kde.org>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

// Launcher app tile (grid, pinned row, folders, search results).
// M3 Expressive motion: staggered entrance, spring hover, squish on press, zoom-out on launch,
// wiggle in edit mode; badges for new apps and notifications; drop target for folders/pinning.
import QtQuick
import QtQuick.Effects
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami
import "i18n.js" as I18n

Item {
  id: favItem
  function i18n(k, a1, a2) { return I18n.t(k, a1, a2); }

  // data: either a Kicker model row (tileModel/tileIndex) or a bare app id
  property var tileModel: null
  property int tileIndex: -1
  property var triggerModel: null
  property string forcedId: ""
  property bool isHiddenApp: false
  property bool isPinned: false          // row of the launcher favourites
  property string folderId: ""           // shown inside a folder
  property bool forceCurrent: false
  property int staggerIndex: tileIndex

  readonly property string appId: forcedId.length ? appIndex.sid(forcedId)
                                  : (tileModel && tileModel.favoriteId ? appIndex.sid(tileModel.favoriteId) : "")
  readonly property var iconSource: { var r = appIndex.revision; if (appIndex.iconsBlank) return ""; var t = appIndex.themedIconFor(appId); return t.length ? t : (tileModel ? tileModel.decoration : appIndex.iconFor(appId)); }
  readonly property string appNameStr: {
    if (tileModel) return tileModel.display ? String(tileModel.display) : "";
    var r = appIndex.revision;
    return appIndex.nameFor(appId);
  }
  readonly property string launcherUrlStr: appId.length ? "applications:" + appId
                                           : (tileModel && tileModel.url ? String(tileModel.url) : "")
  property var url: tileModel && tileModel.url ? tileModel.url : ""

  readonly property bool isPinnedToDock: {
    if (!favItem.appId || typeof kicker === "undefined" || !kicker.tasksModel || !kicker.tasksModel.launcherList) return false;
    var list = kicker.tasksModel.launcherList;
    for (var i = 0; i < list.length; ++i) {
      var u = (list[i] || "").toString();
      if (appIndex.sid(u) === favItem.appId) return true;
    }
    return false;
  }
  readonly property bool isNewApp: tileModel ? tileModel.isNewlyInstalled === true : appIndex.isNew(appId)
  readonly property int badgeCount: { var b = appIndex.badges; return appIndex.badgeFor(appId); }

  width: root.cellSizeWidth
  height: root.cellSizeHeight

  property Item dragIconItem: appicon
  z: Drag.active ? 4 : (dropArea.zone.length ? 3 : 1)

  // ───────────── actions ─────────────
  function triggerAction(actionId, arg) {
    if (triggerModel && tileIndex >= 0) return triggerModel.trigger(tileIndex, actionId || "", arg === undefined ? null : arg);
    return appIndex.trigger(appId, actionId, arg);
  }

  function trigger() {
    if (root.editMode) { nudge.restart(); return; }
    triggerAction("", null);
    launchAnim.restart();
    root.closeAfterLaunch();
  }

  function openActionMenu(visualParent, x, y) {
    if (typeof root === "undefined" || !root || !root.launcherContextMenu) return;
    root.launcherContextMenu.open(visualParent, Qt.point(x, y), {
      appId: favItem.appId,
      appName: favItem.appNameStr,
      icon: favItem.iconSource,
      launcherUrlStr: favItem.launcherUrlStr,
      isPinnedToDock: favItem.isPinnedToDock,
      isHidden: favItem.isHiddenApp,
      isPinned: favItem.isPinned || (kicker.globalFavorites && kicker.globalFavorites.isFavorite(favItem.launcherUrlStr)),
      pinnedIndex: favItem.isPinned ? favItem.tileIndex : -1,
      folderId: favItem.folderId,
      isNew: favItem.isNewApp,
      actions: (favItem.tileModel && favItem.tileModel.actionList) ? favItem.tileModel.actionList : appIndex.actionsFor(favItem.appId),
      trigger: function(actionId, arg) { return favItem.triggerAction(actionId, arg); }
    });
  }

  function performDrag(handler) {
    if (!handler.active) {
      kicker.dragSource.Drag.active = false;
      kicker.dragSource.Drag.imageSource = "";
      kicker.dragSource.sourceItem = null;
      kicker.dragSource.sourceId = "";
      kicker.dragSource.sourceFolder = "";
      kicker.dragSource.sourcePinned = -1;
      return;
    }
    favItem.dragIconItem.grabToImage(result => {
      if (!handler.active) return;
      kicker.dragSource.sourceItem = favItem;
      kicker.dragSource.sourceId = favItem.appId;
      kicker.dragSource.sourceFolder = favItem.folderId;
      kicker.dragSource.sourcePinned = favItem.isPinned ? favItem.tileIndex : -1;
      kicker.dragSource.Drag.imageSource = result.url;
      kicker.dragSource.Drag.mimeData = { "text/uri-list": [favItem.launcherUrlStr || favItem.url] };
      kicker.dragSource.Drag.active = handler.active;
    });
  }

  // ───────────── state ─────────────
  readonly property bool isCurrent: {
    if (forceCurrent) return true;
    var isCurr = (typeof GridView.isCurrentItem !== "undefined") && Boolean(GridView.isCurrentItem);
    var isKbd = (typeof GridView.view !== "undefined") && GridView.view && Boolean(GridView.view.movedWithKeyboard) && GridView.view.activeFocus;
    return isCurr && isKbd;
  }
  readonly property bool isHovered: ma.containsMouse
  readonly property color accent: Kirigami.Theme.highlightColor
  readonly property color fg: Kirigami.Theme.textColor

  // (no per-tile entrance wave: the whole page fades in once, see LauncherPopup)
  Connections {
    target: root
    function onVisibleChanged() { if (!root.visible) { launchAnim.stop(); favItem.launchT = 0; } }
  }

  // launch: icon zooms out and fades while the popup closes
  property real launchT: 0
  NumberAnimation { id: launchAnim; target: favItem; property: "launchT"; from: 0; to: 1; duration: 220; easing.type: Easing.OutCubic }

  // refusal nudge (click in edit mode)
  SequentialAnimation {
    id: nudge
    NumberAnimation { target: appicon; property: "rotation"; to: 6; duration: 50 }
    NumberAnimation { target: appicon; property: "rotation"; to: -6; duration: 80 }
    NumberAnimation { target: appicon; property: "rotation"; to: 0; duration: 120; easing.type: Easing.OutBack }
  }

  // ───────────── visuals ─────────────
  // state layer: circle on hover that morphs into a squircle when pressed / focused / drop target
  Rectangle {
    id: stateLayer
    readonly property bool dropCenter: dropArea.zone === "center"
    anchors.horizontalCenter: appicon.horizontalCenter
    anchors.verticalCenter: appicon.verticalCenter
    width: root.iconSize + (dropCenter ? 26 : 16)
    height: width
    radius: ma.pressed ? width * 0.28 : ((favItem.isCurrent || dropCenter) ? width * 0.32 : width / 2)
    color: dropCenter ? Qt.rgba(favItem.accent.r, favItem.accent.g, favItem.accent.b, 0.30)
         : favItem.isCurrent ? Qt.rgba(favItem.accent.r, favItem.accent.g, favItem.accent.b, 0.26)
         : Qt.rgba(favItem.fg.r, favItem.fg.g, favItem.fg.b, ma.pressed ? 0.16 : 0.09)
    border.width: (favItem.isCurrent || dropCenter) ? 1.5 : 0
    border.color: favItem.accent
    opacity: (favItem.isHovered || favItem.isCurrent || ma.pressed || dropCenter) ? 1 : 0
    scale: opacity > 0 ? 1 : 0.7
    Behavior on opacity { NumberAnimation { duration: 140 } }
    Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
    Behavior on radius { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
    Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
  }

  // pinned reordering: insertion bar on the left/right edge
  Rectangle {
    visible: dropArea.zone === "before" || dropArea.zone === "after"
    width: 4; radius: 2
    height: root.iconSize
    y: appicon.y
    x: dropArea.zone === "before" ? 0 : parent.width - width
    color: favItem.accent
  }

  Item {
    id: appicon
    anchors.top: parent.top
    anchors.topMargin: Kirigami.Units.smallSpacing * 2
    anchors.horizontalCenter: parent.horizontalCenter
    width: root.iconSize
    height: width

    readonly property real hoverScale: ma.pressed ? 0.88 : (favItem.isHovered ? 1.08 : 1.0)
    scale: hoverScale * (1 + 0.32 * favItem.launchT)
    opacity: 1 - favItem.launchT
    transformOrigin: Item.Center
    Behavior on scale { enabled: !launchAnim.running; NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2.0 } }

    // edit-mode wiggle
    SequentialAnimation on rotation {
      running: root.editMode && favItem.visible && favItem.appId.length > 0
      loops: Animation.Infinite
      PauseAnimation { duration: (Math.max(0, favItem.tileIndex) % 4) * 45 }
      NumberAnimation { to: 2.2; duration: 140; easing.type: Easing.InOutSine }
      NumberAnimation { to: -2.2; duration: 140; easing.type: Easing.InOutSine }
      onStopped: appicon.rotation = 0
    }

    Kirigami.Icon {
      id: rawIcon
      anchors.fill: parent
      roundToIconSize: false
      source: favItem.iconSource
      layer.enabled: Plasmoid.configuration.themedIcons === true
      layer.effect: MultiEffect { colorization: 1.0; colorizationColor: Kirigami.Theme.highlightColor }
    }

    // notification count (top-right)
    Rectangle {
      visible: favItem.badgeCount > 0
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.rightMargin: -6
      anchors.topMargin: -4
      height: 20
      width: Math.max(20, countText.implicitWidth + 10)
      radius: 10
      color: favItem.accent
      border.width: 2
      border.color: Kirigami.Theme.backgroundColor
      scale: visible ? 1 : 0
      Behavior on scale { NumberAnimation { duration: 280; easing.type: Easing.OutBack; easing.overshoot: 2 } }
      Text {
        id: countText
        anchors.centerIn: parent
        text: favItem.badgeCount > 99 ? "99+" : favItem.badgeCount
        font.family: "Google Sans Flex"; font.pixelSize: 11; font.weight: Font.Bold
        color: (0.299 * favItem.accent.r + 0.587 * favItem.accent.g + 0.114 * favItem.accent.b) > 0.62 ? "#1d1a2c" : "white"
      }
    }
    // newly installed (top-left, tertiary dot)
    Rectangle {
      visible: favItem.isNewApp && favItem.badgeCount === 0
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.leftMargin: -3
      anchors.topMargin: -3
      width: 12; height: 12; radius: 6
      color: appIndex.tertiary
      border.width: 2
      border.color: Kirigami.Theme.backgroundColor
    }

    // edit mode: remove / hide badge (top-left)
    Rectangle {
      id: editBadge
      readonly property bool show: root.editMode && favItem.appId.length > 0
      visible: scale > 0.01
      scale: show ? 1 : 0
      Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 2 } }
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.leftMargin: -8
      anchors.topMargin: -8
      width: 22; height: 22; radius: 11
      color: Kirigami.Theme.backgroundColor
      border.width: 1
      border.color: Qt.rgba(favItem.fg.r, favItem.fg.g, favItem.fg.b, 0.25)
      Image { id: badgeImg; anchors.centerIn: parent; width: 14; height: 14; sourceSize: Qt.size(28, 28); visible: false
        source: Qt.resolvedUrl(favItem.isHiddenApp ? "icons/add.svg" : (favItem.isPinned ? "icons/keep_off.svg" : (favItem.folderId.length ? "icons/remove.svg" : "icons/visibility_off.svg"))) }
      MultiEffect { anchors.fill: badgeImg; source: badgeImg; colorization: 1.0; colorizationColor: favItem.fg }
      MouseArea {
        anchors.fill: parent
        anchors.margins: -4
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          if (favItem.isHiddenApp) {
            if (typeof combinedRoot !== "undefined" && combinedRoot) combinedRoot.unhideApp(favItem.appId, favItem.appNameStr);
          } else if (favItem.isPinned) {
            kicker.globalFavorites.removeFavorite(favItem.launcherUrlStr);
          } else if (favItem.folderId.length) {
            appIndex.removeFromFolder(favItem.folderId, favItem.appId);
          } else if (typeof combinedRoot !== "undefined" && combinedRoot) {
            combinedRoot.hideApp(favItem.appId, favItem.appNameStr);
            root.toast(favItem.i18n("%1 hidden", favItem.appNameStr));
          }
        }
      }
    }
  }

  PlasmaComponents.Label {
    id: appname
    text: favItem.appNameStr
    font.family: "Google Sans Flex"
    font.pixelSize: root.fullscreen ? 12 : 11
    font.weight: Font.Medium
    color: favItem.isCurrent ? favItem.accent : main.textColor
    anchors {
      top: appicon.bottom
      left: parent.left
      right: parent.right
      topMargin: Kirigami.Units.smallSpacing + 4
      leftMargin: Kirigami.Units.smallSpacing
      rightMargin: Kirigami.Units.smallSpacing
    }
    textFormat: Text.PlainText
    elide: Text.ElideRight
    horizontalAlignment: Text.AlignHCenter
    maximumLineCount: 2
    wrapMode: Text.Wrap
    lineHeight: 0.92
  }

  QQC2.ToolTip {
    visible: favItem.isHovered && appname.truncated && !ma.pressed
    delay: 500
    text: favItem.appNameStr
  }

  MouseArea {
    id: ma
    anchors.fill: parent
    z: parent.z + 1
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: (mouse) => {
      if (mouse.button === Qt.RightButton) {
        favItem.openActionMenu(favItem, mouse.x, mouse.y);
      } else {
        favItem.trigger();
      }
    }
    onEntered: {
      var currentView = favItem.GridView.view;
      if (currentView && currentView.movedWithKeyboard) return;
      if (currentView && !currentView.activeFocus) currentView.forceActiveFocus(Qt.MouseFocusReason);
    }
  }

  DragHandler {
    id: dragHandler
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus
    enabled: favItem.dragIconItem !== null && favItem.appId.length > 0
    target: null
    onActiveChanged: favItem.performDrag(this)
  }

  // drop another app here: centre = make a folder, edges of a pinned tile = reorder
  DropArea {
    id: dropArea
    anchors.fill: parent
    enabled: favItem.appId.length > 0 && !favItem.isHiddenApp && favItem.folderId.length === 0
    property string zone: ""
    function zoneAt(x) {
      var src = kicker.dragSource.sourceId;
      if (!src || src === favItem.appId) return "";
      var fx = x / width;
      if (favItem.isPinned && fx < 0.24) return "before";
      if (favItem.isPinned && fx > 0.76) return "after";
      return "center";
    }
    onEntered: (drag) => { zone = zoneAt(drag.x); }
    onPositionChanged: (drag) => { zone = zoneAt(drag.x); }
    onExited: zone = ""
    onDropped: (drop) => {
      var z = zone;
      zone = "";
      var src = kicker.dragSource.sourceId;
      if (!z || !src) return;
      drop.accept();
      var fav = kicker.globalFavorites;
      var srcPinned = kicker.dragSource.sourcePinned;
      if (z === "center") {
        if (favItem.isPinned) fav.removeFavorite(favItem.launcherUrlStr);
        if (srcPinned >= 0) fav.removeFavorite("applications:" + src);
        appIndex.createFolder(favItem.appId, src);
        root.toast(favItem.i18n("Folder created"));
      } else {
        var target = favItem.tileIndex + (z === "after" ? 1 : 0);
        if (srcPinned >= 0) {
          if (srcPinned < target) target--;
          if (srcPinned !== target) fav.moveRow(srcPinned, target);
        } else {
          fav.addFavorite("applications:" + src, target);
        }
      }
    }
  }
}

/*
    SPDX-FileCopyrightText: 2026 Maciej Kujawiński <maciek.kujawinski@gmail.com>
    SPDX-License-Identifier: GPL-3.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import "../metrics" as LocalMetrics

PlasmaExtras.Representation {
    id: menuPopupRoot

    required property var appletRoot
    required property var trayBackend

    property var currentItemData: null
    readonly property string itemKey: currentItemData ? String(currentItemData.key || "") : ""
    property var menuItems: []
    property bool isLoading: false
    property int _requestToken: 0

    function openForItem(itemData) {
        currentItemData = itemData;
        menuItems = [];
        menuList.resetStack();
        isLoading = true;
        _requestToken += 1;
        var token = _requestToken;
        trayBackend.loadMenu(itemKey, function(res) {
            if (token !== menuPopupRoot._requestToken) {
                return;
            }
            menuPopupRoot.isLoading = false;
            menuPopupRoot.menuItems = (res && Array.isArray(res.items)) ? res.items : [];
        });
    }

    readonly property real dpr: LocalMetrics.Metrics.dpr
    function snap(val) {
        return LocalMetrics.Metrics.snap(val);
    }
    function legacyDp(val) {
        return LocalMetrics.Metrics.legacyDp(val);
    }

    readonly property real availableScreenH: (typeof Screen !== "undefined" && Screen.desktopAvailableHeight > 0)
        ? Screen.desktopAvailableHeight
        : ((typeof Screen !== "undefined" && Screen.height > 0) ? Screen.height : 1080)
    readonly property real maxPopupHeight: Math.min(legacyDp(520.0), Math.max(legacyDp(120.0), availableScreenH - legacyDp(68.0)))

    Layout.preferredWidth: legacyDp(224.0)
    Layout.minimumWidth: Layout.preferredWidth
    Layout.maximumWidth: Layout.preferredWidth

    readonly property real desiredHeight: legacyDp(16.0) + headerRow.height + headerDivider.height + legacyDp(12.0) + contentBody.implicitHeight
    Layout.minimumHeight: legacyDp(96.0)
    Layout.preferredHeight: Math.min(maxPopupHeight, Math.max(legacyDp(96.0), desiredHeight))
    Layout.maximumHeight: maxPopupHeight

    implicitWidth: Layout.preferredWidth
    implicitHeight: Layout.preferredHeight
    width: Layout.preferredWidth
    height: Layout.preferredHeight

    header: null
    footer: null

    Binding {
        when: Boolean(menuPopupRoot.Window && menuPopupRoot.Window.window !== null && menuPopupRoot.Window.window.hasOwnProperty("margin"))
        target: menuPopupRoot.Window ? menuPopupRoot.Window.window : null
        property: "margin"
        value: 1
    }

    Connections {
        target: menuPopupRoot.Window ? menuPopupRoot.Window.window : null
        function onVisibleChanged() {
            var win = menuPopupRoot.Window ? menuPopupRoot.Window.window : null;
            if (win && win.visible) {
                Qt.callLater(() => {
                    if (!win || !win.visible || !win.screen) return;
                    var rightEdge = win.screen.geometry.x + win.screen.geometry.width;
                    var offset = 8;
                    if ((win.x + win.width) > (rightEdge - offset)) {
                        win.x = rightEdge - win.width - offset;
                    }
                });
            }
        }
    }

    contentItem: ColumnLayout {
        id: rootCol
        anchors.fill: parent
        anchors.margins: menuPopupRoot.legacyDp(8.0)
        spacing: menuPopupRoot.legacyDp(6.0)

        // Header with app icon, title and optional Activate button
        RowLayout {
            id: headerRow
            Layout.fillWidth: true
            Layout.preferredHeight: menuPopupRoot.legacyDp(28.8)
            spacing: menuPopupRoot.legacyDp(8.0)

            Item {
                Layout.preferredWidth: menuPopupRoot.legacyDp(16.0)
                Layout.preferredHeight: menuPopupRoot.legacyDp(16.0)
                Layout.leftMargin: menuPopupRoot.legacyDp(6.4)
                Layout.alignment: Qt.AlignVCenter

                Image {
                    id: headerImg
                    anchors.fill: parent
                    visible: Boolean(menuPopupRoot.currentItemData && menuPopupRoot.currentItemData.iconPath) && status === Image.Ready
                    source: (menuPopupRoot.currentItemData && menuPopupRoot.currentItemData.iconPath) ? menuPopupRoot.currentItemData.iconPath : ""
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: true
                }

                Kirigami.Icon {
                    anchors.fill: parent
                    visible: !headerImg.visible
                    isMask: false
                    source: (menuPopupRoot.currentItemData && menuPopupRoot.currentItemData.iconName)
                        ? menuPopupRoot.currentItemData.iconName
                        : "application-x-executable"
                }
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                text: menuPopupRoot.currentItemData ? String(menuPopupRoot.currentItemData.displayTitle || "") : ""
                font.family: "Google Sans Flex"
                font.pixelSize: menuPopupRoot.legacyDp(12.0)
                font.weight: Font.DemiBold
                color: Kirigami.Theme.textColor
                maximumLineCount: 1
                elide: Text.ElideRight
            }

            Rectangle {
                visible: Boolean(menuPopupRoot.currentItemData && !menuPopupRoot.currentItemData.itemIsMenu)
                Layout.preferredHeight: menuPopupRoot.legacyDp(22.4)
                Layout.preferredWidth: openLabel.implicitWidth + menuPopupRoot.legacyDp(14.4)
                Layout.rightMargin: menuPopupRoot.legacyDp(4.0)
                Layout.alignment: Qt.AlignVCenter
                radius: height / 2
                color: openBtnMouse.pressed
                    ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.16)
                    : (openBtnMouse.containsMouse
                        ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.10)
                        : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.05))

                PlasmaComponents3.Label {
                    id: openLabel
                    anchors.centerIn: parent
                    text: "Otwórz"
                    font.family: "Google Sans Flex"
                    font.pixelSize: menuPopupRoot.legacyDp(9.6)
                    font.weight: Font.Medium
                    color: Kirigami.Theme.textColor
                }

                MouseArea {
                    id: openBtnMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        if (!menuPopupRoot.currentItemData) return;
                        var pt = menuPopupRoot.mapToGlobal(0, 0);
                        menuPopupRoot.trayBackend.activateItem(menuPopupRoot.itemKey, pt.x, pt.y);
                        menuPopupRoot.appletRoot.closeAllPopups();
                    }
                }
            }
        }

        Rectangle {
            id: headerDivider
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)
        }

        QQC2.ScrollView {
            id: scrollArea
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: availableWidth

            Item {
                id: contentBody
                width: scrollArea.availableWidth
                implicitHeight: Math.max(menuPopupRoot.legacyDp(32.0), menuList.visible ? menuList.implicitHeight : emptyState.implicitHeight)

                TrayMenuList {
                    id: menuList
                    width: parent.width
                    visible: !menuPopupRoot.isLoading && menuPopupRoot.menuItems.length > 0
                    appletRoot: menuPopupRoot.appletRoot
                    trayBackend: menuPopupRoot.trayBackend
                    itemKey: menuPopupRoot.itemKey
                    rootItems: menuPopupRoot.menuItems

                    onMenuItemActivated: _menuId => {
                        menuPopupRoot.appletRoot.closeAllPopups();
                    }
                }

                PlasmaComponents3.Label {
                    id: emptyState
                    anchors.centerIn: parent
                    visible: !menuList.visible
                    text: menuPopupRoot.isLoading ? "Ładowanie menu…" : "Brak pozycji menu"
                    font.family: "Google Sans Flex"
                    font.pixelSize: menuPopupRoot.legacyDp(10.4)
                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.6)
                }
            }
        }
    }
}

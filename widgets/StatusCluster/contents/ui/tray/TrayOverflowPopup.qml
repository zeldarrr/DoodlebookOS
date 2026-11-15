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
    id: overflowRoot

    required property var appletRoot
    required property var trayBackend

    property var activeMenuItemData: null
    property var activeMenuItems: []
    property bool isMenuLoading: false
    property int _menuReqToken: 0

    readonly property bool inMenuMode: activeMenuItemData !== null

    function resetView() {
        activeMenuItemData = null;
        activeMenuItems = [];
        isMenuLoading = false;
        embeddedMenuList.resetStack();
    }

    function openItemMenu(itemData) {
        if (!itemData) {
            return;
        }
        activeMenuItemData = itemData;
        activeMenuItems = [];
        isMenuLoading = true;
        embeddedMenuList.resetStack();
        _menuReqToken += 1;
        var token = _menuReqToken;
        trayBackend.loadMenu(itemData.key, function(res) {
            if (token !== overflowRoot._menuReqToken) {
                return;
            }
            overflowRoot.isMenuLoading = false;
            overflowRoot.activeMenuItems = (res && Array.isArray(res.items)) ? res.items : [];
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
    readonly property real maxPopupHeight: Math.min(legacyDp(520.0), Math.max(legacyDp(140.0), availableScreenH - legacyDp(68.0)))

    Layout.preferredWidth: legacyDp(260.0)
    Layout.minimumWidth: Layout.preferredWidth
    Layout.maximumWidth: Layout.preferredWidth

    readonly property real bodyContentH: inMenuMode
        ? (embeddedMenuList.visible ? embeddedMenuList.implicitHeight : legacyDp(40.0))
        : (appsListCol.implicitHeight > 0 ? appsListCol.implicitHeight : legacyDp(40.0))
    readonly property real desiredHeight: legacyDp(16.0) + headerRow.height + headerDivider.height + legacyDp(12.0) + bodyContentH

    Layout.minimumHeight: legacyDp(112.0)
    Layout.preferredHeight: Math.min(maxPopupHeight, Math.max(legacyDp(112.0), desiredHeight))
    Layout.maximumHeight: maxPopupHeight

    implicitWidth: Layout.preferredWidth
    implicitHeight: Layout.preferredHeight
    width: Layout.preferredWidth
    height: Layout.preferredHeight

    header: null
    footer: null

    Binding {
        when: Boolean(overflowRoot.Window && overflowRoot.Window.window !== null && overflowRoot.Window.window.hasOwnProperty("margin"))
        target: overflowRoot.Window ? overflowRoot.Window.window : null
        property: "margin"
        value: 1
    }

    Connections {
        target: overflowRoot.Window ? overflowRoot.Window.window : null
        function onVisibleChanged() {
            var win = overflowRoot.Window ? overflowRoot.Window.window : null;
            if (win && win.visible) {
                overflowRoot.resetView();
                Qt.callLater(() => {
                    if (!win || !win.visible || !win.screen) return;
                    var rightEdge = win.screen.geometry.x + win.screen.geometry.width;
                    var offset = 8;
                    if ((win.x + win.width) > (rightEdge - offset)) {
                        win.x = rightEdge - win.width - offset;
                    }
                });
            } else {
                if (overflowRoot.inMenuMode && overflowRoot.activeMenuItemData) {
                    overflowRoot.trayBackend.notifyMenuClosed(overflowRoot.activeMenuItemData.key);
                }
                overflowRoot.resetView();
            }
        }
    }

    Connections {
        target: overflowRoot.trayBackend
        function onOverflowItemsChanged() {
            if (!overflowRoot.trayBackend.hasOverflow && overflowRoot.Window && overflowRoot.Window.window && overflowRoot.Window.window.visible) {
                overflowRoot.appletRoot.closeAllPopups();
            }
        }
    }

    contentItem: ColumnLayout {
        anchors.fill: parent
        anchors.margins: overflowRoot.legacyDp(8.0)
        spacing: overflowRoot.legacyDp(6.0)

        // Header
        RowLayout {
            id: headerRow
            Layout.fillWidth: true
            Layout.preferredHeight: overflowRoot.legacyDp(28.8)
            spacing: overflowRoot.legacyDp(8.0)

            Rectangle {
                visible: overflowRoot.inMenuMode
                Layout.preferredWidth: overflowRoot.legacyDp(25.6)
                Layout.preferredHeight: overflowRoot.legacyDp(25.6)
                Layout.alignment: Qt.AlignVCenter
                radius: overflowRoot.legacyDp(8.0)
                color: backBtnMouse.pressed
                    ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.16)
                    : (backBtnMouse.containsMouse ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08) : "transparent")

                Kirigami.Icon {
                    anchors.centerIn: parent
                    width: overflowRoot.legacyDp(16.0)
                    height: width
                    source: "go-previous-symbolic"
                    isMask: true
                    color: Kirigami.Theme.textColor
                }

                MouseArea {
                    id: backBtnMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        if (overflowRoot.activeMenuItemData) {
                            overflowRoot.trayBackend.notifyMenuClosed(overflowRoot.activeMenuItemData.key);
                        }
                        overflowRoot.resetView();
                    }
                }
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                Layout.leftMargin: overflowRoot.inMenuMode ? 0 : overflowRoot.legacyDp(6.4)
                Layout.alignment: Qt.AlignVCenter
                text: overflowRoot.inMenuMode
                    ? String(overflowRoot.activeMenuItemData.displayTitle || "")
                    : "Ukryte aplikacje"
                font.family: "Google Sans Flex"
                font.pixelSize: overflowRoot.legacyDp(12.0)
                font.weight: Font.DemiBold
                color: Kirigami.Theme.textColor
                elide: Text.ElideRight
            }
        }

        Rectangle {
            id: headerDivider
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)
        }

        QQC2.ScrollView {
            id: overflowScroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: availableWidth

            Item {
                width: overflowScroll.availableWidth
                implicitHeight: overflowRoot.bodyContentH

                // 1. Overflow Apps List
                ColumnLayout {
                    id: appsListCol
                    width: parent.width
                    visible: !overflowRoot.inMenuMode
                    spacing: overflowRoot.legacyDp(3.2)

                    Repeater {
                        model: overflowRoot.trayBackend.overflowItems

                        delegate: Rectangle {
                            id: appRow
                            required property var modelData

                            Layout.fillWidth: true
                            Layout.preferredHeight: overflowRoot.legacyDp(38.4)
                            radius: overflowRoot.legacyDp(12.0)
                            color: rowClickArea.pressed
                                ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
                                : ((rowClickArea.containsMouse || menuArrowMouse.containsMouse)
                                    ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08)
                                    : "transparent")

                            MouseArea {
                                id: rowClickArea
                                anchors.fill: parent
                                z: 0
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                onClicked: mouse => {
                                    if (!appRow.modelData) return;
                                    var globalPt = appRow.mapToGlobal(mouse.x, mouse.y);
                                    if (mouse.button === Qt.MiddleButton) {
                                        overflowRoot.trayBackend.secondaryActivateItem(appRow.modelData.key, globalPt.x, globalPt.y);
                                    } else if (mouse.button === Qt.RightButton || appRow.modelData.itemIsMenu) {
                                        if (appRow.modelData.hasMenu) {
                                            overflowRoot.openItemMenu(appRow.modelData);
                                        } else {
                                            overflowRoot.appletRoot.closeAllPopups();
                                            overflowRoot.trayBackend.contextMenuItem(appRow.modelData.key, globalPt.x, globalPt.y);
                                        }
                                    } else {
                                        overflowRoot.appletRoot.closeAllPopups();
                                        overflowRoot.trayBackend.activateItem(appRow.modelData.key, globalPt.x, globalPt.y);
                                    }
                                }
                            }

                            RowLayout {
                                anchors.fill: parent
                                z: 1
                                anchors.leftMargin: overflowRoot.legacyDp(9.6)
                                anchors.rightMargin: overflowRoot.legacyDp(6.4)
                                spacing: overflowRoot.legacyDp(10.4)

                                Item {
                                    Layout.preferredWidth: overflowRoot.legacyDp(17.6)
                                    Layout.preferredHeight: overflowRoot.legacyDp(17.6)
                                    Layout.alignment: Qt.AlignVCenter

                                    Image {
                                        id: rowImg
                                        anchors.fill: parent
                                        visible: Boolean(appRow.modelData && appRow.modelData.iconPath) && status === Image.Ready
                                        source: (appRow.modelData && appRow.modelData.iconPath) ? appRow.modelData.iconPath : ""
                                        fillMode: Image.PreserveAspectFit
                                        smooth: true
                                        mipmap: true
                                        sourceSize: Qt.size(
                                            Math.max(16, Math.round(width * overflowRoot.dpr)),
                                            Math.max(16, Math.round(height * overflowRoot.dpr))
                                        )
                                    }

                                    Kirigami.Icon {
                                        anchors.fill: parent
                                        visible: !rowImg.visible
                                        isMask: false
                                        source: (appRow.modelData && appRow.modelData.iconName)
                                            ? appRow.modelData.iconName
                                            : "application-x-executable"
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: 1

                                    PlasmaComponents3.Label {
                                        Layout.fillWidth: true
                                        text: appRow.modelData ? String(appRow.modelData.displayTitle || "") : ""
                                        font.family: "Google Sans Flex"
                                        font.pixelSize: overflowRoot.legacyDp(11.2)
                                        font.weight: Font.Medium
                                        color: Kirigami.Theme.textColor
                                        maximumLineCount: 1
                                        elide: Text.ElideRight
                                    }

                                    PlasmaComponents3.Label {
                                        visible: text.length > 0
                                        Layout.fillWidth: true
                                        text: appRow.modelData ? String(appRow.modelData.tooltipSubtitle || "") : ""
                                        font.family: "Google Sans Flex"
                                        font.pixelSize: overflowRoot.legacyDp(9.6)
                                        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.65)
                                        maximumLineCount: 1
                                        elide: Text.ElideRight
                                    }
                                }

                                Rectangle {
                                    visible: Boolean(appRow.modelData && appRow.modelData.hasMenu)
                                    Layout.preferredWidth: overflowRoot.legacyDp(25.6)
                                    Layout.preferredHeight: overflowRoot.legacyDp(25.6)
                                    Layout.alignment: Qt.AlignVCenter
                                    radius: overflowRoot.legacyDp(8.0)
                                    z: 2
                                    color: menuArrowMouse.pressed
                                        ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.16)
                                        : (menuArrowMouse.containsMouse
                                            ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.10)
                                            : "transparent")

                                    Kirigami.Icon {
                                        anchors.centerIn: parent
                                        width: overflowRoot.legacyDp(12.8)
                                        height: width
                                        source: "go-next-symbolic"
                                        isMask: true
                                        color: Kirigami.Theme.textColor
                                    }

                                    MouseArea {
                                        id: menuArrowMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: overflowRoot.openItemMenu(appRow.modelData)
                                    }
                                }
                            }
                        }
                    }
                }

                // 2. Embedded DBusMenu View for Selected App
                TrayMenuList {
                    id: embeddedMenuList
                    width: parent.width
                    visible: overflowRoot.inMenuMode && !overflowRoot.isMenuLoading && overflowRoot.activeMenuItems.length > 0
                    appletRoot: overflowRoot.appletRoot
                    trayBackend: overflowRoot.trayBackend
                    itemKey: overflowRoot.activeMenuItemData ? String(overflowRoot.activeMenuItemData.key || "") : ""
                    rootItems: overflowRoot.activeMenuItems

                    onMenuItemActivated: _menuId => {
                        overflowRoot.appletRoot.closeAllPopups();
                    }
                }

                PlasmaComponents3.Label {
                    anchors.centerIn: parent
                    visible: overflowRoot.inMenuMode && !embeddedMenuList.visible
                    text: overflowRoot.isMenuLoading ? "Ładowanie menu…" : "Brak pozycji menu"
                    font.family: "Google Sans Flex"
                    font.pixelSize: overflowRoot.legacyDp(10.4)
                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.6)
                }
            }
        }
    }
}

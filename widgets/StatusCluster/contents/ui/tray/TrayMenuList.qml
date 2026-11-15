/*
    SPDX-FileCopyrightText: 2026 Maciej Kujawiński <maciek.kujawinski@gmail.com>
    SPDX-License-Identifier: GPL-3.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

ColumnLayout {
    id: menuListRoot

    required property var appletRoot
    required property var trayBackend
    property string itemKey: ""
    property var rootItems: []
    property var submenuStack: [] // Array of { id, title, items }

    signal menuItemActivated(int menuId)

    readonly property var currentItems: submenuStack.length > 0
        ? submenuStack[submenuStack.length - 1].items
        : rootItems

    readonly property bool currentHasLeftDecoration: {
        for (var i = 0; i < currentItems.length; ++i) {
            var it = currentItems[i];
            if (!it || it.isSeparator) {
                continue;
            }
            if ((it.toggleType && it.toggleType.length > 0)
                    || (it.iconPath && it.iconPath.length > 0)
                    || (it.iconName && it.iconName.length > 0)) {
                return true;
            }
        }
        return false;
    }

    function resetStack() {
        submenuStack = [];
    }

    function popSubmenu() {
        if (submenuStack.length > 0) {
            submenuStack = submenuStack.slice(0, submenuStack.length - 1);
        }
    }

    function openSubmenu(entry) {
        if (!entry) {
            return;
        }
        if (entry.children && entry.children.length > 0) {
            submenuStack = submenuStack.concat([{
                id: entry.id,
                title: entry.label || "",
                items: entry.children
            }]);
            return;
        }
        trayBackend.loadSubmenu(itemKey, entry.id, function(res) {
            var loaded = (res && Array.isArray(res.items)) ? res.items : [];
            if (loaded.length > 0) {
                submenuStack = submenuStack.concat([{
                    id: entry.id,
                    title: entry.label || "",
                    items: loaded
                }]);
            } else {
                trayBackend.activateMenuItem(menuListRoot.itemKey, entry.id);
                menuListRoot.menuItemActivated(entry.id);
            }
        });
    }

    spacing: appletRoot.legacyDp(2.4)

    // Back header when drilled into a submenu
    Rectangle {
        id: submenuHeader
        visible: menuListRoot.submenuStack.length > 0
        Layout.fillWidth: true
        Layout.preferredHeight: menuListRoot.appletRoot.legacyDp(30.4)
        radius: menuListRoot.appletRoot.legacyDp(10.0)
        color: backMouse.pressed
            ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
            : (backMouse.containsMouse ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08) : "transparent")

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: menuListRoot.appletRoot.legacyDp(8.0)
            anchors.rightMargin: menuListRoot.appletRoot.legacyDp(8.0)
            spacing: menuListRoot.appletRoot.legacyDp(8.0)

            Kirigami.Icon {
                Layout.preferredWidth: menuListRoot.appletRoot.legacyDp(14.4)
                Layout.preferredHeight: menuListRoot.appletRoot.legacyDp(14.4)
                source: "go-previous-symbolic"
                isMask: true
                color: Kirigami.Theme.textColor
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: menuListRoot.submenuStack.length > 0
                    ? menuListRoot.submenuStack[menuListRoot.submenuStack.length - 1].title
                    : ""
                font.family: "Google Sans Flex"
                font.pixelSize: menuListRoot.appletRoot.legacyDp(11.2)
                font.weight: Font.DemiBold
                color: Kirigami.Theme.textColor
                elide: Text.ElideRight
            }
        }

        MouseArea {
            id: backMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: menuListRoot.popSubmenu()
        }
    }

    Rectangle {
        visible: menuListRoot.submenuStack.length > 0
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        Layout.topMargin: menuListRoot.appletRoot.legacyDp(1.6)
        Layout.bottomMargin: menuListRoot.appletRoot.legacyDp(1.6)
        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)
    }

    Repeater {
        id: entriesRepeater
        model: menuListRoot.currentItems

        delegate: Item {
            id: entryWrapper
            required property var modelData

            readonly property bool isSep: Boolean(modelData && modelData.isSeparator)
            readonly property bool isEnabled: Boolean(modelData && modelData.enabled !== false)
            readonly property bool hasSub: Boolean(modelData && modelData.hasSubmenu)
            readonly property string tType: String(modelData && modelData.toggleType ? modelData.toggleType : "")
            readonly property int tState: (modelData && typeof modelData.toggleState === "number") ? modelData.toggleState : -1

            Layout.fillWidth: true
            Layout.preferredHeight: isSep ? menuListRoot.appletRoot.legacyDp(8.0) : menuListRoot.appletRoot.legacyDp(28.8)

            // Separator
            Rectangle {
                visible: entryWrapper.isSep
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: menuListRoot.appletRoot.legacyDp(8.0)
                anchors.rightMargin: menuListRoot.appletRoot.legacyDp(8.0)
                height: 1
                color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)
            }

            // Action / Label Row
            Rectangle {
                visible: !entryWrapper.isSep
                anchors.fill: parent
                radius: menuListRoot.appletRoot.legacyDp(10.0)
                opacity: entryWrapper.isEnabled ? 1.0 : 0.48
                color: (!entryWrapper.isEnabled) ? "transparent"
                    : (rowMouse.pressed
                        ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
                        : (rowMouse.containsMouse
                            ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08)
                            : "transparent"))

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: menuListRoot.appletRoot.legacyDp(9.6)
                    anchors.rightMargin: menuListRoot.appletRoot.legacyDp(9.6)
                    spacing: menuListRoot.appletRoot.legacyDp(8.0)

                    // Left decoration: checkmark / radio / icon
                    Item {
                        visible: menuListRoot.currentHasLeftDecoration
                        Layout.preferredWidth: menuListRoot.appletRoot.legacyDp(14.4)
                        Layout.preferredHeight: menuListRoot.appletRoot.legacyDp(14.4)
                        Layout.alignment: Qt.AlignVCenter

                        // Checkbox indicator
                        Rectangle {
                            anchors.centerIn: parent
                            visible: entryWrapper.tType === "checkmark"
                            width: menuListRoot.appletRoot.legacyDp(12.8)
                            height: width
                            radius: menuListRoot.appletRoot.legacyDp(4.0)
                            color: entryWrapper.tState === 1 ? menuListRoot.appletRoot.effectiveAccentColor : "transparent"
                            border.width: entryWrapper.tState === 1 ? 0 : 1.5
                            border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.55)

                            Kirigami.Icon {
                                anchors.centerIn: parent
                                visible: entryWrapper.tState === 1
                                width: menuListRoot.appletRoot.legacyDp(9.6)
                                height: width
                                source: "checkmark"
                                isMask: true
                                color: "#1c1e26"
                            }
                        }

                        // Radio indicator
                        Rectangle {
                            anchors.centerIn: parent
                            visible: entryWrapper.tType === "radio"
                            width: menuListRoot.appletRoot.legacyDp(12.8)
                            height: width
                            radius: width / 2
                            color: "transparent"
                            border.width: 1.5
                            border.color: entryWrapper.tState === 1
                                ? menuListRoot.appletRoot.effectiveAccentColor
                                : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.55)

                            Rectangle {
                                anchors.centerIn: parent
                                visible: entryWrapper.tState === 1
                                width: menuListRoot.appletRoot.legacyDp(6.4)
                                height: width
                                radius: width / 2
                                color: menuListRoot.appletRoot.effectiveAccentColor
                            }
                        }

                        // Menu Item Icon
                        Image {
                            id: menuIconImg
                            anchors.fill: parent
                            visible: entryWrapper.tType.length === 0
                                && Boolean(entryWrapper.modelData && entryWrapper.modelData.iconPath && entryWrapper.modelData.iconPath.length > 0)
                                && status === Image.Ready
                            source: (entryWrapper.modelData && entryWrapper.modelData.iconPath) ? entryWrapper.modelData.iconPath : ""
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            mipmap: true
                            asynchronous: true
                            sourceSize: Qt.size(
                                Math.max(16, Math.round(width * menuListRoot.appletRoot.dpr)),
                                Math.max(16, Math.round(height * menuListRoot.appletRoot.dpr))
                            )
                        }

                        Kirigami.Icon {
                            anchors.fill: parent
                            visible: entryWrapper.tType.length === 0
                                && !menuIconImg.visible
                                && Boolean(entryWrapper.modelData && entryWrapper.modelData.iconName && entryWrapper.modelData.iconName.length > 0)
                            isMask: false
                            source: (entryWrapper.modelData && entryWrapper.modelData.iconName) ? entryWrapper.modelData.iconName : ""
                        }
                    }

                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        text: entryWrapper.modelData ? String(entryWrapper.modelData.label || "") : ""
                        font.family: "Google Sans Flex"
                        font.pixelSize: menuListRoot.appletRoot.legacyDp(11.2)
                        font.weight: Font.Normal
                        color: Kirigami.Theme.textColor
                        maximumLineCount: 1
                        elide: Text.ElideRight
                    }

                    Kirigami.Icon {
                        visible: entryWrapper.hasSub
                        Layout.preferredWidth: menuListRoot.appletRoot.legacyDp(12.8)
                        Layout.preferredHeight: menuListRoot.appletRoot.legacyDp(12.8)
                        Layout.alignment: Qt.AlignVCenter
                        source: "go-next-symbolic"
                        isMask: true
                        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.7)
                    }
                }

                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: entryWrapper.isEnabled
                    enabled: entryWrapper.isEnabled
                    onClicked: {
                        if (entryWrapper.hasSub) {
                            menuListRoot.openSubmenu(entryWrapper.modelData);
                        } else {
                            menuListRoot.trayBackend.activateMenuItem(menuListRoot.itemKey, entryWrapper.modelData.id);
                            menuListRoot.menuItemActivated(entryWrapper.modelData.id);
                        }
                    }
                }
            }
        }
    }
}

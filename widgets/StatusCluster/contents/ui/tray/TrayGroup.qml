/*
    SPDX-FileCopyrightText: 2026 Maciej Kujawiński <maciek.kujawinski@gmail.com>
    SPDX-License-Identifier: GPL-3.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import "../components" as Components

Item {
    id: groupRoot

    required property var appletRoot
    required property var trayBackend
    property bool trayOverflowVisible: false
    property string activeTrayMenuKey: ""

    readonly property alias overflowAnchorButton: trayOverflowButton

    visible: trayBackend.allItems.length > 0
    height: appletRoot.railHeight
    width: visible ? trayRow.implicitWidth : 0
    implicitWidth: visible ? trayRow.implicitWidth : 0
    implicitHeight: height

    Row {
        id: trayRow
        height: parent.height
        spacing: groupRoot.appletRoot.qsIconSpacing

        Repeater {
            id: inlineRepeater
            model: groupRoot.trayBackend.inlineItems

            delegate: TrayItemButton {
                required property var modelData
                appletRoot: groupRoot.appletRoot
                trayBackend: groupRoot.trayBackend
                itemData: modelData
                expanded: groupRoot.activeTrayMenuKey === String(modelData.key || "")
            }
        }

        Components.RailIconButton {
            id: trayOverflowButton
            visible: groupRoot.trayBackend.hasOverflow
            iconSource: Qt.resolvedUrl("icons/overflow.svg")
            railHeight: groupRoot.appletRoot.railHeight
            iconSize: groupRoot.appletRoot.qsIconHeight
            dpr: groupRoot.appletRoot.dpr
            highlightCapsuleColor: groupRoot.appletRoot.highlightCapsuleColor
            contentColor: groupRoot.appletRoot.topBarContentColor
            highlightedContentColor: groupRoot.appletRoot.highlightedContentColor
            expanded: groupRoot.trayOverflowVisible

            onClicked: wasExpanded => {
                if (wasExpanded) {
                    groupRoot.appletRoot.closeAllPopups();
                } else {
                    groupRoot.appletRoot.requestTogglePopup("trayOverflow");
                }
            }
        }
    }
}

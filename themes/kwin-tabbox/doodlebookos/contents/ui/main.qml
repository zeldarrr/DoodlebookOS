/*
    DoodlebookOS window switcher (Alt+Tab), Material 3 style.
    Based on KWin's thumbnail_grid (SPDX: 2020 Chris Holland, 2023 Nate Graham, GPL-2.0-or-later).
    SPDX-License-Identifier: GPL-3.0-or-later
    Horizontal strip of rounded live previews (like Android recents). The selected card
    gets a tonal container + accent outline and grows slightly; motion is short (150 ms)
    so the switcher never feels laggy.
*/
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import org.kde.kwin as KWin
import org.kde.kirigami as Kirigami

KWin.TabBoxSwitcher {
    id: tabBox

    Instantiator {
        active: tabBox.visible
        delegate: PlasmaCore.Dialog {
            location: PlasmaCore.Types.Floating
            visible: true
            flags: Qt.ToolTip | Qt.X11BypassWindowManagerHint
            x: tabBox.screenGeometry.x + (tabBox.screenGeometry.width - mainItem.width) / 2
            y: tabBox.screenGeometry.y + (tabBox.screenGeometry.height - mainItem.height) / 2

            mainItem: FocusScope {
                id: root
                focus: true
                readonly property real ratio: tabBox.screenGeometry.width / tabBox.screenGeometry.height
                readonly property int thumbW: Math.round(Math.min(300, tabBox.screenGeometry.width * 0.16))
                readonly property int thumbH: Math.round(thumbW / ratio)
                readonly property int cardW: thumbW + 24
                readonly property int cardH: thumbH + 64
                readonly property color fg: Kirigami.Theme.textColor
                readonly property color accent: Kirigami.Theme.highlightColor
                width: Math.min(tabBox.screenGeometry.width * 0.9, Math.max(cardW, list.count * (cardW + list.spacing) - list.spacing))
                height: cardH

                ListView {
                    id: list
                    anchors.fill: parent
                    orientation: ListView.Horizontal
                    spacing: 12
                    focus: true
                    model: tabBox.model
                    currentIndex: tabBox.currentIndex
                    keyNavigationWraps: true
                    highlightMoveDuration: 150
                    highlightFollowsCurrentItem: true
                    boundsBehavior: Flickable.StopAtBounds
                    onCurrentIndexChanged: tabBox.currentIndex = currentIndex

                    highlight: Rectangle {
                        radius: 28
                        color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
                        border.width: 2
                        border.color: root.accent
                    }

                    delegate: MouseArea {
                        id: card
                        required property int index
                        required property var model
                        readonly property bool current: ListView.isCurrentItem
                        width: root.cardW
                        height: root.cardH
                        hoverEnabled: true
                        onClicked: tabBox.model.activate(index)
                        scale: current ? 1.0 : 0.95
                        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

                        Item {
                            id: thumbBox
                            x: 12; y: 12
                            width: root.thumbW
                            height: root.thumbH
                            // rounded clip of the live preview (layer only while visible)
                            layer.enabled: true
                            layer.smooth: true
                            Rectangle { anchors.fill: parent; radius: 18; color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06) }
                            KWin.WindowThumbnail {
                                anchors.fill: parent
                                wId: card.model.windowId
                            }
                        }

                        RowLayout {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: 14
                            spacing: 8
                            Kirigami.Icon {
                                Layout.preferredWidth: 24
                                Layout.preferredHeight: 24
                                source: card.model.icon
                            }
                            Text {
                                Layout.fillWidth: true
                                text: card.model.caption
                                elide: Text.ElideRight
                                textFormat: Text.PlainText
                                font.family: "Google Sans Flex"
                                font.pixelSize: 13
                                font.weight: card.current ? Font.DemiBold : Font.Normal
                                color: root.fg
                            }
                            Rectangle {
                                visible: card.model.closeable && (card.containsMouse || card.current)
                                Layout.preferredWidth: 24
                                Layout.preferredHeight: 24
                                radius: 12
                                color: closeMa.containsMouse ? Kirigami.Theme.negativeTextColor : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)
                                Kirigami.Icon { anchors.centerIn: parent; width: 14; height: 14; source: "window-close-symbolic"; color: root.fg }
                                MouseArea { id: closeMa; anchors.fill: parent; hoverEnabled: true; onClicked: tabBox.model.close(card.index) }
                            }
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: list.count === 0
                    text: i18ndc("kwin", "@info:placeholder no entries in the task switcher", "No open windows")
                    color: root.fg
                }

                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Left) list.decrementCurrentIndex();
                    else if (event.key === Qt.Key_Right) list.incrementCurrentIndex();
                }
            }
        }
    }
}

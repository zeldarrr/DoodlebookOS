pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "i18n.js" as I18n
import "metrics" as LocalMetrics

ColumnLayout {
    id: gridViewRoot
    anchors.fill: parent
    anchors.topMargin: gridViewRoot.popupContainer.cols === 2 ? LocalMetrics.Metrics.px(3.0) : LocalMetrics.Metrics.legacyDp(20)
    anchors.bottomMargin: gridViewRoot.popupContainer.cols === 2 ? LocalMetrics.Metrics.px(15.0) : LocalMetrics.Metrics.legacyDp(14)
    anchors.leftMargin: gridViewRoot.popupContainer.cols === 2 ? LocalMetrics.Metrics.px(8.0) : LocalMetrics.Metrics.legacyDp(16)
    anchors.rightMargin: gridViewRoot.popupContainer.cols === 2 ? LocalMetrics.Metrics.px(8.0) : LocalMetrics.Metrics.legacyDp(16)
    spacing: gridViewRoot.popupContainer.cols === 2 ? LocalMetrics.Metrics.px(4.0) : LocalMetrics.Metrics.legacyDp(6)

    required property var rootApplet
    required property var popupContainer

    function commitTitle() {
        if (gridViewRoot.rootApplet.editingTitle) {
            gridViewRoot.rootApplet.saveTitle(titleEditor.text);
        }
    }

    Flickable {
        id: gridFlick
        Layout.fillWidth: true
        Layout.fillHeight: true
        contentWidth: width
        contentHeight: appGrid.implicitHeight
        clip: true

        Grid {
            id: appGrid
            width: gridFlick.width
            columns: gridViewRoot.popupContainer.cols
            readonly property real cellW: Math.floor(width / columns)
            readonly property real cellH: columns === 2 ? LocalMetrics.Metrics.px(112.0) : LocalMetrics.Metrics.legacyDp(88)

            Repeater {
                model: gridViewRoot.rootApplet.appList

                Item {
                    id: appTile
                    required property var modelData
                    required property int index

                    width: appGrid.cellW
                    height: appGrid.cellH

                    Column {
                        anchors.centerIn: parent
                        spacing: gridViewRoot.popupContainer.cols === 2 ? LocalMetrics.Metrics.px(9.0) : LocalMetrics.Metrics.legacyDp(6)

                        Item {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: LocalMetrics.Metrics.px(46.0)
                            height: LocalMetrics.Metrics.px(46.0)
                            scale: tileMouse.containsMouse && !tileMouse.pressed ? 1.05 : (tileMouse.pressed ? 0.94 : 1.0)
                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }

                            Kirigami.Icon {
                                anchors.centerIn: parent
                                width: LocalMetrics.Metrics.px(46.0)
                                height: LocalMetrics.Metrics.px(46.0)
                                source: (appTile.modelData && appTile.modelData.icon) || "application-x-executable"
                                smooth: true
                            }
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: appTile.width - LocalMetrics.Metrics.px(8.0)
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            text: appTile.modelData ? appTile.modelData.name : ""
                            font.family: "Google Sans Flex"
                            font.pixelSize: LocalMetrics.Metrics.px(14.5)
                            font.weight: Font.Normal
                            color: gridViewRoot.popupContainer.cText
                        }
                    }

                    MouseArea {
                        id: tileMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        pressAndHoldInterval: 350
                        onClicked: (mouse) => {
                            if (mouse.button === Qt.RightButton) {
                                gridViewRoot.rootApplet.editMode = !gridViewRoot.rootApplet.editMode;
                            } else if (gridViewRoot.rootApplet.editingTitle) {
                                gridViewRoot.rootApplet.saveTitle(titleEditor.text);
                            } else if (!gridViewRoot.rootApplet.editMode) {
                                gridViewRoot.popupContainer.close();
                                gridViewRoot.rootApplet.launchApp(appTile.modelData);
                            }
                        }

                        onPressAndHold: {
                            gridViewRoot.rootApplet.editMode = !gridViewRoot.rootApplet.editMode;
                        }
                    }

                    // Remove Badge (✕) in Edit Mode (Long-press or Right-click)
                    Rectangle {
                        visible: gridViewRoot.rootApplet.editMode
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.topMargin: LocalMetrics.Metrics.legacyDp(4)
                        anchors.rightMargin: LocalMetrics.Metrics.legacyDp(14)
                        width: LocalMetrics.Metrics.legacyDp(20)
                        height: LocalMetrics.Metrics.legacyDp(20)
                        radius: LocalMetrics.Metrics.legacyDp(10)
                        color: "#EA4335"
                        z: 10

                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            font.pixelSize: LocalMetrics.Metrics.legacyDp(10)
                            font.bold: true
                            color: "#FFFFFF"
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                gridViewRoot.rootApplet.removeAppAt(appTile.index);
                            }
                        }
                    }
                }
            }
        }

        // Empty Folder Placeholder
        Item {
            anchors.fill: parent
            visible: gridViewRoot.rootApplet.appList.length === 0

            Column {
                anchors.centerIn: parent
                spacing: LocalMetrics.Metrics.legacyDp(8)

                Kirigami.Icon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: LocalMetrics.Metrics.legacyDp(36)
                    height: LocalMetrics.Metrics.legacyDp(36)
                    source: "folder-new"
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: I18n.t("Folder is empty")
                    font.family: "Google Sans Flex"
                    font.pixelSize: LocalMetrics.Metrics.legacyDp(13)
                    font.weight: Font.Medium
                    color: gridViewRoot.popupContainer.cSub
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: LocalMetrics.Metrics.legacyDp(120)
                    height: LocalMetrics.Metrics.legacyDp(30)
                    radius: LocalMetrics.Metrics.legacyDp(15)
                    color: emptyAddMouse.containsMouse ? gridViewRoot.popupContainer.cPillHover : gridViewRoot.popupContainer.cPill

                    Text {
                        anchors.centerIn: parent
                        text: I18n.t("Add apps")
                        font.family: "Google Sans Flex"
                        font.pixelSize: LocalMetrics.Metrics.legacyDp(12)
                        font.weight: Font.Medium
                        color: gridViewRoot.popupContainer.cText
                    }

                    MouseArea {
                        id: emptyAddMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (gridViewRoot.rootApplet.allSystemApps.length === 0) gridViewRoot.rootApplet.fetchSystemApps();
                            gridViewRoot.rootApplet.addingMode = true;
                            gridViewRoot.rootApplet.editMode = false;
                        }
                    }
                }
            }
        }
    }

    // ====================================================
    // BOTTOM FOLDER TITLE (Click to Rename Inline)
    // ====================================================
    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: LocalMetrics.Metrics.px(34.0)

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width, bottomTitleLabel.implicitWidth + LocalMetrics.Metrics.px(28.0))
            height: LocalMetrics.Metrics.px(28.0)
            radius: LocalMetrics.Metrics.px(14.0)
            color: bottomTitleMouse.containsMouse ? gridViewRoot.popupContainer.cPill : "transparent"
            visible: !gridViewRoot.rootApplet.editingTitle

            Text {
                id: bottomTitleLabel
                anchors.centerIn: parent
                text: gridViewRoot.rootApplet.folderName
                font.family: "Google Sans Flex"
                font.pixelSize: LocalMetrics.Metrics.px(16.5)
                font.weight: Font.Normal
                color: gridViewRoot.popupContainer.cText
                elide: Text.ElideRight
            }

            MouseArea {
                id: bottomTitleMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.IBeamCursor
                onClicked: {
                    titleEditor.text = gridViewRoot.rootApplet.folderName;
                    gridViewRoot.rootApplet.editingTitle = true;
                    titleEditor.forceActiveFocus();
                    titleEditor.selectAll();
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: LocalMetrics.Metrics.px(14.0)
            color: gridViewRoot.popupContainer.cPill
            visible: gridViewRoot.rootApplet.editingTitle

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: LocalMetrics.Metrics.legacyDp(12)
                anchors.rightMargin: LocalMetrics.Metrics.legacyDp(6)
                spacing: LocalMetrics.Metrics.legacyDp(4)

                TextInput {
                    id: titleEditor
                    Layout.fillWidth: true
                    horizontalAlignment: TextInput.AlignHCenter
                    font.family: "Google Sans Flex"
                    font.pixelSize: LocalMetrics.Metrics.px(16.5)
                    color: gridViewRoot.popupContainer.cText
                    selectionColor: gridViewRoot.popupContainer.cAccent
                    selectedTextColor: "#FFFFFF"
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    onAccepted: {
                        gridViewRoot.rootApplet.saveTitle(text);
                    }
                    Keys.onEscapePressed: {
                        gridViewRoot.rootApplet.editingTitle = false;
                    }
                }

                Rectangle {
                    Layout.preferredWidth: LocalMetrics.Metrics.legacyDp(22)
                    Layout.preferredHeight: LocalMetrics.Metrics.legacyDp(22)
                    Layout.alignment: Qt.AlignVCenter
                    radius: LocalMetrics.Metrics.legacyDp(11)
                    color: gridViewRoot.popupContainer.cAccent

                    Text {
                        anchors.centerIn: parent
                        text: "✓"
                        font.pixelSize: LocalMetrics.Metrics.legacyDp(11)
                        font.bold: true
                        color: "#FFFFFF"
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: gridViewRoot.rootApplet.saveTitle(titleEditor.text)
                    }
                }
            }
        }
    }
}

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "i18n.js" as I18n
import "metrics" as LocalMetrics

ColumnLayout {
    id: pickerView
    anchors.fill: parent
    anchors.margins: LocalMetrics.Metrics.legacyDp(16)
    spacing: LocalMetrics.Metrics.legacyDp(10)

    required property var rootApplet
    required property var popupContainer

    RowLayout {
        Layout.fillWidth: true
        spacing: LocalMetrics.Metrics.legacyDp(8)

        Rectangle {
            Layout.preferredWidth: LocalMetrics.Metrics.legacyDp(28)
            Layout.preferredHeight: LocalMetrics.Metrics.legacyDp(28)
            Layout.alignment: Qt.AlignVCenter
            radius: LocalMetrics.Metrics.legacyDp(14)
            color: backMouse.containsMouse ? pickerView.popupContainer.cPillHover : pickerView.popupContainer.cPill

            Text {
                anchors.centerIn: parent
                text: "←"
                font.pixelSize: LocalMetrics.Metrics.legacyDp(14)
                font.bold: true
                color: pickerView.popupContainer.cText
            }

            MouseArea {
                id: backMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    pickerView.rootApplet.addingMode = false;
                    pickerView.rootApplet.searchQuery = "";
                }
            }
        }

        Text {
            Layout.fillWidth: true
            text: I18n.t("Add to:") + " " + pickerView.rootApplet.folderName
            font.family: "Google Sans Flex"
            font.pixelSize: LocalMetrics.Metrics.legacyDp(14)
            font.weight: Font.Bold
            color: pickerView.popupContainer.cText
            elide: Text.ElideRight
        }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: LocalMetrics.Metrics.legacyDp(34)
        radius: LocalMetrics.Metrics.legacyDp(17)
        color: pickerView.popupContainer.cPill

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: LocalMetrics.Metrics.legacyDp(12)
            anchors.rightMargin: LocalMetrics.Metrics.legacyDp(10)
            spacing: LocalMetrics.Metrics.legacyDp(6)

            Text {
                text: "🔍"
                font.pixelSize: LocalMetrics.Metrics.legacyDp(11)
                color: pickerView.popupContainer.cSub
            }

            TextInput {
                id: searchField
                Layout.fillWidth: true
                font.family: "Google Sans Flex"
                font.pixelSize: LocalMetrics.Metrics.legacyDp(12)
                color: pickerView.popupContainer.cText
                clip: true
                onTextChanged: {
                    pickerView.rootApplet.searchQuery = text.trim().toLowerCase();
                }

                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    text: I18n.t("Search apps...")
                    font.family: "Google Sans Flex"
                    font.pixelSize: LocalMetrics.Metrics.legacyDp(12)
                    color: pickerView.popupContainer.cSub
                    visible: searchField.text.length === 0
                }

                Component.onCompleted: {
                    if (pickerView.rootApplet.addingMode) {
                        forceActiveFocus();
                    }
                }
            }
        }
    }

    ListView {
        id: pickerList
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        spacing: LocalMetrics.Metrics.legacyDp(4)

        model: {
            var q = pickerView.rootApplet.searchQuery;
            var src = pickerView.rootApplet.allSystemApps;
            if (!q || q.length === 0) return src;
            var out = [];
            for (var i = 0; i < src.length; i++) {
                if (src[i].name.toLowerCase().indexOf(q) !== -1) {
                    out.push(src[i]);
                }
            }
            return out;
        }

        delegate: Rectangle {
            id: pickerDelegate
            required property var modelData
            required property int index

            width: pickerList.width
            height: LocalMetrics.Metrics.legacyDp(40)
            radius: LocalMetrics.Metrics.legacyDp(12)
            readonly property bool isAdded: pickerView.rootApplet.hasApp(modelData)
            color: rowMouse.containsMouse ? pickerView.popupContainer.cPillHover : (pickerDelegate.isAdded ? pickerView.popupContainer.cPill : "transparent")

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: LocalMetrics.Metrics.legacyDp(8)
                anchors.rightMargin: LocalMetrics.Metrics.legacyDp(10)
                spacing: LocalMetrics.Metrics.legacyDp(10)

                Rectangle {
                    Layout.preferredWidth: LocalMetrics.Metrics.legacyDp(28)
                    Layout.preferredHeight: LocalMetrics.Metrics.legacyDp(28)
                    Layout.alignment: Qt.AlignVCenter
                    radius: LocalMetrics.Metrics.legacyDp(14)
                    color: "#FFFFFF"

                    Kirigami.Icon {
                        anchors.centerIn: parent
                        width: LocalMetrics.Metrics.legacyDp(20)
                        height: LocalMetrics.Metrics.legacyDp(20)
                        source: pickerDelegate.modelData.icon || "application-x-executable"
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: pickerDelegate.modelData.name
                    font.family: "Google Sans Flex"
                    font.pixelSize: LocalMetrics.Metrics.legacyDp(12)
                    font.weight: pickerDelegate.isAdded ? Font.DemiBold : Font.Normal
                    color: pickerView.popupContainer.cText
                    elide: Text.ElideRight
                }

                Rectangle {
                    Layout.preferredWidth: LocalMetrics.Metrics.legacyDp(22)
                    Layout.preferredHeight: LocalMetrics.Metrics.legacyDp(22)
                    Layout.alignment: Qt.AlignVCenter
                    radius: LocalMetrics.Metrics.legacyDp(11)
                    color: pickerDelegate.isAdded ? pickerView.popupContainer.cAccent : pickerView.popupContainer.cPill

                    Text {
                        anchors.centerIn: parent
                        text: pickerDelegate.isAdded ? "✓" : "+"
                        font.pixelSize: LocalMetrics.Metrics.legacyDp(11)
                        font.bold: true
                        color: pickerDelegate.isAdded ? "#FFFFFF" : pickerView.popupContainer.cText
                    }
                }
            }

            MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    pickerView.rootApplet.toggleAppInFolder(pickerDelegate.modelData);
                }
            }
        }
    }
}

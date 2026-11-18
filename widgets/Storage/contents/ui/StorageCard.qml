/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

Item {
    id: card
    property var disks: []
    signal refresh()
    signal open(string path)
    M3Colors { id: pal }

    // settings (Configurer… > Stockage / Apparence)
    readonly property var cfg: Plasmoid.configuration
    readonly property color bgColor: pal.container(cfg.colorRole, cfg.customColor)
    readonly property color fgColor: pal.onContainer(cfg.colorRole, cfg.customColor)
    readonly property color fgVariant: pal.alpha(fgColor, 0.66)
    readonly property real fs: (cfg.fontScale || 100) / 100
    readonly property int barH: cfg.barHeight || 16
    readonly property int rowH: Math.round((cfg.compact ? 22 : 34) * fs) + barH
    readonly property int rowGap: cfg.compact ? 8 : 14
    readonly property int headerH: cfg.showHeader ? 50 : 14

    implicitWidth: 340
    implicitHeight: headerH + 22 + Math.max(1, disks.length) * (rowH + rowGap)

    function human(b) {
        var u = ["o", "Ko", "Mo", "Go", "To"], i = 0;
        while (b >= 1000 && i < u.length - 1) { b /= 1024; i++; }
        return (b >= 100 || i === 0 ? Math.round(b) : b.toFixed(1).replace(".", ",")) + " " + u[i];
    }

    Rectangle {
        anchors.fill: parent
        radius: card.cfg.cornerRadius
        color: Qt.rgba(card.bgColor.r, card.bgColor.g, card.bgColor.b, card.cfg.bgOpacity / 100)
        border.width: card.cfg.outline ? 1 : 0
        border.color: pal.alpha(card.fgColor, 0.22)

        Item {
            id: header
            visible: card.cfg.showHeader
            x: 20
            y: 14
            width: parent.width - 34
            height: visible ? 36 : 0
            Kirigami.Icon {
                id: hIcon
                anchors.verticalCenter: parent.verticalCenter
                width: Math.round(20 * card.fs)
                height: width
                source: card.cfg.headerIcon.length > 0 ? card.cfg.headerIcon : "drive-harddisk"
                isMask: true
                color: card.cfg.colorRole === "surface" || card.cfg.colorRole === "surfaceHigh" ? pal.primary : card.fgColor
            }
            Text {
                anchors.left: hIcon.right
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: card.cfg.headerText.length > 0 ? card.cfg.headerText : "Stockage"
                font.family: pal.font
                font.pixelSize: Math.round(16 * card.fs)
                font.weight: Font.DemiBold
                color: card.fgColor
            }
            Rectangle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 32
                height: 32
                radius: 16
                color: rMa.pressed ? pal.statePress : (rMa.containsMouse ? pal.stateHover : "transparent")
                Kirigami.Icon { anchors.centerIn: parent; width: 16; height: 16; source: "view-refresh"; isMask: true; color: card.fgVariant }
                MouseArea { id: rMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: card.refresh() }
            }
        }

        Column {
            anchors.top: header.bottom
            anchors.topMargin: 8
            x: 20
            width: parent.width - 40
            spacing: card.rowGap

            Repeater {
                model: card.disks
                Item {
                    id: row
                    required property var modelData
                    readonly property real frac: modelData.total > 0 ? modelData.used / modelData.total : 0
                    readonly property bool full: frac * 100 >= card.cfg.warnPercent
                    width: parent.width
                    height: card.rowH

                    Text {
                        id: nm
                        text: row.modelData.name
                        font.family: pal.font
                        font.pixelSize: Math.round(14 * card.fs)
                        font.weight: Font.DemiBold
                        color: card.fgColor
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.baseline: nm.baseline
                        visible: card.cfg.showFreeText
                        text: card.human(row.modelData.total - row.modelData.used) + " libres sur " + card.human(row.modelData.total)
                        font.family: pal.font
                        font.pixelSize: Math.round(12 * card.fs)
                        color: row.full ? pal.error : card.fgVariant
                    }
                    // M3 expressive bar: thick rounded track, active part with a gap and end stop
                    Item {
                        id: bar
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: card.barH
                        readonly property real activeW: Math.max(height, Math.round((width - 4) * row.frac))
                        Rectangle {
                            x: bar.activeW + 4
                            width: parent.width - x
                            height: parent.height
                            radius: Math.min(6, height / 2)
                            topLeftRadius: Math.min(3, height / 2)
                            bottomLeftRadius: Math.min(3, height / 2)
                            color: row.full ? pal.alpha(pal.error, 0.2) : pal.primaryContainer
                            visible: width > 4
                        }
                        Rectangle {
                            width: bar.activeW
                            height: parent.height
                            radius: height / 2
                            topRightRadius: Math.min(3, height / 2)
                            bottomRightRadius: Math.min(3, height / 2)
                            color: row.full ? pal.error : pal.primary
                            Behavior on width { NumberAnimation { duration: Kirigami.Units.longDuration > 1 ? 400 : 0; easing.type: Easing.OutCubic } }
                        }
                        Text {
                            x: 8
                            anchors.verticalCenter: parent.verticalCenter
                            visible: card.cfg.showPercent && bar.activeW > 44 && bar.height >= 12
                            text: Math.round(row.frac * 100) + " %"
                            font.family: pal.font
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            color: pal.primaryText
                        }
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: card.open(row.modelData.open) }
                }
            }
        }
    }
}

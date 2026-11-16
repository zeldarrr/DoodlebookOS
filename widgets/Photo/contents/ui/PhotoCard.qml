/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

Item {
    id: card
    property string source: ""
    // Material 3 Expressive outline (0..100 box) from shape.json, "" = rounded rectangle
    property string shapePath: ""
    signal pick()
    signal next()
    implicitWidth: 432
    implicitHeight: 320

    readonly property var cfg: Plasmoid.configuration
    readonly property real radius: cfg.cornerRadius
    readonly property bool ready: img.status === Image.Ready
    readonly property bool shaped: shapePath.length > 0
    readonly property color bgColor: pal.container(cfg.colorRole, cfg.customColor)
    readonly property color fgColor: pal.onContainer(cfg.colorRole, cfg.customColor)
    readonly property real fs: (cfg.fontScale || 100) / 100

    M3Colors { id: pal }
    HoverHandler { id: hover }

    // placeholder (no image yet, or file gone)
    Rectangle {
        anchors.fill: parent
        radius: card.radius
        color: Qt.rgba(card.bgColor.r, card.bgColor.g, card.bgColor.b, card.cfg.bgOpacity / 100)
        border.width: card.cfg.outline ? 1 : 0
        border.color: pal.alpha(card.fgColor, 0.22)
        visible: !card.ready
        Column {
            anchors.centerIn: parent
            spacing: 12
            visible: img.status !== Image.Loading
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 64
                height: 64
                radius: 22
                color: pal.primaryContainer
                Kirigami.Icon {
                    anchors.centerIn: parent
                    width: 32
                    height: 32
                    source: "insert-image"
                    isMask: true
                    color: pal.primaryContainerText
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: card.source.length > 0 ? "Image introuvable" : "Choisir une image"
                font.family: pal.font
                font.pixelSize: Math.round(15 * card.fs)
                font.weight: Font.DemiBold
                color: card.fgColor
            }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: card.pick() }
    }

    // decoded at the displayed size (never the full photo), drawn once through the mask;
    // the layer is static so it costs nothing per frame
    Image {
        id: img
        anchors.fill: parent
        source: width > 0 && height > 0 ? card.source : ""
        asynchronous: true
        autoTransform: true
        cache: false
        fillMode: card.cfg.fillMode === "fit" ? Image.PreserveAspectFit : Image.PreserveAspectCrop
        sourceSize: Qt.size(Math.ceil(width * Screen.devicePixelRatio), Math.ceil(height * Screen.devicePixelRatio))
        opacity: card.ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
        layer.enabled: true
        layer.smooth: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: mask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
            saturation: card.cfg.saturation / 100
            brightness: -card.cfg.dimPercent / 100 * 0.6
        }
        MouseArea {
            anchors.fill: parent
            enabled: card.ready && card.cfg.clickAction !== "none"
            cursorShape: Qt.PointingHandCursor
            onClicked: card.cfg.clickAction === "next" ? card.next() : Qt.openUrlExternally(card.source)
        }
    }
    Item {
        id: mask
        width: img.width
        height: img.height
        layer.enabled: true
        visible: false
        Rectangle { anchors.fill: parent; radius: card.radius; color: "black"; visible: !card.shaped }
        Shape {
            visible: card.shaped
            anchors.centerIn: parent
            width: 100
            height: 100
            scale: Math.min(mask.width, mask.height) / 100
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: "black"
                strokeColor: "transparent"
                PathSvg { path: card.shapePath }
            }
        }
    }
    // outline on top of the picture
    Rectangle {
        anchors.fill: parent
        visible: card.ready && card.cfg.outline && !card.shaped
        radius: card.radius
        color: "transparent"
        border.width: 1
        border.color: pal.alpha(card.fgColor, 0.3)
    }

    // change button, shown on hover
    Rectangle {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 12
        width: 40
        height: 40
        radius: btnMa.pressed ? 12 : 20
        color: pal.alpha(pal.surface, 0.88)
        visible: card.ready && card.cfg.showButton
        opacity: hover.hovered ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 150 } }
        Behavior on radius { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Kirigami.Icon {
            anchors.centerIn: parent
            width: 20
            height: 20
            source: "insert-image"
            isMask: true
            color: pal.surfaceText
        }
        MouseArea {
            id: btnMa
            anchors.fill: parent
            enabled: parent.opacity > 0
            cursorShape: Qt.PointingHandCursor
            onClicked: card.pick()
        }
    }
}

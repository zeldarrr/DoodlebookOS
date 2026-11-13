/*
    SPDX-FileCopyrightText: 2026 DoodlebookOS
    SPDX-License-Identifier: GPL-3.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import org.kde.kirigami as Kirigami

Item {
    id: iconRoot

    property url source
    property color color: "#ffffff"
    property bool colorize: true
    property real dpr: 1.0
    property real iconHeight: 12.8
    property bool preserveSvgAspect: false

    function snapPx(val) {
        return Math.round(val * dpr) / dpr;
    }

    Image {
        id: rawMetrics
        source: iconRoot.source
        visible: false
    }

    readonly property real svgAspect: (preserveSvgAspect && rawMetrics.implicitHeight > 0)
        ? (rawMetrics.implicitWidth / rawMetrics.implicitHeight)
        : 1.0
    readonly property real resolvedWidth: preserveSvgAspect
        ? snapPx(iconHeight * svgAspect)
        : snapPx(iconHeight)
    readonly property real resolvedHeight: snapPx(iconHeight)
    readonly property bool useDirectRender: !colorize || Qt.colorEqual(color, "#ffffff")

    implicitWidth: resolvedWidth
    implicitHeight: resolvedHeight
    width: resolvedWidth
    height: resolvedHeight

    Image {
        id: srcImg
        anchors.fill: parent
        source: iconRoot.source
        sourceSize.width: Math.round(iconRoot.resolvedWidth * iconRoot.dpr)
        sourceSize.height: Math.round(iconRoot.resolvedHeight * iconRoot.dpr)
        fillMode: Image.PreserveAspectFit
        smooth: true
        visible: iconRoot.useDirectRender
    }

    MultiEffect {
        anchors.fill: srcImg
        source: srcImg
        visible: !iconRoot.useDirectRender
        colorization: 1.0
        colorizationColor: iconRoot.color
        Behavior on colorizationColor { ColorAnimation { duration: Kirigami.Units.shortDuration } }
    }
}

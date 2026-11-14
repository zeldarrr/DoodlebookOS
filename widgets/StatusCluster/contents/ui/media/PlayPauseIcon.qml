import QtQuick
import QtQuick.Effects

Item {
    id: root

    property bool isPlaying: false
    property color color: "#18181c"
    property real iconSize: 16
    readonly property real dpr: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1.0

    implicitWidth: iconSize
    implicitHeight: iconSize

    Image {
        id: iconImg
        anchors.centerIn: parent
        width: root.iconSize
        height: root.iconSize
        sourceSize: Qt.size(Math.max(8, Math.round(root.iconSize * root.dpr)), Math.max(8, Math.round(root.iconSize * root.dpr)))
        fillMode: Image.PreserveAspectFit
        source: root.isPlaying ? Qt.resolvedUrl("icons/pause.svg") : Qt.resolvedUrl("icons/play_arrow.svg")
        visible: false
    }

    MultiEffect {
        anchors.fill: iconImg
        source: iconImg
        colorization: 1.0
        colorizationColor: root.color
    }
}

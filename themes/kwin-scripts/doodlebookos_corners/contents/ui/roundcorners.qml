// SPDX-License-Identifier: GPL-3.0-or-later
// DoodlebookOS rounded screen corners: four tiny static overlays per screen (drawn once, then only
// composited). They are hidden (not destroyed: no buffer reallocation) while the active window is
// fullscreen or a borderless window covering its screen (games), so it can be scanned out directly.
// Maximised windows keep their rounded corners.
import QtQuick
import QtQuick.Window as QW
import QtQuick.Shapes
import QtQml.Models
import org.kde.kwin

Item {
    id: root
    readonly property real radius: 18

    function covers(w, g) {
        var f = w.frameGeometry;
        return f.x <= g.x && f.y <= g.y && f.x + f.width >= g.x + g.width && f.y + f.height >= g.y + g.height;
    }
    function fullscreenOn(screen) {
        var w = Workspace.activeWindow;
        if (!w || w.minimized || w.output !== screen) return false;
        return w.fullScreen || (w.noBorder && covers(w, screen.geometry));
    }

    component Corner: QW.Window {
        id: corner
        required property rect area
        required property int quadrant        // 0 top-left, 1 top-right, 2 bottom-right, 3 bottom-left
        required property bool hidden
        flags: Qt.BypassWindowManagerHint | Qt.FramelessWindowHint | Qt.WindowDoesNotAcceptFocus | Qt.WindowTransparentForInput
        color: "transparent"
        width: root.radius
        height: root.radius
        x: quadrant === 1 || quadrant === 2 ? area.x + area.width - width : area.x
        y: quadrant >= 2 ? area.y + area.height - height : area.y
        visible: !hidden

        Shape {
            anchors.fill: parent
            rotation: corner.quadrant * 90
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: "black"
                strokeColor: "transparent"
                strokeWidth: 0
                startX: 0; startY: 0
                PathLine { x: root.radius; y: 0 }
                PathArc { x: 0; y: root.radius; radiusX: root.radius; radiusY: root.radius; direction: PathArc.Counterclockwise }
                PathLine { x: 0; y: 0 }
            }
        }
    }

    Instantiator {
        model: Workspace.screens
        delegate: Instantiator {
            id: perScreen
            required property var modelData
            readonly property bool hidden: root.fullscreenOn(modelData)
            model: 4
            delegate: Corner {
                required property int index
                area: perScreen.modelData.geometry
                quadrant: index
                hidden: perScreen.hidden
            }
        }
    }
}

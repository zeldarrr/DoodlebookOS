/*
    SPDX-License-Identifier: GPL-3.0-or-later

    Material 3 Expressive loading indicator: a shape that keeps morphing through the M3
    "MaterialShapes" family (soft burst → cookie 9 → pentagon → pill → sunny → cookie 4 → oval)
    on a spring while it rotates, like Android 16's LoadingIndicator.

    Each shape is a smooth radial profile r(θ) = 1 + a·cos(n·θ); a morph interpolates two
    profiles point by point (64 points), so the outline never breaks or kinks. One timer drives
    everything; it only runs while the indicator is visible and `running`.
*/
import QtQuick
import QtQuick.Shapes

Item {
    id: ind

    property bool running: true
    property color color: "white"
    property bool contained: false              // M3 "contained" variant: on a round container
    property color containerColor: Qt.rgba(color.r, color.g, color.b, 0.2)

    implicitWidth: 48
    implicitHeight: 48

    // n lobes, amplitude, phase (radians): the 7 shapes of the Android indicator
    readonly property var shapes: [
        { n: 10, a: 0.075, p: 0.0 },    // soft burst
        { n: 9,  a: 0.06,  p: 0.3 },    // cookie 9
        { n: 5,  a: 0.075, p: 0.0 },    // pentagon (rounded)
        { n: 2,  a: 0.2,   p: 0.0 },    // pill
        { n: 8,  a: 0.05,  p: 0.2 },    // sunny
        { n: 4,  a: 0.1,   p: 0.78 },   // cookie 4
        { n: 2,  a: 0.12,  p: 1.57 },   // oval
    ]
    property int step: 0
    property real morphMs: 1000                 // time since the current morph started
    property real spin: 0                       // degrees

    // spring for the morph (lively: damping 0.6, stiffness 400)
    function spring(ms) {
        if (ms <= 0) return 0;
        var t = ms / 1000, w = 20, z = 0.6, wd = w * 0.8;
        return 1 - Math.exp(-z * w * t) * (Math.cos(wd * t) + (z * w / wd) * Math.sin(wd * t));
    }

    readonly property var outline: {
        var from = shapes[step % shapes.length];
        var to = shapes[(step + 1) % shapes.length];
        var k = spring(morphMs);
        var size = Math.min(width, height) * (contained ? 0.79 : 1.0);
        var R = size / 2 / 1.2;                 // keeps lobes inside the box
        var cx = width / 2, cy = height / 2;
        var pts = [];
        for (var i = 0; i <= 64; i++) {
            var th = i / 64 * Math.PI * 2;
            var r1 = 1 + from.a * Math.cos(from.n * th + from.p);
            var r2 = 1 + to.a * Math.cos(to.n * th + to.p);
            var r = R * (r1 + (r2 - r1) * k);
            pts.push(Qt.point(cx + r * Math.cos(th), cy + r * Math.sin(th)));
        }
        return pts;
    }

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        visible: ind.contained
        color: ind.containerColor
    }

    Shape {
        anchors.fill: parent
        rotation: ind.spin
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: -1
            fillColor: ind.color
            PathPolyline { path: ind.outline }
        }
    }

    // one linear driver: 650 ms per morph, continuous rotation (+ a quarter turn per morph)
    NumberAnimation on morphMs {
        id: driver
        from: 0; to: 650; duration: 650
        loops: 1
        running: ind.running && ind.visible
        onFinished: {
            ind.step = (ind.step + 1) % ind.shapes.length;
            if (ind.running && ind.visible) driver.restart();
        }
    }
    NumberAnimation on spin {
        from: 0; to: 360; duration: 4700
        loops: Animation.Infinite
        running: ind.running && ind.visible
    }
}

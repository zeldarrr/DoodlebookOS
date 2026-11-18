/*
    SPDX-License-Identifier: GPL-3.0-or-later

    DoodlebookOS — Android-style screenshot thumbnail (run by doodlebookos-screenshot).

    1. a full-screen, click-through layer shows the capture over the screen, a soft flash, then
       the capture shrinks into the bottom-left corner on an M3 spring (~0.5 s);
    2. a small card takes over there: click → open the image, « Modifier » → annotate in
       Spectacle, × or swipe left → dismiss. It leaves by itself after 6 s (not while hovered).
    The process quits when the card is gone: nothing stays running between screenshots.
*/
import QtQuick
import QtQuick.Window
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import org.kde.layershell as LayerShell
import org.kde.plasma.plasma5support as P5Support

QtObject {
    id: app

    readonly property string file: {
        var a = Qt.application.arguments;
        var i = a.indexOf("--");
        return i >= 0 && i + 1 < a.length ? a[i + 1] : (a.length ? a[a.length - 1] : "");
    }
    readonly property url fileUrl: "file://" + encodeURI(file).replace(/#/g, "%23").replace(/\?/g, "%3F")

    readonly property bool animate: Kirigami.Units.longDuration > 1
    readonly property int margin: 20
    readonly property int pad: 6
    readonly property int thumbW: 208
    property real ratio: 0.625                 // height / width of the capture, read from the image

    // ── M3 Expressive springs (same as the widgets' motion.js) ─────────────────────────────
    function spring(ms, damping, stiffness) {
        if (ms <= 0) return 0;
        var t = ms / 1000, w = Math.sqrt(stiffness), v;
        if (damping >= 1) {
            v = 1 - Math.exp(-w * t) * (1 + w * t);
        } else {
            var wd = w * Math.sqrt(1 - damping * damping), e = Math.exp(-damping * w * t);
            v = 1 - e * (Math.cos(wd * t) + (damping * w / wd) * Math.sin(wd * t));
        }
        return Math.abs(1 - v) < 0.0005 ? 1 : v;
    }
    function spatial(ms) { return spring(ms, 0.8, 380); }
    function effects(ms) { return spring(ms, 1, 1600); }

    // shared colours (Material You via the KDE colour scheme)
    readonly property color surface: Qt.tint(Kirigami.Theme.backgroundColor, Qt.rgba(accent.r, accent.g, accent.b, 0.08))
    readonly property color accent: Kirigami.Theme.highlightColor
    readonly property color onSurface: Kirigami.Theme.textColor

    function q(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'"; }
    function run(cmd) { exec.connectSource("sh -c " + q(cmd) + " #" + Date.now()); }
    property var exec: P5Support.DataSource {
        engine: "executable"
        onNewData: (source, data) => disconnectSource(source)
    }

    // ── 1. full-screen shrink ──────────────────────────────────────────────────────────────
    property var shrink: Window {
        id: shrink
        flags: Qt.FramelessWindowHint | Qt.WindowTransparentForInput | Qt.WindowDoesNotAcceptFocus
        color: "transparent"
        visible: true

        LayerShell.Window.scope: "doodlebookos-screenshot"
        LayerShell.Window.layer: LayerShell.Window.LayerOverlay
        LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom
                                   | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
        LayerShell.Window.exclusionZone: -1
        LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone

        property real ms: 0
        NumberAnimation on ms {
            id: shrinkAnim
            running: false
            from: 0; to: 560
            duration: app.animate ? 560 : 0
            onFinished: { card.visible = true; handoff.start(); }
        }
        Timer { id: handoff; interval: 60; onTriggered: shrink.visible = false }

        // where the card's image will sit (bottom-left corner)
        readonly property real tw: app.thumbW
        readonly property real th: app.thumbW * app.ratio
        readonly property real tx: app.margin + app.pad
        readonly property real ty: height - app.margin - card.height + app.pad
        readonly property real k: app.spatial(ms - 90)

        Item {
            id: shot
            x: shrink.tx * shrink.k
            y: shrink.ty * shrink.k
            width: shrink.width + (shrink.tw - shrink.width) * shrink.k
            height: shrink.height + (shrink.th - shrink.height) * shrink.k
            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: shotMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
                shadowEnabled: true
                shadowOpacity: 0.35 * shrink.k
                shadowBlur: 0.6
            }
            Image {
                id: img
                anchors.fill: parent
                source: app.fileUrl
                asynchronous: false
                cache: false
                smooth: true
                mipmap: true
                fillMode: Image.Stretch
                onStatusChanged: if (status === Image.Ready) {
                    if (implicitWidth > 0) app.ratio = implicitHeight / implicitWidth;
                    shrinkAnim.start();
                } else if (status === Image.Error) {
                    Qt.quit();
                }
            }
        }
        Rectangle {
            id: shotMask
            width: shot.width
            height: shot.height
            radius: 16 * shrink.k
            visible: false
            layer.enabled: true
        }
        // the soft Android flash
        Rectangle {
            anchors.fill: parent
            color: "white"
            opacity: 0.35 * (1 - app.effects(shrink.ms - 40)) * (shrink.ms > 0 ? 1 : 0)
        }
    }

    // ── 2. the card ────────────────────────────────────────────────────────────────────────
    property var card: Window {
        id: card
        flags: Qt.FramelessWindowHint | Qt.WindowDoesNotAcceptFocus
        color: "transparent"
        visible: false
        width: app.thumbW + 2 * app.pad
        height: Math.round(app.thumbW * app.ratio) + 2 * app.pad + 48

        LayerShell.Window.scope: "doodlebookos-screenshot-card"
        LayerShell.Window.layer: LayerShell.Window.LayerOverlay
        LayerShell.Window.anchors: LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorBottom
        LayerShell.Window.margins.left: app.margin
        LayerShell.Window.margins.bottom: app.margin
        LayerShell.Window.exclusionZone: -1
        LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone

        property real ms: 0
        NumberAnimation on ms { id: cardIn; running: card.visible; from: 0; to: 600; duration: app.animate ? 600 : 0 }
        property real outT: 0
        NumberAnimation on outT {
            id: cardOut
            running: false
            to: 1
            duration: app.animate ? 240 : 0
            easing.type: Easing.InCubic
            onFinished: Qt.quit()
        }
        function dismiss() { if (!cardOut.running) { life.stop(); cardOut.start(); } }

        Timer { id: life; interval: 6000; running: card.visible && !hover.hovered; onTriggered: card.dismiss() }

        Rectangle {
            id: body
            width: card.width
            height: card.height
            radius: 22
            color: app.surface
            border.width: 1
            border.color: Qt.rgba(app.onSurface.r, app.onSurface.g, app.onSurface.b, 0.10)
            // swipe left to dismiss (like Android)
            property real dragX: 0
            x: dragX - (card.width + app.margin + dragX) * card.outT
            opacity: 1 - card.outT
            HoverHandler { id: hover }
            DragHandler {
                id: drag
                target: null
                yAxis.enabled: false
                onActiveTranslationChanged: body.dragX = Math.min(0, activeTranslation.x)
                onActiveChanged: if (!active) {
                    if (body.dragX < -48) card.dismiss();
                    else body.dragX = 0;
                }
            }

            Item {
                id: thumb
                x: app.pad
                y: app.pad
                width: app.thumbW
                height: Math.round(app.thumbW * app.ratio)
                layer.enabled: true
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: thumbMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1.0
                }
                Image {
                    anchors.fill: parent
                    source: app.fileUrl
                    sourceSize.width: app.thumbW * 2
                    smooth: true
                    cache: false
                    scale: thumbTap.pressed ? 0.97 : 1
                    Behavior on scale { NumberAnimation { duration: app.animate ? 160 : 0; easing.type: Easing.OutBack } }
                }
                TapHandler {
                    id: thumbTap
                    onTapped: { Qt.openUrlExternally(app.fileUrl); card.dismiss(); }
                }
            }
            Rectangle {
                id: thumbMask
                width: thumb.width
                height: thumb.height
                radius: 16
                visible: false
                layer.enabled: true
            }

            Row {
                anchors.left: parent.left
                anchors.leftMargin: app.pad + 2
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 8
                spacing: 8
                // buttons rise in after the hand-off, M3 Expressive spring
                opacity: app.effects(card.ms - 80)
                transform: Translate { y: (1 - app.spatial(card.ms - 40)) * 14 }

                Rectangle {
                    id: edit
                    height: 34
                    width: editLabel.implicitWidth + 30
                    radius: editTap.pressed ? 10 : 17
                    Behavior on radius { NumberAnimation { duration: app.animate ? 200 : 0; easing.type: Easing.OutBack } }
                    color: Qt.tint(app.surface, Qt.rgba(app.accent.r, app.accent.g, app.accent.b, editHover.hovered ? 0.34 : 0.24))
                    Text {
                        id: editLabel
                        anchors.centerIn: parent
                        text: "Modifier"
                        color: app.onSurface
                        font.family: "Google Sans Flex"
                        font.pixelSize: 14
                        font.weight: Font.Medium
                    }
                    HoverHandler { id: editHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        id: editTap
                        onTapped: { app.run("spectacle -E " + app.q(app.file)); card.dismiss(); }
                    }
                }
            }
            Rectangle {
                // close
                anchors.right: parent.right
                anchors.rightMargin: app.pad + 2
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 8
                width: 34
                height: 34
                radius: 17
                color: closeHover.hovered ? Qt.rgba(app.onSurface.r, app.onSurface.g, app.onSurface.b, 0.10) : "transparent"
                opacity: app.effects(card.ms - 120)
                Kirigami.Icon {
                    anchors.centerIn: parent
                    width: 18
                    height: 18
                    source: "window-close-symbolic"
                    color: app.onSurface
                    isMask: true
                }
                HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: card.dismiss() }
            }
        }
    }
}

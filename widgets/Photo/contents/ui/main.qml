/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * DoodlebookOS Image: one picture (or a folder slideshow), decoded once at the widget's size.
 * The slideshow timer only runs when a folder and an interval are set; nothing polls otherwise.
 */
import QtQuick
import QtCore
import QtQuick.Dialogs
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5

PlasmoidItem {
    id: root
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    preferredRepresentation: fullRepresentation

    readonly property var cfg: Plasmoid.configuration
    function q(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'"; }

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: "Choisir une image…"
            icon.name: "insert-image"
            onTriggered: picker.open()
        },
        PlasmaCore.Action {
            text: "Image suivante"
            icon.name: "go-next"
            visible: root.slides.length > 1
            onTriggered: root.nextSlide()
        }
    ]

    FileDialog {
        id: picker
        title: "Choisir une image"
        nameFilters: ["Images (*.png *.jpg *.jpeg *.webp *.avif *.jxl *.heic *.bmp *.gif *.svg)", "Tous les fichiers (*)"]
        currentFolder: StandardPaths.writableLocation(StandardPaths.PicturesLocation)
        onAccepted: Plasmoid.configuration.imagePath = selectedFile.toString()
    }

    // ── helpers run once (shapes) or when the slideshow folder changes ──
    property var shapePaths: ({})
    property var slides: []
    property int slideIndex: 0
    readonly property string slideFolder: String(cfg.slideshowFolder || "").replace(/^file:\/\//, "")

    P5.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        property var callbacks: ({})
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName);
            var cb = callbacks[sourceName];
            delete callbacks[sourceName];
            if (cb) cb(String(data["stdout"] || ""));
        }
    }
    function run(cmd, cb) {
        var src = cmd + " # " + Date.now() + Math.random();
        exec.callbacks[src] = cb;
        exec.connectSource(src);
    }
    function loadShapes() {
        run("cat \"$HOME/.config/doodlebookos/shape.json\"", function (out) {
            try {
                var d = JSON.parse(out), m = {};
                for (var i = 0; i < d.shapes.length; ++i) m[d.shapes[i].name] = d.shapes[i].path;
                root.shapePaths = m;
            } catch (e) {}
        });
    }
    function loadSlides() {
        if (slideFolder.length === 0) { slides = []; return; }
        run("find " + q(decodeURIComponent(slideFolder)) + " -maxdepth 1 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.avif' -o -iname '*.jxl' -o -iname '*.heic' -o -iname '*.gif' -o -iname '*.bmp' \\) | sort",
            function (out) {
                var list = out.split("\n").filter(function (l) { return l.length > 0; });
                root.slides = list;
                root.slideIndex = list.length > 0 ? Math.floor(Math.random() * list.length) : 0;
            });
    }
    function nextSlide() {
        if (slides.length > 1) slideIndex = (slideIndex + 1) % slides.length;
    }
    onSlideFolderChanged: loadSlides()
    Component.onCompleted: { loadShapes(); loadSlides(); }

    Timer {
        interval: Math.max(1, root.cfg.slideshowMinutes) * 60 * 1000
        repeat: true
        running: root.slides.length > 1 && root.cfg.slideshowMinutes > 0
        onTriggered: root.nextSlide()
    }

    readonly property string currentSource: slides.length > 0
        ? "file://" + slides[Math.min(slideIndex, slides.length - 1)]
        : cfg.imagePath

    fullRepresentation: PhotoCard {
        source: root.currentSource
        shapePath: root.cfg.shape !== "rounded" && root.shapePaths[root.cfg.shape] ? root.shapePaths[root.cfg.shape] : ""
        onPick: picker.open()
        onNext: root.nextSlide()
    }
}

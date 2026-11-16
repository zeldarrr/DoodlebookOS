/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * DoodlebookOS Jeux: installed Steam games (contents/code/games.py), read at load and every 15 min.
 */
import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5

PlasmoidItem {
    id: root
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    preferredRepresentation: fullRepresentation

    property var games: []
    property string lastJson: ""
    readonly property string helperPath: decodeURIComponent(Qt.resolvedUrl("../code/games.py").toString().replace(/^file:\/\//, ""))
    function q(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'"; }

    P5.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName);
            var txt = String(data["stdout"] || "").trim();
            if (txt === root.lastJson) return;
            try { var g = JSON.parse(txt); } catch (e) { return; }
            if (!Array.isArray(g)) return;
            root.lastJson = txt;
            root.games = g;
        }
    }
    function refresh() { exec.connectSource("python3 " + q(helperPath) + " # " + Date.now()); }

    Timer { interval: 15 * 60 * 1000; repeat: true; running: true; onTriggered: root.refresh() }
    Component.onCompleted: refresh()

    fullRepresentation: GamesCard {
        games: root.games
        onLaunch: id => Qt.openUrlExternally("steam://rungameid/" + id)
        onOpenLibrary: Qt.openUrlExternally("steam://nav/games")
    }
}

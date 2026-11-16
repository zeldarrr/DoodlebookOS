/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * DoodlebookOS Stockage: disk usage (contents/code/storage.py), read at load, every 10 min and on click.
 */
import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5

PlasmoidItem {
    id: root
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    preferredRepresentation: fullRepresentation

    property var disks: []
    property string lastJson: ""
    readonly property string helperPath: decodeURIComponent(Qt.resolvedUrl("../code/storage.py").toString().replace(/^file:\/\//, ""))
    function q(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'"; }

    P5.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName);
            var txt = String(data["stdout"] || "").trim();
            if (txt === root.lastJson) return;
            try { var d = JSON.parse(txt); } catch (e) { return; }
            if (!Array.isArray(d)) return;
            root.lastJson = txt;
            root.disks = d;
        }
    }
    function refresh() { exec.connectSource("python3 " + q(helperPath) + " # " + Date.now()); }

    Timer { interval: Math.max(1, Plasmoid.configuration.refreshMinutes) * 60 * 1000; repeat: true; running: true; onTriggered: root.refresh() }
    Component.onCompleted: refresh()

    fullRepresentation: StorageCard {
        disks: root.disks
        onRefresh: root.refresh()
        onOpen: path => Qt.openUrlExternally("file://" + path)
    }
}

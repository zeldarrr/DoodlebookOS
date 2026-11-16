// SPDX-License-Identifier: GPL-3.0-or-later
// DoodlebookOS game mode — detection, inside KWin, driven only by window signals (no polling).
// A window counts as a game when it is a Steam/Proton/Wine/gamescope window, or when it goes
// fullscreen / covers its whole screen and is not a known non-game (browser, video player, office,
// editor, chat…). Game mode stays on while at least one game window exists (alt-tab doesn't flip
// it). The work itself is done by ~/.local/bin/doodlebookos-gamemode, started through systemd.
import QtQuick
import org.kde.kwin

Item {
    id: root

    property var games: ({})          // internalId -> true
    property int gameCount: 0
    property bool sentOn: false
    property var tracked: ({})        // internalId -> [[signal, handler], …] (disconnected on unload)

    readonly property var notGames: /^(zen|app\.zen_browser|firefox|org\.mozilla|librewolf|chromium|chrome|google-chrome|brave|vivaldi|opera|vlc|mpv|haruna|celluloid|smplayer|totem|io\.github\.celluloid|org\.kde\.[a-z]+|dolphin|okular|gwenview|kdenlive|konsole|kate|kwrite|elisa|spectacle|libreoffice|soffice|onlyoffice|desktopeditors|obs|com\.obsproject|vesktop|discord|dev\.vencord|steam$|steamwebhelper|code|codium|krita|inkscape|gimp|blender|plasmashell|krunner|xdg-desktop-portal|org\.freedesktop|moonlight|com\.moonlight|sunshine|freetube|jellyfin|kodi)/i

    function lc(s) { return String(s || "").toLowerCase(); }
    function coversOutput(w) {
        var o = w.output;
        if (!o) return false;
        var g = o.geometry, f = w.frameGeometry;
        return f.x <= g.x && f.y <= g.y && f.x + f.width >= g.x + g.width && f.y + f.height >= g.y + g.height;
    }
    function isGame(w) {
        if (!w || !w.normalWindow || w.deleted) return false;
        var cls = lc(w.resourceClass), df = lc(w.desktopFileName);
        if (/^steam_app_\d+/.test(cls) || /\.exe$/.test(cls) || cls === "gamescope" || /^steam_app_/.test(df)) return true;
        if (root.notGames.test(cls) || root.notGames.test(df)) return false;
        return w.fullScreen || coversOutput(w);
    }

    function evaluate(w) {
        var id = String(w.internalId);
        if (games[id] || !isGame(w)) return;      // sticky until the window closes
        var g = games; g[id] = true; games = g;
        gameCount++;
        settle.restart();
    }
    function track(w) {
        if (!w || !w.normalWindow) return;
        var id = String(w.internalId);
        if (tracked[id]) return;
        var onFs = function () { root.evaluate(w); };
        var onGeo = function () { if (!root.games[id]) root.evaluate(w); };
        w.fullScreenChanged.connect(onFs);
        w.frameGeometryChanged.connect(onGeo);
        tracked[id] = [[w.fullScreenChanged, onFs], [w.frameGeometryChanged, onGeo]];
        evaluate(w);
    }
    function forget(w) {
        var id = String(w.internalId);
        delete tracked[id];
        if (games[id]) {
            var g = games; delete g[id]; games = g;
            gameCount = Math.max(0, gameCount - 1);
            settle.restart();
        }
    }

    // on after 1.5 s (skips windows that flash fullscreen while mapping), off 3 s after the last game
    Timer {
        id: settle
        interval: root.gameCount > 0 ? 1500 : 3000
        onTriggered: {
            if (root.gameCount > 0 && !root.sentOn) { root.sentOn = true; root.run("auto-on"); }
            else if (root.gameCount === 0 && root.sentOn) { root.sentOn = false; root.run("auto-off"); }
        }
    }

    DBusCall {
        id: unit
        service: "org.freedesktop.systemd1"
        path: "/org/freedesktop/systemd1"
        dbusInterface: "org.freedesktop.systemd1.Manager"
        method: "StartUnit"
    }
    function run(cmd) {
        unit.arguments = ["doodlebookos-gamemode@" + cmd + ".service", "replace"];
        unit.call();
    }

    ShortcutHandler {
        name: "DoodlebookOS Game Mode"
        text: "Mode jeu DoodlebookOS (activer / désactiver)"
        sequence: "Meta+Shift+G"
        onActivated: root.run("toggle")
    }

    Connections {
        target: Workspace
        function onWindowAdded(w) { root.track(w); }
        function onWindowRemoved(w) { root.forget(w); }
    }

    // JS handlers connected to windows outlive the script: drop them when it is unloaded
    Component.onDestruction: {
        for (var id in tracked) {
            var list = tracked[id];
            for (var i = 0; i < list.length; i++) {
                try { list[i][0].disconnect(list[i][1]); } catch (e) {}
            }
        }
        tracked = {};
    }

    Component.onCompleted: {
        run("session");
        var list = Workspace.windows;
        for (var i = 0; i < list.length; i++) track(list[i]);
    }
}

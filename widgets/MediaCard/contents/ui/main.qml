/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * DoodlebookOS Lecteur: MPRIS (event driven); the position is refreshed once a second only while
 * something is playing.
 */
import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.private.mpris as Mpris

PlasmoidItem {
    id: root
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    preferredRepresentation: fullRepresentation

    Mpris.Mpris2Model { id: mpris }
    // the multiplexer sometimes keeps an idle player (e.g. Bluetooth headphones without metadata),
    // so pick ourselves: a playing player first, else the multiplexer's choice, else any with a title
    Instantiator {
        id: players
        model: mpris
        delegate: QtObject {
            required property var container
            required property bool isMultiplexer
            readonly property bool isPlaying: container ? container.playbackStatus === Mpris.PlaybackStatus.Playing : false
            readonly property bool hasTrack: container ? String(container.track || "").length > 0 : false
        }
    }
    readonly property var player: {
        var cur = mpris.currentPlayer;
        var fallback = cur && String(cur.track || "").length > 0 ? cur : null;
        for (var i = 0; i < players.count; i++) {
            var o = players.objectAt(i);
            if (!o || o.isMultiplexer || !o.hasTrack) continue;
            if (o.isPlaying) return o.container;
            if (!fallback) fallback = o.container;
        }
        return fallback;
    }
    readonly property bool playing: player ? player.playbackStatus === Mpris.PlaybackStatus.Playing : false

    Timer {
        interval: 1000
        repeat: true
        running: root.playing
        onTriggered: if (root.player) root.player.updatePosition()
    }

    fullRepresentation: MediaCardView {
        hasMedia: root.player !== null && String(root.player.track || "").length > 0
        track: root.player ? String(root.player.track || "") : ""
        artist: root.player ? String(root.player.artist || "") : ""
        artUrl: root.player ? String(root.player.artUrl || "") : ""
        playing: root.playing
        position: root.player ? Number(root.player.position || 0) : 0
        length: root.player ? Number(root.player.length || 0) : 0
        canNext: root.player ? root.player.canGoNext : false
        canPrev: root.player ? root.player.canGoPrevious : false
        onPlayPause: if (root.player) root.player.PlayPause()
        onNext: if (root.player) root.player.Next()
        onPrev: if (root.player) root.player.Previous()
        onRaise: if (root.player) root.player.Raise()
    }
}

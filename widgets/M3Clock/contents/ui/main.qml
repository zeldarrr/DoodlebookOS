/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * DoodlebookOS Horloge: wakes once per minute, aligned on the minute (Plasma's shared time engine,
 * which also follows suspend/resume and time zone changes).
 */
import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5

PlasmoidItem {
    id: root
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    preferredRepresentation: fullRepresentation

    P5.DataSource {
        id: timeSource
        engine: "time"
        connectedSources: ["Local"]
        interval: 60000
        intervalAlignment: P5.Types.AlignToMinute
    }

    fullRepresentation: ClockCard {
        now: timeSource.data["Local"] && timeSource.data["Local"]["DateTime"] ? timeSource.data["Local"]["DateTime"] : new Date()
    }
}

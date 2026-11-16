/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * DoodlebookOS Calendrier: the grid is only rebuilt when the day (or the shown month) changes.
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
    readonly property var now: timeSource.data["Local"] && timeSource.data["Local"]["DateTime"] ? timeSource.data["Local"]["DateTime"] : new Date()
    // only changes once a day, so the grid isn't rebuilt every minute
    readonly property string dayKey: Qt.formatDate(now, "yyyy-MM-dd")

    fullRepresentation: CalendarCard { dayKey: root.dayKey }
}

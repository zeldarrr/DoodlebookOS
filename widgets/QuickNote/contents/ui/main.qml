/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * DoodlebookOS Note: saved to the applet config 700 ms after the last keystroke and on focus loss.
 */
import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore

PlasmoidItem {
    id: root
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    preferredRepresentation: fullRepresentation

    fullRepresentation: NoteCard {
        initialText: Plasmoid.configuration.noteText
        onSave: text => { if (Plasmoid.configuration.noteText !== text) Plasmoid.configuration.noteText = text; }
    }
}

/*
    SPDX-License-Identifier: GPL-3.0-or-later

    KDE's Switch (org.kde.desktop) with the Material 3 indicator. Placement of the indicator
    as in KDE's Switch.qml (SPDX: 2017 Marco Martin, The Qt Company; LGPL-3.0-only OR GPL-2.0-or-later).
*/
import QtQuick
import org.kde.desktop as KD

KD.Switch {
    id: control

    indicator: M3SwitchIndicator {
        x: control.contentItem !== null && control.contentItem.width > 0
           ? (control.mirrored ? control.width - width - control.rightPadding : control.leftPadding)
           : control.leftPadding + (control.availableWidth - width) / 2
        y: (control.contentItem !== null && (control.contentItem instanceof Text || control.contentItem instanceof TextEdit)
            && control.contentItem.lineCount > 1)
           ? control.topPadding
           : control.topPadding + Math.round((control.availableHeight - height) / 2)
        control: control
    }
}

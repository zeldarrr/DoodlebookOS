/*
    SPDX-License-Identifier: GPL-3.0-or-later

    KDE's SwitchDelegate (org.kde.desktop) with the Material 3 indicator. Placement of the
    indicator as in KDE's SwitchDelegate.qml (SPDX: 2017 Marco Martin, The Qt Company, 2025 Nate
    Graham; LGPL-3.0-only OR GPL-2.0-or-later).
*/
import QtQuick
import QtQuick.Templates as T
import org.kde.desktop as KD

KD.SwitchDelegate {
    id: controlRoot

    indicator: M3SwitchIndicator {
        x: !controlRoot.mirrored ? controlRoot.horizontalPadding : controlRoot.width - width - controlRoot.horizontalPadding
        y: controlRoot.topPadding + (controlRoot.display === T.AbstractButton.TextUnderIcon ? 0 : (controlRoot.availableHeight - height) / 2)
        control: controlRoot
    }
}

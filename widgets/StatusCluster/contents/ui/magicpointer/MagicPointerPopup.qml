/*
    SPDX-FileCopyrightText: 2026 DoodlebookOS
    SPDX-License-Identifier: GPL-3.0-or-later
*/

import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import "../metrics" as LocalMetrics

Item {
    id: magicPointerRoot

    implicitWidth: LocalMetrics.Metrics.legacyDp(160)
    implicitHeight: LocalMetrics.Metrics.legacyDp(56)

    QQC2.Label {
        anchors.centerIn: parent
        text: "Magic Pointer"
        font.family: "Google Sans Flex"
        font.weight: Font.DemiBold
        font.pixelSize: LocalMetrics.Metrics.legacyDp(13)
        color: Kirigami.Theme.textColor
    }
}

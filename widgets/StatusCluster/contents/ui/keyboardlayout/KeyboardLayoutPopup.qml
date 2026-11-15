/*
    SPDX-FileCopyrightText: 2026 DoodlebookOS
    SPDX-License-Identifier: GPL-3.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import "../metrics" as LocalMetrics

Item {
    id: keyboardLayoutPopupRoot

    implicitWidth: LocalMetrics.Metrics.legacyDp(128.0)
    implicitHeight: LocalMetrics.Metrics.legacyDp(44.8)
}

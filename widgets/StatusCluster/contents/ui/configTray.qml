/*
    SPDX-FileCopyrightText: 2026 Maciej Kujawiński <maciek.kujawinski@gmail.com>
    SPDX-License-Identifier: GPL-3.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCMUtils

KCMUtils.SimpleKCM {
    id: page

    property alias cfg_trayMaxInlineIcons: maxInlineSpin.value
    property alias cfg_trayShowPassive: showPassiveCheck.checked
    property alias cfg_trayHiddenIds: hiddenIdsField.text

    Kirigami.FormLayout {
        QQC2.SpinBox {
            id: maxInlineSpin
            Kirigami.FormData.label: "Maks. slotów w pasku:"
            from: 1
            to: 8
        }

        QQC2.CheckBox {
            id: showPassiveCheck
            Kirigami.FormData.label: "Ikony w tle:"
            text: "Pokazuj pasywne aplikacje (Status: Passive)"
        }

        QQC2.TextField {
            id: hiddenIdsField
            Kirigami.FormData.label: "Ukryte ID:"
            placeholderText: "np. org.kde.kdeconnect, steam"
            Layout.fillWidth: true
        }
    }
}

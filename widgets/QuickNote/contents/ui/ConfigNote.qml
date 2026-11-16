/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCMUtils

KCMUtils.SimpleKCM {
    id: page
    property string cfg_textAlign
    property alias cfg_monospace: monoBox.checked
    property alias cfg_placeholder: placeholderField.text
    property alias cfg_padding: padSlider.value

    Kirigami.FormLayout {
        QQC2.ComboBox {
            id: alignBox
            Kirigami.FormData.label: "Alignement :"
            model: [{ value: "left", text: "À gauche" }, { value: "center", text: "Centré" }, { value: "right", text: "À droite" }]
            textRole: "text"
            valueRole: "value"
            Component.onCompleted: currentIndex = Math.max(0, indexOfValue(page.cfg_textAlign))
            onActivated: page.cfg_textAlign = currentValue
        }
        QQC2.CheckBox { id: monoBox; Kirigami.FormData.label: "Police :"; text: "Chasse fixe (code, listes)" }
        RowLayout {
            Kirigami.FormData.label: "Marges intérieures :"
            QQC2.Slider { id: padSlider; from: 8; to: 48; stepSize: 2; Layout.preferredWidth: Kirigami.Units.gridUnit * 12 }
            QQC2.Label { text: Math.round(padSlider.value) + " px" }
        }
        QQC2.TextField { id: placeholderField; Kirigami.FormData.label: "Texte d'attente :"; placeholderText: "Écris quelque chose…" }
    }
}

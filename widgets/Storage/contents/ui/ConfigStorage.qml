/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCMUtils

KCMUtils.SimpleKCM {
    property alias cfg_barHeight: barSlider.value
    property alias cfg_showPercent: pctBox.checked
    property alias cfg_showFreeText: freeBox.checked
    property alias cfg_refreshMinutes: refreshSpin.value
    property alias cfg_warnPercent: warnSlider.value
    property alias cfg_compact: compactBox.checked

    Kirigami.FormLayout {
        RowLayout {
            Kirigami.FormData.label: "Épaisseur des barres :"
            QQC2.Slider { id: barSlider; from: 4; to: 32; stepSize: 2; Layout.preferredWidth: Kirigami.Units.gridUnit * 12 }
            QQC2.Label { text: Math.round(barSlider.value) + " px" }
        }
        QQC2.CheckBox { id: pctBox; Kirigami.FormData.label: "Afficher :"; text: "Pourcentage dans la barre" }
        QQC2.CheckBox { id: freeBox; text: "Espace libre / total" }
        QQC2.CheckBox { id: compactBox; text: "Mode compact (lignes serrées)" }
        RowLayout {
            Kirigami.FormData.label: "Alerte (rouge) à partir de :"
            QQC2.Slider { id: warnSlider; from: 50; to: 100; stepSize: 1; Layout.preferredWidth: Kirigami.Units.gridUnit * 12 }
            QQC2.Label { text: Math.round(warnSlider.value) + " %" }
        }
        QQC2.SpinBox { id: refreshSpin; Kirigami.FormData.label: "Actualiser toutes les (min) :"; from: 1; to: 240 }
    }
}

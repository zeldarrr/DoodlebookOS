/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCMUtils
import org.kde.iconthemes as KIconThemes

KCMUtils.SimpleKCM {
    property alias cfg_showLauncherButton: launcherBox.checked
    property alias cfg_showPhoneHub: phoneBox.checked
    property alias cfg_showSeparator: sepBox.checked
    property alias cfg_showTooltips: tipBox.checked
    property alias cfg_themedIcons: tintBox.checked
    property alias cfg_dockIconScale: iconSlider.value
    property alias cfg_dockSpacing: spaceSlider.value
    property alias cfg_launcherIcon: iconField.text

    Kirigami.FormLayout {
        QQC2.CheckBox { id: launcherBox; Kirigami.FormData.label: "Boutons :"; text: "Bouton du lanceur (« D »)" }
        QQC2.CheckBox { id: phoneBox; text: "Bouton du téléphone (Phone Hub)" }
        QQC2.CheckBox { id: sepBox; text: "Séparateur" }
        QQC2.CheckBox { id: tipBox; text: "Infobulles au survol" }
        RowLayout {
            Kirigami.FormData.label: "Icône du lanceur :"
            Kirigami.Icon { source: iconField.text.length > 0 ? iconField.text : "start-here"; Layout.preferredWidth: 22; Layout.preferredHeight: 22 }
            QQC2.TextField { id: iconField; placeholderText: "« D » DoodlebookOS" }
            QQC2.Button { text: "Choisir…"; icon.name: "document-open"; onClicked: iconDialog.open() }
            QQC2.Button { icon.name: "edit-clear"; visible: iconField.text.length > 0; onClicked: iconField.text = "" }
        }

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Icônes" }
        RowLayout {
            Kirigami.FormData.label: "Taille :"
            QQC2.Slider { id: iconSlider; from: 60; to: 125; stepSize: 5; Layout.preferredWidth: Kirigami.Units.gridUnit * 12 }
            QQC2.Label { text: Math.round(iconSlider.value) + " %" }
        }
        RowLayout {
            Kirigami.FormData.label: "Espacement :"
            QQC2.Slider { id: spaceSlider; from: 0; to: 200; stepSize: 10; Layout.preferredWidth: Kirigami.Units.gridUnit * 12 }
            QQC2.Label { text: Math.round(spaceSlider.value) + " %" }
        }
        QQC2.CheckBox {
            id: tintBox
            Kirigami.FormData.label: "Teinte :"
            text: "Recolorer les icônes (filtre, inutile avec le thème Material You)"
        }
        QQC2.Label {
            Kirigami.FormData.label: "Forme :"
            text: "Clic droit sur le dock → bouton de forme (ou « doodlebookos-icons shape »)"
            opacity: 0.7
            wrapMode: Text.WordWrap
        }
    }

    KIconThemes.IconDialog {
        id: iconDialog
        onIconNameChanged: if (iconDialog.iconName) iconField.text = iconDialog.iconName
    }
}

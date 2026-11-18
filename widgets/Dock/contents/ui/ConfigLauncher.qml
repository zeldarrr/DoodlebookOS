/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCMUtils

KCMUtils.SimpleKCM {
    property alias cfg_popupWidth: widthSpin.value
    property alias cfg_numberColumns: colSpin.value
    property alias cfg_launcherIconSize: iconSpin.value
    property alias cfg_launcherRowHeight: rowSpin.value
    property alias cfg_launcherHeight: heightSlider.value
    property alias cfg_launcherPadding: padSpin.value
    property alias cfg_showRecentFiles: recentBox.checked
    property alias cfg_dimBackground: dimBox.checked
    property alias cfg_launcherFullscreen: fullBox.checked
    property alias cfg_useSystemFontSettings: sysFontBox.checked
    property alias cfg_fontFamily: fontField.text
    property alias cfg_fontSize: fontSpin.value

    Kirigami.FormLayout {
        QQC2.SpinBox { id: widthSpin; Kirigami.FormData.label: "Largeur (px) :"; from: 420; to: 1600; stepSize: 20 }
        RowLayout {
            Kirigami.FormData.label: "Hauteur :"
            QQC2.Slider { id: heightSlider; from: 40; to: 95; stepSize: 1; Layout.preferredWidth: Kirigami.Units.gridUnit * 12 }
            QQC2.Label { text: Math.round(heightSlider.value) + " % de l'écran" }
        }
        QQC2.SpinBox { id: colSpin; Kirigami.FormData.label: "Colonnes :"; from: 3; to: 12 }
        QQC2.SpinBox { id: iconSpin; Kirigami.FormData.label: "Taille des icônes (px) :"; from: 28; to: 96; stepSize: 2 }
        QQC2.SpinBox { id: rowSpin; Kirigami.FormData.label: "Hauteur d'une ligne (px) :"; from: 60; to: 160; stepSize: 2 }
        QQC2.SpinBox { id: padSpin; Kirigami.FormData.label: "Marges (px) :"; from: 4; to: 48; stepSize: 2 }

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Contenu" }
        QQC2.CheckBox { id: recentBox; Kirigami.FormData.label: "Afficher :"; text: "Fichiers récents" }
        QQC2.CheckBox { id: dimBox; text: "Assombrir le bureau derrière" }
        QQC2.CheckBox { id: fullBox; text: "Plein écran" }

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Police" }
        QQC2.CheckBox { id: sysFontBox; Kirigami.FormData.label: "Police :"; text: "Utiliser la police du système" }
        QQC2.TextField { id: fontField; Kirigami.FormData.label: "Famille :"; enabled: !sysFontBox.checked; placeholderText: "Google Sans Flex" }
        QQC2.SpinBox { id: fontSpin; Kirigami.FormData.label: "Taille :"; enabled: !sysFontBox.checked; from: 7; to: 24 }
    }
}

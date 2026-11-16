/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * DoodlebookOS — "Apparence" page shared by the desktop widgets (same file in each widget package).
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCMUtils
import org.kde.kquickcontrols as KQuickControls
import org.kde.iconthemes as KIconThemes

KCMUtils.SimpleKCM {
    id: page

    property string cfg_colorRole
    property string cfg_customColor
    property alias cfg_bgOpacity: opacitySlider.value
    property alias cfg_cornerRadius: radiusSlider.value
    property alias cfg_outline: outlineBox.checked
    property alias cfg_fontScale: fontSlider.value

    readonly property var roles: [
        { value: "surface", text: "Surface" },
        { value: "surfaceHigh", text: "Surface (plus marquée)" },
        { value: "primary", text: "Conteneur principal" },
        { value: "secondary", text: "Conteneur secondaire" },
        { value: "tertiary", text: "Conteneur tertiaire" },
        { value: "accent", text: "Couleur d'accent" },
        { value: "custom", text: "Couleur au choix" }
    ]

    Kirigami.FormLayout {
        QQC2.ComboBox {
            id: roleBox
            Kirigami.FormData.label: "Couleur de la carte :"
            model: page.roles
            textRole: "text"
            valueRole: "value"
            Component.onCompleted: currentIndex = Math.max(0, indexOfValue(page.cfg_colorRole))
            onActivated: page.cfg_colorRole = currentValue
        }
        KQuickControls.ColorButton {
            Kirigami.FormData.label: "Couleur :"
            visible: roleBox.currentValue === "custom"
            showAlphaChannel: false
            color: page.cfg_customColor.length > 0 ? page.cfg_customColor : Kirigami.Theme.highlightColor
            onAccepted: (c) => page.cfg_customColor = c.toString()
        }
        RowLayout {
            Kirigami.FormData.label: "Opacité du fond :"
            QQC2.Slider { id: opacitySlider; from: 0; to: 100; stepSize: 5; Layout.preferredWidth: Kirigami.Units.gridUnit * 12 }
            QQC2.Label { text: Math.round(opacitySlider.value) + " %" }
        }
        RowLayout {
            Kirigami.FormData.label: "Arrondi des coins :"
            QQC2.Slider { id: radiusSlider; from: 0; to: 64; stepSize: 2; Layout.preferredWidth: Kirigami.Units.gridUnit * 12 }
            QQC2.Label { text: Math.round(radiusSlider.value) + " px" }
        }
        QQC2.CheckBox {
            id: outlineBox
            Kirigami.FormData.label: "Contour :"
            text: "Fin contour autour de la carte"
        }
        RowLayout {
            Kirigami.FormData.label: "Taille du texte :"
            QQC2.Slider { id: fontSlider; from: 70; to: 170; stepSize: 5; Layout.preferredWidth: Kirigami.Units.gridUnit * 12 }
            QQC2.Label { text: Math.round(fontSlider.value) + " %" }
        }
    }

}

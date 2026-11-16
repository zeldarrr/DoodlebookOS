/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Dialogs
import QtCore
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCMUtils

KCMUtils.SimpleKCM {
    id: page
    property alias cfg_imagePath: imageField.text
    property string cfg_shape
    property string cfg_fillMode
    property string cfg_clickAction
    property alias cfg_showButton: buttonBox.checked
    property alias cfg_slideshowFolder: folderField.text
    property alias cfg_slideshowMinutes: slideSpin.value
    property alias cfg_saturation: satSlider.value
    property alias cfg_dimPercent: dimSlider.value

    // same names as `doodlebookos-icons shape`; "rounded" = rectangle with the radius of the Apparence page
    readonly property var shapes: [
        { value: "rounded", text: "Rectangle arrondi" }, { value: "circle", text: "Cercle" }, { value: "square", text: "Carré" },
        { value: "arch", text: "Arche" }, { value: "pentagon", text: "Pentagone" }, { value: "gem", text: "Gemme" },
        { value: "cookie4", text: "Cookie 4" }, { value: "cookie6", text: "Cookie 6" }, { value: "cookie7", text: "Cookie 7" },
        { value: "cookie9", text: "Cookie 9" }, { value: "cookie12", text: "Cookie 12" }, { value: "sunny", text: "Soleil" },
        { value: "verysunny", text: "Grand soleil" }, { value: "clover4", text: "Trèfle 4" }, { value: "clover8", text: "Trèfle 8" },
        { value: "flower", text: "Fleur" }, { value: "softburst", text: "Éclat" }
    ]

    FileDialog {
        id: imageDialog
        nameFilters: ["Images (*.png *.jpg *.jpeg *.webp *.avif *.jxl *.heic *.bmp *.gif *.svg)"]
        currentFolder: StandardPaths.writableLocation(StandardPaths.PicturesLocation)
        onAccepted: imageField.text = selectedFile.toString()
    }
    FolderDialog {
        id: folderDialog
        currentFolder: StandardPaths.writableLocation(StandardPaths.PicturesLocation)
        onAccepted: folderField.text = selectedFolder.toString()
    }

    Kirigami.FormLayout {
        RowLayout {
            Kirigami.FormData.label: "Image :"
            QQC2.TextField { id: imageField; Layout.preferredWidth: Kirigami.Units.gridUnit * 14 }
            QQC2.Button { icon.name: "document-open"; text: "Choisir…"; onClicked: imageDialog.open() }
        }
        QQC2.ComboBox {
            Kirigami.FormData.label: "Forme :"
            model: page.shapes
            textRole: "text"
            valueRole: "value"
            Component.onCompleted: currentIndex = Math.max(0, indexOfValue(page.cfg_shape))
            onActivated: page.cfg_shape = currentValue
        }
        QQC2.ComboBox {
            Kirigami.FormData.label: "Cadrage :"
            model: [{ value: "crop", text: "Remplir (rogner)" }, { value: "fit", text: "Image entière" }]
            textRole: "text"
            valueRole: "value"
            Component.onCompleted: currentIndex = Math.max(0, indexOfValue(page.cfg_fillMode))
            onActivated: page.cfg_fillMode = currentValue
        }
        QQC2.ComboBox {
            Kirigami.FormData.label: "Clic sur l'image :"
            model: [{ value: "open", text: "Ouvrir l'image" }, { value: "next", text: "Image suivante (diaporama)" }, { value: "none", text: "Rien" }]
            textRole: "text"
            valueRole: "value"
            Component.onCompleted: currentIndex = Math.max(0, indexOfValue(page.cfg_clickAction))
            onActivated: page.cfg_clickAction = currentValue
        }
        QQC2.CheckBox { id: buttonBox; Kirigami.FormData.label: "Bouton :"; text: "Bouton « changer » au survol" }

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Diaporama" }
        RowLayout {
            Kirigami.FormData.label: "Dossier :"
            QQC2.TextField { id: folderField; placeholderText: "(aucun : une seule image)"; Layout.preferredWidth: Kirigami.Units.gridUnit * 14 }
            QQC2.Button { icon.name: "folder-open"; text: "Choisir…"; onClicked: folderDialog.open() }
            QQC2.Button { icon.name: "edit-clear"; visible: folderField.text.length > 0; onClicked: folderField.text = "" }
        }
        QQC2.SpinBox { id: slideSpin; Kirigami.FormData.label: "Changer toutes les (min, 0 = jamais) :"; from: 0; to: 1440 }

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Effets" }
        RowLayout {
            Kirigami.FormData.label: "Saturation :"
            QQC2.Slider { id: satSlider; from: -100; to: 100; stepSize: 5; Layout.preferredWidth: Kirigami.Units.gridUnit * 12 }
            QQC2.Label { text: Math.round(satSlider.value) }
        }
        RowLayout {
            Kirigami.FormData.label: "Assombrir :"
            QQC2.Slider { id: dimSlider; from: 0; to: 80; stepSize: 5; Layout.preferredWidth: Kirigami.Units.gridUnit * 12 }
            QQC2.Label { text: Math.round(dimSlider.value) + " %" }
        }
    }
}

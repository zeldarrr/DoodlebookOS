/*
    SPDX-License-Identifier: GPL-3.0-or-later
*/
import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    property alias cfg_City: city.text
    property alias cfg_ShowWeather: weather.checked
    property string cfg_Image

    QQC2.CheckBox {
        id: weather
        Kirigami.FormData.label: "Météo :"
        text: "Afficher la météo sous la date"
    }
    QQC2.TextField {
        id: city
        enabled: weather.checked
        Kirigami.FormData.label: "Ville :"
        placeholderText: "Automatique (selon le réseau)"
    }
}

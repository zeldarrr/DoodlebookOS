import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: "Image"
        icon: "insert-image"
        source: "ConfigPhoto.qml"
    }
    ConfigCategory {
        name: "Apparence"
        icon: "preferences-desktop-color"
        source: "ConfigCard.qml"
    }
}

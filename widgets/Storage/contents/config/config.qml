import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: "Stockage"
        icon: "drive-harddisk"
        source: "ConfigStorage.qml"
    }
    ConfigCategory {
        name: "Apparence"
        icon: "preferences-desktop-color"
        source: "ConfigCard.qml"
    }
}

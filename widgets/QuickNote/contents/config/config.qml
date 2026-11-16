import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: "Note"
        icon: "document-edit"
        source: "ConfigNote.qml"
    }
    ConfigCategory {
        name: "Apparence"
        icon: "preferences-desktop-color"
        source: "ConfigCard.qml"
    }
}

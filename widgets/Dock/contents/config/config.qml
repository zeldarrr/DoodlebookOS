import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: "Dock"
        icon: "preferences-desktop-icons"
        source: "ConfigDock.qml"
    }
    ConfigCategory {
        name: "Lanceur"
        icon: "applications-all"
        source: "ConfigLauncher.qml"
    }
}

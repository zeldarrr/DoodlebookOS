/*
 * SPDX-FileCopyrightText: 2024-2026 Maciej Kujawiński <maciek.kujawinski@gmail.com>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

pragma ComponentBehavior: Bound
import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.taskmanager as TaskManager
import org.kde.plasma.private.kicker 0.1 as Kicker
import org.kde.plasma.workspace.dbus 1.0 as DBus

PlasmoidItem {
    id: kicker

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    property alias tasksModel: tasksModel
    property alias rootModel: rootModel
    property alias runnerModel: runnerModel
    property alias launcherPopup: launcherPopup
    property alias phoneHubPopup: phoneHubPopup
    property Item compactRepItem: null

    property QtObject globalFavorites: rootModel.favoritesModel
    property QtObject systemFavorites: rootModel.systemFavoritesModel

    TaskManager.VirtualDesktopInfo {
        id: virtualDesktopInfo
    }

    TaskManager.TasksModel {
        id: tasksModel
        property bool initialized: false

        virtualDesktop: virtualDesktopInfo.currentDesktop
        filterByCurrentVirtualDesktop: false
        filterByScreen: false
        filterByActivity: false
        sortMode: TaskManager.TasksModel.SortManual
        launchInPlace: true
        separateLaunchers: true
        hideActivatedLaunchers: true
        groupMode: TaskManager.TasksModel.GroupApplications
        groupInline: false
        groupingWindowTasksThreshold: -1

        onLauncherListChanged: {
            if (!initialized) return;
            if (launcherList) {
                Plasmoid.configuration.launchers = launcherList;
                if (typeof Plasmoid.configuration.writeConfig === "function") {
                    Plasmoid.configuration.writeConfig();
                }
            }
        }

        Component.onCompleted: {
            var raw = Plasmoid.configuration.launchers;
            var list = [];
            if (raw) {
                if (Array.isArray(raw)) {
                    list = Array.from(raw);
                } else if (typeof raw === "string") {
                    list = raw.split(",").map(s => s.trim()).filter(s => s.length > 0);
                } else if (typeof raw.length === "number") {
                    for (var i = 0; i < raw.length; ++i) {
                        list.push(raw[i]);
                    }
                }
            }
            if (list.length === 0) {
                list = [
                    "preferred://browser",
                    "preferred://filemanager",
                    "applications:org.kde.konsole.desktop",
                    "applications:org.kde.discover.desktop",
                    "applications:systemsettings.desktop"
                ];
                Plasmoid.configuration.launchers = list;
                if (typeof Plasmoid.configuration.writeConfig === "function") {
                    Plasmoid.configuration.writeConfig();
                }
            }
            tasksModel.launcherList = list;
            initialized = true;
        }
    }

    Kicker.RootModel {
        id: rootModel
        appletInterface: kicker
        autoPopulate: false
        appNameFormat: 0
        flat: true
        sorted: true
        showSeparators: false
        showAllApps: true
        showAllAppsCategorized: false
        showTopLevelItems: true
        showRecentApps: true
        showRecentDocs: true
        showPowerSession: false
        highlightNewlyInstalledApps: true

        onRecentOrderingChanged: {
            Plasmoid.configuration.recentOrdering = recentOrdering;
        }

        Component.onCompleted: {
            favoritesModel.initForClient("org.kde.plasma.kicker.favorites.instance-" + Plasmoid.id);
            if (!Plasmoid.configuration.favoritesPortedToKAstats) {
                if (favoritesModel.count < 1) {
                    favoritesModel.portOldFavorites(Plasmoid.configuration.favoriteApps);
                }
                Plasmoid.configuration.favoritesPortedToKAstats = true;
            }
            rootModel.refresh();
        }
    }

    Connections {
        target: kicker.globalFavorites
        function onFavoritesChanged() {
            Plasmoid.configuration.favoriteApps = target.favorites;
        }
    }

    Connections {
        target: kicker.systemFavorites
        function onFavoritesChanged() {
            Plasmoid.configuration.favoriteSystemActions = target.favorites;
        }
    }

    Connections {
        target: Plasmoid.configuration
        function onFavoriteAppsChanged() {
            kicker.globalFavorites.favorites = Plasmoid.configuration.favoriteApps;
        }
        function onFavoriteSystemActionsChanged() {
            kicker.systemFavorites.favorites = Plasmoid.configuration.favoriteSystemActions;
        }
        function onAppsRefreshTriggerChanged() {
            rootModel.refresh();
        }
    }

    Kicker.RunnerModel {
        id: runnerModel
        favoritesModel: kicker.globalFavorites
        appletInterface: kicker
        mergeResults: true
        // fast runners only (AppStream, Bazaar, dictionary, spell check, web shortcuts… made every
        // keystroke slow; apps come from AppIndex, the web from the DuckDuckGo row)
        runners: ["krunner_services", "calculator", "unitconverter", "krunner_systemsettings", "baloosearch",
                  "krunner_recentdocuments", "locations", "krunner_placesrunner", "windows", "krunner_shell",
                  "krunner_powerdevil", "krunner_sessions", "org.kde.datetime"]
    }

    readonly property Item dragSource: Item {
        id: dragSource
        property Item sourceItem
        property string sourceId: ""        // storageId of the dragged app
        property string sourceFolder: ""    // folder id when dragged out of a folder
        property int sourcePinned: -1       // row in the launcher favourites, -1 otherwise
        Drag.dragType: Drag.Automatic
    }

    // launcher data hub: categories, search, folders, badges
    AppIndex {
        id: appIndex
        appsModel: kicker.allAppsModel
    }
    property QtObject allAppsModel: null
    function syncAllApps() {
        var m = rootModel.count > 2 ? rootModel.modelForRow(2) : null;
        if (m !== allAppsModel) allAppsModel = m;
    }
    Connections {
        target: rootModel
        function onRefreshed() { kicker.syncAllApps(); }
        function onCountChanged() { kicker.syncAllApps(); }
    }

    preferredRepresentation: compactRepresentation

    compactRepresentation: CompactRepresentation {
        id: compactRep
        tasksModel: kicker.tasksModel
        launcherPopup: kicker.launcherPopup
        phoneHubPopup: kicker.phoneHubPopup
    }

    fullRepresentation: compactRepresentation

    PhoneHubPopup {
        id: phoneHubPopup
        visualParentItem: (kicker.compactRepItem && kicker.compactRepItem.phoneHubBtn) ? kicker.compactRepItem.phoneHubBtn : null
        plasmoidConfiguration: Plasmoid.configuration
        popupWidth: Math.max(360, Math.min(440, Math.round(Screen.width * 0.26)))
        maxPopupHeight: Math.round(Screen.height * 0.72)
        panelHeight: kicker.compactRepItem ? kicker.compactRepItem.effectiveHeight : 52
    }

    DimOverlay {
        id: dimOverlay
        bottomGap: kicker.compactRepItem ? kicker.compactRepItem.effectiveHeight : 52
    }

    LauncherPopup {
        id: launcherPopup
        rootModel: rootModel
        plasmoidConfiguration: Plasmoid.configuration
        dimOverlayItem: dimOverlay
        visualParentItem: (kicker.compactRepItem && kicker.compactRepItem.popupAnchor) ? kicker.compactRepItem.popupAnchor : kicker.compactRepItem
        fullscreen: Plasmoid.configuration.launcherFullscreen === true
        popupWidth: fullscreen ? Screen.width - 48 : Math.min(Screen.width - 40, Math.max(420, Plasmoid.configuration.popupWidth || 600))
        popupHeight: fullscreen ? Screen.height - (kicker.compactRepItem ? kicker.compactRepItem.effectiveHeight : 52) - 36
                                : Math.round(Screen.height * 0.72)
        panelHeight: kicker.compactRepItem ? kicker.compactRepItem.effectiveHeight : 52
    }

    DBus.Properties {
        id: krunnerBridge
        busType: DBus.BusType.Session
        service: "org.kde.krunner"
        path: "/App"
        iface: "org.kde.krunner.App"

        property int lastTriggerCount: -1

        onPropertiesChanged: (iface, changed, invalidated) => {
            if (changed && typeof changed.triggerCount !== "undefined") {
                var count = Number(changed.triggerCount);
                if (lastTriggerCount === -1) {
                    lastTriggerCount = count;
                    return;
                }
                if (count > lastTriggerCount) {
                    lastTriggerCount = count;
                    var q = (changed.queryText !== undefined) ? changed.queryText.toString() : "";
                    if (q.length > 0) {
                        launcherPopup.openWithQuery(q);
                    } else {
                        launcherPopup.toggle();
                    }
                }
            }
        }
    }

    Connections {
        target: Plasmoid
        function onActivated() {
            launcherPopup.toggle();
        }
    }

    Component.onCompleted: {
        syncAllApps();
        if (Plasmoid.containment && typeof Plasmoid.containment.setContainmentActions === "function") {
            Plasmoid.containment.setContainmentActions("RightButton;NoModifier", "");
        }
    }
}
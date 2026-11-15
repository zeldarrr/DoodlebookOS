/*
    SPDX-FileCopyrightText: 2026 DoodlebookOS
    SPDX-License-Identifier: GPL-3.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami

// Backend subsystem imports
import org.kde.plasma.private.mpris as Mpris
import org.kde.notificationmanager as NotificationManager
import org.kde.plasma.networkmanagement as PlasmaNM
import org.kde.plasma.private.battery as PlasmaBattery
import org.kde.plasma.private.volume as Volume
import org.kde.plasma.private.clipboard as Klipper
import org.kde.taskmanager as TaskManager
import org.kde.bluezqt as BluezQt
import org.kde.plasma.workspace.keyboardlayout as KeyboardLayoutPlugin

// Sub-module UI components
import "components" as Components
import "keyboardlayout" as KeyboardLayoutUI
import "media" as Media
import "magicpointer" as MagicPointerUI
import "notifications" as NotificationsUI
import "notifications/global" as NotifGlobal
import "quicksettings" as QuickSettingsUI
import "tray" as TrayUI
import "metrics" as LocalMetrics

PlasmoidItem {
    id: root

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    Plasmoid.contextualActions: []

    Binding {
        target: LocalMetrics.Metrics
        property: "hostDpr"
        value: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1.0
    }
    Binding {
        target: LocalMetrics.Metrics
        property: "uiScale"
        value: (Plasmoid.configuration && typeof Plasmoid.configuration.shellScale === "number" && Plasmoid.configuration.shellScale > 0)
            ? Plasmoid.configuration.shellScale
            : 1.0
    }

    Connections {
        target: Plasmoid
        function onActivated() {
            root.toggleQSPopup();
        }
    }

    // Native Klipper engine instance - maintains clipboard history & prevents Wayland timeout drop
    Klipper.KlipperInterface {
        id: klipperInterface
    }
    Klipper.HistoryModel {
        id: clipboardHistoryModel
    }

    readonly property bool isVertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property real dpr: LocalMetrics.Metrics.dpr
    readonly property bool isTop: Plasmoid.location === PlasmaCore.Types.TopEdge || (Plasmoid.containment && Plasmoid.containment.location === PlasmaCore.Types.TopEdge)

    TaskManager.VirtualDesktopInfo {
        id: virtualDesktopInfo
    }

    TaskManager.TasksModel {
        id: maximizedTasksModel

        activity: Plasmoid.containment ? Plasmoid.containment.activity : ""
        filterByActivity: true
        screenGeometry: Plasmoid.containment ? Plasmoid.containment.screenGeometry : Qt.rect(0, 0, 0, 0)
        filterByScreen: true
        filterMinimized: true
        filterNotMaximized: true

        Component.onCompleted: {
            if (maximizedTasksModel.hasOwnProperty("filterByCurrentVirtualDesktop")) {
                maximizedTasksModel.filterByCurrentVirtualDesktop = true;
            } else {
                maximizedTasksModel.virtualDesktop = Qt.binding(() => virtualDesktopInfo.currentDesktop);
                maximizedTasksModel.filterByVirtualDesktop = true;
            }
        }
    }

    readonly property bool hasMaximizedWindow: root.isTop && maximizedTasksModel.count > 0

    readonly property real effectiveHeight: {
        var h = 0;
        if (Plasmoid.containment && typeof Plasmoid.containment.height === "number" && Plasmoid.containment.height > 20) {
            h = isVertical ? Plasmoid.containment.width : Plasmoid.containment.height;
        } else if (parent && (isVertical ? parent.width : parent.height) > 20) {
            h = isVertical ? parent.width : parent.height;
        }
        return (h > 20) ? h : LocalMetrics.Metrics.px(36.0);
    }

    function snap(val) {
        return LocalMetrics.Metrics.snap(val);
    }

    function px(refPx) {
        return LocalMetrics.Metrics.px(refPx);
    }

    function legacyDp(oldDp) {
        return LocalMetrics.Metrics.legacyDp(oldDp);
    }

    function barPx(itemRefPx, refBarPx) {
        return LocalMetrics.Metrics.barPx(effectiveHeight, itemRefPx, refBarPx);
    }

    // ==========================================
    // UNIFIED RAIL METRICS (Punkt 0 Top Bar Design Tokens: 36 px = 29 dp)
    // ==========================================
    readonly property real railHeight: LocalMetrics.Metrics.barPx(effectiveHeight, 24.0, 36.0)             // 24 px physical at 36 px panel height
    readonly property real qsIconHeight: LocalMetrics.Metrics.barPx(effectiveHeight, 14.4, 36.0)           // 14.4 px box
    readonly property real railTopMargin: LocalMetrics.Metrics.snap((effectiveHeight - railHeight) / 2)   // 6 px physical at 36 px panel height
    readonly property real clusterRightMargin: LocalMetrics.Metrics.barPx(effectiveHeight, 20.0, 36.0)     // 20 px + 4 px Plasma panel padding = 24 px right screen margin
    readonly property real itemSpacing: LocalMetrics.Metrics.barPx(effectiveHeight, 8.0, 36.0)             // 8 px physical between pills
    readonly property real qsIconSpacing: LocalMetrics.Metrics.barPx(effectiveHeight, 6.0, 36.0)           // 6 px physical between QS icons
    readonly property real keyboardLayoutFontSize: effectiveHeight * 0.3125                                // 11.25 px physical at 36 px panel height

    // Common Colors & Styling Tokens
    readonly property color topBarContentColor: {
        if (hasMaximizedWindow) {
            return "#ffffff";
        }
        if (Plasmoid.configuration && Plasmoid.configuration.contentColor && Plasmoid.configuration.contentColor.length > 0) {
            return Plasmoid.configuration.contentColor;
        }
        return Kirigami.Theme.textColor;
    }
    readonly property bool isLightContent: {
        var c = topBarContentColor;
        return (c.r * 0.299 + c.g * 0.587 + c.b * 0.114) > 0.5;
    }
    readonly property color highlightedContentColor: Kirigami.Theme.highlightedTextColor
    readonly property color highlightCapsuleColor: Kirigami.Theme.highlightColor
    readonly property color effectiveAccentColor: {
        if (Plasmoid.configuration && Plasmoid.configuration.useCustomAccentColor && Plasmoid.configuration.accentColor) {
            return Plasmoid.configuration.accentColor;
        }
        return Kirigami.Theme.highlightColor;
    }

    // ==========================================
    // 1. MEDIA BACKEND (MediaPill)
    // ==========================================
    Item {
        id: mediaBackend
        visible: false

        readonly property string rawTrack: mpris2Model.currentPlayer?.track ?? ""

        readonly property string track: {
            let raw = String(rawTrack);
            // 1. Usunięcie prefiksu powiadomień np. "(3) ", "(99+) "
            raw = raw.replace(/^\(\d+\+?\)\s*/, "");
            // 2. Usunięcie powszechnych sufiksów serwisów np. " - YouTube", " - SoundCloud"
            raw = raw.replace(/\s*-\s*YouTube(?:\s*Music)?$/i, "");
            raw = raw.replace(/\s*-\s*SoundCloud$/i, "");
            raw = raw.trim();
            if (raw.length === 0) {
                return (identity.length > 0) ? identity : i18n("Media");
            }
            return raw;
        }

        readonly property string artist: mpris2Model.currentPlayer?.artist ?? ""
        readonly property string identity: mpris2Model.currentPlayer?.identity ?? ""

        readonly property string artUrl: {
            const raw = String(mpris2Model.currentPlayer?.artUrl ?? "");
            if (raw.length > 0 && raw.startsWith("/")) return "file://" + raw;
            return raw;
        }

        readonly property bool isChromeFallbackArt: {
            const url = artUrl.toLowerCase();
            return url.includes(".com.google.chrome") || url.includes(".org.chromium.chromium") || url.includes("google-chrome");
        }

        readonly property bool hasRealArtwork: artUrl.length > 0 && !isChromeFallbackArt

        readonly property string appIcon: {
            const idLower = identity.toLowerCase();
            if (idLower.includes("chrome") || idLower.includes("chromium") || isChromeFallbackArt) return "google-chrome";
            if (idLower.includes("firefox")) return "firefox";
            if (idLower.includes("spotify")) return "spotify";
            if (idLower.includes("vlc")) return "vlc";
            if (mpris2Model.currentPlayer?.iconName) {
                const icon = String(mpris2Model.currentPlayer.iconName);
                if (icon !== "multimedia-audio-player" && icon !== "audio-x-generic") return icon;
            }
            return "multimedia-audio-player";
        }

        readonly property bool canSeek: mpris2Model.currentPlayer?.canSeek ?? false

        readonly property int playbackStatus: mpris2Model.currentPlayer?.playbackStatus ?? Mpris.PlaybackStatus.Stopped
        readonly property bool isPlaying: mediaBackend.playbackStatus === Mpris.PlaybackStatus.Playing

        property double position: mpris2Model.currentPlayer?.position ?? 0
        property double length: mpris2Model.currentPlayer?.length ?? 0

        readonly property bool hasMedia: mpris2Model.currentPlayer !== null && rawTrack.trim().length > 0
        readonly property bool hasActiveMedia: hasMedia && (playbackStatus === Mpris.PlaybackStatus.Playing || playbackStatus === Mpris.PlaybackStatus.Paused)

        property bool effectiveVisible: hasActiveMedia

        Timer {
            id: hideDebounceTimer
            interval: 3500 // 3.5s grace period WYŁĄCZNIE przy pauzie wciąż istniejącego utworu
            repeat: false
            onTriggered: {
                if (mediaDialog.visible) {
                    return;
                }
                mediaBackend.effectiveVisible = mediaBackend.hasActiveMedia;
            }
        }

        function syncVisibility(): void {
            if (hasActiveMedia) {
                hideDebounceTimer.stop();
                mediaBackend.effectiveVisible = true;
            } else if (!hasMedia) {
                // Gdy brak mediów / brak utworu / zamknięto źródło -> natychmiast ukrywamy!
                hideDebounceTimer.stop();
                mediaBackend.effectiveVisible = false;
                if (mediaDialog.visible) {
                    mediaDialog.visible = false;
                }
            } else if (!mediaDialog.visible) {
                // Utwór istnieje, ale jest na pauzie -> odczekaj 3.5s bufora
                hideDebounceTimer.restart();
            }
        }

        onHasActiveMediaChanged: syncVisibility()
        onHasMediaChanged: syncVisibility()
        onRawTrackChanged: syncVisibility()

        Connections {
            target: mediaDialog
            function onVisibleChanged() {
                if (!mediaDialog.visible) {
                    if (!mediaBackend.hasMedia) {
                        mediaBackend.effectiveVisible = false;
                    } else if (!mediaBackend.hasActiveMedia) {
                        hideDebounceTimer.restart();
                    }
                }
            }
        }

        function togglePlaying(): void {
            if (mpris2Model.currentPlayer) {
                if (isPlaying) mpris2Model.currentPlayer.Pause();
                else mpris2Model.currentPlayer.Play();
            }
        }

        function seek(newPosMicros: double): void {
            if (mpris2Model.currentPlayer) mpris2Model.currentPlayer.position = newPosMicros;
        }

        function changeVolume(delta: double): void {
            if (mpris2Model.currentPlayer) mpris2Model.currentPlayer.changeVolume(delta, true);
        }

        Mpris.Mpris2Model {
            id: mpris2Model
        }
    }

    // ==========================================
    // 2. NOTIFICATIONS BACKEND
    // ==========================================
    NotificationManager.Settings {
        id: notifSettings
    }

    NotificationManager.Notifications {
        id: notifHistoryModel
        showExpired: true
        showDismissed: true
        showJobs: notifSettings.jobsInNotifications
        sortMode: NotificationManager.Notifications.SortByTypeAndUrgency
        groupMode: NotificationManager.Notifications.GroupDisabled
        ignoreBlacklistDuringInhibition: true
        blacklistedDesktopEntries: notifSettings.historyBlacklistedApplications
        blacklistedNotifyRcNames: notifSettings.historyBlacklistedServices
        urgencies: NotificationManager.Notifications.CriticalUrgency
                 | NotificationManager.Notifications.NormalUrgency
                 | NotificationManager.Notifications.LowUrgency
    }

    readonly property var plasmoidRef: Plasmoid
    property alias notifBellButton: notifBellButton
    property alias mediaPillButton: mediaPillButton
    property alias qsPillButton: qsPillButton
    readonly property bool notifPopupVisible: notifDialog.visible

    Component.onCompleted: {
        NotifGlobal.Globals.adopt(root);
        root.updateWifiSignal();
        root.updateUnreadNotifs();
    }

    Component.onDestruction: {
        NotifGlobal.Globals.forget(root);
    }

    property int unreadNotifCount: 0

    function updateUnreadNotifs() {
        if (notifDialog.visible) {
            unreadNotifCount = 0;
            return;
        }
        var unread = notifHistoryModel ? notifHistoryModel.unreadNotificationsCount : 0;
        unreadNotifCount = Math.min(99, Math.max(0, unread));
    }

    Connections {
        target: notifHistoryModel
        function onRowsInserted() { root.updateUnreadNotifs(); }
        function onRowsRemoved() { root.updateUnreadNotifs(); }
        function onDataChanged() { root.updateUnreadNotifs(); }
        function onModelReset() { root.updateUnreadNotifs(); }
        function onUnreadNotificationsCountChanged() { root.updateUnreadNotifs(); }
    }

    Connections {
        target: NotifGlobal.Globals.popupNotificationsModel
        function onRowsInserted() { root.updateUnreadNotifs(); }
        function onRowsRemoved() { root.updateUnreadNotifs(); }
        function onModelReset() { root.updateUnreadNotifs(); }
    }
    readonly property bool isDndActive: Boolean(notifSettings.notificationsInhibitedUntil && notifSettings.notificationsInhibitedUntil > new Date())

    function toggleDoNotDisturbMode(): void {
        if (isDndActive) {
            notifSettings.notificationsInhibitedUntil = undefined;
        } else {
            var d = new Date();
            d.setFullYear(d.getFullYear() + 1);
            notifSettings.notificationsInhibitedUntil = d;
        }
        notifSettings.save();
    }

    PlasmaCore.Action {
        id: clearHistoryAction
        text: typeof i18n === "function" ? i18n("Clear All Notifications") : "Clear All Notifications"
        icon.name: "edit-clear-history"
        visible: notifHistoryModel.expiredNotificationsCount > 0
        onTriggered: {
            notifHistoryModel.clear(NotificationManager.Notifications.ClearExpired);
        }
    }

    // ==========================================
    // 3. QUICK SETTINGS BACKEND
    // ==========================================
    property alias nmStatus: nmStatus
    property alias batteryModel: batteryModel
    readonly property bool hasInternalBattery: batteryModel ? Boolean(batteryModel.hasCumulative || (batteryModel.hasInternalBatteries && batteryModel.percent > 0)) : false
    property alias paSinkModel: paSinkModel

    PlasmaNM.NetworkStatus {
        id: nmStatus
    }

    PlasmaNM.EnabledConnections {
        id: nmEnabled
    }

    PlasmaNM.NetworkModel {
        id: nmNetworkModel
    }

    PlasmaNM.AppletProxyModel {
        id: nmAppletProxyModel
        sourceModel: nmNetworkModel
    }

    property int activeWifiSignal: -1
    property bool hasActiveWifi: false
    property bool hasActiveWired: false

    function updateWifiSignal() {
        var foundWired = false;
        var foundWifi = false;
        var wifiSig = -1;

        var count = nmAppletProxyModel.rowCount();
        for (var i = 0; i < count; i++) {
            var idx = nmAppletProxyModel.index(i, 0);
            var state = nmAppletProxyModel.data(idx, PlasmaNM.NetworkModel.ConnectionStateRole);
            var type = nmAppletProxyModel.data(idx, PlasmaNM.NetworkModel.TypeRole);

            if (state === PlasmaNM.Enums.Activated) {
                if (type === PlasmaNM.Enums.Wired) {
                    foundWired = true;
                } else if (type === PlasmaNM.Enums.Wireless && !foundWifi) {
                    var sig = nmAppletProxyModel.data(idx, PlasmaNM.NetworkModel.SignalRole);
                    if (sig !== undefined && sig !== null && !isNaN(sig)) {
                        wifiSig = Number(sig);
                    } else {
                        wifiSig = 100;
                    }
                    foundWifi = true;
                }
            }
        }

        hasActiveWired = foundWired;
        hasActiveWifi = foundWifi;
        activeWifiSignal = wifiSig;
    }

    Connections {
        target: nmAppletProxyModel
        function onDataChanged() { root.updateWifiSignal(); }
        function onRowsInserted() { root.updateWifiSignal(); }
        function onRowsRemoved() { root.updateWifiSignal(); }
        function onModelReset() { root.updateWifiSignal(); }
    }

    Connections {
        target: nmEnabled
        function onWirelessEnabledChanged() { root.updateWifiSignal(); }
    }

    readonly property url currentWifiIcon: {
        if (hasActiveWired) {
            return Qt.resolvedUrl("quicksettings/icons/ethernet.svg");
        }

        if (!nmEnabled.wirelessEnabled) {
            return Qt.resolvedUrl("quicksettings/icons/wifi_off.svg");
        }

        // If no active Wi-Fi connection found
        if (!hasActiveWifi) {
            return Qt.resolvedUrl("quicksettings/icons/wifi_0.svg");
        }

        // Map signal strength (0-100%) to 3 stages (2 arcs + dot)
        if (activeWifiSignal <= 33) {
            return Qt.resolvedUrl("quicksettings/icons/wifi_1.svg");
        } else if (activeWifiSignal <= 66) {
            return Qt.resolvedUrl("quicksettings/icons/wifi_2.svg");
        } else {
            return Qt.resolvedUrl("quicksettings/icons/wifi_3.svg");
        }
    }

    PlasmaBattery.BatteryControlModel {
        id: batteryModel
    }

    readonly property url currentBatteryIcon: {
        var bm = batteryModel;
        if (!bm) {
            return Qt.resolvedUrl("quicksettings/icons/battery_android_full_bolt.svg");
        }
        var hasInternal = root.hasInternalBattery;
        var plugged = Boolean(bm.pluggedIn);
        var st = bm.state;
        var pct = bm.percent;

        // Desktop PC or device without internal battery
        if (!hasInternal) {
            return Qt.resolvedUrl("quicksettings/icons/battery_android_full_bolt.svg");
        }

        var val = (pct !== undefined && pct !== null) ? pct : 100;
        // On AC power: actively charging (state 1), fully charged (state 3), or plugged in
        var isPlugged = (plugged || st === 1 || st === 3);

        // Actively charging or plugged in on AC power
        if (isPlugged) {
            if (val <= 15) {
                return Qt.resolvedUrl("quicksettings/icons/battery_android_bolt.svg");
            } else if (val <= 35) {
                return Qt.resolvedUrl("quicksettings/icons/battery_android_2_bolt.svg");
            } else if (val <= 55) {
                return Qt.resolvedUrl("quicksettings/icons/battery_android_4_bolt.svg");
            } else if (val <= 75) {
                return Qt.resolvedUrl("quicksettings/icons/battery_android_5_bolt.svg");
            } else if (val <= 92) {
                return Qt.resolvedUrl("quicksettings/icons/battery_android_6_bolt.svg");
            } else {
                return Qt.resolvedUrl("quicksettings/icons/battery_android_full_bolt.svg");
            }
        }

        // On battery (Discharging)
        if (val <= 5) {
            return Qt.resolvedUrl("quicksettings/icons/battery_android_alert.svg");
        } else if (val <= 15) {
            return Qt.resolvedUrl("quicksettings/icons/battery_android_0.svg");
        } else if (val <= 35) {
            return Qt.resolvedUrl("quicksettings/icons/battery_android_2.svg");
        } else if (val <= 55) {
            return Qt.resolvedUrl("quicksettings/icons/battery_android_4.svg");
        } else if (val <= 75) {
            return Qt.resolvedUrl("quicksettings/icons/battery_android_5.svg");
        } else if (val <= 92) {
            return Qt.resolvedUrl("quicksettings/icons/battery_android_6.svg");
        } else {
            return Qt.resolvedUrl("quicksettings/icons/battery_android_full.svg");
        }
    }

    Volume.SinkModel {
        id: paSinkModel
    }

    // ==========================================
    // 4. BLUETOOTH CONNECTED & KEYBOARD LAYOUT BACKEND
    // ==========================================
    property int _btConnTrigger: 0

    Connections {
        target: (typeof BluezQt !== "undefined" && BluezQt.Manager) ? BluezQt.Manager : null
        function onConnectedDevicesChanged() { root._btConnTrigger++; }
        function onDeviceAdded() { root._btConnTrigger++; }
        function onDeviceRemoved() { root._btConnTrigger++; }
        function onDeviceChanged() { root._btConnTrigger++; }
        function onUsableAdapterChanged() { root._btConnTrigger++; }
        function onBluetoothOperationalChanged() { root._btConnTrigger++; }
    }

    readonly property bool hasConnectedBluetoothDevice: {
        var _t = _btConnTrigger;
        if (typeof BluezQt === "undefined" || !BluezQt.Manager) return false;
        if (BluezQt.Manager.bluetoothBlocked) return false;
        if (BluezQt.Manager.usableAdapter && !BluezQt.Manager.usableAdapter.powered) return false;
        if (!BluezQt.Manager.connectedDevices) return false;
        return BluezQt.Manager.connectedDevices.length > 0;
    }

    KeyboardLayoutPlugin.KeyboardLayout {
        id: keyboardLayoutBackend
    }

    readonly property bool hasMultipleKeyboardLayouts: Boolean(
        keyboardLayoutBackend &&
        keyboardLayoutBackend.layoutsList &&
        keyboardLayoutBackend.layoutsList.length >= 2
    )

    readonly property string activeKeyboardLayoutCode: {
        if (!keyboardLayoutBackend || !keyboardLayoutBackend.layoutsList || keyboardLayoutBackend.layoutsList.length === 0) {
            return "";
        }
        var idx = keyboardLayoutBackend.layout;
        if (idx < 0 || idx >= keyboardLayoutBackend.layoutsList.length) {
            idx = 0;
        }
        var entry = keyboardLayoutBackend.layoutsList[idx];
        var code = (entry && entry.shortName) ? String(entry.shortName) : "";
        return code.trim().toUpperCase();
    }

    // ==========================================
    // POPUP MANAGEMENT (Handshake & Seamless Switching)
    // ==========================================
    readonly property var popupDialogs: ({
        "trayOverflow": trayOverflowDialog,
        "trayMenu": trayMenuDialog,
        "media": mediaDialog,
        "keyboardlayout": keyboardLayoutDialog,
        "magicpointer": magicPointerDialog,
        "notif": notifDialog,
        "qs": qsDialog
    })

    TrayUI.TrayBackend {
        id: trayBackend
        appletRoot: root
    }

    Timer {
        id: popupSwitchTimer
        interval: 35
        repeat: false
        property string targetPopup: ""
        onTriggered: {
            var dlg = root.popupDialogs[targetPopup];
            if (dlg) {
                dlg.visible = true;
            }
            targetPopup = "";
        }
    }

    function closeAllPopups() {
        popupSwitchTimer.stop();
        for (var key in root.popupDialogs) {
            var dlg = root.popupDialogs[key];
            if (dlg) {
                dlg.visible = false;
            }
        }
    }

    function requestTogglePopup(name) {
        popupSwitchTimer.stop();

        var targetDlg = root.popupDialogs[name];
        if (!targetDlg) {
            return;
        }

        if (targetDlg.visible) {
            closeAllPopups();
            return;
        }

        var anyOtherOpen = false;
        for (var key in root.popupDialogs) {
            var dlg = root.popupDialogs[key];
            if (dlg && dlg.visible) {
                anyOtherOpen = true;
                break;
            }
        }
        closeAllPopups();

        if (anyOtherOpen) {
            popupSwitchTimer.targetPopup = name;
            popupSwitchTimer.restart();
        } else {
            targetDlg.visible = true;
        }
    }

    function toggleQSPopup() {
        requestTogglePopup("qs");
    }

    function requestOpenTrayMenu(itemData, anchorButton, wasExpandedOnPress) {
        popupSwitchTimer.stop();
        if (!itemData || !anchorButton) {
            return;
        }
        if (wasExpandedOnPress) {
            closeAllPopups();
            return;
        }

        var anyOtherOpen = false;
        for (var key in root.popupDialogs) {
            var dlg = root.popupDialogs[key];
            if (dlg && dlg.visible) {
                anyOtherOpen = true;
                break;
            }
        }
        closeAllPopups();

        trayMenuDialog.visualParent = anchorButton;
        trayMenuView.openForItem(itemData);

        if (anyOtherOpen) {
            popupSwitchTimer.targetPopup = "trayMenu";
            popupSwitchTimer.restart();
        } else {
            trayMenuDialog.visible = true;
        }
    }

    // ==========================================
    // CLUSTER COMPACT PANEL REPRESENTATION
    // ==========================================
    preferredRepresentation: fullRepresentation
    compactRepresentation: null

    Layout.fillHeight: !isVertical
    Layout.fillWidth: isVertical

    implicitWidth: isVertical ? effectiveHeight : (clusterRow.implicitWidth + clusterRightMargin)
    implicitHeight: isVertical ? (clusterRow.implicitHeight + clusterRightMargin) : effectiveHeight
    width: implicitWidth
    height: implicitHeight
    Layout.minimumWidth: implicitWidth
    Layout.preferredWidth: implicitWidth
    Layout.minimumHeight: implicitHeight
    Layout.preferredHeight: implicitHeight

    Item {
        id: panelContainer
        anchors.fill: parent
        z: 1

        Row {
            id: clusterRow
            anchors.right: root.isVertical ? undefined : parent.right
            anchors.rightMargin: root.isVertical ? 0 : root.clusterRightMargin
            anchors.bottom: root.isVertical ? parent.bottom : undefined
            anchors.bottomMargin: root.isVertical ? root.clusterRightMargin : 0
            anchors.top: root.isVertical ? undefined : parent.top
            anchors.topMargin: root.isVertical ? 0 : root.railTopMargin
            anchors.horizontalCenter: root.isVertical ? parent.horizontalCenter : undefined
            spacing: root.itemSpacing
            height: root.railHeight

            // 0. APP TRAY GROUP (StatusNotifierItem apps + overflow capsule)
            TrayUI.TrayGroup {
                id: trayGroup
                appletRoot: root
                trayBackend: trayBackend
                trayOverflowVisible: trayOverflowDialog.visible
                activeTrayMenuKey: trayMenuDialog.visible ? trayMenuView.itemKey : ""
            }

            // 1. MEDIA PILL BUTTON
            Media.MediaPill {
                id: mediaPillButton
                appletRoot: root
                mediaBackend: mediaBackend
                expanded: mediaDialog.visible
            }

            // 1.25. KEYBOARD LAYOUT BUTTON
            KeyboardLayoutUI.KeyboardLayoutPill {
                id: keyboardLayoutButton
                appletRoot: root
                expanded: keyboardLayoutDialog.visible
            }

            // 1.5. MAGIC POINTER BUTTON
            Components.RailIconButton {
                id: magicPointerButton
                iconSource: Qt.resolvedUrl("magicpointer/icons/arrow.svg")
                railHeight: root.railHeight
                iconSize: root.qsIconHeight
                dpr: root.dpr
                highlightCapsuleColor: root.highlightCapsuleColor
                contentColor: root.topBarContentColor
                highlightedContentColor: root.highlightedContentColor
                expanded: magicPointerDialog.visible

                onClicked: wasExpanded => {
                    if (wasExpanded) {
                        root.closeAllPopups();
                    } else {
                        root.requestTogglePopup("magicpointer");
                    }
                }
            }

            // 2. NOTIFICATIONS BELL BUTTON
            NotificationsUI.NotifBellPill {
                id: notifBellButton
                appletRoot: root
                expanded: notifDialog.visible
            }

            // 3. QUICK SETTINGS BUTTON (Bluetooth, DND, Wi-Fi, Power)
            QuickSettingsUI.QuickSettingsPill {
                id: qsPillButton
                appletRoot: root
                expanded: qsDialog.visible
            }
        }
    }

    // ==========================================
    // POPUP DIALOGS
    // ==========================================

    // 1. Media Popup Dialog
    PlasmaCore.Dialog {
        id: mediaDialog
        visualParent: mediaPillButton
        location: Plasmoid.location
        flags: Qt.Popup | Qt.WindowStaysOnTopHint
        hideOnWindowDeactivate: true
        backgroundHints: PlasmaCore.Types.NoBackground
        width: mediaExpandedView ? mediaExpandedView.implicitWidth : root.legacyDp(360.0)
        height: mediaExpandedView ? mediaExpandedView.implicitHeight : root.legacyDp(158.4)

        mainItem: Media.ExpandedRepresentation {
            id: mediaExpandedView
            root: mediaBackend
        }
    }

    // 1.25. Keyboard Layout Popup Dialog
    PlasmaCore.AppletPopup {
        id: keyboardLayoutDialog
        visualParent: keyboardLayoutButton
        appletInterface: root
        popupDirection: Qt.BottomEdge
        margin: 1
        removeBorderStrategy: PlasmaCore.AppletPopup.Never
        hideOnWindowDeactivate: true
        backgroundHints: PlasmaCore.AppletPopup.StandardBackground
        width: keyboardLayoutView ? keyboardLayoutView.implicitWidth : root.legacyDp(128.0)
        height: keyboardLayoutView ? keyboardLayoutView.implicitHeight : root.legacyDp(44.8)

        mainItem: KeyboardLayoutUI.KeyboardLayoutPopup {
            id: keyboardLayoutView
        }
    }

    // 1.5. Magic Pointer Popup Dialog
    PlasmaCore.AppletPopup {
        id: magicPointerDialog
        visualParent: magicPointerButton
        appletInterface: root
        popupDirection: Qt.BottomEdge
        margin: 1
        removeBorderStrategy: PlasmaCore.AppletPopup.Never
        hideOnWindowDeactivate: true
        backgroundHints: PlasmaCore.AppletPopup.StandardBackground
        width: magicPointerView ? magicPointerView.implicitWidth : root.legacyDp(160.0)
        height: magicPointerView ? magicPointerView.implicitHeight : root.legacyDp(56.0)

        mainItem: MagicPointerUI.MagicPointerPopup {
            id: magicPointerView
        }
    }

    // 2. Notifications Popup Dialog
    PlasmaCore.AppletPopup {
        id: notifDialog
        visualParent: notifBellButton
        appletInterface: root
        popupDirection: Qt.BottomEdge
        margin: 1
        removeBorderStrategy: PlasmaCore.AppletPopup.Never
        hideOnWindowDeactivate: true
        backgroundHints: PlasmaCore.AppletPopup.StandardBackground
        width: notifFullView ? notifFullView.implicitWidth : root.px(376.0)
        height: notifFullView ? notifFullView.implicitHeight : root.px(588.0)

        onVisibleChanged: {
            if (notifDialog.visible) {
                NotifGlobal.Globals.popupNotificationsModel.hideInhibitionSummary();
                var popupModel = NotifGlobal.Globals.popupNotificationsModel;
                if (popupModel) {
                    for (var p = popupModel.rowCount() - 1; p >= 0; --p) {
                        popupModel.expire(popupModel.index(p, 0));
                    }
                }
            } else {
                if (notifHistoryModel) {
                    notifHistoryModel.lastRead = undefined; // reset to now in C++
                    notifHistoryModel.collapseAllGroups();
                }
            }
            NotifGlobal.Globals.positionPopups();
            root.updateUnreadNotifs();
        }

        mainItem: NotificationsUI.FullRepresentation {
            id: notifFullView
            appletInterface: root
            clearHistoryAction: clearHistoryAction
            historyModel: notifHistoryModel
        }
    }

    // 3. Quick Settings Drawer Dialog
    PlasmaCore.AppletPopup {
        id: qsDialog
        visualParent: qsPillButton
        appletInterface: root
        popupDirection: Qt.BottomEdge
        margin: 1
        removeBorderStrategy: PlasmaCore.AppletPopup.Never
        hideOnWindowDeactivate: true
        backgroundHints: PlasmaCore.AppletPopup.StandardBackground
        width: qsFullView ? qsFullView.implicitWidth : root.px(376.0)
        height: qsFullView ? qsFullView.implicitHeight : root.px(540.0)

        mainItem: QuickSettingsUI.FullRepresentation {
            id: qsFullView
            appletRoot: root
        }
    }

    // 4. App Tray Overflow Popup Dialog
    PlasmaCore.AppletPopup {
        id: trayOverflowDialog
        visualParent: trayGroup.overflowAnchorButton
        appletInterface: root
        popupDirection: Qt.BottomEdge
        margin: 1
        removeBorderStrategy: PlasmaCore.AppletPopup.Never
        hideOnWindowDeactivate: true
        backgroundHints: PlasmaCore.AppletPopup.StandardBackground
        width: trayOverflowView ? trayOverflowView.implicitWidth : root.legacyDp(260.0)
        height: trayOverflowView ? trayOverflowView.implicitHeight : root.legacyDp(160.0)

        mainItem: TrayUI.TrayOverflowPopup {
            id: trayOverflowView
            appletRoot: root
            trayBackend: trayBackend
        }
    }

    // 5. App Tray Item Menu Popup Dialog (DBusMenu Material You)
    PlasmaCore.AppletPopup {
        id: trayMenuDialog
        visualParent: trayGroup
        appletInterface: root
        popupDirection: Qt.BottomEdge
        margin: 1
        removeBorderStrategy: PlasmaCore.AppletPopup.Never
        hideOnWindowDeactivate: true
        backgroundHints: PlasmaCore.AppletPopup.StandardBackground
        width: trayMenuView ? trayMenuView.implicitWidth : root.legacyDp(224.0)
        height: trayMenuView ? trayMenuView.implicitHeight : root.legacyDp(140.0)

        onVisibleChanged: {
            if (!visible && trayMenuView && trayMenuView.itemKey.length > 0) {
                trayBackend.notifyMenuClosed(trayMenuView.itemKey);
            }
        }

        mainItem: TrayUI.TrayMenuPopup {
            id: trayMenuView
            appletRoot: root
            trayBackend: trayBackend
        }
    }
}

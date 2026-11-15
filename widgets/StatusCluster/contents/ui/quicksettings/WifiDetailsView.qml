import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.networkmanagement as PlasmaNM
import org.kde.kcmutils as KCMUtils
import "i18n.js" as I18n
import "../metrics" as LocalMetrics

Item {
    id: wifiViewRoot

    function i18n(k, a1, a2) { return I18n.t(k, a1, a2); }

    property var fullRep: null
    property string selectedSsidToConnect: ""
    property string passwordInput: ""
    property bool showPassword: false

    readonly property string appFontFamily: "Google Sans Flex"

    property bool isExpanded: false
    readonly property int totalNetworksCount: (currentConnFinder && currentConnFinder.hasActive ? 1 : 0) + visibleNetworksTracker.names.length
    readonly property bool shouldShowSeeAll: !isExpanded && totalNetworksCount > 4
    readonly property int maxVisibleAvailable: (currentConnFinder && currentConnFinder.hasActive) ? 2 : 3

    readonly property real dpr: LocalMetrics.Metrics.dpr
    function snap(val) {
        return LocalMetrics.Metrics.snap(val);
    }
    function px(val) {
        return LocalMetrics.Metrics.px(val);
    }
    function legacyDp(val) {
        return LocalMetrics.Metrics.legacyDp(val);
    }

    function wifiSignalIcon(signal) {
        var sig = (signal !== undefined && signal !== null) ? Number(signal) : 0;
        if (sig <= 0) return Qt.resolvedUrl("icons/wifi_0.svg");
        if (sig <= 33) return Qt.resolvedUrl("icons/wifi_1.svg");
        if (sig <= 66) return Qt.resolvedUrl("icons/wifi_2.svg");
        return Qt.resolvedUrl("icons/wifi_3.svg");
    }

    implicitHeight: viewHeader.height + scrollView.anchors.topMargin + contentCol.implicitHeight

    signal closeRequested()

    PlasmaNM.Handler {
        id: nmHandler
    }

    PlasmaNM.EnabledConnections {
        id: nmEnabled
    }

    Component {
        id: nmComponent
        PlasmaNM.NetworkModel {}
    }

    property var networkModel: null

    PlasmaNM.AppletProxyModel {
        id: appletProxyModel
    }

    Item {
        id: visibleNetworksTracker
        property var names: []

        function refresh() {
            var list = [];
            var count = appletProxyModel.rowCount();
            for (var i = 0; i < count; i++) {
                var idx = appletProxyModel.index(i, 0);
                var n = appletProxyModel.data(idx, PlasmaNM.NetworkModel.NameRole) || "";
                var st = appletProxyModel.data(idx, PlasmaNM.NetworkModel.ConnectionStateRole);
                if (n.length > 0 && st !== PlasmaNM.Enums.Activated) {
                    list.push(n);
                }
            }
            names = list;
        }

        Connections {
            target: appletProxyModel
            function onDataChanged() { visibleNetworksTracker.refresh(); }
            function onRowsInserted() { visibleNetworksTracker.refresh(); }
            function onRowsRemoved() { visibleNetworksTracker.refresh(); }
            function onModelReset() { visibleNetworksTracker.refresh(); }
        }
    }

    onVisibleChanged: {
        if (visible) {
            if (!networkModel) {
                networkModel = nmComponent.createObject(wifiViewRoot);
                appletProxyModel.sourceModel = networkModel;
            }
            nmHandler.requestScan();
            visibleNetworksTracker.refresh();
        } else {
            isExpanded = false;
            selectedSsidToConnect = "";
            passwordInput = "";
            showPassword = false;
        }
    }

    // Top Sticky Header
    Rectangle {
        id: viewHeader
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: headerCol.anchors.topMargin + headerCol.implicitHeight + wifiViewRoot.legacyDp(8.0)
        color: "transparent"
        z: 10

        // Back Arrow Button (Left)
        Rectangle {
            id: backBtn
            anchors.left: parent.left
            anchors.top: parent.top
            width: wifiViewRoot.legacyDp(32.0)
            height: wifiViewRoot.legacyDp(32.0)
            radius: wifiViewRoot.legacyDp(8.0)
            color: backMouse.pressed
                   ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.18)
                   : (backMouse.containsMouse ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.1) : "transparent")

            Kirigami.Icon {
                anchors.centerIn: parent
                width: wifiViewRoot.legacyDp(24.0)
                height: wifiViewRoot.legacyDp(24.0)
                source: Qt.resolvedUrl("icons/arrow_back.svg")
                isMask: true
                color: Kirigami.Theme.textColor
            }

            MouseArea {
                id: backMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    wifiViewRoot.closeRequested();
                }
            }
        }

        // Center Titles & Separator
        ColumnLayout {
            id: headerCol
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: wifiViewRoot.snap((backBtn.height - internetLabel.implicitHeight) / 2)
            spacing: wifiViewRoot.legacyDp(4.8)

            PlasmaComponents3.Label {
                id: internetLabel
                text: i18n("Internet")
                font.family: wifiViewRoot.appFontFamily
                font.bold: true
                font.pixelSize: wifiViewRoot.legacyDp(12.0)
                color: Kirigami.Theme.textColor
                Layout.alignment: Qt.AlignHCenter
            }

            PlasmaComponents3.Label {
                text: i18n("Tap a network to connect")
                font.family: wifiViewRoot.appFontFamily
                font.pixelSize: wifiViewRoot.legacyDp(9.6)
                color: Kirigami.Theme.disabledTextColor
                Layout.alignment: Qt.AlignHCenter
            }

            Rectangle {
                Layout.topMargin: wifiViewRoot.legacyDp(4.8)
                Layout.preferredWidth: wifiViewRoot.legacyDp(136.8)
                Layout.preferredHeight: wifiViewRoot.legacyDp(4.0)
                Layout.alignment: Qt.AlignHCenter
                radius: wifiViewRoot.legacyDp(2.0)
                color: fullRep ? fullRep.oneUiTrackBg : Kirigami.Theme.alternateBackgroundColor
            }
        }

        // Scan / Refresh Button (Right Top)
        Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            width: wifiViewRoot.legacyDp(32.0)
            height: wifiViewRoot.legacyDp(32.0)
            radius: wifiViewRoot.legacyDp(8.0)
            visible: Boolean(nmEnabled.wirelessEnabled)
            color: scanMouse.pressed
                   ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.18)
                   : (scanMouse.containsMouse ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.1) : "transparent")

            Kirigami.Icon {
                id: refreshIcon
                anchors.centerIn: parent
                width: wifiViewRoot.legacyDp(25.6)
                height: wifiViewRoot.legacyDp(25.6)
                source: Qt.resolvedUrl("icons/refresh.svg")
                isMask: true
                color: Kirigami.Theme.textColor

                RotationAnimation on rotation {
                    running: nmHandler.scanning
                    from: 0
                    to: 360
                    duration: 1000
                    loops: Animation.Infinite
                }
            }

            MouseArea {
                id: scanMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    nmHandler.requestScan();
                }
            }
        }
    }

    // Scrollable Content
    QQC2.ScrollView {
        id: scrollView
        anchors.top: viewHeader.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: wifiViewRoot.legacyDp(8.0)
        clip: true
        contentWidth: availableWidth
        QQC2.ScrollBar.vertical.policy: QQC2.ScrollBar.AlwaysOff
        QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

        ColumnLayout {
            id: contentCol
            width: scrollView.availableWidth
            spacing: 0

            // === 1. WHEN WI-FI IS DISABLED ===
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: wifiViewRoot.legacyDp(180.0)
                radius: wifiViewRoot.legacyDp(16.0)
                color: fullRep ? fullRep.oneUiTrackBg : Kirigami.Theme.alternateBackgroundColor
                visible: !nmEnabled.wirelessEnabled

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: wifiViewRoot.legacyDp(10.0)

                    Kirigami.Icon {
                        source: Qt.resolvedUrl("icons/wifi_panel.svg")
                        Layout.preferredWidth: wifiViewRoot.legacyDp(42.0)
                        Layout.preferredHeight: wifiViewRoot.legacyDp(42.0)
                        Layout.alignment: Qt.AlignHCenter
                        opacity: 0.4
                        isMask: true
                        color: Kirigami.Theme.textColor
                    }

                    PlasmaComponents3.Label {
                        text: i18n("Wi-Fi is off")
                        font.family: wifiViewRoot.appFontFamily
                        font.bold: true
                        font.pixelSize: wifiViewRoot.snap(Kirigami.Theme.defaultFont.pixelSize * 1.15 * LocalMetrics.Metrics.clampedScale)
                        color: Kirigami.Theme.textColor
                        Layout.alignment: Qt.AlignHCenter
                    }

                    PlasmaComponents3.Label {
                        text: i18n("Turn on Wi-Fi to see available networks.")
                        font.family: wifiViewRoot.appFontFamily
                        font.pixelSize: wifiViewRoot.snap(Kirigami.Theme.smallFont.pixelSize * 1.05 * LocalMetrics.Metrics.clampedScale)
                        color: Kirigami.Theme.disabledTextColor
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredHeight: wifiViewRoot.legacyDp(36.0)
                        Layout.preferredWidth: wifiViewRoot.legacyDp(130.0)
                        radius: wifiViewRoot.legacyDp(18.0)
                        color: fullRep ? fullRep.effectiveAccentColor : Kirigami.Theme.highlightColor

                        PlasmaComponents3.Label {
                            anchors.centerIn: parent
                            text: i18n("Turn on Wi-Fi")
                            font.family: wifiViewRoot.appFontFamily
                            font.bold: true
                            font.pixelSize: wifiViewRoot.snap(Kirigami.Theme.defaultFont.pixelSize * LocalMetrics.Metrics.clampedScale)
                            color: Kirigami.Theme.highlightedTextColor
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                nmHandler.enableWireless(true);
                            }
                        }
                    }
                }
            }

            // === 2. WHEN WI-FI IS ENABLED ===
            ColumnLayout {
                Layout.fillWidth: true
                spacing: wifiViewRoot.legacyDp(1.6)
                visible: Boolean(nmEnabled.wirelessEnabled)

                // Wi-Fi Label + Material 3 Switch Row
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: wifiViewRoot.legacyDp(32.0)
                    Layout.topMargin: wifiViewRoot.legacyDp(14.4)
                    Layout.leftMargin: wifiViewRoot.legacyDp(19.2)
                    Layout.rightMargin: wifiViewRoot.legacyDp(19.2)
                    Layout.bottomMargin: wifiViewRoot.legacyDp(14.4)

                    PlasmaComponents3.Label {
                        text: i18n("Wi-Fi")
                        font.family: wifiViewRoot.appFontFamily
                        font.bold: true
                        font.pixelSize: wifiViewRoot.legacyDp(12.0)
                        color: Kirigami.Theme.textColor
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    // Material 3 Expressive Switch
                    Item {
                        id: m3Switch
                        Layout.preferredWidth: wifiViewRoot.legacyDp(36.8)
                        Layout.preferredHeight: wifiViewRoot.legacyDp(22.4)
                        Layout.alignment: Qt.AlignVCenter

                        readonly property bool checked: Boolean(nmEnabled.wirelessEnabled)

                        // Track (Szyna kapsułkowa)
                        Rectangle {
                            id: switchTrack
                            anchors.fill: parent
                            radius: height / 2.0
                            color: m3Switch.checked
                                   ? (fullRep ? fullRep.effectiveAccentColor : Kirigami.Theme.highlightColor)
                                   : (fullRep ? fullRep.oneUiTrackBg : Kirigami.Theme.alternateBackgroundColor)
                            border.width: m3Switch.checked ? 0 : 1.5
                            border.color: fullRep ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.28) : Kirigami.Theme.separatorColor

                            Behavior on color { ColorAnimation { duration: 150 } }
                            Behavior on border.color { ColorAnimation { duration: 150 } }

                            // Thumb (Gałka M3 powiększająca się i przesuwająca)
                            Rectangle {
                                id: switchThumb
                                height: m3Switch.checked ? wifiViewRoot.legacyDp(16.8) : wifiViewRoot.legacyDp(11.2)
                                width: height
                                radius: height / 2.0
                                anchors.verticalCenter: parent.verticalCenter
                                x: m3Switch.checked
                                   ? (parent.width - width - wifiViewRoot.legacyDp(2.8))
                                   : wifiViewRoot.legacyDp(3.6)

                                color: m3Switch.checked
                                       ? (Kirigami.Theme.highlightedTextColor)
                                       : (Kirigami.Theme.textColor)

                                Behavior on x {
                                    NumberAnimation {
                                        duration: 200
                                        easing.type: Easing.OutCubic
                                    }
                                }
                                Behavior on height {
                                    NumberAnimation {
                                        duration: 150
                                        easing.type: Easing.OutCubic
                                    }
                                }
                                Behavior on color { ColorAnimation { duration: 150 } }

                                // Checkmark icon wewnątrz gałki po włączeniu
                                Kirigami.Icon {
                                    anchors.centerIn: parent
                                    width: wifiViewRoot.legacyDp(9.6)
                                    height: wifiViewRoot.legacyDp(9.6)
                                    source: Qt.resolvedUrl("icons/check.svg")
                                    isMask: true
                                    color: fullRep ? fullRep.effectiveAccentColor : Kirigami.Theme.highlightColor
                                    opacity: m3Switch.checked ? 1.0 : 0.0
                                    visible: opacity > 0.0

                                    Behavior on opacity {
                                        NumberAnimation { duration: 150 }
                                    }
                                }
                            }
                        }

                        MouseArea {
                            id: switchMouse
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                nmHandler.enableWireless(!m3Switch.checked);
                            }
                        }
                    }
                }

                // Finder for active connection
                Item {
                    id: currentConnFinder
                    property bool hasActive: false
                    property string activeName: ""
                    property string activeConnPath: ""
                    property string activeDevPath: ""
                    property int activeSignalInt: 0
                    property int activeSecType: 0
                    property bool isSecured: false

                    function updateActive() {
                        var count = appletProxyModel.rowCount();
                        for (var i = 0; i < count; i++) {
                            var idx = appletProxyModel.index(i, 0);
                            var state = appletProxyModel.data(idx, PlasmaNM.NetworkModel.ConnectionStateRole);
                            if (state === PlasmaNM.Enums.Activated) {
                                activeName = appletProxyModel.data(idx, PlasmaNM.NetworkModel.NameRole) || "";
                                activeConnPath = appletProxyModel.data(idx, PlasmaNM.NetworkModel.ConnectionPathRole) || "";
                                activeDevPath = appletProxyModel.data(idx, PlasmaNM.NetworkModel.DevicePathRole) || "";
                                var sig = appletProxyModel.data(idx, PlasmaNM.NetworkModel.SignalRole);
                                activeSignalInt = (sig !== undefined && sig !== null) ? Number(sig) : 0;
                                var sec = appletProxyModel.data(idx, PlasmaNM.NetworkModel.SecurityTypeRole);
                                activeSecType = (sec !== undefined && sec !== null) ? Number(sec) : 0;
                                isSecured = (activeSecType !== PlasmaNM.Enums.None);
                                hasActive = (activeName.length > 0);
                                return;
                            }
                        }
                        hasActive = false;
                        activeName = "";
                        activeConnPath = "";
                        activeDevPath = "";
                        activeSignalInt = 0;
                        activeSecType = 0;
                        isSecured = false;
                    }

                    Connections {
                        target: appletProxyModel
                        function onDataChanged() { currentConnFinder.updateActive(); }
                        function onRowsInserted() { currentConnFinder.updateActive(); }
                        function onRowsRemoved() { currentConnFinder.updateActive(); }
                        function onModelReset() { currentConnFinder.updateActive(); }
                    }
                }

                // Active connected network tile (if any)
                Rectangle {
                    id: activeNetTile
                    Layout.fillWidth: true
                    Layout.preferredHeight: wifiViewRoot.px(72.0)
                    radius: wifiViewRoot.legacyDp(16.0)
                    topLeftRadius: wifiViewRoot.legacyDp(16.0)
                    topRightRadius: wifiViewRoot.legacyDp(16.0)
                    bottomLeftRadius: wifiViewRoot.legacyDp(16.0)
                    bottomRightRadius: wifiViewRoot.legacyDp(16.0)
                    visible: Boolean(currentConnFinder.hasActive)
                    color: fullRep ? fullRep.effectiveAccentColor : Kirigami.Theme.highlightColor

                    readonly property color onPrimaryColor: Kirigami.Theme.highlightedTextColor

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: wifiViewRoot.legacyDp(18.4)
                        anchors.rightMargin: wifiViewRoot.legacyDp(17.6)
                        spacing: wifiViewRoot.legacyDp(12.0)

                        // Wi-Fi Signal Icon (z gradientem/stopniami siły sygnału)
                        Kirigami.Icon {
                            Layout.preferredWidth: wifiViewRoot.legacyDp(22.0)
                            Layout.preferredHeight: wifiViewRoot.legacyDp(22.0)
                            Layout.alignment: Qt.AlignVCenter
                            source: wifiViewRoot.wifiSignalIcon(currentConnFinder.activeSignalInt)
                            isMask: true
                            color: activeNetTile.onPrimaryColor
                        }

                        // Network Title + Connected subtitle
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: wifiViewRoot.legacyDp(2.4)

                            PlasmaComponents3.Label {
                                text: currentConnFinder.activeName
                                font.family: wifiViewRoot.appFontFamily
                                font.bold: false
                                font.weight: Font.DemiBold // waga 600
                                font.pixelSize: wifiViewRoot.legacyDp(12.4)
                                color: activeNetTile.onPrimaryColor
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            PlasmaComponents3.Label {
                                text: i18n("Connected")
                                font.family: wifiViewRoot.appFontFamily
                                font.pixelSize: wifiViewRoot.legacyDp(9.6)
                                color: Qt.rgba(activeNetTile.onPrimaryColor.r, activeNetTile.onPrimaryColor.g, activeNetTile.onPrimaryColor.b, 0.92)
                                Layout.fillWidth: true
                            }
                        }

                        // Ikonka ustawień po prawej stronie (settings1.svg) powiększona
                        Rectangle {
                            Layout.preferredWidth: wifiViewRoot.legacyDp(28.8)
                            Layout.preferredHeight: wifiViewRoot.legacyDp(28.8)
                            Layout.alignment: Qt.AlignVCenter
                            radius: wifiViewRoot.legacyDp(7.2)
                            color: activeSettingsMouse.pressed ? Qt.rgba(0, 0, 0, 0.25)
                                                               : (activeSettingsMouse.containsMouse ? Qt.rgba(0, 0, 0, 0.15) : "transparent")

                            Kirigami.Icon {
                                anchors.centerIn: parent
                                width: wifiViewRoot.legacyDp(22.4)
                                height: wifiViewRoot.legacyDp(22.4)
                                source: Qt.resolvedUrl("icons/settings1.svg")
                                isMask: true
                                color: activeNetTile.onPrimaryColor
                            }

                            MouseArea {
                                id: activeSettingsMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    KCMUtils.KCMLauncher.openSystemSettings("kcm_networkmanagement");
                                    if (wifiViewRoot.fullRep) {
                                        wifiViewRoot.fullRep.closeDrawer();
                                    }
                                }
                            }
                        }
                    }
                }

                // Networks Repeater (Available networks)
                Repeater {
                    model: appletProxyModel

                    delegate: ColumnLayout {
                        id: networkDelegate
                        Layout.fillWidth: true
                        spacing: wifiViewRoot.legacyDp(1.6)

                        readonly property string netName: model.Name || ""
                        readonly property int netSignal: (model.Signal !== undefined && model.Signal !== null) ? model.Signal : 0
                        readonly property int netState: (model.ConnectionState !== undefined) ? model.ConnectionState : 0
                        readonly property string netConnPath: model.ConnectionPath || ""
                        readonly property string netDevPath: model.DevicePath || ""
                        readonly property string netSpecPath: model.SpecificPath || ""
                        readonly property int netSecType: (model.SecurityType !== undefined) ? model.SecurityType : 0
                        readonly property bool isSecured: netSecType !== PlasmaNM.Enums.None
                        readonly property bool isActivated: netState === PlasmaNM.Enums.Activated
                        readonly property bool isActivating: netState === PlasmaNM.Enums.Activating
                        readonly property bool isPromptingPassword: wifiViewRoot.selectedSsidToConnect === netName

                        readonly property int visibleIdx: visibleNetworksTracker.names.indexOf(netName)
                        readonly property int visibleTotal: visibleNetworksTracker.names.length
                        readonly property bool isSingleItem: visibleTotal <= 1
                        readonly property bool isFirstItem: visibleIdx === 0
                        readonly property bool isLastItem: visibleIdx >= 0 && visibleIdx === (visibleTotal - 1)

                        visible: netName.length > 0 && !isActivated && (!wifiViewRoot.shouldShowSeeAll || visibleIdx < wifiViewRoot.maxVisibleAvailable)

                        // Network Tile Row
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: wifiViewRoot.px(72.0)
                            radius: 1
                            topLeftRadius: (networkDelegate.isSingleItem || networkDelegate.isFirstItem) ? wifiViewRoot.legacyDp(16.0) : 1
                            topRightRadius: (networkDelegate.isSingleItem || networkDelegate.isFirstItem) ? wifiViewRoot.legacyDp(16.0) : 1
                            bottomLeftRadius: (!wifiViewRoot.shouldShowSeeAll && (networkDelegate.isSingleItem || networkDelegate.isLastItem)) ? wifiViewRoot.legacyDp(16.0) : 1
                            bottomRightRadius: (!wifiViewRoot.shouldShowSeeAll && (networkDelegate.isSingleItem || networkDelegate.isLastItem)) ? wifiViewRoot.legacyDp(16.0) : 1
                            color: itemMouseArea.pressed
                                   ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.16)
                                   : (itemMouseArea.containsMouse ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08) : (fullRep ? fullRep.oneUiTrackBg : Kirigami.Theme.alternateBackgroundColor))

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: wifiViewRoot.legacyDp(18.4)
                                anchors.rightMargin: wifiViewRoot.legacyDp(17.6)
                                spacing: wifiViewRoot.legacyDp(12.0)

                                // Wi-Fi Signal Icon (ze stopniami siły sygnału)
                                Kirigami.Icon {
                                    Layout.preferredWidth: wifiViewRoot.legacyDp(22.0)
                                    Layout.preferredHeight: wifiViewRoot.legacyDp(22.0)
                                    Layout.alignment: Qt.AlignVCenter
                                    source: wifiViewRoot.wifiSignalIcon(networkDelegate.netSignal)
                                    isMask: true
                                    color: Kirigami.Theme.textColor
                                }

                                // Network Title Only (bez napisów z mocą i zabezpieczeniami)
                                PlasmaComponents3.Label {
                                    text: networkDelegate.netName
                                    font.family: wifiViewRoot.appFontFamily
                                    font.bold: false
                                    font.weight: Font.DemiBold // waga 600
                                    font.pixelSize: wifiViewRoot.legacyDp(12.4)
                                    color: Kirigami.Theme.textColor
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                // Kłódka po prawej stronie kafelka
                                Item {
                                    Layout.preferredWidth: wifiViewRoot.legacyDp(28.8)
                                    Layout.preferredHeight: wifiViewRoot.legacyDp(28.8)
                                    Layout.alignment: Qt.AlignVCenter
                                    visible: networkDelegate.isSecured

                                    Kirigami.Icon {
                                        anchors.centerIn: parent
                                        width: wifiViewRoot.legacyDp(22.4)
                                        height: wifiViewRoot.legacyDp(22.4)
                                        source: Qt.resolvedUrl("icons/custom_lock.svg")
                                        isMask: true
                                        color: Kirigami.Theme.disabledTextColor
                                    }
                                }

                                PlasmaComponents3.BusyIndicator {
                                    Layout.preferredWidth: wifiViewRoot.legacyDp(22.0)
                                    Layout.preferredHeight: wifiViewRoot.legacyDp(22.0)
                                    Layout.alignment: Qt.AlignVCenter
                                    running: networkDelegate.isActivating
                                    visible: networkDelegate.isActivating
                                }
                            }

                            MouseArea {
                                id: itemMouseArea
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    if (networkDelegate.isActivating) return;
                                    // If saved connection profile exists
                                    if (networkDelegate.netConnPath.length > 0) {
                                        nmHandler.activateConnection(networkDelegate.netConnPath, networkDelegate.netDevPath, networkDelegate.netSpecPath);
                                    } else if (!networkDelegate.isSecured) {
                                        // Open network without password
                                        nmHandler.addAndActivateConnection(networkDelegate.netDevPath, networkDelegate.netSpecPath);
                                    } else {
                                        // Password needed
                                        if (wifiViewRoot.selectedSsidToConnect === networkDelegate.netName) {
                                            wifiViewRoot.selectedSsidToConnect = "";
                                        } else {
                                            wifiViewRoot.selectedSsidToConnect = networkDelegate.netName;
                                            wifiViewRoot.passwordInput = "";
                                        }
                                    }
                                }
                            }
                        }

                        // Inline Password Input Card
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: pwdCol.implicitHeight + wifiViewRoot.legacyDp(20.0)
                            radius: wifiViewRoot.legacyDp(12.0)
                            color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.06)
                            border.width: 1
                            border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)
                            visible: networkDelegate.isPromptingPassword

                            ColumnLayout {
                                id: pwdCol
                                anchors.fill: parent
                                anchors.margins: wifiViewRoot.legacyDp(10.0)
                                spacing: wifiViewRoot.legacyDp(8.0)

                                PlasmaComponents3.Label {
                                    text: i18n("Enter password for %1:", networkDelegate.netName)
                                    font.family: wifiViewRoot.appFontFamily
                                    font.bold: true
                                    font.pixelSize: wifiViewRoot.snap(Kirigami.Theme.smallFont.pixelSize * LocalMetrics.Metrics.clampedScale)
                                    color: Kirigami.Theme.textColor
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: wifiViewRoot.legacyDp(8.0)

                                    QQC2.TextField {
                                        id: pwdField
                                        Layout.fillWidth: true
                                        font.family: wifiViewRoot.appFontFamily
                                        font.pixelSize: wifiViewRoot.snap(Kirigami.Theme.defaultFont.pixelSize * LocalMetrics.Metrics.clampedScale)
                                        placeholderText: i18n("Network password")
                                        echoMode: wifiViewRoot.showPassword ? TextInput.Normal : TextInput.Password
                                        text: wifiViewRoot.passwordInput
                                        onTextChanged: {
                                            wifiViewRoot.passwordInput = text;
                                        }
                                        onAccepted: {
                                            if (text.length > 0) {
                                                nmHandler.addAndActivateConnection(networkDelegate.netDevPath, networkDelegate.netSpecPath, text);
                                                wifiViewRoot.selectedSsidToConnect = "";
                                            }
                                        }
                                    }

                                    // Eye toggle
                                    Rectangle {
                                        width: wifiViewRoot.legacyDp(32.0)
                                        height: wifiViewRoot.legacyDp(32.0)
                                        radius: wifiViewRoot.legacyDp(6.0)
                                        color: eyeMouse.containsMouse ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12) : "transparent"

                                        Kirigami.Icon {
                                            anchors.centerIn: parent
                                            width: wifiViewRoot.legacyDp(18.0)
                                            height: wifiViewRoot.legacyDp(18.0)
                                            source: wifiViewRoot.showPassword ? "visibility" : "hint"
                                            color: Kirigami.Theme.textColor
                                        }

                                        MouseArea {
                                            id: eyeMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onClicked: {
                                                wifiViewRoot.showPassword = !wifiViewRoot.showPassword;
                                            }
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: wifiViewRoot.legacyDp(8.0)

                                    Item { Layout.fillWidth: true }

                                    PlasmaComponents3.Button {
                                        text: i18n("Cancel")
                                        font.family: wifiViewRoot.appFontFamily
                                        onClicked: {
                                            wifiViewRoot.selectedSsidToConnect = "";
                                        }
                                    }

                                    PlasmaComponents3.Button {
                                        text: i18n("Connect")
                                        font.family: wifiViewRoot.appFontFamily
                                        highlighted: true
                                        enabled: wifiViewRoot.passwordInput.length >= 8
                                        onClicked: {
                                            nmHandler.addAndActivateConnection(networkDelegate.netDevPath, networkDelegate.netSpecPath, wifiViewRoot.passwordInput);
                                            wifiViewRoot.selectedSsidToConnect = "";
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // "See all" Tile (shown when shouldShowSeeAll)
                Rectangle {
                    id: seeAllTile
                    Layout.fillWidth: true
                    Layout.preferredHeight: wifiViewRoot.px(72.0)
                    radius: 1
                    topLeftRadius: 1
                    topRightRadius: 1
                    bottomLeftRadius: wifiViewRoot.legacyDp(16.0)
                    bottomRightRadius: wifiViewRoot.legacyDp(16.0)
                    visible: wifiViewRoot.shouldShowSeeAll
                    color: seeAllMouse.pressed
                           ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.16)
                           : (seeAllMouse.containsMouse ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08) : (fullRep ? fullRep.oneUiTrackBg : Kirigami.Theme.alternateBackgroundColor))

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: wifiViewRoot.legacyDp(18.4)
                        anchors.rightMargin: wifiViewRoot.legacyDp(17.6)
                        spacing: wifiViewRoot.legacyDp(12.0)

                        // Arrow right icon
                        Kirigami.Icon {
                            Layout.preferredWidth: wifiViewRoot.legacyDp(22.0)
                            Layout.preferredHeight: wifiViewRoot.legacyDp(22.0)
                            Layout.alignment: Qt.AlignVCenter
                            source: Qt.resolvedUrl("icons/arrow_right.svg")
                            isMask: true
                            color: Kirigami.Theme.textColor
                        }

                        // "See all" label
                        PlasmaComponents3.Label {
                            text: i18n("See all")
                            font.family: wifiViewRoot.appFontFamily
                            font.bold: false
                            font.weight: Font.Medium // waga 500
                            font.pixelSize: wifiViewRoot.legacyDp(12.4)
                            color: Kirigami.Theme.textColor
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                        }
                    }

                    MouseArea {
                        id: seeAllMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            wifiViewRoot.isExpanded = true;
                        }
                    }
                }
            }

            // === 3. BOTTOM MORE SETTINGS ACTION ===
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: wifiViewRoot.legacyDp(36.0)
                Layout.topMargin: wifiViewRoot.legacyDp(80.0)
                radius: height / 2.0
                color: moreNetMouse.pressed
                       ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.18)
                       : (moreNetMouse.containsMouse ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08) : (fullRep ? fullRep.oneUiTrackBg : Kirigami.Theme.alternateBackgroundColor))

                RowLayout {
                    anchors.centerIn: parent
                    spacing: wifiViewRoot.legacyDp(8.0)

                    Kirigami.Icon {
                        Layout.preferredWidth: wifiViewRoot.legacyDp(16.0)
                        Layout.preferredHeight: wifiViewRoot.legacyDp(16.0)
                        Layout.alignment: Qt.AlignVCenter
                        source: Qt.resolvedUrl("icons/settings.svg")
                        isMask: true
                        color: Kirigami.Theme.textColor
                    }

                    PlasmaComponents3.Label {
                        text: i18n("More Wi-Fi settings")
                        font.family: wifiViewRoot.appFontFamily
                        font.pixelSize: wifiViewRoot.snap(Kirigami.Theme.defaultFont.pixelSize * LocalMetrics.Metrics.clampedScale)
                        color: Kirigami.Theme.textColor
                        Layout.alignment: Qt.AlignVCenter
                    }
                }

                MouseArea {
                    id: moreNetMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        KCMUtils.KCMLauncher.openSystemSettings("kcm_networkmanagement");
                        if (wifiViewRoot.fullRep) {
                            wifiViewRoot.fullRep.closeDrawer();
                        }
                    }
                }
            }
        }
    }
}

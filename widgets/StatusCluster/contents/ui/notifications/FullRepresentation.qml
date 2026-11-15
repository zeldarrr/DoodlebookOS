/*
    SPDX-FileCopyrightText: 2018-2019 Kai Uwe Broulik <kde@privat.broulik.de>
    SPDX-FileCopyrightText: 2026 DoodlebookOS

    SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import QtQuick.Layouts

import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCMUtils

import org.kde.notificationmanager as NotificationManager

import "i18n.js" as I18n
import "../metrics" as LocalMetrics

PlasmaExtras.Representation {
    id: fullRepresentationRoot

    function i18n(k, a1, a2) { return I18n.t(k, a1, a2); }

    required property PlasmoidItem appletInterface
    required property PlasmaCore.Action clearHistoryAction
    required property NotificationManager.Notifications historyModel

    readonly property bool hasNotifications: (historyList && historyList.count > 0) || (historyModel && historyModel.count > 0)

    Item {
        id: buttonThemeScope
        Kirigami.Theme.colorSet: Kirigami.Theme.Button
        Kirigami.Theme.inherit: false
    }

    readonly property color cardBackgroundColor: buttonThemeScope ? buttonThemeScope.Kirigami.Theme.backgroundColor : Kirigami.Theme.backgroundColor

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

    // Punkt 0 referencyjna szerokość panelu powiadomień (376 px fizycznych)
    Layout.preferredWidth: px(376.0)
    Layout.minimumWidth: Layout.preferredWidth
    Layout.maximumWidth: Layout.preferredWidth

    // Marginesy z Notifications.png: boczne i górny 16px, dolny 14px
    readonly property real sideMargin: px(16.0)
    readonly property real topMargin: px(16.0)
    readonly property real bottomMargin: px(14.0)

    readonly property real baseHeight: legacyDp(240.0)
    readonly property real availableScreenH: (typeof Screen !== "undefined" && Screen.desktopAvailableHeight > 0)
        ? Screen.desktopAvailableHeight
        : ((typeof Screen !== "undefined" && Screen.height > 0) ? Screen.height : 1080)
    readonly property real maxPopupHeight: Math.min(legacyDp(750.0), Math.max(legacyDp(240.0), availableScreenH - px(56.0) - px(16.0)))

    readonly property real calculatedHeight: {
        if (!hasNotifications) {
            return baseHeight;
        }
        var ch = (historyList && historyList.contentHeight > 0)
            ? historyList.contentHeight
            : (historyModel ? historyModel.count * legacyDp(76.0) : 0);
        var extraVertical = topMargin + px(16.0) + px(40.0) + bottomMargin;
        return Math.min(maxPopupHeight, Math.max(baseHeight, ch + extraVertical));
    }

    Layout.minimumHeight: baseHeight
    Layout.preferredHeight: calculatedHeight
    Layout.maximumHeight: maxPopupHeight

    implicitWidth: Layout.preferredWidth
    implicitHeight: Layout.preferredHeight
    width: Layout.preferredWidth
    height: Layout.preferredHeight

    Layout.fillHeight: Plasmoid.formFactor === PlasmaCore.Types.Vertical

    header: null
    footer: null

    property int timeTick: 0

    Timer {
        id: relativeTimeTimer
        interval: 30000
        repeat: true
        running: Boolean(fullRepresentationRoot.Window && fullRepresentationRoot.Window.window && fullRepresentationRoot.Window.window.visible)
        onTriggered: fullRepresentationRoot.timeTick += 1
    }

    Binding {
        when: fullRepresentationRoot.Window && fullRepresentationRoot.Window.window !== null && fullRepresentationRoot.Window.window.hasOwnProperty("margin")
        target: fullRepresentationRoot.Window ? fullRepresentationRoot.Window.window : null
        property: "margin"
        value: 1
    }

    Connections {
        target: fullRepresentationRoot.Window ? fullRepresentationRoot.Window.window : null
        function onVisibleChanged() {
            var win = fullRepresentationRoot.Window ? fullRepresentationRoot.Window.window : null;
            if (win && win.visible) {
                fullRepresentationRoot.timeTick += 1;
                if (historyList) {
                    historyList.positionViewAtBeginning();
                    historyList.currentIndex = -1;
                }
                Qt.callLater(() => {
                    if (!win || !win.visible || !win.screen) return;
                    var screenW = win.screen.geometry.width;
                    var screenX = win.screen.geometry.x;
                    var rightEdge = screenX + screenW;
                    var offset = 8;
                    if ((win.x + win.width) > (rightEdge - offset)) {
                        win.x = rightEdge - win.width - offset;
                    }
                });
            }
        }
    }

    function formatRelativeTime(date) {
        if (!date || isNaN(date.getTime())) return "";
        var now = Date.now();
        var diffMs = now - date.getTime();
        if (diffMs < 0) return i18n("now");
        var diffSec = Math.floor(diffMs / 1000);
        if (diffSec < 60) return i18n("now");
        var diffMin = Math.floor(diffSec / 60);
        if (diffMin < 60) return diffMin + " " + i18n("min");
        var diffHours = Math.floor(diffMin / 60);
        if (diffHours < 24) return diffHours + " " + i18n("h");
        var diffDays = Math.floor(diffHours / 24);
        return diffDays + " " + i18n("d");
    }

    function clearAllNotifications() {
        fullRepresentationRoot.clearHistoryAction.trigger();
        if (fullRepresentationRoot.historyModel) {
            fullRepresentationRoot.historyModel.clear(NotificationManager.Notifications.ClearExpired);
            for (var i = fullRepresentationRoot.historyModel.count - 1; i >= 0; --i) {
                var idx = fullRepresentationRoot.historyModel.index(i, 0);
                if (fullRepresentationRoot.historyModel.data(idx, NotificationManager.Notifications.ClosableRole)) {
                    fullRepresentationRoot.historyModel.close(idx);
                }
            }
        }
    }



    contentItem: Item {
        id: mainContainer

        // 1. Populated State: Notification Cards List
        ListView {
            id: historyList
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                bottom: bottomBar.top
                topMargin: fullRepresentationRoot.topMargin
                leftMargin: fullRepresentationRoot.sideMargin
                rightMargin: fullRepresentationRoot.sideMargin
                bottomMargin: fullRepresentationRoot.px(16.0)
            }
            model: fullRepresentationRoot.historyModel
            spacing: 0
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            currentIndex: -1

            delegate: Item {
                id: delegateRoot
                width: historyList.width
                implicitHeight: delegateCol.implicitHeight

                required property int index
                required property var model

                required property int type
                required property bool hasDefaultAction
                required property list<string> actionLabels
                required property list<string> actionNames
                required property string applicationName
                required property string applicationIconName
                required property date updated
                required property date created
                required property string summary
                required property string body
                required property var image
                required property string iconName
                required property list<url> urls
                required property int percentage
                required property bool resident
                required property int urgency
                required property bool hasReplyAction
                required property string replyActionLabel
                required property string replyPlaceholderText

                property bool cardExpanded: true

                readonly property bool isSilent: urgency === NotificationManager.Notifications.LowUrgency
                readonly property bool showSilentHeader: {
                    if (!isSilent) return false;
                    if (index === 0) return true;
                    var prevIdx = fullRepresentationRoot.historyModel.index(index - 1, 0);
                    var prevUrgency = fullRepresentationRoot.historyModel.data(prevIdx, NotificationManager.Notifications.UrgencyRole);
                    return prevUrgency !== NotificationManager.Notifications.LowUrgency;
                }

                readonly property string currentApp: delegateRoot.applicationName || ""
                readonly property bool prevSameApp: {
                    if (delegateRoot.index <= 0 || !fullRepresentationRoot.historyModel) return false;
                    var pIdx = fullRepresentationRoot.historyModel.index(delegateRoot.index - 1, 0);
                    var pApp = fullRepresentationRoot.historyModel.data(pIdx, NotificationManager.Notifications.ApplicationNameRole) || "";
                    var pUrg = fullRepresentationRoot.historyModel.data(pIdx, NotificationManager.Notifications.UrgencyRole);
                    var isPrevSilent = (pUrg === NotificationManager.Notifications.LowUrgency);
                    return (pApp === currentApp) && (delegateRoot.isSilent === isPrevSilent);
                }
                readonly property bool nextSameApp: {
                    if (!fullRepresentationRoot.historyModel || delegateRoot.index >= (fullRepresentationRoot.historyModel.count - 1)) return false;
                    var nIdx = fullRepresentationRoot.historyModel.index(delegateRoot.index + 1, 0);
                    var nApp = fullRepresentationRoot.historyModel.data(nIdx, NotificationManager.Notifications.ApplicationNameRole) || "";
                    var nUrg = fullRepresentationRoot.historyModel.data(nIdx, NotificationManager.Notifications.UrgencyRole);
                    var isNextSilent = (nUrg === NotificationManager.Notifications.LowUrgency);
                    return (nApp === currentApp) && (delegateRoot.isSilent === isNextSilent);
                }

                readonly property bool isFirstOfSegment: !prevSameApp
                readonly property bool isLastOfSegment: !nextSameApp

                height: delegateCol.implicitHeight + (isLastOfSegment ? fullRepresentationRoot.legacyDp(6.4) : fullRepresentationRoot.legacyDp(1.6))

                Column {
                    id: delegateCol
                    width: parent.width
                    height: implicitHeight
                    spacing: 0

                    // Section header "Ciche"
                    Item {
                        width: parent.width
                        height: visible ? fullRepresentationRoot.legacyDp(36) : 0
                        visible: delegateRoot.showSilentHeader

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: fullRepresentationRoot.legacyDp(4)
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: fullRepresentationRoot.legacyDp(8)
                            text: i18n("Silent")
                            font.bold: true
                            font.pixelSize: fullRepresentationRoot.legacyDp(15)
                            color: Kirigami.Theme.textColor
                            opacity: 0.75
                        }
                    }

                    // Card Rectangle
                    Rectangle {
                        id: cardRect
                        width: parent.width
                        height: cardInnerCol.implicitHeight + fullRepresentationRoot.legacyDp(24)
                        implicitHeight: height
                        radius: 1
                        topLeftRadius: delegateRoot.isFirstOfSegment ? fullRepresentationRoot.legacyDp(16) : 1
                        topRightRadius: delegateRoot.isFirstOfSegment ? fullRepresentationRoot.legacyDp(16) : 1
                        bottomLeftRadius: delegateRoot.isLastOfSegment ? fullRepresentationRoot.legacyDp(16) : 1
                        bottomRightRadius: delegateRoot.isLastOfSegment ? fullRepresentationRoot.legacyDp(16) : 1
                        color: fullRepresentationRoot.cardBackgroundColor

                        HoverHandler {
                            id: cardHover
                        }

                        // Hover & Press feedback overlay
                        Rectangle {
                            anchors.fill: parent
                            radius: 1
                            topLeftRadius: parent.topLeftRadius
                            topRightRadius: parent.topRightRadius
                            bottomLeftRadius: parent.bottomLeftRadius
                            bottomRightRadius: parent.bottomRightRadius
                            color: Kirigami.Theme.textColor
                            opacity: cardBodyMouse.pressed ? 0.20 : (cardHover.hovered ? 0.08 : 0)
                            Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }
                        }

                        ColumnLayout {
                            id: cardInnerCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: fullRepresentationRoot.legacyDp(12)
                            spacing: fullRepresentationRoot.legacyDp(6)

                            // Top row
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: fullRepresentationRoot.legacyDp(10)

                                // App Icon Badge
                                Rectangle {
                                    Layout.preferredWidth: fullRepresentationRoot.legacyDp(36)
                                    Layout.preferredHeight: fullRepresentationRoot.legacyDp(36)
                                    Layout.alignment: Qt.AlignTop
                                    radius: width / 2
                                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)

                                    Kirigami.Icon {
                                        anchors.centerIn: parent
                                        width: fullRepresentationRoot.legacyDp(20)
                                        height: width
                                        readonly property string resolvedIconName: String(delegateRoot.iconName || delegateRoot.applicationIconName || "preferences-system-notifications")
                                        source: delegateRoot.iconName || delegateRoot.applicationIconName || "preferences-system-notifications"
                                        isMask: resolvedIconName.endsWith("-symbolic") || resolvedIconName === "preferences-system-notifications"
                                        color: Kirigami.Theme.textColor
                                        visible: !cardImg.visible
                                    }

                                    Kirigami.Icon {
                                        id: cardImg
                                        anchors.centerIn: parent
                                        width: fullRepresentationRoot.legacyDp(22)
                                        height: width
                                        source: delegateRoot.image || ""
                                        visible: Boolean(delegateRoot.image) && valid
                                    }
                                }

                                // Texts column
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignTop
                                    spacing: fullRepresentationRoot.legacyDp(2)

                                    // App Name • Relative Time
                                    Text {
                                        Layout.fillWidth: true
                                        text: {
                                            void(fullRepresentationRoot.timeTick);
                                            var timeDate = isNaN(delegateRoot.updated) ? delegateRoot.created : delegateRoot.updated;
                                            var t = fullRepresentationRoot.formatRelativeTime(timeDate);
                                            if (!delegateRoot.isFirstOfSegment) {
                                                return t || "";
                                            }
                                            var app = delegateRoot.applicationName || i18n("System");
                                            return t ? (app + " • " + t) : app;
                                        }
                                        font.pixelSize: fullRepresentationRoot.legacyDp(12)
                                        color: Kirigami.Theme.textColor
                                        opacity: 0.75
                                        elide: Text.ElideRight
                                    }

                                    // Summary / Title
                                    Text {
                                        Layout.fillWidth: true
                                        text: delegateRoot.summary || delegateRoot.body || ""
                                        font.weight: Font.DemiBold
                                        font.pixelSize: fullRepresentationRoot.legacyDp(14)
                                        color: Kirigami.Theme.textColor
                                        wrapMode: delegateRoot.cardExpanded ? Text.Wrap : Text.NoWrap
                                        elide: Text.ElideRight
                                        maximumLineCount: delegateRoot.cardExpanded ? 3 : 1
                                    }

                                    // Body
                                    Text {
                                        Layout.fillWidth: true
                                        visible: delegateRoot.cardExpanded && delegateRoot.body && delegateRoot.body.length > 0 && delegateRoot.summary && delegateRoot.summary.length > 0
                                        text: delegateRoot.body || ""
                                        font.pixelSize: fullRepresentationRoot.legacyDp(13)
                                        color: Kirigami.Theme.textColor
                                        opacity: 0.85
                                        wrapMode: Text.Wrap
                                        textFormat: Text.StyledText
                                        onLinkActivated: link => Qt.openUrlExternally(link)
                                    }

                                    // Job progress bar (if JobType)
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.topMargin: fullRepresentationRoot.legacyDp(4)
                                        height: fullRepresentationRoot.legacyDp(4)
                                        radius: fullRepresentationRoot.legacyDp(2)
                                        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)
                                        visible: delegateRoot.type === NotificationManager.Notifications.JobType

                                        Rectangle {
                                            width: parent.width * (Math.max(0, Math.min(100, delegateRoot.percentage || 0)) / 100)
                                            height: parent.height
                                            radius: fullRepresentationRoot.legacyDp(2)
                                            color: Kirigami.Theme.highlightColor
                                        }
                                    }
                                }

                                // Control buttons (close on hover + chevron)
                                RowLayout {
                                    Layout.alignment: Qt.AlignTop
                                    spacing: fullRepresentationRoot.legacyDp(4)

                                    // Close button (visible on card hover)
                                    Rectangle {
                                        Layout.preferredWidth: fullRepresentationRoot.legacyDp(26)
                                        Layout.preferredHeight: fullRepresentationRoot.legacyDp(26)
                                        Layout.alignment: Qt.AlignVCenter
                                        radius: width / 2
                                        color: closeMouse.pressed
                                               ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.25)
                                               : (closeMouse.containsMouse ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.20) : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12))
                                        opacity: (cardHover.hovered || closeMouse.containsMouse || closeMouse.pressed) ? 1.0 : 0.0
                                        Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }

                                        Kirigami.Icon {
                                            anchors.centerIn: parent
                                            width: fullRepresentationRoot.legacyDp(13)
                                            height: width
                                            source: "window-close-symbolic"
                                            color: Kirigami.Theme.textColor
                                        }

                                        MouseArea {
                                            id: closeMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onClicked: {
                                                fullRepresentationRoot.historyModel.close(fullRepresentationRoot.historyModel.index(delegateRoot.index, 0));
                                            }
                                        }
                                    }

                                    // Chevron button
                                    Rectangle {
                                        Layout.preferredWidth: fullRepresentationRoot.legacyDp(24)
                                        Layout.preferredHeight: fullRepresentationRoot.legacyDp(16)
                                        Layout.alignment: Qt.AlignVCenter
                                        radius: height / 2.0
                                        color: chevMouse.pressed
                                               ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.25)
                                               : (chevMouse.containsMouse ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.20) : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12))
                                        visible: delegateRoot.body && delegateRoot.body.length > 0 && delegateRoot.summary && delegateRoot.summary.length > 0

                                        Kirigami.Icon {
                                            anchors.centerIn: parent
                                            width: fullRepresentationRoot.legacyDp(11)
                                            height: width
                                            source: delegateRoot.cardExpanded ? Qt.resolvedUrl("icons/chevron_up.svg") : Qt.resolvedUrl("icons/chevron_down.svg")
                                            isMask: true
                                            color: Kirigami.Theme.textColor
                                        }

                                        MouseArea {
                                            id: chevMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: delegateRoot.cardExpanded = !delegateRoot.cardExpanded
                                        }
                                    }
                                }
                            }

                            // Action buttons Flow
                            Flow {
                                id: actionsFlow
                                Layout.fillWidth: true
                                Layout.leftMargin: fullRepresentationRoot.legacyDp(46)
                                Layout.topMargin: fullRepresentationRoot.legacyDp(2)
                                spacing: fullRepresentationRoot.legacyDp(14)
                                visible: delegateRoot.cardExpanded && delegateRoot.actionLabels && delegateRoot.actionLabels.length > 0
                                width: cardRect.width - fullRepresentationRoot.legacyDp(24) - fullRepresentationRoot.legacyDp(46)

                                Repeater {
                                    model: (delegateRoot.cardExpanded && delegateRoot.actionLabels) ? delegateRoot.actionLabels : []
                                    Item {
                                        required property int index
                                        required property string modelData

                                        width: actText.implicitWidth
                                        height: actText.implicitHeight

                                        Text {
                                            id: actText
                                            text: parent.modelData
                                            font.bold: true
                                            font.pixelSize: fullRepresentationRoot.legacyDp(13)
                                            color: actMouse.containsMouse ? Kirigami.Theme.highlightColor : Kirigami.Theme.linkColor
                                        }

                                        MouseArea {
                                            id: actMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onClicked: {
                                                var actName = delegateRoot.actionNames[parent.index];
                                                var rowIdx = fullRepresentationRoot.historyModel.index(delegateRoot.index, 0);
                                                var behavior = delegateRoot.resident ? NotificationManager.Notifications.None : NotificationManager.Notifications.Close;
                                                fullRepresentationRoot.historyModel.invokeAction(rowIdx, actName, behavior);
                                            }
                                        }
                                    }
                                }
                            }

                            // Inline reply field
                            RowLayout {
                                id: replyRow
                                Layout.fillWidth: true
                                Layout.leftMargin: fullRepresentationRoot.legacyDp(46)
                                Layout.topMargin: fullRepresentationRoot.legacyDp(4)
                                visible: delegateRoot.cardExpanded && delegateRoot.hasReplyAction
                                spacing: fullRepresentationRoot.legacyDp(6)

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: fullRepresentationRoot.legacyDp(30)
                                    radius: height / 2
                                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)

                                    TextInput {
                                        id: replyInput
                                        anchors.fill: parent
                                        anchors.leftMargin: fullRepresentationRoot.legacyDp(10)
                                        anchors.rightMargin: fullRepresentationRoot.legacyDp(10)
                                        verticalAlignment: TextInput.AlignVCenter
                                        color: Kirigami.Theme.textColor
                                        font.pixelSize: fullRepresentationRoot.legacyDp(13)
                                        clip: true
                                        onAccepted: {
                                            if (text.trim().length > 0) {
                                                var rowIdx = fullRepresentationRoot.historyModel.index(delegateRoot.index, 0);
                                                var behavior = delegateRoot.resident ? NotificationManager.Notifications.None : NotificationManager.Notifications.Close;
                                                fullRepresentationRoot.historyModel.reply(rowIdx, text.trim(), behavior);
                                                text = "";
                                            }
                                        }

                                        Text {
                                            anchors.fill: parent
                                            verticalAlignment: Text.AlignVCenter
                                            text: delegateRoot.replyPlaceholderText || i18n("Reply…")
                                            color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.5)
                                            font.pixelSize: fullRepresentationRoot.legacyDp(13)
                                            visible: !replyInput.text && !replyInput.activeFocus
                                        }
                                    }
                                }

                                Rectangle {
                                    width: fullRepresentationRoot.legacyDp(30)
                                    height: fullRepresentationRoot.legacyDp(30)
                                    radius: height / 2
                                    color: sendMouse.pressed
                                           ? Qt.darker(Kirigami.Theme.highlightColor, 1.2)
                                           : (sendMouse.containsMouse ? Qt.lighter(Kirigami.Theme.highlightColor, 1.15) : Kirigami.Theme.highlightColor)

                                    Kirigami.Icon {
                                        anchors.centerIn: parent
                                        width: fullRepresentationRoot.legacyDp(14)
                                        height: width
                                        source: "document-send"
                                        color: Kirigami.Theme.highlightedTextColor
                                    }

                                    MouseArea {
                                        id: sendMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: {
                                            if (replyInput.text.trim().length > 0) {
                                                var rowIdx = fullRepresentationRoot.historyModel.index(delegateRoot.index, 0);
                                                var behavior = delegateRoot.resident ? NotificationManager.Notifications.None : NotificationManager.Notifications.Close;
                                                fullRepresentationRoot.historyModel.reply(rowIdx, replyInput.text.trim(), behavior);
                                                replyInput.text = "";
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Card body click (invokes default action)
                        MouseArea {
                            id: cardBodyMouse
                            anchors.fill: parent
                            z: -1
                            hoverEnabled: true
                            cursorShape: delegateRoot.hasDefaultAction ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                var rowIdx = fullRepresentationRoot.historyModel.index(delegateRoot.index, 0);
                                if (delegateRoot.hasDefaultAction) {
                                    var behavior = delegateRoot.resident ? NotificationManager.Notifications.None : NotificationManager.Notifications.Close;
                                    fullRepresentationRoot.historyModel.invokeDefaultAction(rowIdx, behavior);
                                } else if (delegateRoot.urls && delegateRoot.urls.length === 1) {
                                    Qt.openUrlExternally(delegateRoot.urls[0]);
                                }
                            }
                        }
                    }
                }
            }
        }

        // 2. Empty State: Centered Trophy & Message
        Item {
            id: emptyStateView
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                bottom: bottomBar.top
                topMargin: fullRepresentationRoot.topMargin
                leftMargin: fullRepresentationRoot.sideMargin
                rightMargin: fullRepresentationRoot.sideMargin
                bottomMargin: fullRepresentationRoot.px(16.0)
            }
            visible: !fullRepresentationRoot.hasNotifications

            ColumnLayout {
                anchors.centerIn: parent
                spacing: fullRepresentationRoot.legacyDp(16)

                Kirigami.Icon {
                    Layout.alignment: Qt.AlignHCenter
                    source: Qt.resolvedUrl("assets/trophy.svg")
                    width: fullRepresentationRoot.legacyDp(42)
                    height: width
                    isMask: true
                    color: Kirigami.Theme.textColor
                    opacity: 0.6
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: i18n("No notifications")
                    font.weight: Font.DemiBold
                    font.pixelSize: fullRepresentationRoot.legacyDp(17)
                    color: Kirigami.Theme.textColor
                }
            }
        }

        // 3. Bottom Action Bar
        RowLayout {
            id: bottomBar
            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
                leftMargin: fullRepresentationRoot.sideMargin
                rightMargin: fullRepresentationRoot.sideMargin
                bottomMargin: fullRepresentationRoot.bottomMargin
            }
            height: fullRepresentationRoot.px(40.0)
            spacing: fullRepresentationRoot.px(8.0)

            // History Button (Left)
            Rectangle {
                Layout.preferredWidth: fullRepresentationRoot.px(60.0)
                Layout.preferredHeight: fullRepresentationRoot.px(40.0)
                radius: height / 2
                color: histMouse.pressed
                       ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.20)
                       : (histMouse.containsMouse ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08) : fullRepresentationRoot.cardBackgroundColor)
                Behavior on color { ColorAnimation { duration: 150 } }

                Kirigami.Icon {
                    anchors.centerIn: parent
                    source: Qt.resolvedUrl("icons/history.svg")
                    width: fullRepresentationRoot.legacyDp(20)
                    height: width
                    isMask: true
                    color: Kirigami.Theme.textColor
                }

                MouseArea {
                    id: histMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: KCMUtils.KCMLauncher.openSystemSettings("kcm_notifications")
                }
            }

            // "Clear all" Button (Center, only shown in populated state)
            Rectangle {
                id: clearBtn
                visible: fullRepresentationRoot.hasNotifications
                Layout.fillWidth: true
                Layout.preferredHeight: fullRepresentationRoot.px(40.0)
                radius: height / 2
                color: clearMouse.pressed
                       ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.20)
                       : (clearMouse.containsMouse ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08) : fullRepresentationRoot.cardBackgroundColor)
                Behavior on color { ColorAnimation { duration: 150 } }

                Text {
                    anchors.centerIn: parent
                    text: i18n("Clear all")
                    color: Kirigami.Theme.textColor
                    font.weight: Font.DemiBold
                    font.pixelSize: fullRepresentationRoot.legacyDp(14)
                }

                MouseArea {
                    id: clearMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: fullRepresentationRoot.clearAllNotifications()
                }
            }

            // Spacer when empty state
            Item {
                Layout.fillWidth: true
                visible: !fullRepresentationRoot.hasNotifications
            }

            // Notification Settings Button (Right)
            Rectangle {
                Layout.preferredWidth: fullRepresentationRoot.px(60.0)
                Layout.preferredHeight: fullRepresentationRoot.px(40.0)
                radius: height / 2
                color: setMouse.pressed
                       ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.20)
                       : (setMouse.containsMouse ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08) : fullRepresentationRoot.cardBackgroundColor)
                Behavior on color { ColorAnimation { duration: 150 } }

                Kirigami.Icon {
                    anchors.centerIn: parent
                    source: Qt.resolvedUrl("icons/notification_settings.svg")
                    width: fullRepresentationRoot.legacyDp(20)
                    height: width
                    isMask: true
                    color: Kirigami.Theme.textColor
                }

                MouseArea {
                    id: setMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: KCMUtils.KCMLauncher.openSystemSettings("kcm_notifications")
                }
            }
        }
    }
}

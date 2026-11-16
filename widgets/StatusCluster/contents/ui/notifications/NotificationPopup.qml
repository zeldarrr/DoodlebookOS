/*
    SPDX-FileCopyrightText: 2019 Kai Uwe Broulik <kde@privat.broulik.de>

    SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
*/

import QtQuick
import QtQuick.Layouts

import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.kquickcontrolsaddons as KQuickAddons
import plasma.applet.org.kde.plasma.notifications as NotificationsApplet

NotificationsApplet.NotificationWindow {
    id: notificationPopup

    readonly property real dpr: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1.0
    function snap(val) {
        return Math.round(val * dpr) / dpr;
    }

    backgroundHints: PlasmaCore.Types.NoBackground

    property int popupWidth: snap(309.6)

    // Maximum width the popup can take to not break out of the screen geometry.
    readonly property int availableWidth: (Screen.desktopAvailableWidth > 0 ? Screen.desktopAvailableWidth : Screen.width) - 32

    readonly property int minimumContentWidth: popupWidth
    readonly property int maximumContentWidth: Math.min((availableWidth > 0 ? availableWidth : Number.MAX_VALUE), popupWidth * 3)

    property alias modelInterface: notificationItem.modelInterface

    property int modelTimeout
    property int dismissTimeout

    property var defaultActionFallbackWindowIdx

    signal expired
    signal hoverEntered
    signal hoverExited

    property int defaultTimeout: 5000
    readonly property int effectiveTimeout: {
        if (modelTimeout === -1) {
            return defaultTimeout;
        }
        if (dismissTimeout) {
            return dismissTimeout;
        }
        return modelTimeout;
    }

    // On wayland we need focus to copy to the clipboard, we change on mouse interaction until the cursor leaves
    takeFocus: notificationItem.modelInterface.replying || focusListener.wantsFocus

    visible: false

    height: mainItem.implicitHeight + topPadding + bottomPadding
    width: mainItem.implicitWidth + leftPadding + rightPadding

    // Hide the rectangular theme frame drawn by PlasmaWindow behind our own rounded card
    function hideFrameBackground() {
        if (!notificationPopup.contentItem) {
            return;
        }
        const kids = notificationPopup.contentItem.children;
        for (let i = 0; i < kids.length; ++i) {
            if (kids[i] !== notificationPopup.mainItem) {
                kids[i].visible = false;
            }
        }
    }

    Component.onCompleted: hideFrameBackground()
    onVisibleChanged: {
        if (visible) {
            hideFrameBackground();
        }
    }

    mainItem: KQuickAddons.MouseEventListener {
        id: focusListener
        property bool wantsFocus: false

        implicitWidth: Math.min(Math.max(notificationPopup.minimumContentWidth, notificationItem.Layout.preferredWidth), Math.max(notificationPopup.minimumContentWidth, notificationPopup.maximumContentWidth))
        implicitHeight: notificationItem.implicitHeight

        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        onPressed: wantsFocus = true
        onContainsMouseChanged: {
            wantsFocus = wantsFocus && containsMouse;
            if (containsMouse) {
                notificationPopup.hoverEntered();
            } else {
                notificationPopup.hoverExited();
            }
        }

        // Activate default action when dragging a file over the notification.
        DropArea {
            id: activateDefaultActionDropArea
            anchors.fill: parent

            property bool containsAcceptableDrag: false
            property point lastPosition: Qt.point(-1, -1)

            onEntered: (event) => {
                if (notificationItem.modelInterface.hasDefaultAction) {
                    dragActivationTimer.restart();
                    containsAcceptableDrag = true;
                    lastPosition = Qt.point(drag.x, drag.y);
                } else {
                    drag.accepted = false;
                }
            }
            onPositionChanged: {
                if (containsAcceptableDrag) {
                    const manhattanLength = Math.abs((drag.x - lastPosition.x) + (drag.y - lastPosition.y));
                    if (manhattanLength > Application.styleHints.startDragDistance) {
                        dragActivationTimer.restart();
                        lastPosition = Qt.point(drag.x, drag.y);
                    }
                }
            }
            onDropped: {
                containsAcceptableDrag = false;
            }
            onExited: {
                containsAcceptableDrag = false;
                dragActivationTimer.stop();
            }
        }

        Timer {
            id: dragActivationTimer
            interval: 250 // same as Task Manager
            repeat: false
            onTriggered: notificationItem.modelInterface.defaultActionInvoked()
        }

        Item {
            id: content
            anchors.fill: parent

            function finish() {
                if (notificationPopup.dismissTimeout) {
                    notificationPopup.modelInterface.dismissClicked();
                } else {
                    notificationPopup.expired();
                }
            }
            function leave() {
                if (exitAnim.running) {
                    return;
                }
                if (Kirigami.Units.longDuration <= 0) {   // animations disabled
                    finish();
                    return;
                }
                // fly toward the nearest screen edge
                exitAnim.dir = (notificationPopup.x + notificationPopup.width / 2 >= Screen.virtualX + Screen.width / 2) ? 1 : -1;
                exitAnim.start();
            }
            function resetExit() {
                exitAnim.stop();
                notificationItem.opacity = 1;
                notificationItem.scale = 1;
                exitSlide.x = 0;
            }

            // M3 Expressive exit: short lift, then shrink + slide out + fade on the emphasized-accelerate curve
            SequentialAnimation {
                id: exitAnim
                property real dir: 1
                NumberAnimation {
                    target: notificationItem; property: "scale"; to: 1.03
                    duration: Kirigami.Units.shortDuration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1, 1]
                }
                ParallelAnimation {
                    NumberAnimation {
                        target: notificationItem; property: "scale"; to: 0.88
                        duration: Kirigami.Units.longDuration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: [0.3, 0.0, 0.8, 0.15, 1, 1]
                    }
                    NumberAnimation {
                        target: exitSlide; property: "x"; to: exitAnim.dir * notificationPopup.snap(36)
                        duration: Kirigami.Units.longDuration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: [0.3, 0.0, 0.8, 0.15, 1, 1]
                    }
                    NumberAnimation {
                        target: notificationItem; property: "opacity"; to: 0
                        duration: Kirigami.Units.longDuration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: [0.3, 0.0, 0.8, 0.15, 1, 1]
                    }
                }
                ScriptAction { script: content.finish() }
            }

            LayoutMirroring.enabled: Application.layoutDirection === Qt.RightToLeft
            LayoutMirroring.childrenInherit: true

            Timer {
                id: timer
                interval: notificationPopup.effectiveTimeout
                running: {
                    if (!notificationPopup.visible) {
                        return false;
                    }
                    if (focusListener.containsMouse) {
                        return false;
                    }
                    if (interval <= 0) {
                        return false;
                    }
                    if (activateDefaultActionDropArea.containsAcceptableDrag) {
                        return false;
                    }
                    if (notificationItem.modelInterface.replying
                            && (notificationPopup.active || notificationItem.modelInterface.hasPendingReply)) {
                        return false;
                    }
                    return true;
                }
                onTriggered: content.leave()
            }

            DelegatePopup {
                id: notificationItem
                anchors.fill: parent
                transform: Translate { id: exitSlide }

                Layout.preferredHeight: implicitHeight
                Layout.preferredWidth: notificationPopup.snap(309.6)

                modelInterface {
                    closable: true
                    timeout: timer.running ? timer.interval : 0

                    // When notification is updated, restart hide timer
                    onTimeChanged: {
                        content.resetExit();
                        if (timer.running) {
                            timer.restart();
                            notificationItem.restartCountdown();
                        }
                    }
                }
            }
        }
    }
}

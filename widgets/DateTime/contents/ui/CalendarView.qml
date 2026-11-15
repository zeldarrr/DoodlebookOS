/*
    SPDX-FileCopyrightText: 2013 Sebastian Kügler <sebas@kde.org>
    SPDX-FileCopyrightText: 2015 Martin Klapetek <mklapetek@kde.org>
    SPDX-FileCopyrightText: 2021 Carl Schwan <carlschwan@kde.org>
    SPDX-FileCopyrightText: 2023 ivan tkachenko <me@ratijas.tk>
    SPDX-FileCopyrightText: 2024-2026 Maciej Kujawiński <maciek.kujawinski@gmail.com>

    SPDX-License-Identifier: GPL-3.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import org.kde.plasma.plasmoid
import org.kde.plasma.workspace.calendar as PlasmaCalendar
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import "calendar" as CustomCalendar
import "metrics" as LocalMetrics

// Pure Single-Column Month View (No agenda, no additional clocks)
PlasmaExtras.Representation {
    id: calendar

    Kirigami.Theme.colorSet: Kirigami.Theme.Window
    Kirigami.Theme.inherit: true

    function snap(val) {
        return LocalMetrics.Metrics.snap(val);
    }

    // Punkt 0 (3440x1440 @125%): 376 x 391 px
    readonly property real baseCalendarWidth: LocalMetrics.Metrics.px(376.0)
    readonly property real baseCalendarHeight: LocalMetrics.Metrics.px(391.0)
    readonly property real calendarFontPixelSize: LocalMetrics.Metrics.px(16.5)

    Layout.preferredWidth: baseCalendarWidth
    Layout.minimumWidth: baseCalendarWidth
    Layout.maximumWidth: baseCalendarWidth

    Layout.preferredHeight: baseCalendarHeight
    Layout.minimumHeight: baseCalendarHeight
    Layout.maximumHeight: baseCalendarHeight

    implicitWidth: baseCalendarWidth
    implicitHeight: baseCalendarHeight
    width: baseCalendarWidth
    height: baseCalendarHeight

    readonly property alias monthView: monthView
    readonly property double headerHeight: monthView.viewHeader.implicitHeight

    PlasmaCalendar.EventPluginsManager {
        id: eventPluginsManager
        enabledPlugins: Plasmoid.configuration.enabledCalendarPlugins
    }

    Binding {
        when: calendar.Window && calendar.Window.window !== null
        target: calendar.Window ? calendar.Window.window : null
        property: "margin"
        value: 1
    }
    Binding {
        when: calendar.Window && calendar.Window.window !== null
        target: calendar.Window ? calendar.Window.window : null
        property: "width"
        value: calendar.baseCalendarWidth
    }
    Binding {
        when: calendar.Window && calendar.Window.window !== null
        target: calendar.Window ? calendar.Window.window : null
        property: "height"
        value: calendar.baseCalendarHeight
    }
    Binding {
        when: calendar.Window && calendar.Window.window !== null
        target: calendar.Window ? calendar.Window.window : null
        property: "minimumWidth"
        value: calendar.baseCalendarWidth
    }
    Binding {
        when: calendar.Window && calendar.Window.window !== null
        target: calendar.Window ? calendar.Window.window : null
        property: "maximumWidth"
        value: calendar.baseCalendarWidth
    }
    Binding {
        when: calendar.Window && calendar.Window.window !== null
        target: calendar.Window ? calendar.Window.window : null
        property: "minimumHeight"
        value: calendar.baseCalendarHeight
    }
    Binding {
        when: calendar.Window && calendar.Window.window !== null
        target: calendar.Window ? calendar.Window.window : null
        property: "maximumHeight"
        value: calendar.baseCalendarHeight
    }

    function adjustWindowPosition() {
        var win = calendar.Window ? calendar.Window.window : null;
        if (!win || !win.visible || !win.screen) return;
        win.minimumWidth = calendar.baseCalendarWidth;
        win.maximumWidth = calendar.baseCalendarWidth;
        win.minimumHeight = calendar.baseCalendarHeight;
        win.maximumHeight = calendar.baseCalendarHeight;
        win.width = calendar.baseCalendarWidth;
        win.height = calendar.baseCalendarHeight;
        var screenW = win.screen.geometry.width;
        var screenH = win.screen.geometry.height;
        var screenX = win.screen.geometry.x;
        var screenY = win.screen.geometry.y;
        var rightEdge = screenX + screenW;
        var bottomEdge = screenY + screenH;
        var offset = 8;

        if (win.x < screenX + offset) {
            win.x = screenX + offset;
        } else if ((win.x + win.width) > (rightEdge - offset)) {
            win.x = rightEdge - win.width - offset;
        }

        if (win.y < screenY + offset) {
            win.y = screenY + offset;
        } else if ((win.y + win.height) > (bottomEdge - offset)) {
            win.y = bottomEdge - win.height - offset;
        }
    }

    Connections {
        target: calendar.Window ? calendar.Window.window : null
        function onVisibleChanged() {
            var win = calendar.Window ? calendar.Window.window : null;
            if (win && win.visible) {
                Qt.callLater(calendar.adjustWindowPosition);
            }
        }
    }

    header: null

    FocusScope {
        id: monthViewWrapper
        anchors.fill: parent

        CustomCalendar.MonthView {
            id: monthView
            viewHeader.height: calendar.headerHeight

            anchors {
                fill: parent
                leftMargin: LocalMetrics.Metrics.px(5.0)
                rightMargin: LocalMetrics.Metrics.px(5.0)
                bottomMargin: LocalMetrics.Metrics.px(4.0)
            }

            eventPluginsManager: eventPluginsManager
            today: root.currentTime
            firstDayOfWeek: Plasmoid.configuration.firstDayOfWeek > -1
                ? Plasmoid.configuration.firstDayOfWeek
                : Qt.locale().firstDayOfWeek
            showWeekNumbers: Plasmoid.configuration.showWeekNumbers

            showDigitalClockHeader: true
            calendarFontPixelSize: calendar.calendarFontPixelSize

            KeyNavigation.left: KeyNavigation.tab
            KeyNavigation.tab: viewHeader.previousButton
            Keys.onUpPressed: viewHeader.previousButton.forceActiveFocus(Qt.BacktabFocusReason);
        }
    }
}

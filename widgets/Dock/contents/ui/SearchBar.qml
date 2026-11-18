/*
 * SPDX-FileCopyrightText: 2024-2026 Maciej Kujawiński <maciek.kujawinski@gmail.com>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import org.kde.kirigami as Kirigami
import "i18n.js" as I18n

Rectangle {
    id: searchBarRoot

    function i18n(k, a1, a2) { return I18n.t(k, a1, a2); }

    radius: height / 2
    color: main.contrastBgColor

    property alias textField: textField

    Timer { id: runnerDebounce; interval: 110; onTriggered: runnerModel.query = textField.text }
    Timer { id: enterDelay; interval: 160; onTriggered: textField.triggerSelectedResult(false) }

    readonly property string predictedName: {
        var q = textField.text ? textField.text.trim() : "";
        if (q.length === 0) return "";

        // 1. RunnerList's top result
        if (stack.currentItem && typeof stack.currentItem.topResultName === "string" && stack.currentItem.topResultName.length > 0) {
            return stack.currentItem.topResultName;
        }

        // 2. Instant fallback from installed apps / favorites
        if (typeof main !== "undefined" && main && typeof main.findAppByNamePrefix === "function") {
            var fb = main.findAppByNamePrefix(q);
            if (fb && fb.length > 0) return fb;
        }

        return "";
    }

    readonly property string ghostSuffix: {
        var query = textField.text;
        if (!query || query.length === 0) return "";
        var name = predictedName;
        if (!name || name.length === 0) return "";

        var lowerQuery = query.toLowerCase().trim();
        var lowerName = name.toLowerCase().trim();
        if (lowerQuery.length === 0) return "";

        var actionText = " - " + i18n("launch");

        // Only show ghost suffix when the name starts with the typed query (clean inline autocomplete)
        if (lowerName.indexOf(lowerQuery) === 0) {
            var remainder = name.substring(query.length);
            return remainder + actionText;
        }

        return "";
    }

    readonly property bool anim: Kirigami.Units.longDuration > 1
    readonly property bool active: textField.text.length > 0
    function tint(a) { return Qt.rgba(main.textColor.r, main.textColor.g, main.textColor.b, a); }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 8
        spacing: 8

        // leading icon: search, morphing into a back arrow while a query is typed (click = clear)
        Item {
            Layout.preferredWidth: 36
            Layout.preferredHeight: 36
            Layout.alignment: Qt.AlignVCenter

            Rectangle {
                anchors.fill: parent
                radius: backMa.pressed ? 12 : 18
                color: searchBarRoot.tint(backMa.pressed ? 0.12 : (backMa.containsMouse && searchBarRoot.active ? 0.08 : 0))
                Behavior on radius { NumberAnimation { duration: searchBarRoot.anim ? 200 : 0; easing.type: Easing.OutBack } }
            }
            Kirigami.Icon {
                anchors.centerIn: parent
                width: 22; height: 22
                source: Qt.resolvedUrl("icons/search.svg")
                isMask: true
                color: main.textColor
                opacity: searchBarRoot.active ? 0 : 0.75
                rotation: searchBarRoot.active ? 90 : 0
                scale: searchBarRoot.active ? 0.5 : 1
                Behavior on opacity { NumberAnimation { duration: searchBarRoot.anim ? 150 : 0 } }
                Behavior on rotation { NumberAnimation { duration: searchBarRoot.anim ? 300 : 0; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: searchBarRoot.anim ? 300 : 0; easing.type: Easing.OutCubic } }
            }
            Kirigami.Icon {
                anchors.centerIn: parent
                width: 22; height: 22
                source: Qt.resolvedUrl("icons/arrow_back.svg")
                isMask: true
                color: main.textColor
                opacity: searchBarRoot.active ? 1 : 0
                rotation: searchBarRoot.active ? 0 : -90
                scale: searchBarRoot.active ? 1 : 0.5
                Behavior on opacity { NumberAnimation { duration: searchBarRoot.anim ? 150 : 0 } }
                Behavior on rotation { NumberAnimation { duration: searchBarRoot.anim ? 300 : 0; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
                Behavior on scale { NumberAnimation { duration: searchBarRoot.anim ? 300 : 0; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
            }
            MouseArea {
                id: backMa
                anchors.fill: parent
                enabled: searchBarRoot.active
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { textField.clear(); textField.forceActiveFocus(); }
            }
        }

        // Text input field
        TextField {
            id: textField
            Layout.fillHeight: true
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            font.family: main.textFont
            font.pointSize: main.textSize + 2
            color: main.textColor
            verticalAlignment: TextInput.AlignVCenter

            placeholderText: i18n("Search apps, files, calculations…")
            placeholderTextColor: Qt.rgba(main.textColor.r, main.textColor.g, main.textColor.b, 0.55)

            background: Item {}
            focus: true

            Text {
                id: ghostTextLabel
                anchors.baseline: textField.baseline
                anchors.left: parent.left
                anchors.leftMargin: (textField.leftPadding || 0) - (textField.contentX || 0)
                anchors.right: parent.right
                anchors.rightMargin: textField.rightPadding || 0
                font: textField.font
                textFormat: Text.RichText
                clip: true
                text: {
                    if (!textField.text || !searchBarRoot.ghostSuffix) return "";
                    function escapeHtml(str) {
                        return str.toString()
                                  .replace(/&/g, "&amp;")
                                  .replace(/</g, "&lt;")
                                  .replace(/>/g, "&gt;")
                                  .replace(/"/g, "&quot;");
                    }
                    var ghostColor = Qt.rgba(main.textColor.r, main.textColor.g, main.textColor.b, 0.38);
                    return "<span style='white-space: pre; color: transparent;'>" + escapeHtml(textField.text) + "</span>"
                         + "<span style='white-space: pre; color: " + ghostColor + ";'>" + escapeHtml(searchBarRoot.ghostSuffix) + "</span>";
                }
                visible: textField.text.length > 0 && searchBarRoot.ghostSuffix.length > 0
                elide: Text.ElideRight
                z: -1
                enabled: false
            }

            onTextChanged: {
                if (!activeFocus) textField.forceActiveFocus(Qt.ShortcutFocusReason);
                // apps are matched instantly (AppIndex); KRunner (files, settings, maths…) only once
                // typing pauses, so every keystroke doesn't restart all runners and reset the list
                if (text.length === 0) {
                    runnerDebounce.stop();
                    runnerModel.query = "";
                } else {
                    runnerDebounce.restart();
                }
            }

            function triggerSelectedResult(shiftPressed) {
                var cur = stack.currentItem;
                if (!cur) return;
                if (typeof cur.activateSelection === "function") { cur.activateSelection(shiftPressed); return; }
                // apps page: launch the first visible app
                var view = cur.viewItem;
                if (view && view.count > 0 && view.model && typeof view.model.trigger === "function") {
                    view.model.trigger(Math.max(0, view.currentIndex), "", null);
                    root.closeAfterLaunch();
                }
            }

            onAccepted: {
                if (runnerDebounce.running) {
                    // Enter right after typing: query KRunner now and act once its first results are in
                    runnerDebounce.stop();
                    runnerModel.query = text;
                    enterDelay.restart();
                } else {
                    triggerSelectedResult(false);
                }
            }

            Keys.onPressed: event => {
                var cur = stack.currentItem;
                var inResults = cur && typeof cur.moveSel === "function";
                if (event.key === Qt.Key_Escape) {
                    event.accepted = true;
                    if (root.handleEscape()) return;
                    if (main.searching) clear(); else root.closeAnimated();
                } else if ((event.key === Qt.Key_Tab || event.key === Qt.Key_Right) && !(event.modifiers & Qt.ShiftModifier)
                           && searchBarRoot.ghostSuffix.length > 0 && cursorPosition === text.length && searchBarRoot.predictedName.length > 0) {
                    // accept the inline completion
                    text = searchBarRoot.predictedName;
                    cursorPosition = text.length;
                    event.accepted = true;
                } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
                    event.accepted = true;
                    if (inResults) cur.moveSel(event.key === Qt.Key_Down ? 1 : -1);
                    else if (event.key === Qt.Key_Down) main.focusZone(1);
                } else if (event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp) {
                    if (inResults) { cur.moveSel(event.key === Qt.Key_PageDown ? 5 : -5); event.accepted = true; }
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    event.accepted = true;
                    triggerSelectedResult(Boolean(event.modifiers & Qt.ShiftModifier));
                }
                // Tab without a completion bubbles up to MainView (focus zones)
            }
        }

        // trailing clear button: springs in with the first character
        Item {
            Layout.preferredWidth: searchBarRoot.active ? 36 : 0
            Layout.preferredHeight: 36
            Layout.alignment: Qt.AlignVCenter
            Behavior on Layout.preferredWidth { NumberAnimation { duration: searchBarRoot.anim ? 220 : 0; easing.type: Easing.OutCubic } }
            visible: Layout.preferredWidth > 0.5

            Rectangle {
                anchors.centerIn: parent
                width: 36; height: 36
                radius: clearMa.pressed ? 12 : 18
                color: searchBarRoot.tint(clearMa.pressed ? 0.12 : (clearMa.containsMouse ? 0.08 : 0))
                scale: searchBarRoot.active ? 1 : 0.3
                Behavior on scale { NumberAnimation { duration: searchBarRoot.anim ? 320 : 0; easing.type: Easing.OutBack; easing.overshoot: 2 } }
                Behavior on radius { NumberAnimation { duration: searchBarRoot.anim ? 200 : 0; easing.type: Easing.OutBack } }
                Kirigami.Icon {
                    anchors.centerIn: parent
                    width: 20; height: 20
                    source: Qt.resolvedUrl("icons/close.svg")
                    isMask: true
                    color: main.textColor
                    opacity: 0.8
                }
            }
            MouseArea {
                id: clearMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { textField.clear(); textField.forceActiveFocus(); }
            }
        }
    }
}

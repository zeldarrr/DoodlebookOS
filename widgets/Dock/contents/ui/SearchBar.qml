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

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        spacing: 8

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
    }
}

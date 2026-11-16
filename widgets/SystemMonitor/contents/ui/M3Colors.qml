/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * DoodlebookOS — Material You tonal roles derived from the active (Material You) colour scheme.
 * Pure bindings: recomputed only when the scheme changes.
 */
import QtQuick
import org.kde.kirigami as Kirigami

QtObject {
    readonly property color accent: Kirigami.Theme.highlightColor
    readonly property color bg: Kirigami.Theme.backgroundColor
    readonly property color fg: Kirigami.Theme.textColor
    readonly property bool dark: (bg.r * 0.299 + bg.g * 0.587 + bg.b * 0.114) < 0.5

    function mix(a, b, t) { return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1); }
    function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a); }

    readonly property color surface: mix(bg, accent, 0.07)
    readonly property color surfaceHigh: mix(bg, accent, 0.13)
    readonly property color surfaceHighest: mix(bg, accent, 0.20)
    readonly property color primary: accent
    readonly property color primaryText: dark ? mix(bg, Qt.rgba(0, 0, 0, 1), 0.45) : Qt.rgba(1, 1, 1, 1)
    readonly property color primaryContainer: mix(bg, accent, 0.34)
    readonly property color primaryContainerText: dark ? mix(fg, accent, 0.22) : mix(fg, accent, 0.5)
    readonly property color secondary: Qt.hsla((accent.hslHue + 0.92) % 1.0, Math.min(1, accent.hslSaturation * 0.75 + 0.1), dark ? 0.76 : 0.42, 1)
    readonly property color tertiary: Qt.hsla((accent.hslHue + 0.14) % 1.0, Math.min(1, accent.hslSaturation * 0.85 + 0.1), dark ? 0.78 : 0.40, 1)
    readonly property color tertiaryContainer: mix(bg, tertiary, 0.30)
    readonly property color tertiaryContainerText: dark ? mix(fg, tertiary, 0.3) : mix(fg, tertiary, 0.55)
    readonly property color surfaceText: fg
    readonly property color surfaceTextVariant: alpha(fg, 0.66)
    readonly property color outline: alpha(fg, 0.14)
    readonly property color stateHover: alpha(fg, 0.08)
    readonly property color statePress: alpha(fg, 0.14)
    readonly property color error: dark ? "#ffb4ab" : "#ba1a1a"
    readonly property string font: "Google Sans Flex"
}

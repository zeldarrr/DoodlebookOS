pragma Singleton

import QtQuick
import QtQuick.Window

// Shared Punkt 0 UI scale metrics (3440x1440 @125% baseline: 1 dp = 1.25 px).
QtObject {
    id: metricsRoot

    readonly property real baselineDpr: 1.25
    property real hostDpr: 0.0
    readonly property real dpr: (hostDpr > 0) ? hostDpr : (Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1.0)
    property real uiScale: 1.0

    readonly property real clampedScale: (uiScale >= 0.75 && uiScale <= 1.50) ? uiScale : 1.0

    function snap(val) {
        return Math.round(val * dpr) / dpr;
    }

    // Exact Punkt 0 measured physical pixel -> KDE dp scaled by uiScale
    function px(refPx) {
        return snap((refPx * clampedScale) / baselineDpr);
    }

    // Fallback for unmeasured legacy dp: applies 8/9 (376/423) Punkt 0 factor + uiScale
    function legacyDp(oldDp) {
        return snap(oldDp * (8.0 / 9.0) * clampedScale);
    }

    // Proportional sizing relative to live panel/bar height (Top Bar ref=36 px, Dock ref=56 px)
    function barPx(effectiveBarH, itemRefPx, refBarPx) {
        return snap(effectiveBarH * (itemRefPx / refBarPx));
    }
}

/*
    DoodlebookOS desktop mode — Android 16 "desktop windowing" style options for KWin.
    SPDX-License-Identifier: GPL-3.0-or-later

    Adds a "Desktop mode" sub-menu to the window menu (opened by the ▾ next to the
    title in the DoodlebookOS decoration, or Alt+F3):
      Fullscreen · Split screen left / right · Floating (centred) · Picture-in-picture
    Picture-in-picture shrinks the window to the bottom-right corner, keeps it above
    the others and on every desktop; choosing it again restores the window.
    Shortcuts are registered without default keys (System Settings › Shortcuts › KWin).
*/

"use strict";

const STRINGS = {
    en: {
        menu: "Desktop mode",
        fullscreen: "Fullscreen",
        left: "Split screen — left",
        right: "Split screen — right",
        floating: "Floating (centred)",
        pip: "Picture-in-picture",
        pipExit: "Exit picture-in-picture",
    },
    fr: {
        menu: "Mode bureau",
        fullscreen: "Plein écran",
        left: "Écran partagé — gauche",
        right: "Écran partagé — droite",
        floating: "Fenêtre flottante (centrée)",
        pip: "Image dans l'image",
        pipExit: "Quitter l'image dans l'image",
    },
};
const T = STRINGS[readConfig("Language", "en")] || STRINGS.en;

const pipState = {}; // internalId -> { geometry, keepAbove, onAllDesktops }

function area(window) {
    return workspace.clientArea(KWin.MaximizeArea, window);
}

function untile(window) {
    try { window.setMaximize(false, false); } catch (e) {}
    try { if (window.tile) window.tile = null; } catch (e) {}
}

function setGeometry(window, x, y, w, h) {
    window.frameGeometry = { x: Math.round(x), y: Math.round(y), width: Math.round(w), height: Math.round(h) };
}

function quickTile(window, side) {
    if (window.fullScreen) window.fullScreen = false;
    exitPip(window);
    workspace.activeWindow = window;
    if (side === "left") workspace.slotWindowQuickTileLeft();
    else workspace.slotWindowQuickTileRight();
}

function floating(window) {
    if (window.fullScreen) window.fullScreen = false;
    exitPip(window);
    untile(window);
    const a = area(window);
    const w = Math.min(a.width * 0.68, Math.max(window.minSize.width, 960));
    const h = Math.min(a.height * 0.78, Math.max(window.minSize.height, 640));
    setGeometry(window, a.x + (a.width - w) / 2, a.y + (a.height - h) / 2, w, h);
}

function isPip(window) {
    return pipState[window.internalId] !== undefined;
}

function enterPip(window) {
    if (isPip(window)) return;
    if (window.fullScreen) window.fullScreen = false;
    const g = window.frameGeometry;
    pipState[window.internalId] = {
        geometry: { x: g.x, y: g.y, width: g.width, height: g.height },
        keepAbove: window.keepAbove,
        onAllDesktops: window.onAllDesktops,
    };
    untile(window);
    const a = area(window);
    const margin = 24;
    const w = Math.max(window.minSize.width, Math.round(a.width * 0.26));
    const h = Math.max(window.minSize.height, Math.round(w * 9 / 16));
    setGeometry(window, a.x + a.width - w - margin, a.y + a.height - h - margin, w, h);
    window.keepAbove = true;
    window.onAllDesktops = true;
}

function exitPip(window) {
    const s = pipState[window.internalId];
    if (!s) return;
    delete pipState[window.internalId];
    window.keepAbove = s.keepAbove;
    window.onAllDesktops = s.onAllDesktops;
    setGeometry(window, s.geometry.x, s.geometry.y, s.geometry.width, s.geometry.height);
}

function managed(window) {
    return window && window.normalWindow && !window.specialWindow;
}

registerUserActionsMenu(function (window) {
    if (!managed(window)) return null;
    return {
        text: T.menu,
        items: [
            {
                text: T.fullscreen,
                checkable: true,
                checked: window.fullScreen,
                triggered: function () { exitPip(window); window.fullScreen = !window.fullScreen; },
            },
            { text: T.left, triggered: function () { quickTile(window, "left"); } },
            { text: T.right, triggered: function () { quickTile(window, "right"); } },
            { text: T.floating, triggered: function () { floating(window); } },
            {
                text: isPip(window) ? T.pipExit : T.pip,
                checkable: true,
                checked: isPip(window),
                triggered: function () { if (isPip(window)) exitPip(window); else enterPip(window); },
            },
        ],
    };
});

function withActive(fn) {
    return function () {
        const w = workspace.activeWindow;
        if (managed(w)) fn(w);
    };
}

registerShortcut("DoodlebookOS: Floating window", "DoodlebookOS: " + T.floating, "", withActive(floating));
registerShortcut("DoodlebookOS: Picture-in-picture", "DoodlebookOS: " + T.pip, "",
                 withActive(function (w) { if (isPip(w)) exitPip(w); else enterPip(w); }));

workspace.windowRemoved.connect(function (window) {
    delete pipState[window.internalId];
});

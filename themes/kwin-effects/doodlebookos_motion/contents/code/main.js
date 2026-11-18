/*
    DoodlebookOS Motion — Material 3 window open/close animation for KWin.
    Based on KWin's "Scale" effect (SPDX: 2018, 2021 Vlad Zahorodnii, GPL-2.0-or-later).

    SPDX-License-Identifier: GPL-3.0-or-later

    Open : the window rises 24 px and grows from 92 % (dialogs: 95 %, no rise) with the
           M3 "emphasized decelerate" feel (fast start, long soft landing), opacity
           reaches 100 % in the first part of the motion.
    Close: shrinks to 96 %, drops 12 px and fades with the "emphasized accelerate"
           feel, shorter than the opening (M3: exits are quicker than entrances).
    From the icon (Android): a window opened from the dock or the launcher grows out of the icon
           that was clicked (the pointer, when it is on the dock or the launcher just closed),
           and a window whose dock icon is known closes back into it.
    Durations follow the global animation speed slider (animationTime()).
*/

"use strict";

const blacklist = {
    "ksmserver ksmserver": [],
    "ksmserver-logout-greeter ksmserver-logout-greeter": [],
    "ksplashqml ksplashqml": [],
    "spectacle org.kde.spectacle": ["region-editor"],
};

class DoodlebookMotion {
    constructor() {
        effect.configChanged.connect(this.loadConfig.bind(this));
        effect.animationEnded.connect(this.cleanupForcedRoles.bind(this));
        effects.windowAdded.connect(this.slotWindowAdded.bind(this));
        effects.windowClosed.connect(this.slotWindowClosed.bind(this));
        effects.windowDataChanged.connect(this.slotWindowDataChanged.bind(this));
        effects.windowActivated.connect(this.slotWindowActivated.bind(this));
        this.launcherClosedAt = 0;
        this.lastActive = null;
        this.loadConfig();
    }

    // On Wayland a window's dock icon position is gone once it is closed: keep a copy while it
    // lives (on activation and minimize, never per frame)
    static cacheIcon(w) {
        try {
            const g = w && w.iconGeometry;
            if (g && g.width > 0 && g.height > 0) {
                w.dbIcon = { x: g.x, y: g.y, width: g.width, height: g.height };
            }
        } catch (e) {
            // the window went away
        }
    }

    slotWindowActivated(w) {
        if (this.lastActive) {
            DoodlebookMotion.cacheIcon(this.lastActive);
        }
        if (w) {
            DoodlebookMotion.cacheIcon(w);
        }
        this.lastActive = w;
    }

    static isShell(w) {
        return w.windowClass == "plasmashell plasmashell" || w.windowClass == "plasmashell org.kde.plasmashell";
    }

    // the DoodlebookOS launcher: a large plasmashell dock window that doesn't touch a screen edge
    static isLauncher(w) {
        if (!w.dock || !DoodlebookMotion.isShell(w)) {
            return false;
        }
        const g = w.geometry;
        const s = w.screen && w.screen.geometry;
        if (!s || !(s.width > 0)) {
            return false;
        }
        const gap = Math.min(g.y - s.y, s.y + s.height - (g.y + g.height), g.x - s.x, s.x + s.width - (g.x + g.width));
        return gap > 24 && g.height >= 420;
    }

    // Where a new window was launched from: the pointer, if it is on a Plasma dock/panel or the
    // launcher closed less than 1.5 s ago (the app icon that was clicked). Else null.
    launchOrigin() {
        const c = effects.cursorPos;
        if (Date.now() - this.launcherClosedAt < 1500) {
            return c;
        }
        const list = effects.stackingOrder || [];
        for (let i = 0; i < list.length; i++) {
            const d = list[i];
            if (d.dock && DoodlebookMotion.isShell(d)) {
                const g = d.geometry;
                if (c.x >= g.x && c.x < g.x + g.width && c.y >= g.y && c.y < g.y + g.height) {
                    return c;
                }
            }
        }
        return null;
    }

    loadConfig() {
        this.openDuration = animationTime(effect.readConfig("OpenDuration", 420) || 420);
        this.closeDuration = animationTime(effect.readConfig("CloseDuration", 220) || 220);
        this.rise = effect.readConfig("Rise", 24);
    }

    static isAnimated(window) {
        if (window.windowClass == "plasmashell plasmashell"
                || window.windowClass == "plasmashell org.kde.plasmashell") {
            return window.hasDecoration;
        }
        const tags = blacklist[window.windowClass];
        if (tags && (tags.length === 0 || tags.includes(window.tag))) {
            return false;
        }
        if (window.hasDecoration) {
            return true;
        }
        if (window.popupWindow || window.lockScreen || window.outline || !window.managed) {
            return false;
        }
        return window.normalWindow || window.dialog;
    }

    static isDialog(window) {
        return window.dialog || window.modal || window.transient;
    }

    setupForcedRoles(window) {
        window.setData(Effect.WindowForceBackgroundContrastRole, true);
        window.setData(Effect.WindowForceBlurRole, true);
    }

    cleanupForcedRoles(window) {
        window.setData(Effect.WindowForceBackgroundContrastRole, null);
        window.setData(Effect.WindowForceBlurRole, null);
    }

    slotWindowAdded(window) {
        if (window.minimizedChanged && (window.normalWindow || window.hasDecoration)) {
            window.minimizedChanged.connect(() => DoodlebookMotion.cacheIcon(window));
        }
        if (effects.hasActiveFullScreenEffect || !DoodlebookMotion.isAnimated(window) || !window.visible) {
            return;
        }
        if (effect.isGrabbed(window, Effect.WindowAddedGrabRole)) {
            return;
        }
        const dialog = DoodlebookMotion.isDialog(window);
        const origin = dialog ? null : this.launchOrigin();
        if (origin) {
            // grow out of the clicked icon: scale about the centre while the centre travels from
            // the icon to its place, same curve for both, so the window seems to unfold from it
            const g = window.geometry;
            const d = Math.round(this.openDuration * 1.1);
            const dx = origin.x - (g.x + g.width / 2);
            const dy = origin.y - (g.y + g.height / 2);
            this.setupForcedRoles(window);
            this.launcherClosedAt = 0;
            window.motionIn = animate({ window: window, duration: d, animations: [
                { type: Effect.Scale, from: 0.18, to: 1.0, curve: QEasingCurve.OutQuint, duration: d },
                { type: Effect.Translation, from: { value1: dx * 0.82, value2: dy * 0.82 }, to: { value1: 0, value2: 0 },
                  curve: QEasingCurve.OutQuint, duration: d },
                { type: Effect.Opacity, from: 0, to: 1, curve: QEasingCurve.OutCubic, duration: Math.round(d * 0.35) },
            ] });
            return;
        }
        const d = dialog ? Math.round(this.openDuration * 0.8) : this.openDuration;
        const anims = [
            { type: Effect.Scale, from: dialog ? 0.95 : 0.92, curve: QEasingCurve.OutQuint, duration: d },
            { type: Effect.Opacity, from: 0, curve: QEasingCurve.OutCubic, duration: Math.round(d * 0.5) },
        ];
        if (!dialog && this.rise > 0) {
            anims.push({ type: Effect.Translation, from: { value1: 0, value2: this.rise }, to: { value1: 0, value2: 0 },
                         curve: QEasingCurve.OutQuint, duration: d });
        }
        this.setupForcedRoles(window);
        window.motionIn = animate({ window: window, duration: d, animations: anims });
    }

    slotWindowClosed(window) {
        if (window === this.lastActive) {
            this.lastActive = null;
        }
        if (DoodlebookMotion.isLauncher(window)) {
            this.launcherClosedAt = Date.now();
        }
        if (effects.hasActiveFullScreenEffect || !DoodlebookMotion.isAnimated(window)) {
            return;
        }
        if (!window.visible || window.skipsCloseAnimation) {
            return;
        }
        if (effect.isGrabbed(window, Effect.WindowClosedGrabRole)) {
            return;
        }
        if (window.motionIn) {
            cancel(window.motionIn);
            delete window.motionIn;
        }
        const dialog = DoodlebookMotion.isDialog(window);
        const live = window.iconGeometry;
        const icon = live && live.width > 0 ? live : window.dbIcon;
        if (!dialog && icon && icon.width > 0 && icon.height > 0) {
            // back into its dock icon (published by the DoodlebookOS dock)
            const g = window.geometry;
            const d = Math.round(this.closeDuration * 1.25);
            const dx = (icon.x + icon.width / 2) - (g.x + g.width / 2);
            const dy = (icon.y + icon.height / 2) - (g.y + g.height / 2);
            this.setupForcedRoles(window);
            window.motionOut = animate({ window: window, duration: d, animations: [
                { type: Effect.Scale, to: 0.15, curve: QEasingCurve.InCubic, duration: d },
                { type: Effect.Translation, to: { value1: dx * 0.85, value2: dy * 0.85 }, curve: QEasingCurve.InCubic, duration: d },
                { type: Effect.Opacity, to: 0, curve: QEasingCurve.InQuad, duration: d },
            ] });
            return;
        }
        const d = this.closeDuration;
        const anims = [
            { type: Effect.Scale, to: dialog ? 0.97 : 0.96, curve: QEasingCurve.InCubic, duration: d },
            { type: Effect.Opacity, to: 0, curve: QEasingCurve.InQuad, duration: d },
        ];
        if (!dialog && this.rise > 0) {
            anims.push({ type: Effect.Translation, to: { value1: 0, value2: Math.round(this.rise / 2) },
                         curve: QEasingCurve.InCubic, duration: d });
        }
        this.setupForcedRoles(window);
        window.motionOut = animate({ window: window, duration: d, animations: anims });
    }

    slotWindowDataChanged(window, role) {
        if (role == Effect.WindowAddedGrabRole) {
            if (window.motionIn && effect.isGrabbed(window, role)) {
                cancel(window.motionIn);
                delete window.motionIn;
                this.cleanupForcedRoles(window);
            }
        } else if (role == Effect.WindowClosedGrabRole) {
            if (window.motionOut && effect.isGrabbed(window, role)) {
                cancel(window.motionOut);
                delete window.motionOut;
                this.cleanupForcedRoles(window);
            }
        }
    }
}

new DoodlebookMotion();

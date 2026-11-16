/*
    DoodlebookOS Motion — Material 3 window open/close animation for KWin.
    Based on KWin's "Scale" effect (SPDX: 2018, 2021 Vlad Zahorodnii, GPL-2.0-or-later).

    SPDX-License-Identifier: GPL-3.0-or-later

    Open : the window rises 24 px and grows from 92 % (dialogs: 95 %, no rise) with the
           M3 "emphasized decelerate" feel (fast start, long soft landing), opacity
           reaches 100 % in the first part of the motion.
    Close: shrinks to 96 %, drops 12 px and fades with the "emphasized accelerate"
           feel, shorter than the opening (M3: exits are quicker than entrances).
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
        this.loadConfig();
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
        if (effects.hasActiveFullScreenEffect || !DoodlebookMotion.isAnimated(window) || !window.visible) {
            return;
        }
        if (effect.isGrabbed(window, Effect.WindowAddedGrabRole)) {
            return;
        }
        const dialog = DoodlebookMotion.isDialog(window);
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

/*
    DoodlebookOS Popups — Material 3 Expressive motion for popups, menus and tooltips.
    Takes over the windows of KWin's "Fading popups" (disable that one), with the same grab
    protocol, so an effect that already animates a window (sliding popups…) keeps it.

    SPDX-License-Identifier: GPL-3.0-or-later

    Panels (Plasma applet popups: quick settings, notifications, calendar, tray menus…, and the
    large floating windows widgets draw as "docks": the DoodlebookOS launcher, Phone Hub)
      open : unfold from the panel edge they hang from, growing out of the button that was
             clicked (the pointer, when it is in the panel) — scale 85 % → 100 % along the edge
             normal, 93 % across, on a spring-like curve (~1.5 % overshoot, M3 Expressive
             "default spatial"), contents faded in during the first 160 ms ("fast effects").
      close: fold back towards the same point in 180 ms, accelerating (M3: exits are shorter).
    Menus (context menus, drop-downs, combo boxes): grow from the corner nearest the pointer,
      opaque after 100 ms; close with a 120 ms fade.
    Tooltips: fade (+ a small scale for applications' own tooltips).
    Durations follow the global animation speed (animationTime()): "instant" — what the
    DoodlebookOS power saver sets — turns everything off. Only GPU transforms are used.
*/

"use strict";

const blacklist = [
    "ksmserver ksmserver",
    "ksmserver-logout-greeter ksmserver-logout-greeter",
    "kscreenlocker_greet kscreenlocker_greet",
    "ksplashqml ksplashqml",
];

function isShell(w) {
    return w.windowClass == "plasmashell plasmashell" || w.windowClass == "plasmashell org.kde.plasmashell";
}

// A plasmashell "dock" window that doesn't touch a screen edge is a popup drawn by a widget, not
// a panel (panels, even floating ones, reach the edge). Only the large ones (launcher, Phone Hub):
// the dock's small menus and window previews animate themselves in QML.
function isFloatingShellDock(w) {
    if (!w.dock || !isShell(w)) {
        return false;
    }
    const g = w.geometry;
    const s = screenRect(w);
    if (!s) {
        return false;
    }
    const gap = Math.min(g.y - s.y, s.y + s.height - (g.y + g.height), g.x - s.x, s.x + s.width - (g.x + g.width));
    return gap > 24 && g.height >= 420;
}

function kindOf(w) {
    if (blacklist.indexOf(w.windowClass) != -1) {
        return "";
    }
    if (w.appletPopup || isFloatingShellDock(w)) {
        return "panel";
    }
    if (w.tooltip) {
        return "tooltip";
    }
    if (w.popupMenu || w.dropdownMenu || w.comboBox || w.popupWindow) {
        return "menu";
    }
    if (w.outline) {
        return "fade";
    }
    if (!w.managed) {
        // override-redirect popups (X11); some utility windows look like popups but aren't
        return w.utility ? "" : "menu";
    }
    if (w.splash || w.toolbar || w.onScreenDisplay) {
        return "fade";
    }
    return "";
}

// The output the window is on; a window that was just created may not have one yet.
function screenRect(w) {
    const outs = [w.screen, effects.activeScreen];
    for (let i = 0; i < outs.length; i++) {
        const g = outs[i] && outs[i].geometry;
        if (g && g.width > 0) {
            return g;
        }
    }
    const v = effects.virtualScreenGeometry;
    if (v && v.width > 0) {
        return v;
    }
    return null;
}

function clamp(v, lo, hi) {
    return Math.max(lo, Math.min(hi, v));
}

class DoodlebookPopups {
    constructor() {
        effect.configChanged.connect(this.loadConfig.bind(this));
        effects.windowAdded.connect(this.slotWindowAdded.bind(this));
        effects.windowClosed.connect(this.slotWindowClosed.bind(this));
        effects.windowDataChanged.connect(this.slotWindowDataChanged.bind(this));
        this.loadConfig();
    }

    loadConfig() {
        this.panelIn = animationTime(effect.readConfig("PanelOpenDuration", 450) || 450);
        this.panelOut = animationTime(effect.readConfig("PanelCloseDuration", 180) || 180);
        this.menuIn = animationTime(effect.readConfig("MenuOpenDuration", 260) || 260);
        this.menuOut = animationTime(effect.readConfig("MenuCloseDuration", 120) || 120);
        this.fadeIn = animationTime(160);
        this.quickFade = animationTime(110);
    }

    // The Plasma panel the popup hangs from: a plasmashell dock touching a screen edge, right
    // next to the popup and overlapping it along that edge. Null when there's none.
    static hostEdge(w, g, s) {
        const list = effects.stackingOrder || [];
        let best = null;
        let bestGap = 1e9;
        for (let i = 0; i < list.length; i++) {
            const d = list[i];
            if (d === w || !d.dock || !isShell(d)) {
                continue;
            }
            const p = d.geometry;
            let edge, gap;
            if (p.width >= p.height) {
                if (Math.min(p.x + p.width, g.x + g.width) - Math.max(p.x, g.x) <= 0) {
                    continue;
                }
                if (p.y <= s.y + 1) {
                    edge = Effect.Top;
                    gap = g.y - (p.y + p.height);
                } else if (p.y + p.height >= s.y + s.height - 1) {
                    edge = Effect.Bottom;
                    gap = p.y - (g.y + g.height);
                } else {
                    continue;
                }
            } else {
                if (Math.min(p.y + p.height, g.y + g.height) - Math.max(p.y, g.y) <= 0) {
                    continue;
                }
                if (p.x <= s.x + 1) {
                    edge = Effect.Left;
                    gap = g.x - (p.x + p.width);
                } else if (p.x + p.width >= s.x + s.width - 1) {
                    edge = Effect.Right;
                    gap = p.x - (g.x + g.width);
                } else {
                    continue;
                }
            }
            if (gap >= -8 && gap < bestGap) {
                best = edge;
                bestGap = gap;
            }
        }
        return best;
    }

    // Where a panel hangs from (the Plasma panel next to it, else the nearer of the top and bottom
    // screen edges), and the point on that edge it grows from: the pointer when it is in the
    // panel strip next to the popup — the button that was clicked — else the popup's middle.
    static panelOrigin(w) {
        const g = w.geometry;
        const s = screenRect(w) || { x: 0, y: 0, width: g.x + g.width, height: g.y + g.height + g.y };
        const c = effects.cursorPos;
        let edge = DoodlebookPopups.hostEdge(w, g, s);
        if (edge === null) {
            edge = g.y - s.y <= s.y + s.height - (g.y + g.height) ? Effect.Top : Effect.Bottom;
        }
        const vertical = edge == Effect.Top || edge == Effect.Bottom;
        const reach = 160;                     // the pointer must be in the panel, near the popup
        let along;                             // offset of the origin from the popup's centre
        if (vertical) {
            const inStrip = edge == Effect.Top ? c.y <= g.y + 4 && c.y >= g.y - reach
                                               : c.y >= g.y + g.height - 4 && c.y <= g.y + g.height + reach;
            const x = inStrip && c.x >= g.x - reach && c.x <= g.x + g.width + reach
                    ? clamp(c.x, g.x + 28, g.x + g.width - 28) : g.x + g.width / 2;
            along = x - (g.x + g.width / 2);
        } else {
            const inStrip = edge == Effect.Left ? c.x <= g.x + 4 && c.x >= g.x - reach
                                                : c.x >= g.x + g.width - 4 && c.x <= g.x + g.width + reach;
            const y = inStrip && c.y >= g.y - reach && c.y <= g.y + g.height + reach
                    ? clamp(c.y, g.y + 28, g.y + g.height - 28) : g.y + g.height / 2;
            along = y - (g.y + g.height / 2);
        }
        return { edge: edge, vertical: vertical, along: along };
    }

    // Scale anchored on `edge`, plus the translation that moves the fixed point from the edge's
    // middle to `along` (same curve and duration, so the point stays exactly in place).
    static unfold(o, across, normal, curve, duration, opening) {
        const sx = o.vertical ? across : normal;
        const sy = o.vertical ? normal : across;
        const shift = o.along * (1 - across);
        const scale = { type: Effect.Scale, sourceAnchor: o.edge, targetAnchor: o.edge, curve: curve, duration: duration };
        const move = { type: Effect.Translation, curve: curve, duration: duration };
        const point = o.vertical ? { value1: shift, value2: 0 } : { value1: 0, value2: shift };
        if (opening) {
            scale.from = { value1: sx, value2: sy };
            scale.to = { value1: 1, value2: 1 };
            move.from = point;
            move.to = { value1: 0, value2: 0 };
        } else {
            scale.to = { value1: sx, value2: sy };
            move.to = point;
        }
        return Math.abs(shift) >= 0.5 ? [scale, move] : [scale];
    }

    static menuCorner(w) {
        const g = w.geometry;
        const c = effects.cursorPos;
        const v = c.y <= g.y + g.height / 2 ? Effect.Top : Effect.Bottom;
        const h = c.x <= g.x + g.width / 2 ? Effect.Left : Effect.Right;
        return v | h;
    }

    slotWindowAdded(w) {
        if (effects.hasActiveFullScreenEffect || !w.visible) {
            return;
        }
        const kind = kindOf(w);
        if (!kind) {
            return;
        }
        let duration, anims;
        if (kind == "panel") {
            duration = this.panelIn;
            const o = DoodlebookPopups.panelOrigin(w);
            w.dbOrigin = o;
            anims = DoodlebookPopups.unfold(o, 0.93, 0.85, QEasingCurve.OutBack, duration, true);
            anims.push({ type: Effect.Opacity, from: 0, to: 1, curve: QEasingCurve.OutCubic, duration: this.fadeIn });
        } else if (kind == "menu") {
            duration = this.menuIn;
            const corner = DoodlebookPopups.menuCorner(w);
            anims = [
                { type: Effect.Scale, from: { value1: 0.92, value2: 0.82 }, to: { value1: 1, value2: 1 },
                  sourceAnchor: corner, targetAnchor: corner, curve: QEasingCurve.OutBack, duration: duration },
                { type: Effect.Opacity, from: 0, to: 1, curve: QEasingCurve.OutCubic, duration: Math.round(duration * 0.4) },
            ];
        } else if (kind == "tooltip") {
            duration = this.fadeIn;
            anims = [{ type: Effect.Opacity, from: 0, to: 1, curve: QEasingCurve.OutCubic, duration: duration }];
            if (!isShell(w)) {                 // DoodlebookOS tooltips already pop from their icon
                anims.push({ type: Effect.Scale, from: 0.94, to: 1, curve: QEasingCurve.OutQuint, duration: duration });
            }
        } else {
            duration = this.fadeIn;
            anims = [{ type: Effect.Opacity, from: 0, to: 1, curve: QEasingCurve.Linear, duration: duration }];
        }
        if (duration <= 0 || !effect.grab(w, Effect.WindowAddedGrabRole)) {
            return;
        }
        w.dbPopupIn = animate({ window: w, duration: duration, animations: anims });
    }

    slotWindowClosed(w) {
        if (effects.hasActiveFullScreenEffect || !w.visible || w.skipsCloseAnimation) {
            return;
        }
        const kind = kindOf(w);
        if (!kind) {
            return;
        }
        if (w.dbPopupIn) {
            cancel(w.dbPopupIn);
            delete w.dbPopupIn;
        }
        let duration, anims;
        if (kind == "panel") {
            duration = this.panelOut;
            const o = w.dbOrigin || DoodlebookPopups.panelOrigin(w);
            anims = DoodlebookPopups.unfold(o, 0.97, 0.93, QEasingCurve.InCubic, duration, false);
            anims.push({ type: Effect.Opacity, to: 0, curve: QEasingCurve.InQuad, duration: duration });
        } else if (kind == "menu") {
            duration = this.menuOut;
            anims = [{ type: Effect.Opacity, to: 0, curve: QEasingCurve.OutQuad, duration: duration }];
        } else {
            duration = this.quickFade;
            anims = [{ type: Effect.Opacity, to: 0, curve: QEasingCurve.OutQuad, duration: duration }];
        }
        if (duration <= 0 || !effect.grab(w, Effect.WindowClosedGrabRole)) {
            return;
        }
        w.dbPopupOut = animate({ window: w, duration: duration, animations: anims });
    }

    slotWindowDataChanged(w, role) {
        // another effect took the window over: let it animate alone
        if (role == Effect.WindowAddedGrabRole) {
            if (w.dbPopupIn && effect.isGrabbed(w, role)) {
                cancel(w.dbPopupIn);
                delete w.dbPopupIn;
            }
        } else if (role == Effect.WindowClosedGrabRole) {
            if (w.dbPopupOut && effect.isGrabbed(w, role)) {
                cancel(w.dbPopupOut);
                delete w.dbPopupOut;
            }
        }
    }
}

new DoodlebookPopups();

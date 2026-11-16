// SPDX-License-Identifier: GPL-3.0-or-later
// DoodlebookOS Focus: every window fades to greyscale while the effect is loaded.
// Uses KWin's own saturation attribute (rendered in the normal pass, no offscreen copy).
// Unloading the effect cancels the animations, which restores the colours.
"use strict";

var focus = {
    duration: 450,
    add: function (w) {
        if (!w || w.doodlebookosFocus) {
            return;
        }
        w.doodlebookosFocus = set({
            window: w,
            duration: focus.duration,
            curve: QEasingCurve.OutCubic,
            animations: [{ type: Effect.Saturation, from: 1.0, to: 0.0 }]
        });
    },
    init: function () {
        effects.windowAdded.connect(focus.add);
        var list = effects.stackingOrder;
        for (var i = 0; i < list.length; ++i) {
            focus.add(list[i]);
        }
    }
};

focus.init();

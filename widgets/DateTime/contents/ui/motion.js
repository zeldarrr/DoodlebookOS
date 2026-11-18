// SPDX-License-Identifier: GPL-3.0-or-later
// Material 3 Expressive motion springs (the values of Jetpack Compose's MotionScheme.expressive()),
// evaluated analytically: a damped harmonic oscillator of unit mass released from 0 towards 1.
// One linear driver (time in nominal ms) feeds every element: no per-item animation objects,
// a handful of cheap bindings per frame, and the same feel as Android 16's Quick Settings.
.pragma library

function spring(ms, damping, stiffness) {
    if (ms <= 0)
        return 0;
    var t = ms / 1000;
    var w = Math.sqrt(stiffness);
    var v;
    if (damping >= 1) {
        v = 1 - Math.exp(-w * t) * (1 + w * t);
    } else {
        var wd = w * Math.sqrt(1 - damping * damping);
        var e = Math.exp(-damping * w * t);
        v = 1 - e * (Math.cos(wd * t) + (damping * w / wd) * Math.sin(wd * t));
    }
    // settled: exactly 1, so an opacity of 0.99999 doesn't keep an opacity node in the scene graph
    return Math.abs(1 - v) < 0.0005 ? 1 : v;
}

// spatial springs: position / size / shape (they overshoot a little — "expressive")
function fastSpatial(ms) { return spring(ms, 0.6, 800); }      // ~240 ms, 9 % overshoot
function defaultSpatial(ms) { return spring(ms, 0.8, 380); }   // ~350 ms, 1.5 % overshoot
function slowSpatial(ms) { return spring(ms, 0.8, 200); }      // ~480 ms
// effects springs: opacity / colour (critically damped, never overshoot)
function fastEffects(ms) { return spring(ms, 1, 3800); }       // ~ 80 ms
function effects(ms) { return spring(ms, 1, 1600); }           // ~130 ms
function slowEffects(ms) { return spring(ms, 1, 800); }        // ~190 ms

// nominal → real duration factor of the global animation speed (Kirigami longDuration is 200 at 1×)
function speed(longDuration) { return Math.max(0, longDuration) / 200; }

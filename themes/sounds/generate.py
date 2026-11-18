#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""DoodlebookOS sound theme — original, discreet, Android-like system sounds.

Every sound is synthesised here (soft marimba / glass tones, a short room reverb, low level),
then encoded to Ogg Vorbis with ffmpeg:
    python3 themes/sounds/generate.py          → themes/sounds/DoodlebookOS/stereo/*.oga
Sounds not made here fall back to Ocean, then freedesktop (index.theme: Inherits).
"""
import os
import subprocess

import numpy as np

SR = 48000
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "DoodlebookOS", "stereo")
rng = np.random.default_rng(7)


def hz(note):
    """'E5' / 'C#6' → frequency."""
    names = {"C": -9, "D": -7, "E": -5, "F": -4, "G": -2, "A": 0, "B": 2}
    n, rest = note[0], note[1:]
    shift = 0
    while rest and rest[0] in "#b":
        shift += 1 if rest[0] == "#" else -1
        rest = rest[1:]
    return 440.0 * 2 ** ((names[n] + shift + 12 * (int(rest) - 4)) / 12)


def env(n, attack=0.004):
    a = max(1, int(attack * SR))
    e = np.ones(n)
    e[:a] = 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, a))
    return e


def marimba(f, dur=0.6, decay=0.22, bright=1.0):
    """Wooden mallet: fundamental + the marimba's 4th partial (3.93×) + a fast 'tick'."""
    t = np.arange(int(dur * SR)) / SR
    s = (np.sin(2 * np.pi * f * t) * np.exp(-t / decay)
         + 0.22 * bright * np.sin(2 * np.pi * 3.93 * f * t) * np.exp(-t / (decay / 4))
         + 0.05 * bright * np.sin(2 * np.pi * 9.2 * f * t) * np.exp(-t / (decay / 12)))
    return s * env(len(t))


def glass(f, dur=0.9, decay=0.35):
    """Soft bell (FM): a little shimmer that fades into a pure tone."""
    t = np.arange(int(dur * SR)) / SR
    idx = 1.2 * np.exp(-t / (decay / 3))
    s = np.sin(2 * np.pi * f * t + idx * np.sin(2 * np.pi * 2.0 * f * t)) * np.exp(-t / decay)
    return s * env(len(t), 0.006)


def bubble(f0, f1, dur=0.06):
    """Short pitched 'pop' (volume ticks, clicks)."""
    t = np.arange(int(dur * SR)) / SR
    f = f0 + (f1 - f0) * (1 - np.exp(-t / (dur / 3)))
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * np.exp(-t / (dur / 4)) * env(len(t), 0.002)


def whoosh(dur=0.45):
    """Filtered noise sweep (empty trash)."""
    n = int(dur * SR)
    noise = rng.standard_normal(n)
    out = np.zeros(n)
    y = 0.0
    t = np.arange(n) / SR
    cut = 0.02 + 0.25 * np.sin(np.pi * t / dur) ** 2          # one-pole low-pass, opening then closing
    for i in range(n):
        y += cut[i] * (noise[i] - y)
        out[i] = y
    return out * np.sin(np.pi * t / dur) ** 1.5


def seq(*parts):
    """[(start_seconds, signal, gain), ...] → one buffer."""
    end = max(int(s * SR) + len(x) for s, x, _ in parts)
    out = np.zeros(end)
    for s, x, g in parts:
        i = int(s * SR)
        out[i:i + len(x)] += g * x
    return out


def reverb(x, size=0.45, mix=0.14):
    """Small room: exponentially decaying noise impulse response (FFT convolution)."""
    n = int(size * SR)
    t = np.arange(n) / SR
    ir = rng.standard_normal(n) * np.exp(-t / (size / 5))
    ir[: int(0.008 * SR)] = 0                                 # pre-delay
    ir /= np.sqrt(np.sum(ir ** 2))
    m = len(x) + n
    wet = np.fft.irfft(np.fft.rfft(x, m) * np.fft.rfft(ir, m), m)[:m]
    dry = np.concatenate([x, np.zeros(n)])
    return dry + mix * wet / (np.max(np.abs(wet)) + 1e-9) * np.max(np.abs(x))


def finish(x, level_db=-16.0, width=0.0004):
    x = reverb(x)
    # trim the silent tail
    idx = np.where(np.abs(x) > np.max(np.abs(x)) * 1e-3)[0]
    x = x[: idx[-1] + int(0.02 * SR)] if len(idx) else x
    x *= 10 ** (level_db / 20) / (np.max(np.abs(x)) + 1e-9)
    fade = min(len(x), int(0.015 * SR))
    x[-fade:] *= np.linspace(1, 0, fade)
    d = int(width * SR)                                       # tiny Haas delay: soft stereo
    left = x
    right = np.concatenate([np.zeros(d), x[: len(x) - d]])
    return np.stack([left, right], axis=1).astype(np.float32)


def write(name, x):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".oga")
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "2", "-i", "-",
                    "-c:a", "libvorbis", "-q:a", "4", "-map_metadata", "-1", path],
                   input=x.tobytes(), check=True)


def main():
    M, G = marimba, glass
    s = {}
    # notifications: two rising wooden notes, like a message on Android
    s["message-new-instant"] = finish(seq((0, M(hz("E6")), 0.8), (0.085, M(hz("B6")), 1.0)), -15)
    s["message-new-email"] = finish(seq((0, M(hz("G5")), 0.8), (0.09, M(hz("D6")), 0.9), (0.18, M(hz("G6")), 0.7)), -16)
    s["message-attention"] = finish(seq((0, G(hz("A5")), 1.0), (0.12, G(hz("E6")), 0.8)), -15)
    s["message-highlight"] = s["message-attention"]
    s["dialog-information"] = finish(seq((0, G(hz("C6"), 0.7, 0.28), 1.0)), -17)
    s["dialog-question"] = finish(seq((0, M(hz("A5")), 0.8), (0.11, M(hz("E6")), 0.9)), -17)
    s["dialog-warning"] = finish(seq((0, M(hz("D5"), 0.5, 0.18), 1.0), (0.13, M(hz("D5"), 0.5, 0.18), 0.8)), -15)
    s["dialog-warning-auth"] = finish(seq((0, G(hz("F5"), 0.6, 0.25), 1.0)), -16)
    s["dialog-error"] = finish(seq((0, M(hz("E5")), 1.0), (0.12, M(hz("A4")), 0.9)), -14)
    s["dialog-error-serious"] = s["dialog-error"]
    s["dialog-error-critical"] = finish(seq((0, M(hz("E5")), 1.0), (0.11, M(hz("C5")), 0.9), (0.22, M(hz("A4")), 0.9)), -13)
    # outcomes
    s["outcome-success"] = finish(seq((0, M(hz("C6")), 0.8), (0.07, M(hz("E6")), 0.8), (0.14, M(hz("G6")), 0.9)), -16)
    s["completion-success"] = s["outcome-success"]
    s["complete-media-burn"] = s["outcome-success"]
    s["outcome-failure"] = finish(seq((0, M(hz("G5")), 0.9), (0.1, M(hz("D5")), 0.9)), -15)
    s["completion-fail"] = s["outcome-failure"]
    # devices and power (the Android "plug" sound is a soft rising glide)
    s["device-added"] = finish(seq((0, M(hz("G5")), 0.7), (0.06, M(hz("C6")), 0.8), (0.12, M(hz("G6")), 0.9)), -16)
    s["device-removed"] = finish(seq((0, M(hz("G6")), 0.8), (0.06, M(hz("C6")), 0.8), (0.12, M(hz("G5")), 0.9)), -16)
    s["power-plug"] = finish(seq((0, G(hz("E5"), 0.8, 0.3), 0.7), (0.09, G(hz("B5"), 0.9, 0.35), 0.9)), -16)
    s["power-unplug"] = finish(seq((0, G(hz("B5"), 0.6, 0.22), 0.8), (0.09, G(hz("E5"), 0.7, 0.28), 0.8)), -17)
    s["battery-low"] = finish(seq((0, M(hz("A4"), 0.5, 0.2), 1.0), (0.2, M(hz("A4"), 0.5, 0.2), 0.9)), -14)
    s["battery-caution"] = s["battery-low"]
    s["battery-full"] = finish(seq((0, G(hz("E6"), 0.9, 0.35), 1.0)), -18)
    # session
    chord = [("C5", 0), ("G5", 0.09), ("D6", 0.18), ("E6", 0.27), ("B6", 0.36)]
    s["desktop-login"] = finish(seq(*[(t, G(hz(n), 1.6, 0.7), 0.8) for n, t in chord]), -15)
    s["desktop-logout"] = finish(seq(*[(t, G(hz(n), 1.2, 0.5), 0.8) for (n, _), t in zip(reversed(chord[:4]), (0, 0.09, 0.18, 0.27))]), -16)
    s["service-login"] = finish(seq((0, G(hz("G5"), 0.8, 0.3), 0.8), (0.09, G(hz("D6"), 0.9, 0.35), 0.8)), -17)
    s["service-logout"] = finish(seq((0, G(hz("D6"), 0.7, 0.25), 0.8), (0.09, G(hz("G5"), 0.8, 0.3), 0.8)), -17)
    s["theme-demo"] = s["desktop-login"]
    # small UI sounds: very short, quiet
    s["audio-volume-change"] = finish(bubble(1300, 1500, 0.05), -20)
    s["bell"] = finish(bubble(900, 1100, 0.07), -18)
    s["bell-window-system"] = s["bell"]
    s["button-pressed"] = finish(bubble(2200, 1800, 0.025), -24)
    s["button-pressed-modifier"] = s["button-pressed"]
    s["trash-empty"] = finish(seq((0, whoosh(0.45), 1.0), (0.3, M(hz("C6"), 0.4, 0.12), 0.25)), -18)
    s["screen-capture"] = finish(seq((0, bubble(3000, 2400, 0.03), 1.0), (0.05, bubble(2000, 1600, 0.04), 0.8)), -18)
    s["camera-shutter"] = s["screen-capture"]
    # alarm / call: a gentle repeated motif
    motif = [("E6", 0), ("B6", 0.12), ("G#6", 0.24), ("E6", 0.48)]
    s["alarm-clock-elapsed"] = finish(seq(*[(t + r * 1.1, M(hz(n), 0.7, 0.3), 0.9) for r in range(3) for n, t in motif]), -13)
    s["phone-incoming-call"] = finish(seq(*[(t + r * 1.3, G(hz(n), 0.9, 0.4), 0.9) for r in range(3) for n, t in motif]), -13)
    for name, x in s.items():
        write(name, x)
    print(f"{len(s)} sons → {OUT}")


if __name__ == "__main__":
    main()

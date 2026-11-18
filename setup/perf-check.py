#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""DoodlebookOS — mesure de consommation au repos (CPU par processus + batterie).

    python3 setup/perf-check.py [--seconds 60] [--delay 10]

Lancez-le, puis ne touchez plus à rien (et laissez le terminal sans sortie qui défile) : après
--delay secondes il mesure pendant --seconds le temps CPU de chaque processus et, sur batterie,
la puissance moyenne tirée (W). Repères sur un portable récent : bureau (kwin_wayland +
plasmashell + kded6) < 1,5 % au repos, puissance au repos 4–7 W selon l'écran.
"""
import argparse
import glob
import os
import time

HZ = os.sysconf("SC_CLK_TCK")
DESKTOP = ("kwin_wayland", "plasmashell", "kded6", "ksmserver", "kglobalacceld", "xdg-desktop-por",
           "Xwayland", "pipewire", "wireplumber", "baloo_file", "powerdevil", "org_kde_powerde")


def procs():
    out = {}
    for p in glob.glob("/proc/[0-9]*"):
        try:
            with open(p + "/stat") as f:
                st = f.read()
            name = st[st.index("(") + 1:st.rindex(")")]
            fields = st[st.rindex(")") + 2:].split()
            out[int(p[6:])] = (name, int(fields[11]) + int(fields[12]))
        except (OSError, ValueError, IndexError):
            pass
    return out


def cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().replace(b"\0", b" ").decode(errors="replace").strip()
    except OSError:
        return ""


def battery():
    for b in sorted(glob.glob("/sys/class/power_supply/BAT*")):
        def rd(k):
            try:
                with open(f"{b}/{k}") as f:
                    return f.read().strip()
            except OSError:
                return None
        return rd
    return None


def watts(rd):
    if rd is None:
        return None
    p = rd("power_now")
    if p:
        return int(p) / 1e6
    i, v = rd("current_now"), rd("voltage_now")
    if i and v:
        return int(i) * int(v) / 1e12
    return None


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    ap.add_argument("--seconds", type=int, default=60)
    ap.add_argument("--delay", type=int, default=10)
    a = ap.parse_args()

    rd = battery()
    print(f"Mesure dans {a.delay} s pendant {a.seconds} s — ne touchez plus à rien…", flush=True)
    time.sleep(a.delay)
    p0, t0 = procs(), time.time()
    samples = []
    while time.time() - t0 < a.seconds:
        time.sleep(min(2, a.seconds))
        w = watts(rd)
        if w:
            samples.append(w)
    p1, dt = procs(), time.time() - t0

    rows = []
    for pid, (name, t) in p1.items():
        if pid in p0 and p0[pid][0] == name:
            c = (t - p0[pid][1]) / HZ / dt * 100
            if c >= 0.05:
                rows.append((c, name, pid))
    rows.sort(reverse=True)
    desk = sum(c for c, n, _ in rows if n.startswith(DESKTOP))
    ours = [(c, n, pid) for c, n, pid in rows if "doodlebookos" in cmdline(pid)]

    print("\nCPU (% d'un cœur) :")
    for c, n, pid in rows[:15]:
        mark = "  ← DoodlebookOS" if "doodlebookos" in cmdline(pid) else ""
        print(f"  {c:6.2f} %  {n} ({pid}){mark}")
    print(f"\nBureau (kwin, plasmashell, kded…) : {desk:.2f} %")
    print(f"Démons DoodlebookOS actifs : {sum(c for c, _, _ in ours):.2f} %")
    if rd is not None:
        status = rd("status") or "?"
        if samples and status.lower() == "discharging":
            print(f"Batterie ({status}) : {sum(samples) / len(samples):.2f} W en moyenne "
                  f"(min {min(samples):.2f}, max {max(samples):.2f})")
        else:
            print(f"Batterie : {status} — débranchez le chargeur pour mesurer la puissance.")
    try:
        with open(os.path.expanduser("~/.local/state/doodlebookos/powersave.json")) as f:
            print("Économie d'énergie DoodlebookOS : active" if f.read().strip() not in ("", "{}") else "")
    except OSError:
        pass


if __name__ == "__main__":
    main()

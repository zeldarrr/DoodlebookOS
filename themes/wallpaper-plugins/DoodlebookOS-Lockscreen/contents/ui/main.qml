/*
    SPDX-License-Identifier: GPL-3.0-or-later

    DoodlebookOS lock screen (Material 3 Expressive, like Android 16).

    A wallpaper plugin for the lock screen: Plasma's own lock screen keeps the password prompt,
    media controls and session switching; this draws everything behind it — the wallpaper, a big
    two-line clock in Google Sans Flex, the date and the weather. When the prompt shows, Plasma
    blurs this layer, so the clock recedes behind the password field like on Android.

    Motion: the clock rises line by line on M3 Expressive springs while its weight grows (the
    Pixel clock "breathes" on wake); minutes roll when they change. Everything is driven by one
    timer that stops once settled: nothing runs while the screen sits locked.
*/
import QtQuick
import QtCore
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

WallpaperItem {
    id: root

    readonly property string fallbackImage: StandardPaths.writableLocation(StandardPaths.GenericDataLocation)
                                            + "/doodlebookos/lockscreen-materialyou.jpg"
    readonly property string imagePath: {
        var p = root.configuration.Image || "";
        if (p === "") return fallbackImage;
        return p.indexOf("/") === 0 ? "file://" + p : p;
    }

    readonly property color accent: Kirigami.Theme.highlightColor
    // Android lock screen clock: a very light tint of the wallpaper's primary colour
    readonly property color clockColor: Qt.tint("#ffffff", Qt.rgba(accent.r, accent.g, accent.b, 0.32))
    readonly property color softColor: Qt.rgba(1, 1, 1, 0.86)
    readonly property string fontFamily: "Google Sans Flex"
    readonly property bool twelveHour: Qt.locale().timeFormat(Locale.ShortFormat).toLowerCase().indexOf("a") !== -1

    accentColor: accent

    // ── time ────────────────────────────────────────────────────────────────────────────────
    property date now: new Date()
    Timer {
        // wakes on the next minute boundary only (60 s apart), not every second
        id: tick
        interval: Math.max(1000, 60000 - (new Date().getSeconds() * 1000 + new Date().getMilliseconds()) + 50)
        running: true
        repeat: false
        onTriggered: {
            root.now = new Date();
            interval = Math.max(1000, 60000 - (root.now.getSeconds() * 1000 + root.now.getMilliseconds()) + 50);
            start();
        }
    }
    readonly property string hours: twelveHour ? String(now.getHours() % 12 === 0 ? 12 : now.getHours() % 12)
                                               : Qt.formatTime(now, "HH")
    readonly property string minutes: Qt.formatTime(now, "mm")
    readonly property string dateText: {
        var s = now.toLocaleDateString(Qt.locale(), "dddd d MMMM");
        return s.charAt(0).toUpperCase() + s.slice(1);
    }

    // ── M3 Expressive springs (same as the widgets' motion.js) ──────────────────────────────
    function spring(ms, damping, stiffness) {
        if (ms <= 0) return 0;
        var t = ms / 1000, w = Math.sqrt(stiffness), v;
        if (damping >= 1) {
            v = 1 - Math.exp(-w * t) * (1 + w * t);
        } else {
            var wd = w * Math.sqrt(1 - damping * damping), e = Math.exp(-damping * w * t);
            v = 1 - e * (Math.cos(wd * t) + (damping * w / wd) * Math.sin(wd * t));
        }
        return Math.abs(1 - v) < 0.0005 ? 1 : v;
    }
    function spatial(ms) { return spring(ms, 0.8, 380); }      // defaultSpatial
    function slowSpatial(ms) { return spring(ms, 0.8, 200); }
    function effects(ms) { return spring(ms, 1, 1600); }

    property real revealMs: 0
    NumberAnimation on revealMs {
        id: reveal
        from: 0; to: 1400
        duration: Kirigami.Units.longDuration > 1 ? 1400 * Kirigami.Units.longDuration / 200 : 0
        running: true
    }
    // line i rises 56 px and fades in, 70 ms after the previous one
    function lineOpacity(i) { return effects(revealMs - 80 - i * 70); }
    function lineShift(i) { return (1 - spatial(revealMs - 40 - i * 70)) * 56; }
    // the clock "breathes": weight 300 → 560 on the slow spring
    readonly property real clockWeight: 300 + 260 * slowSpatial(revealMs - 120)

    // ── wallpaper ───────────────────────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: "#101014"
    }
    Image {
        id: wall
        anchors.fill: parent
        source: root.imagePath
        fillMode: Image.PreserveAspectCrop
        sourceSize: Qt.size(root.width, root.height)
        asynchronous: false
        cache: false
        // very slow settle, like Android's wallpaper zoom on wake
        scale: 1.06 - 0.06 * root.slowSpatial(root.revealMs)
        opacity: status === Image.Ready ? 1 : 0
    }
    // legibility scrim: darker behind the clock and at the bottom, clear in the middle
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.38) }
            GradientStop { position: 0.45; color: Qt.rgba(0, 0, 0, 0.12) }
            GradientStop { position: 0.8; color: Qt.rgba(0, 0, 0, 0.06) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.32) }
        }
    }

    // ── clock ───────────────────────────────────────────────────────────────────────────────
    component RollDigits: Item {
        id: roll
        property string text
        property real size
        property real weight
        property int line
        implicitWidth: Math.max(cur.implicitWidth, prev.implicitWidth)
        implicitHeight: size * 0.86
        clip: true
        property real swapMs: 100000
        NumberAnimation on swapMs { id: swap; from: 0; to: 700; running: false
            duration: Kirigami.Units.longDuration > 1 ? 700 * Kirigami.Units.longDuration / 200 : 0 }
        onTextChanged: {
            prev.text = cur.text;
            cur.text = text;
            if (prev.text !== "" && prev.text !== text) swap.restart();
        }
        Component.onCompleted: cur.text = text
        readonly property real k: root.spatial(swapMs)
        Text {
            id: prev
            anchors.horizontalCenter: parent.horizontalCenter
            y: (parent.height - height) / 2 - roll.k * roll.size * 0.5
            opacity: 1 - root.effects(roll.swapMs)
            visible: roll.swapMs < 700
            font.family: root.fontFamily
            font.pixelSize: roll.size
            font.variableAxes: { "wght": roll.weight, "ROND": 100 }
            color: root.clockColor
            renderType: Text.QtRendering
        }
        Text {
            id: cur
            anchors.horizontalCenter: parent.horizontalCenter
            y: (parent.height - height) / 2 + (1 - roll.k) * roll.size * 0.5
            opacity: roll.swapMs < 700 ? root.effects(roll.swapMs - 60) : 1
            font.family: root.fontFamily
            font.pixelSize: roll.size
            font.variableAxes: { "wght": roll.weight, "ROND": 100 }
            color: root.clockColor
            renderType: Text.QtRendering
        }
    }

    Column {
        id: clockColumn
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(root.height * 0.13)
        spacing: -Math.round(clockSize * 0.08)
        readonly property real clockSize: Math.round(Math.min(root.height * 0.21, root.width * 0.17))

        RollDigits {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.hours
            size: clockColumn.clockSize
            weight: root.clockWeight
            opacity: root.lineOpacity(0)
            transform: Translate { y: root.lineShift(0) }
        }
        RollDigits {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.minutes
            size: clockColumn.clockSize
            weight: root.clockWeight
            opacity: root.lineOpacity(1)
            transform: Translate { y: root.lineShift(1) }
        }
        Item { width: 1; height: Math.round(clockColumn.clockSize * 0.22) }

        // "smartspace" line: date · weather
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 12
            opacity: root.lineOpacity(2)
            transform: Translate { y: root.lineShift(2) }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.dateText
                color: root.softColor
                font.family: root.fontFamily
                font.pixelSize: Math.round(clockColumn.clockSize * 0.12)
                font.variableAxes: { "wght": 500, "ROND": 100 }
            }
            Rectangle {
                visible: weather.ready
                anchors.verticalCenter: parent.verticalCenter
                width: 5; height: 5; radius: 2.5
                color: root.softColor
                opacity: 0.6
            }
            Kirigami.Icon {
                visible: weather.ready
                anchors.verticalCenter: parent.verticalCenter
                width: Math.round(clockColumn.clockSize * 0.15)
                height: width
                source: weather.icon
                isMask: true
                color: root.softColor
            }
            Text {
                visible: weather.ready
                anchors.verticalCenter: parent.verticalCenter
                text: weather.temp + "°"
                color: root.softColor
                font.family: root.fontFamily
                font.pixelSize: Math.round(clockColumn.clockSize * 0.12)
                font.variableAxes: { "wght": 500, "ROND": 100 }
            }
        }
    }

    // ── weather (open-meteo, like the Weather widget; refreshed every 30 min while locked) ──
    QtObject {
        id: weather
        property bool ready: false
        property int temp: 0
        property string icon: "weather-clear"
        readonly property string city: root.configuration.City || ""

        function iconFor(code, day) {
            var n = day ? "" : "-night";
            if (code === 0) return "weather-clear" + n;
            if (code <= 2) return "weather-few-clouds" + n;
            if (code === 3) return "weather-overcast";
            if (code === 45 || code === 48) return "weather-fog";
            if (code >= 51 && code <= 57) return "weather-showers-scattered" + (day ? "" : "-night");
            if ((code >= 61 && code <= 67) || (code >= 80 && code <= 82)) return "weather-showers";
            if ((code >= 71 && code <= 77) || code === 85 || code === 86) return "weather-snow";
            if (code >= 95) return "weather-storm";
            return "weather-overcast";
        }
        function get(url, done) {
            var x = new XMLHttpRequest();
            x.open("GET", url, true);
            x.timeout = 8000;
            x.onreadystatechange = function () {
                if (x.readyState === XMLHttpRequest.DONE && x.status === 200) {
                    try { done(JSON.parse(x.responseText)); } catch (e) {}
                }
            };
            x.send();
        }
        function load(lat, lon) {
            get("https://api.open-meteo.com/v1/forecast?latitude=" + lat + "&longitude=" + lon
                + "&current=temperature_2m,is_day,weather_code&timezone=auto", function (d) {
                if (!d.current) return;
                weather.temp = Math.round(d.current.temperature_2m);
                weather.icon = weather.iconFor(d.current.weather_code, d.current.is_day === 1);
                weather.ready = true;
            });
        }
        // the city set here, else the network's location (like the Weather widget)
        function refresh() {
            if (!root.configuration.ShowWeather) { ready = false; return; }
            if (city === "") {
                get("https://ipwho.is/", function (r) {
                    if (r && r.success !== false && typeof r.latitude === "number") load(r.latitude, r.longitude);
                });
                return;
            }
            get("https://geocoding-api.open-meteo.com/v1/search?count=1&format=json&name=" + encodeURIComponent(city), function (g) {
                if (g.results && g.results.length) load(g.results[0].latitude, g.results[0].longitude);
            });
        }
        onCityChanged: refresh()
        Component.onCompleted: refresh()
    }
    Timer { interval: 30 * 60 * 1000; repeat: true; running: root.configuration.ShowWeather; onTriggered: weather.refresh() }
}

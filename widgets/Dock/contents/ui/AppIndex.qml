// SPDX-License-Identifier: GPL-3.0-or-later
// Launcher data hub: app index (categories, search words, "new" and notification badges),
// typo-tolerant search, folders. Everything is rebuilt from model/notification signals only.
import QtQuick
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.notificationmanager as NotificationManager
import "i18n.js" as I18n

Item {
    id: idx
    visible: false
    function i18n(k, a1, a2) { return I18n.t(k, a1, a2); }

    property var appsModel: null
    property var meta: ({})          // storageId -> {c, k, d, src}   (code/apps.py index)
    property var entries: []         // model order: {row, id, name, key, words, ini, kf, kwords, df, obj}
    property var byId: ({})
    property var rowIds: []          // model row -> storageId ("" when unknown)
    property var idByName: ({})      // display name -> storageId (recent apps rows)
    property var counts: ({})        // category -> app count
    property int revision: 0         // bumped whenever entries/meta/folders change
    property var badges: ({})        // storageId -> notification count
    property var folders: []         // [{id, name, apps: [storageId]}]
    property var folderOfId: ({})    // storageId -> folder id
    property color tertiary: Kirigami.Theme.highlightColor
    property color onTertiary: Kirigami.Theme.highlightedTextColor
    // colours of the generated Material You app icons (doodlebookos-materialyou), for the dock buttons
    property bool hasIconColors: false
    property color iconBg: "transparent"
    property color iconFg: Kirigami.Theme.textColor
    // Material 3 Expressive shape shared with the generated icons (doodlebookos-icons shape …)
    property string shapeName: "circle"
    property string shapePath: ""
    property real shapeTurn: 0
    property var shapes: []

    readonly property var categoryKeys: ["all", "games", "internet", "media", "graphics", "office", "dev", "education", "system", "utilities", "other"]
    readonly property var categoryLabels: ({
        "all": "All", "games": "Games", "internet": "Internet", "media": "Multimedia", "graphics": "Graphics",
        "office": "Office", "dev": "Development", "education": "Education", "system": "System",
        "utilities": "Utilities", "other": "Other"
    })
    function categoryLabel(key) { return i18n(categoryLabels[key] || key); }

    readonly property string helper: decodeURIComponent(String(Qt.resolvedUrl("../code/apps.py")).replace("file://", ""))
    function shq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'"; }

    // ───────────── ids / text ─────────────
    function sid(raw) {
        var s = String(raw || "");
        if (s.indexOf("applications:") === 0) s = s.substring(13);
        if (s.indexOf("file://") === 0 || s.indexOf("/") === 0) s = s.substring(s.lastIndexOf("/") + 1);
        if (s.length && s.indexOf(".desktop") === -1) s += ".desktop";
        return s;
    }
    function fold(s) {
        s = String(s || "").toLowerCase();
        try { s = s.normalize("NFD").replace(/[̀-ͯ]/g, ""); } catch (e) {}
        return s;
    }
    function initialsOf(name) {
        var parts = String(name).replace(/([a-z])([A-Z])/g, "$1 $2").split(/[\s\-_.:\/]+/);
        var out = "";
        for (var i = 0; i < parts.length; i++) if (parts[i].length) out += parts[i][0];
        return fold(out);
    }

    // ───────────── model mirror ─────────────
    Instantiator {
        id: mirror
        model: idx.appsModel
        delegate: QtObject {
            required property int index
            required property var model
            readonly property string fid: model.favoriteId ? String(model.favoriteId) : ""
            readonly property string name: model.display ? String(model.display) : ""
            readonly property bool isNew: model.isNewlyInstalled === true
        }
        onObjectAdded: rebuild.restart()
        onObjectRemoved: rebuild.restart()
    }
    Timer { id: rebuild; interval: 0; onTriggered: idx.build() }

    function build() {
        var list = [], map = {}, cnt = { "all": 0 }, rows = [], names = {};
        for (var i = 0; i < mirror.count; i++) {
            var o = mirror.objectAt(i);
            rows.push(o && o.fid ? sid(o.fid) : "");
            if (!o || !o.fid) continue;
            var id = sid(o.fid);
            names[o.name] = id;
            var m = meta[id] || null;
            var key = fold(o.name);
            var kf = m ? fold(m.k) : "";
            var e = { row: i, id: id, name: o.name, key: key, words: key.split(/[\s\-_.:\/()]+/),
                      ini: initialsOf(o.name), kf: kf, kwords: kf.split(/\s+/), df: m ? fold(m.d) : "",
                      cat: m ? m.c : "other", src: m ? m.src : "", ti: m && m.ti ? m.ti : "", obj: o };
            list.push(e);
            map[id] = e;
            cnt.all++;
            cnt[e.cat] = (cnt[e.cat] || 0) + 1;
        }
        entries = list;
        byId = map;
        rowIds = rows;
        idByName = names;
        counts = cnt;
        revision++;
    }

    function entry(id) { return byId[sid(id)] || null; }
    function category(id) { var e = entry(id); return e ? e.cat : "other"; }
    function iconFor(id) { var e = entry(id); return e && e.ti ? e.ti : (e && e.obj ? e.obj.model.decoration : "application-x-executable"); }
    // Material You name for apps whose .desktop points at a picture file ("" when the theme handles it already)
    function themedIconFor(id) { var e = entry(id); return e && e.ti ? e.ti : ""; }
    function nameFor(id) { var e = entry(id); return e ? e.name : ""; }
    function isNew(id) { var e = entry(id); return Boolean(e && e.obj && e.obj.isNew); }
    function actionsFor(id) { var e = entry(id); return e && e.obj && e.obj.model.actionList ? e.obj.model.actionList : []; }
    function trigger(id, actionId, arg) {
        var e = entry(id);
        if (!e || !appsModel) return false;
        return appsModel.trigger(e.row, actionId || "", arg === undefined ? null : arg);
    }
    function launch(id) { return trigger(id, "", null); }

    // ───────────── typo-tolerant search ─────────────
    // optimal string alignment distance with an early exit above `max`
    function dist(a, b, max) {
        if (Math.abs(a.length - b.length) > max) return max + 1;
        var prev2 = [], prev = [], cur = [];
        for (var j = 0; j <= b.length; j++) prev[j] = j;
        for (var i = 1; i <= a.length; i++) {
            cur = [i];
            var best = i;
            for (j = 1; j <= b.length; j++) {
                var cost = a[i - 1] === b[j - 1] ? 0 : 1;
                var v = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost);
                if (i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1]) v = Math.min(v, prev2[j - 2] + 1);
                cur[j] = v;
                if (v < best) best = v;
            }
            if (best > max) return max + 1;
            prev2 = prev; prev = cur;
        }
        return prev[b.length];
    }
    function subseq(q, s) {
        var p = 0;
        for (var i = 0; i < s.length && p < q.length; i++) if (s[i] === q[p]) p++;
        return p === q.length;
    }
    function scoreToken(e, q) {
        var n = e.key, i;
        if (n === q) return 1000;
        if (n.indexOf(q) === 0) return 900 - n.length * 0.2;
        for (i = 1; i < e.words.length; i++) if (e.words[i].indexOf(q) === 0) return 820;
        if (q.length >= 2 && e.ini.indexOf(q) === 0) return 780;
        var at = n.indexOf(q);
        if (at > 0) return 700 - at;
        for (i = 0; i < e.kwords.length; i++) if (e.kwords[i].length && e.kwords[i].indexOf(q) === 0) return 620;
        if (q.length >= 3 && e.kf.indexOf(q) !== -1) return 560;
        if (q.length >= 3) {
            var max = q.length >= 7 ? 2 : 1;
            for (i = 0; i < e.words.length; i++) {
                var w = e.words[i];
                if (w.length < q.length - max) continue;
                var d = dist(q, w.substring(0, q.length), max);
                if (d > max) d = dist(q, w, max);
                if (d <= max) return 480 - d * 60;
            }
            for (i = 0; i < e.kwords.length; i++) {
                if (e.kwords[i].length >= q.length && dist(q, e.kwords[i].substring(0, q.length), 1) <= 1) return 380;
            }
        }
        if (q.length >= 2 && subseq(q, n)) return 300 - (n.length - q.length);
        if (q.length >= 4 && e.df.indexOf(q) !== -1) return 200;
        return 0;
    }
    function search(query, limit) {
        var q = fold(query).trim();
        if (!q.length) return [];
        var tokens = q.split(/\s+/);
        var res = [];
        for (var i = 0; i < entries.length; i++) {
            var e = entries[i];
            var s = scoreToken(e, q);
            if (s <= 0 && tokens.length > 1) {
                var sum = 0;
                for (var t = 0; t < tokens.length; t++) {
                    var ts = scoreToken(e, tokens[t]);
                    if (ts <= 0) { sum = 0; break; }
                    sum += ts;
                }
                s = sum / tokens.length * 0.9;
            }
            if (s > 0) res.push({ e: e, s: s });
        }
        res.sort(function (a, b) { return b.s - a.s || a.e.name.localeCompare(b.e.name); });
        var out = [];
        for (i = 0; i < res.length && i < (limit || 8); i++) out.push(res[i].e);
        return out;
    }

    // ───────────── folders (Plasmoid.configuration.launcherFolders, JSON) ─────────────
    function loadFolders() {
        var list = [];
        try { list = JSON.parse(Plasmoid.configuration.launcherFolders || "[]"); } catch (e) { list = []; }
        applyFolders(Array.isArray(list) ? list : []);
    }
    function applyFolders(list) {
        var map = {};
        for (var i = 0; i < list.length; i++)
            for (var j = 0; j < list[i].apps.length; j++) map[list[i].apps[j]] = list[i].id;
        folders = list;
        folderOfId = map;
        revision++;
    }
    function saveFolders(list) {
        applyFolders(list);
        Plasmoid.configuration.launcherFolders = JSON.stringify(list);
    }
    function cloneFolders() { return JSON.parse(JSON.stringify(folders)); }
    function folderById(fid) {
        for (var i = 0; i < folders.length; i++) if (folders[i].id === fid) return folders[i];
        return null;
    }
    function createFolder(idA, idB) {
        idA = sid(idA); idB = sid(idB);
        if (!idA || !idB || idA === idB) return "";
        var list = cloneFolders();
        for (var i = 0; i < list.length; i++) list[i].apps = list[i].apps.filter(function (a) { return a !== idA && a !== idB; });
        list = list.filter(function (f) { return f.apps.length > 0; });
        var ca = category(idA), cb = category(idB);
        var name = (ca === cb && ca !== "other") ? categoryLabel(ca) : i18n("Folder");
        var fid = "f" + Date.now();
        list.push({ id: fid, name: name, apps: [idB, idA] });
        saveFolders(list);
        return fid;
    }
    function addToFolder(fid, id) {
        id = sid(id);
        var list = cloneFolders();
        for (var i = 0; i < list.length; i++) {
            list[i].apps = list[i].apps.filter(function (a) { return a !== id; });
            if (list[i].id === fid) list[i].apps.push(id);
        }
        saveFolders(list.filter(function (f) { return f.apps.length > 0; }));
    }
    function addToNewFolder(id) {
        id = sid(id);
        var list = cloneFolders();
        for (var i = 0; i < list.length; i++) list[i].apps = list[i].apps.filter(function (a) { return a !== id; });
        var c = category(id);
        var fid = "f" + Date.now();
        list = list.filter(function (f) { return f.apps.length > 0; });
        list.push({ id: fid, name: c !== "other" ? categoryLabel(c) : i18n("Folder"), apps: [id] });
        saveFolders(list);
        return fid;
    }
    function deleteFolder(fid) {
        saveFolders(cloneFolders().filter(function (f) { return f.id !== fid; }));
    }
    function removeFromFolder(fid, id) {
        id = sid(id);
        var list = cloneFolders();
        for (var i = 0; i < list.length; i++)
            if (list[i].id === fid) list[i].apps = list[i].apps.filter(function (a) { return a !== id; });
        // a folder with a single app dissolves (Android behaviour)
        saveFolders(list.filter(function (f) { return f.apps.length > 1; }));
    }
    function renameFolder(fid, name) {
        var list = cloneFolders();
        for (var i = 0; i < list.length; i++) if (list[i].id === fid) list[i].name = String(name).trim() || list[i].name;
        saveFolders(list);
    }
    function moveInFolder(fid, from, to) {
        var list = cloneFolders();
        for (var i = 0; i < list.length; i++) {
            if (list[i].id !== fid) continue;
            var a = list[i].apps;
            if (from < 0 || from >= a.length || to < 0 || to >= a.length) return;
            a.splice(to, 0, a.splice(from, 1)[0]);
        }
        saveFolders(list);
    }

    Connections {
        target: Plasmoid.configuration
        function onLauncherFoldersChanged() {
            if (JSON.stringify(idx.folders) !== (Plasmoid.configuration.launcherFolders || "[]")) idx.loadFolders();
        }
    }

    // ───────────── helper process (index on load and when the app list changes) ─────────────
    Plasma5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        property var callbacks: ({})
        onNewData: (src, data) => {
            disconnectSource(src);
            var cb = callbacks[src];
            delete callbacks[src];
            if (cb) cb(data["stdout"] || "", data["exit code"]);
        }
    }
    function run(args, cb) {
        var src = "python3 " + shq(helper) + " " + args + " # " + Date.now() + Math.random();
        if (cb) exec.callbacks[src] = cb;
        exec.connectSource(src);
    }
    function sh(cmd, cb) {
        var src = cmd + " # " + Date.now() + Math.random();
        if (cb) exec.callbacks[src] = cb;
        exec.connectSource(src);
    }
    function reloadMeta() {
        run("index", function (out) {
            try { idx.meta = JSON.parse(out).apps || {}; } catch (e) { return; }
            idx.build();
        });
    }
    Timer { id: metaDebounce; interval: 800; onTriggered: idx.reloadMeta() }
    onAppsModelChanged: metaDebounce.restart()

    function loadPalette() {
        sh("cat \"$HOME/.config/doodlebookos/palette.json\"", function (out) {
            try {
                var p = JSON.parse(out);
                idx.hasIconColors = !!(p.enabled && p.iconBg && p.iconFg);
                if (idx.hasIconColors) { idx.iconBg = p.iconBg; idx.iconFg = p.iconFg; }
                if (p.enabled && p.tertiary) { idx.tertiary = p.tertiary; idx.onTertiary = p.onTertiary; return; }
            } catch (e) { idx.hasIconColors = false; }
            idx.tertiary = Kirigami.Theme.highlightColor;
            idx.onTertiary = Kirigami.Theme.highlightedTextColor;
        });
    }
    function loadShape() {
        sh("cat \"$HOME/.config/doodlebookos/shape.json\"", function (out) {
            try {
                var d = JSON.parse(out);
                idx.shapes = d.shapes || [];
                idx.shapePath = d.path || "";
                idx.shapeTurn = d.turn || 0;
                idx.shapeName = d.name || "circle";
            } catch (e) {
                idx.shapeName = "circle";
            }
        });
    }
    function setShape(name) {
        idx.shapeName = name;                       // the buttons follow at once
        for (var i = 0; i < idx.shapes.length; ++i) {
            if (idx.shapes[i].name === name) { idx.shapePath = idx.shapes[i].path; idx.shapeTurn = idx.shapes[i].turn || 0; }
        }
        shapeApply.restart();                       // icons rebuilt once the user stops clicking
    }
    Timer {
        id: shapeApply
        interval: 700
        onTriggered: idx.sh("doodlebookos-icons shape " + idx.shapeName, function () { idx.loadShape(); idx.refreshIcons(); })
    }
    // Kirigami.Icon keeps the pixmap it drew from a QIcon until its source changes: after the icon theme
    // is rebuilt (new shape, new wallpaper colours) blank the sources for one tick so every icon reloads.
    property bool iconsBlank: false
    function refreshIcons() { iconsBlank = true; iconsUnblank.restart(); }
    Timer { id: iconsUnblank; interval: 16; onTriggered: idx.iconsBlank = false }
    Timer { id: iconsAfterTheme; interval: 1500; onTriggered: idx.refreshIcons() }
    // any icon theme change (dock picker, doodlebookos-icons in a terminal, System Settings) ends with
    // KIconLoader's iconChanged broadcast: one idle dbus-monitor waits for it, no polling
    function watchIcons() {
        sh("dbus-monitor --session \"type='signal',path='/KIconLoader',interface='org.kde.KIconLoader',member='iconChanged'\" | grep -m1 -q 'member=iconChanged'",
           function (out, code) {
               if (code !== 0) return;            // no session bus / dbus-monitor: stay quiet, never spin
               iconsSettle.restart();
               idx.watchIcons();
           });
    }
    Timer { id: iconsSettle; interval: 400; onTriggered: { idx.loadPalette(); idx.loadShape(); idx.refreshIcons(); } }
    Connections {
        target: Kirigami.Theme
        function onHighlightColorChanged() { idx.loadPalette(); idx.loadShape(); iconsAfterTheme.restart(); }
    }

    // ───────────── notification badges (apps with notifications in the history) ─────────────
    NotificationManager.Notifications {
        id: notifModel
        showExpired: true
        showDismissed: true
        showJobs: false
        showNotifications: true
    }
    Instantiator {
        id: notifMirror
        model: notifModel
        delegate: QtObject {
            required property var model
            readonly property string de: model.desktopEntry ? String(model.desktopEntry) : ""
        }
        onObjectAdded: badgeRebuild.restart()
        onObjectRemoved: badgeRebuild.restart()
    }
    Timer {
        id: badgeRebuild
        interval: 120
        onTriggered: {
            var b = {};
            for (var i = 0; i < notifMirror.count; i++) {
                var o = notifMirror.objectAt(i);
                if (o && o.de) { var id = idx.sid(o.de); b[id] = (b[id] || 0) + 1; }
            }
            idx.badges = b;
        }
    }
    function badgeFor(id) { return badges[sid(id)] || 0; }

    Component.onCompleted: {
        loadFolders();
        loadPalette();
        loadShape();
        watchIcons();
    }
}

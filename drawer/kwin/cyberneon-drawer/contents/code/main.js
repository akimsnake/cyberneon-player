// CyberNeon Drawer, KWin side: reports "desktop mode" to the drawer program over D-Bus.
// desktop mode = Show Desktop is on, or there is no open (not minimized) normal window on the current virtual desktop.
// (The drawer itself is made of layer-shell surfaces, so KWin needs no help to show it.)

function log(msg) {
    try { console.warn(msg); } catch (e) { print(msg); }
}

var last = null;

function onThisDesktop(w) {
    if (w.onAllDesktops) return true;
    try {
        var d = w.desktops;
        for (var i = 0; i < d.length; i++) if (d[i] === workspace.currentDesktop) return true;
    } catch (e) { return true; }
    return false;
}

function isAppWindow(w) {
    if (!w || !w.normalWindow || w.minimized) return false;
    var c = String(w.resourceClass || "").toLowerCase();
    if (c.indexOf("cyberneon-drawer") >= 0 || c.indexOf("plasmashell") >= 0) return false;
    return onThisDesktop(w);
}

function compute() {
    var showing = false;
    try { showing = workspace.showingDesktop === true; } catch (e) { }
    if (showing) return true;
    var list = workspace.windowList();
    for (var i = 0; i < list.length; i++) {
        if (isAppWindow(list[i])) return false;
    }
    return true;
}

function report(force) {
    var now = compute();
    if (!force && now === last) return;
    last = now;
    log("cyberneon-drawer: desktop mode " + now);
    callDBus("org.cyberneon.Drawer", "/Drawer", "org.cyberneon.Drawer", "setDesktopMode", now);
}

function watch(w) {
    try { w.minimizedChanged.connect(function () { report(false); }); } catch (e) { }
    try { w.desktopsChanged.connect(function () { report(false); }); } catch (e) { }
}

workspace.windowAdded.connect(function (w) { watch(w); report(true); });     // also tells a freshly started drawer
workspace.windowRemoved.connect(function () { report(false); });
try { workspace.currentDesktopChanged.connect(function () { report(false); }); } catch (e) { }
try { workspace.showingDesktopChanged.connect(function () { report(false); }); } catch (e) { }

var existing = workspace.windowList();
for (var i = 0; i < existing.length; i++) watch(existing[i]);
log("cyberneon-drawer: desktop watcher loaded");
report(true);

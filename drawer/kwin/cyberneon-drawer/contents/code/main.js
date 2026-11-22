// CyberNeon Drawer, KWin side:
//  - keeps the drawer window where it belongs (left edge, full height, above everything, not in the taskbar)
//  - reacts to the pointer pushing against the left screen edge: shows the drawer window
// The drawer program itself plays the slide animation and hides (minimizes) the window again.

var CLASS = "cyberneon-drawer";
print("cyberneon-drawer: script loaded");
var WIDTH = 380;                       // must match the width in Drawer.qml

function isDrawer(w) {
    if (!w) return false;
    var a = String(w.resourceClass || "").toLowerCase();
    var b = String(w.desktopFileName || "").toLowerCase();
    return a.indexOf(CLASS) >= 0 || b.indexOf(CLASS) >= 0;
}

function findDrawer() {
    var list = workspace.windowList();
    for (var i = 0; i < list.length; i++) {
        if (isDrawer(list[i])) return list[i];
    }
    return null;
}

function set(w, name, value) {
    try { w[name] = value; } catch (e) { }
}

function place(w) {
    var out = null;
    try { out = workspace.screenAt(workspace.cursorPos); } catch (e) { }
    if (!out) out = workspace.activeScreen;
    var area = workspace.clientArea(KWin.MaximizeArea, out, workspace.currentDesktop);   // without panels
    w.frameGeometry = Qt.rect(area.x, area.y, WIDTH, area.height);
}

function setup(w) {
    if (!isDrawer(w)) return;
    print("cyberneon-drawer: found window " + w.resourceClass + " / " + w.desktopFileName);
    set(w, "skipTaskbar", true);
    set(w, "skipPager", true);
    set(w, "skipSwitcher", true);
    set(w, "keepAbove", true);
    set(w, "noBorder", true);
    set(w, "onAllDesktops", true);
    place(w);
    w.minimized = true;                // starts hidden; the edge brings it out
}

function showDrawer() {
    print("cyberneon-drawer: left edge triggered");
    var w = findDrawer();
    if (!w) { print("cyberneon-drawer: no drawer window found"); return; }
    place(w);
    w.minimized = false;
    workspace.activeWindow = w;
}

workspace.windowAdded.connect(setup);
var existing = workspace.windowList();
for (var i = 0; i < existing.length; i++) setup(existing[i]);

var LEFT = (typeof KWin !== "undefined" && KWin.ElectricLeft !== undefined) ? KWin.ElectricLeft : 6;
var ok = registerScreenEdge(LEFT, showDrawer);
print("cyberneon-drawer: edge " + LEFT + " registered: " + ok);

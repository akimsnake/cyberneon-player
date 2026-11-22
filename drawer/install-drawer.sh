#!/usr/bin/env bash
# Installs the CyberNeon Drawer: a neon panel that slides out from the left screen edge (Wayland, KDE Plasma).
#   install:  bash drawer/install-drawer.sh
#   remove:   bash drawer/install-drawer.sh remove
set -e
SRC="$(cd "$(dirname "$0")" && pwd)"
AUTOSTART="$HOME/.config/autostart/cyberneon-drawer.desktop"
APPS="$HOME/.local/share/applications/cyberneon-drawer.desktop"

kwin_call() {
  for q in qdbus6 qdbus-qt6 qdbus; do
    if command -v "$q" >/dev/null 2>&1; then "$q" org.kde.KWin "$@" >/dev/null 2>&1 && return 0; fi
  done
  return 1
}

KWIN_PKG="$SRC/kwin/cyberneon-drawer"

# the KWin script only reports "desktop is free / windows are open" to the drawer
remove_old_script() {
  kwin_call /Scripting org.kde.kwin.Scripting.unloadScript cyberneon-drawer || true
  kwriteconfig6 --file kwinrc --group Plugins --key cyberneon-drawerEnabled false 2>/dev/null || true
  kpackagetool6 --type=KWin/Script --remove cyberneon-drawer >/dev/null 2>&1 || true
  kwin_call /KWin reconfigure || true
}

if [ "${1:-}" = "remove" ]; then
  pkill -f "drawer/drawer.py" 2>/dev/null || true
  remove_old_script
  rm -f "$AUTOSTART" "$APPS" "$HOME/.local/bin/cyberneon-drawer"
  echo "Drawer removed."
  exit 0
fi

if [ ! -d /usr/lib/qt6/qml/org/kde/layershell ] && [ ! -d /usr/lib64/qt6/qml/org/kde/layershell ]; then
  echo "Missing: layer-shell-qt.   sudo pacman -S layer-shell-qt"
  exit 1
fi
if [ "${XDG_SESSION_TYPE:-}" != "wayland" ]; then
  echo "Note: this drawer needs a Wayland session (yours: ${XDG_SESSION_TYPE:-unknown})."
fi

mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications" "$HOME/.config/autostart"

# KWin keeps a loaded script in memory: unload, replace the files, switch off and on
remove_old_script
kpackagetool6 --type=KWin/Script --install "$KWIN_PKG" >/dev/null
kwriteconfig6 --file kwinrc --group Plugins --key cyberneon-drawerEnabled true
kwin_call /KWin reconfigure || true

cat > "$HOME/.local/bin/cyberneon-drawer" << LAUNCH
#!/usr/bin/env bash
exec python3 "$SRC/drawer.py" "\$@"
LAUNCH
chmod 755 "$HOME/.local/bin/cyberneon-drawer"

cat > "$APPS" << DESKTOP
[Desktop Entry]
Type=Application
Name=CyberNeon Drawer
Exec=$HOME/.local/bin/cyberneon-drawer
Icon=cyberneon-player
Terminal=false
NoDisplay=true
StartupWMClass=cyberneon-drawer
DESKTOP

cat > "$AUTOSTART" << DESKTOP
[Desktop Entry]
Type=Application
Name=CyberNeon Drawer
Exec=$HOME/.local/bin/cyberneon-drawer
Terminal=false
X-KDE-autostart-after=panel
DESKTOP

# (re)start the drawer
pkill -f "drawer/drawer.py" 2>/dev/null || true
sleep 0.5
nohup "$HOME/.local/bin/cyberneon-drawer" >/tmp/cyberneon-drawer.log 2>&1 &
sleep 1.5
if pgrep -f "drawer/drawer.py" >/dev/null; then
  echo "Installed and running. Push the mouse against the LEFT edge of the screen."
else
  echo "The drawer did not start. Log:"; cat /tmp/cyberneon-drawer.log
fi
echo "  launcher buttons:  ~/.config/cyberneon-drawer/launchers.json   (edit, then run this script again)"
echo "  notes:             ~/.local/share/cyberneon-drawer/notes.txt"
echo "  remove:            bash $0 remove"

#!/usr/bin/env bash
# Installs the CyberNeon Drawer (slides out from the left screen edge) and its KWin script.
#   install:  bash drawer/install-drawer.sh
#   remove:   bash drawer/install-drawer.sh remove
set -e
SRC="$(cd "$(dirname "$0")" && pwd)"
KWIN_PKG="$SRC/kwin/cyberneon-drawer"
AUTOSTART="$HOME/.config/autostart/cyberneon-drawer.desktop"
APPS="$HOME/.local/share/applications/cyberneon-drawer.desktop"

reconfigure() {
  for q in qdbus6 qdbus-qt6 qdbus; do
    if command -v "$q" >/dev/null 2>&1; then "$q" org.kde.KWin /KWin reconfigure >/dev/null 2>&1 && return 0; fi
  done
  dbus-send --session --dest=org.kde.KWin /KWin org.kde.KWin.reconfigure >/dev/null 2>&1 || true
}

if [ "${1:-}" = "remove" ]; then
  pkill -f "drawer/drawer.py" 2>/dev/null || true
  kwriteconfig6 --file kwinrc --group Plugins --key cyberneon-drawerEnabled false
  kpackagetool6 --type=KWin/Script --remove cyberneon-drawer >/dev/null 2>&1 || true
  rm -f "$AUTOSTART" "$APPS" "$HOME/.local/bin/cyberneon-drawer"
  reconfigure
  echo "Drawer removed."
  exit 0
fi

mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications" "$HOME/.config/autostart"

# launcher
cat > "$HOME/.local/bin/cyberneon-drawer" << LAUNCH
#!/usr/bin/env bash
exec python3 "$SRC/drawer.py" "\$@"
LAUNCH
chmod 755 "$HOME/.local/bin/cyberneon-drawer"

# desktop file: lets Wayland match the window to the app; hidden from the menu
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

# start at login
cat > "$AUTOSTART" << DESKTOP
[Desktop Entry]
Type=Application
Name=CyberNeon Drawer
Exec=$HOME/.local/bin/cyberneon-drawer
Terminal=false
X-KDE-autostart-after=panel
DESKTOP

# KWin script (it moves the window and listens to the screen edge)
kpackagetool6 --type=KWin/Script --upgrade "$KWIN_PKG" >/dev/null 2>&1 || kpackagetool6 --type=KWin/Script --install "$KWIN_PKG"
kwriteconfig6 --file kwinrc --group Plugins --key cyberneon-drawerEnabled true
reconfigure

# (re)start the drawer
pkill -f "drawer/drawer.py" 2>/dev/null || true
nohup "$HOME/.local/bin/cyberneon-drawer" >/dev/null 2>&1 &

echo "Installed. Push the mouse against the LEFT edge of the screen."
echo "  widgets list:  ~/.config/cyberneon-drawer/launchers.json   (edit, then restart: bash $0)"
echo "  notes:         ~/.local/share/cyberneon-drawer/notes.txt"
echo "If nothing happens: System Settings > Workspace Behavior > Screen Edges, set the left edge to 'No Action'"
echo "(the drawer script uses that edge), and check Window Management > KWin Scripts that CyberNeon Drawer is ticked."
echo "Remove everything:  bash $0 remove"

#!/usr/bin/env bash
# Installs the CyberNeon Player widget, the control tool and an app-menu launcher.
# Run: bash ~/cyberneon-player/install-widget.sh
set -e
SRC="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$HOME/.local/share/plasma/plasmoids" "$HOME/.local/bin" "$HOME/.local/share/applications" \
         "$HOME/.local/share/icons/hicolor/scalable/apps"

# app icon (used by the menu, the panel and the task manager)
cp "$SRC/cyberneon-player.svg" "$HOME/.local/share/icons/hicolor/scalable/apps/cyberneon-player.svg"

# widget
rm -rf "$HOME/.local/share/plasma/plasmoids/org.cyberneon.player"
cp -r "$SRC/widget/org.cyberneon.player" "$HOME/.local/share/plasma/plasmoids/"

# control tool used by the widget
install -m 755 "$SRC/cyberneon-ctl" "$HOME/.local/bin/cyberneon-ctl"

# launcher (starts the player from wherever it is installed)
cat > "$HOME/.local/bin/cyberneon-player" << LAUNCH
#!/usr/bin/env bash
exec python3 "$SRC/main.py" "\$@"
LAUNCH
chmod 755 "$HOME/.local/bin/cyberneon-player"

# app menu entry
cat > "$HOME/.local/share/applications/cyberneon-player.desktop" << DESKTOP
[Desktop Entry]
Type=Application
Name=CyberNeon Player
Comment=Neon cyberpunk music player
Exec=$HOME/.local/bin/cyberneon-player
Icon=cyberneon-player
Categories=AudioVideo;Audio;Player;
Terminal=false
StartupNotify=false
StartupWMClass=cyberneon-player
DESKTOP

# let KDE notice the new launcher / icon right away
kbuildsycoca6 >/dev/null 2>&1 || true
gtk-update-icon-cache -q "$HOME/.local/share/icons/hicolor" >/dev/null 2>&1 || true

echo "Installed:"
echo "  widget   -> ~/.local/share/plasma/plasmoids/org.cyberneon.player"
echo "  tools    -> ~/.local/bin/cyberneon-ctl, ~/.local/bin/cyberneon-player"
echo "  launcher -> app menu: CyberNeon Player"
echo
echo "Now: right-click desktop or panel -> Add Widgets -> 'CyberNeon Player'."
echo "If it is not listed, restart the shell:  kquitapp6 plasmashell; kstart plasmashell"

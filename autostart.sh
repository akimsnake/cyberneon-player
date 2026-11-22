#!/usr/bin/env bash
# Start CyberNeon Player in the background (tray icon, no window) at every login.
#   enable:   bash ~/cyberneon-player/autostart.sh on
#   disable:  bash ~/cyberneon-player/autostart.sh off
set -e
FILE="$HOME/.config/autostart/cyberneon-player.desktop"
case "${1:-on}" in
  on)
    mkdir -p "$HOME/.config/autostart"
    cat > "$FILE" << DESKTOP
[Desktop Entry]
Type=Application
Name=CyberNeon Player (background)
Exec=$HOME/.local/bin/cyberneon-player --background
Icon=cyberneon-player
Terminal=false
X-KDE-autostart-after=panel
DESKTOP
    echo "Autostart enabled: $FILE" ;;
  off)
    rm -f "$FILE"
    echo "Autostart disabled" ;;
  *) echo "usage: autostart.sh on|off"; exit 1 ;;
esac

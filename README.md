# CyberNeon Player

A neon cyberpunk music player for your own music files: black and purple, translucent, with a live audio
visualizer, albums you build yourself, and a matching KDE Plasma widget.

Built with Python, PySide6 and QML. Runs on Linux (KDE Plasma recommended) and Windows.

<!-- Add screenshots here: ![player](docs/screenshot-player.png) ![gallery](docs/screenshot-gallery.png) -->

## Features

- **Your albums, your way**: make albums, drag songs in, set the song order by dragging or typing a number,
  pick a cover, edit title, artist and year. Your music files are never modified.
- **Gallery and album page**: cover grid with 3D hover tilt, and a full album page with a glowing cover and a
  background of slowly moving colours taken from the cover.
- **Neon visualizer**: live spectrum bars from the real audio, with a smooth animated fallback.
- **Drag and drop**: drop songs, folders or `.cue` files into the window.
- **Remembers where you stopped**: song, queue and second, restored on the next start.
- **M3U import and export** for playlists.
- **"Now playing" notification** with cover art for every new song (can be switched off).
- **Audio CD images**: `.cue` sheets (with `.wav`, `.flac`, `.ape`, `.wv`) show up as albums; raw `.bin` is converted once with ffmpeg.
- **Formats**: mp3, m4a (AAC), flac, ogg, opus, wav, ape, wv.
- **Tray and background mode**: closing the window keeps the music playing.
- **Plasma widget** (Linux): the same neon bars, cover, progress and controls on your desktop or panel.

## Install

### Windows

Download `CyberNeonPlayer-Setup.exe` from the latest successful run of the
[build-windows](../../actions/workflows/build-windows.yml) workflow (Actions tab, artifact `CyberNeonPlayer-Setup`)
and run it. No admin rights needed. Windows may show a SmartScreen warning because the installer is not code-signed:
choose *More info, Run anyway*.

### Linux (Arch / CachyOS)

```bash
sudo pacman -S pyside6 qt6-multimedia-ffmpeg python-mutagen python-numpy
git clone https://github.com/akimsnake/cyberneon-player.git
cd cyberneon-player
python3 main.py
```

Optional: `sudo pacman -S ffmpeg` for raw `.bin` disc images.
Install the app-menu launcher and the Plasma widget:

```bash
bash install-widget.sh
```

Then right-click the desktop or panel, *Add Widgets*, *CyberNeon Player*.
Start in the tray at login: `bash autostart.sh on`.

Other distributions: install PySide6 (Qt 6.5+, 6.8+ for the live visualizer), mutagen and numpy with pip.

## Use

Put your music in `~/Music` (Windows: `Music`) or press **FOLDER**. `Space` plays and pauses.
Make an album with **NEW ALBUM**, then add songs with **+ FILES**, the **+** button on a song, or by dragging
files into the window. The full guide is in [docs/USER-GUIDE.md](docs/USER-GUIDE.md).

## Build the Windows installer yourself

On a Windows PC with Python, double-click `windows\build-windows.bat` (add Inno Setup for the installer:
`winget install JRSoftware.InnoSetup`). Or let GitHub build it: the workflow in `.github/workflows/build-windows.yml`
runs on every push and can be started by hand from the Actions tab.

## Project layout

| Path | What it is |
| --- | --- |
| `main.py` | Backend: playback, library, queue, tray, notifications, widget feed |
| `library.py` | Pure logic: tags, albums, cue sheets, M3U, user data |
| `viz.py` | Spectrum analysis for the visualizer |
| `Main.qml`, `Neon*.qml`, `Blob.qml` | The interface |
| `widget/` | Plasma 6 widget |
| `windows/` | Windows build kit and installer script |

## Notes

Albums, edits and covers are stored next to the app data (`~/.local/share/cyberneon-player` on Linux,
`%LOCALAPPDATA%\CyberNeonPlayer` on Windows). Deleting an album or hiding a song only affects the player,
never the music files.

## License

No license file yet. Add one (for example MIT) if you want others to reuse the code.

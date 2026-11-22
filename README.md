# CyberNeon Player

Dependencies (CachyOS / Arch):

    sudo pacman -S pyside6 qt6-multimedia-ffmpeg python-mutagen python-numpy

Run:

    python3 main.py

Put your music in ~/Music, or press FOLDER to choose another folder.
Space = play/pause. Double-click an album or a track to play.

## Widget

    bash ~/cyberneon-player/install-widget.sh

Then: right-click desktop or panel -> Add Widgets -> "CyberNeon Player".
The widget talks to the player through ~/.cache/cyberneon-player/state.json
and the socket $XDG_RUNTIME_DIR/cyberneon-player.sock (tool: cyberneon-ctl).

## Background mode

Closing the window keeps the music playing (tray icon: click = show/hide, right click = menu).
Start hidden:  cyberneon-player --background
Autostart at login:  bash ~/cyberneon-player/autostart.sh on   (off to disable)
Clicking the cover in the widget opens the player window.

## Your own albums

NEW ALBUM (header) creates an album marked with a star. In it:
- "+" on any song adds that song to one of your albums; "+ FILES" adds files from anywhere
- click a track number to move the song to that position (the others shift)
- COVER picks a picture (copied to ~/.local/share/cyberneon-player/covers/)
- EDIT renames, DELETE removes the album (songs on disk are never touched or deleted)
Albums are stored in ~/.local/share/cyberneon-player/albums.json

## Visualizer

40 neon bars under the song list. "LIVE" = analysis of the real audio (needs python-numpy and Qt 6.8+),
"SIM" = simulated animation (used when live data is not available). VIZ in the header hides it.
It only runs while the window is visible, so it costs nothing in the tray.

## Editing songs and albums

ED on a song changes its title/artist, EDIT on an album changes its name/artist.
The edits are saved in ~/.local/share/cyberneon-player/albums.json and apply inside the player only;
music files are never modified. Empty field = original tag.

## Formats

mp3, m4a (AAC), flac, ogg, opus, wav.

## Pinning to the panel

Pin the player from the app menu (CyberNeon Player) or from its running window.
If an old grey entry exists, unpin it first, then run install-widget.sh again.

## Gallery

Tabs LIST / GALLERY under the header. GALLERY shows all albums as a grid of covers with name, artist and year.
Hover = zoom + quick play button; click opens the album with its song list. SIZE slider changes the cover size.

## Widget visualizer

The widget shows the same neon bars. It reads a read-only feed from the player on http://127.0.0.1:47615/state
(local only, ~12 times per second while playing). After updating, run install-widget.sh and restart the shell:
    kquitapp6 plasmashell; kstart plasmashell

## Year and 3D hover

NEW ALBUM / EDIT have a Year field (empty = none; for folder albums empty = original year).
In the gallery, hovering a card tilts it in 3D toward the pointer, with a light spot, parallax on the cover and a neon glow plate.
If the tilt feels inverted, change the signs of tiltY / tiltX in Main.qml (search "tiltY").

## Smooth animations

Buttons fade and press in, and the label cross-fades (> <-> ||). In the widget the bars glide between updates
(feed at 20 Hz while playing), the progress bar glides, and play/pause reacts instantly.
After updating run install-widget.sh and restart the shell: kquitapp6 plasmashell; kstart plasmashell

## Hiding albums, Playlist

Albums from your folder are built from the tags inside the files, so they cannot be "deleted" in the player.
HIDE (album header, or on a gallery card) removes an album from the player; HIDDEN (n) next to LIST/GALLERY restores it.
Files are never touched. Your own albums have DELETE.
Songs without an album tag are collected in one album called "Playlist" with no artist.
In EDIT of a folder album, artist "-" means "no artist". The year is taken from the date tag (20211022 -> 2021).

## Editing every album

All albums (folder albums and your own) can be edited inside the player; files are never touched:
- + FILES adds songs by hand; "+" on a song adds it to any album; x removes a song from the album
- drag a song by its :: handle to reorder (a magenta line shows where it lands), or click its number and type a position
- hovering a button of a song (ED, +, x) lights up the whole row
- "Playlist" = songs without an album tag (and anything tagged "Playlist"): no artist, no year

## Audio CD: .cue images and .cda

- A .cue sheet (with .wav / .flac / .ape / .wv / .mp3 / .m4a image, or one file per track) in your music folder shows up as an album
  with the cue's title, artist, year and track titles. Tracks play inside the image file (no copying); the next track
  continues without a gap. Cue files in UTF-8 and Windows code pages (Cyrillic) are read.
- .bin raw images: converted to FLAC once with ffmpeg (sudo pacman -S ffmpeg), kept in ~/.cache/cyberneon-player/bin,
  then used like any other image. The header shows "Converting disc image ..." meanwhile.
- + FILES also accepts a .cue file (all its tracks are added to the album).
- .cda files are NOT audio (they are 44-byte shortcuts to a track on the disc): they are skipped and the header says so.
  Copy the tracks from the disc as .wav/.flac, or use a .cue image.

## Auto albums

AUTO ALBUMS (next to LIST / GALLERY): OFF (default) = the tags inside your files do not create albums; all songs are in
"Playlist" and you make the albums yourself (NEW ALBUM, + FILES, "+" on a song). Disc images (.cue) keep their own album.
ON = albums are built from the tags again.

HIDDEN (n) opens a large window: RESTORE per album, RESTORE ALL, CLOSE.

## Album page

Click an album in GALLERY: its cover flies from the card to a full album page (BACK or Esc to return):
big cover on the left (neon glow that pulses with the bass, 3D tilt toward the pointer, light spot), blurred cover as a
colourful background, album info + buttons + the song list on the right, visualizer along the bottom.
Everything from the list works there too: drag songs, ED / + / x, EDIT, + FILES, COVER, DELETE / HIDE.
(Blur and glow use QtQuick.Effects, Qt 6.5+.)

The album page background is made of the cover's main colours (picked from the picture) as big soft blobs that drift
slowly and are blurred together; the colours change smoothly when you open another album. The animation stops when
the page is hidden.

## Your Playlist, LIBRARY, album order

- Albums are no longer built from your files by themselves (AUTO ALBUMS is OFF by default). On the first start the player
  creates an EMPTY album "Playlist" (the star marks your own albums). You fill it yourself.
- LIBRARY tab (next to LIST / GALLERY): all songs of the music folder with a search box. "+" puts a song into any of your albums,
  double-click plays. With AUTO ALBUMS ON you can also take songs from the albums made from the tags ("+" on any song).
- Drag albums into your own order: grab the :: handle of an album in LIST, or drag a card in GALLERY. A line / frame shows
  where it lands. SORT switches to MY ORDER by itself (the order is saved); the other sort modes still work.

## New: drag & drop, resume, M3U, "Now playing"

- **Drag & drop**: drag songs, folders (subfolders too) or a .cue file from the file manager into the window.
  They are added to the album that is currently selected (the pink "DROP TO ADD" screen shows which one).
  With no album selected they go into "Playlist".
- **Resume**: on start the player puts back the song, the queue and the second where you stopped (paused; press play).
- **M3U**: `EXPORT M3U` (album header) saves the album as a .m3u8 playlist; `IMPORT M3U` (top bar) turns a
  playlist file into a new album of your own. Relative paths, Windows paths and file:// links work; missing files are skipped.
- **Now playing**: a desktop notification with cover, title, artist and album on every new song.
  The `NOTIFY: ON/OFF` button in the top bar switches it. Nothing pops up on resume.

## Windows installer (for a friend)

The code also runs on Windows. The .exe cannot be built on Linux, so there are two ways:
1. On a Windows PC: double-click `windows\build-windows.bat` (needs Python; for the installer also
   Inno Setup: `winget install JRSoftware.InnoSetup`). Result: `windows\Output\CyberNeonPlayer-Setup.exe`.
2. Without Windows: put this folder on GitHub; `.github/workflows/build-windows.yml` builds the installer in the cloud
   (Actions tab -> artifact "CyberNeonPlayer-Setup").
Windows has no Plasma widget; the player, tray icon, notifications and resume work. Music folder: Music; ffmpeg is only
needed for raw .bin disc images.

#!/usr/bin/env python3
"""CyberNeon Player: neon cyberpunk music player (PySide6 + QML)."""
import collections
import ctypes
import json
import os
import shutil
import sys
import time
from pathlib import Path

from PySide6.QtCore import Property, QObject, QPointF, QProcess, QSettings, QThread, QTimer, QUrl, Qt, Signal, Slot
from PySide6.QtGui import QColor, QIcon, QImage, QPainter, QPen, QPixmap, QPolygonF
from PySide6.QtMultimedia import QAudioOutput, QMediaPlayer
from PySide6.QtNetwork import QHostAddress, QLocalServer, QTcpServer
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickImageProvider
from PySide6.QtQuickControls2 import QQuickStyle
from PySide6.QtWidgets import QApplication, QMenu, QSystemTrayIcon

import library
import viz

IS_WIN = os.name == "nt"
HERE = Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parent))      # _MEIPASS: inside the Windows .exe build
SORTS = ["album", "artist", "year", "manual"]      # manual = your own order (drag albums)
RUNTIME = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp"))
SOCKET = "cyberneon-player" if IS_WIN else str(RUNTIME / "cyberneon-player.sock")   # Windows: a named pipe
HTTP_PORT = 47615                    # read-only state for the widget, 127.0.0.1 only
if IS_WIN:
    _LOCAL = Path(os.environ.get("LOCALAPPDATA", str(Path.home() / "AppData" / "Local"))) / "CyberNeonPlayer"
    CACHE, DATA = _LOCAL / "cache", _LOCAL / "data"
else:
    CACHE = Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache"))) / "cyberneon-player"
    DATA = Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local" / "share"))) / "cyberneon-player"
BIN_CACHE = CACHE / "bin"            # disc images (.bin) converted to FLAC, once
library.BIN_CACHE_DIR = str(BIN_CACHE)
USERFILE = DATA / "albums.json"      # your own albums
COVER_CACHE_MAX = 40                 # decoded covers kept in memory (512x512 each, about 1 MB)
COVERS = DATA / "covers"             # copies of the pictures you chose


class Scanner(QThread):
    done = Signal(list, dict)

    def __init__(self, folder, parent=None):
        super().__init__(parent)
        self._folder = folder

    def run(self):
        info = {}
        tracks = library.scan_folder(self._folder, info, str(BIN_CACHE))
        self.done.emit(tracks, info)


class Backend(QObject):
    albumsChanged = Signal()
    currentChanged = Signal()
    positionChanged = Signal()
    durationChanged = Signal()
    playingChanged = Signal()
    volumeChanged = Signal()
    shuffleChanged = Signal()
    repeatChanged = Signal()
    scanningChanged = Signal()
    folderChanged = Signal()
    sortChanged = Signal()
    noteChanged = Signal()
    autoChanged = Signal()
    notifyChanged = Signal()
    songStarted = Signal(int)          # a new song began playing (global track index)

    def __init__(self):
        super().__init__()
        self.settings = QSettings("CyberNeon", "Player")
        self._folder = str(self.settings.value("folder", str(Path.home() / "Music")))
        self._volume = float(self.settings.value("volume", 0.7))
        self._sort = int(self.settings.value("sort", 0)) % len(SORTS)
        self._shuffle = str(self.settings.value("shuffle", "false")).lower() == "true"
        self._repeat = int(self.settings.value("repeat", 0)) % 3
        self._auto = str(self.settings.value("autoAlbums", "false")).lower() == "true"   # tags make albums by themselves
        self._notify = str(self.settings.value("notify", "true")).lower() == "true"   # "Now playing" pop-up
        self._restored = False
        self._tracks, self._albums = [], []
        self._hidden = {}
        self._all_tag_albums = []
        self._loaded_file = ""              # audio file currently set as the player's source
        self._pending_seek = None           # cue tracks: jump here as soon as the file is loaded
        self._play_after_load = False
        self._cur_start, self._cur_end = 0, None   # range of the current song inside its file (cue images)
        self._last_end = 0.0
        self._note = ""
        self._cda_note = ""
        self._bins, self._conv, self._conv_ok = [], None, False
        self._n_scanned = 0                 # tracks[:n] come from the folder scan, the rest from your albums
        self._user = library.user_load(str(USERFILE))
        if not self._user.get("seeded"):                  # first start: an EMPTY album "Playlist" that you fill yourself
            if not any(a["name"].strip().lower() == "playlist" for a in self._user["albums"]):
                library.user_create(self._user, "Playlist")       # (not if you already made one with that name)
            self._user["seeded"] = True
            try:
                library.user_save(str(USERFILE), self._user)
            except OSError:
                pass
        self._rev = 0
        self._ctx_cover_path = ""           # cover of the album we are playing from (if it has a custom one)
        self._queue = library.PlayQueue()
        self._current = -1
        self._scanning = False
        self._version = 0
        self._cover_cache = {}
        self._palette_cache = {}
        self._scanner = None

        self.audio = QAudioOutput(self)
        self.player = QMediaPlayer(self)
        self.player.setAudioOutput(self.audio)
        self.audio.setVolume(self._volume ** 2)
        self.player.positionChanged.connect(self._on_position)
        self.player.durationChanged.connect(lambda _=0: self.durationChanged.emit())
        self.player.playbackStateChanged.connect(lambda _=0: self.playingChanged.emit())
        self.player.mediaStatusChanged.connect(self._on_status)
        self._state_timer = QTimer(self)                 # remember the place every few seconds while playing
        self._state_timer.setInterval(5000)
        self._state_timer.timeout.connect(self.save_state)
        self._state_timer.start()
        self.player.playbackStateChanged.connect(lambda _=0: self.save_state())

    # ----- properties for QML -----
    @Property("QVariantList", notify=albumsChanged)
    def albums(self):
        return self._albums

    @Property("QVariantList", notify=albumsChanged)
    def hiddenAlbums(self):
        return [{"id": k, "name": v.get("name", k), "artist": v.get("artist", "")} for k, v in self._hidden.items()]

    @Property(int, notify=albumsChanged)
    def rev(self):
        return self._rev

    @Property(int, notify=albumsChanged)
    def version(self):
        return self._version

    @Property(int, notify=albumsChanged)
    def trackCount(self):
        return self._n_scanned

    @Property(int, notify=currentChanged)
    def currentIndex(self):
        return self._current

    def _cur(self, key):
        return self._tracks[self._current][key] if 0 <= self._current < len(self._tracks) else ""

    @Property(str, notify=currentChanged)
    def currentTitle(self):
        return self._cur("title")

    @Property(str, notify=currentChanged)
    def currentArtist(self):
        return self._cur("artist")

    @Property(str, notify=currentChanged)
    def currentAlbum(self):
        return self._cur("album")

    @Property(str, notify=currentChanged)
    def currentCover(self):
        return Path(self._ctx_cover_path).as_uri() if self._ctx_cover_path else ""

    @Property(int, notify=positionChanged)
    def positionMs(self):
        return max(0, int(self.player.position()) - self._cur_start)

    @Property(int, notify=durationChanged)
    def durationMs(self):
        if self._cur_end is not None:
            return max(0, int(self._cur_end - self._cur_start))
        d = int(self.player.duration())
        if d > 0:
            return max(0, d - self._cur_start)
        if 0 <= self._current < len(self._tracks):
            return int(self._tracks[self._current]["length"] * 1000)
        return 0

    @Property(str, notify=noteChanged)
    def note(self):
        return self._note

    @Property(bool, notify=autoChanged)
    def autoAlbums(self):
        return self._auto

    @Property(bool, notify=notifyChanged)
    def notifications(self):
        return self._notify

    @Slot()
    def toggleNotifications(self):
        self._notify = not self._notify
        self.settings.setValue("notify", "true" if self._notify else "false")
        self.notifyChanged.emit()

    @Slot()
    def toggleAutoAlbums(self):
        """ON: the tags inside the files create albums. OFF (default): all songs are in Playlist and you make the albums."""
        self._auto = not self._auto
        self.settings.setValue("autoAlbums", "true" if self._auto else "false")
        self.autoChanged.emit()
        self._refresh_albums()

    @Property(bool, notify=playingChanged)
    def playing(self):
        return self.player.playbackState() == QMediaPlayer.PlaybackState.PlayingState

    def _get_volume(self):
        return self._volume

    def _set_volume(self, v):
        v = max(0.0, min(1.0, float(v)))
        if v != self._volume:
            self._volume = v
            self.audio.setVolume(v * v)       # squared: closer to perceived loudness
            self.settings.setValue("volume", v)
            self.volumeChanged.emit()

    volume = Property(float, _get_volume, _set_volume, notify=volumeChanged)

    @Property(bool, notify=shuffleChanged)
    def shuffle(self):
        return self._shuffle

    @Property(int, notify=repeatChanged)
    def repeatMode(self):
        return self._repeat

    @Property(bool, notify=scanningChanged)
    def scanning(self):
        return self._scanning

    @Property(str, notify=folderChanged)
    def folder(self):
        return self._folder

    @Property(int, notify=sortChanged)
    def sortMode(self):
        return self._sort

    # ----- library -----
    def start(self):
        self.rescan()

    @Slot()
    def rescan(self):
        if self._scanning:
            return
        self._scanning = True
        self.scanningChanged.emit()
        self._scanner = Scanner(self._folder, self)
        self._scanner.done.connect(self._on_scanned)
        self._scanner.start()

    def _set_note(self, text):
        if text != self._note:
            self._note = text
            self.noteChanged.emit()

    def _after_scan(self, info):
        self._cda_note = ""
        if info.get("cda"):
            self._cda_note = ("%d .cda files skipped: .cda is only a shortcut to a CD track, not audio. "
                              "Copy the tracks from the disc as .wav/.flac, or use a .cue image." % info["cda"])
        self._set_note(self._cda_note)
        self._bins.extend(b for b in info.get("bins", []) if b not in self._bins)
        self._convert_next()

    def _convert_next(self):
        """Raw disc images (.bin) are converted to FLAC once (needs ffmpeg), then played like any other file."""
        if self._conv is not None or not self._bins:
            return
        src = self._bins.pop(0)
        if not shutil.which("ffmpeg"):
            self._bins.clear()
            self._set_note("Disc image %s needs ffmpeg: sudo pacman -S ffmpeg" % os.path.basename(src))
            return
        out = library.bin_cache_path(src, str(BIN_CACHE))
        os.makedirs(str(BIN_CACHE), exist_ok=True)
        tmp = out + ".part"
        proc = QProcess(self)
        self._conv = proc
        proc.finished.connect(lambda code, _status, s=src, t=tmp, o=out: self._on_converted(code, s, t, o))
        proc.start("ffmpeg", ["-y", "-v", "error", "-f", "s16le", "-ar", "44100", "-ac", "2", "-i", src, "-f", "flac", tmp])
        self._set_note("Converting disc image %s (first time only)..." % os.path.basename(src))

    def _on_converted(self, code, src, tmp, out):
        self._conv = None
        if code == 0 and os.path.isfile(tmp):
            os.replace(tmp, out)
            self._conv_ok = True
        else:
            try:
                os.remove(tmp)
            except OSError:
                pass
            self._set_note("Could not convert %s (is it a raw audio CD image?)" % os.path.basename(src))
        if self._bins:
            self._convert_next()
        elif self._conv_ok:
            self._conv_ok = False
            self._set_note(self._cda_note)
            self.rescan()

    def _on_scanned(self, tracks, info=None):
        self._tracks = tracks
        self._n_scanned = len(tracks)
        self._cover_cache.clear()
        self._version += 1
        self._scanning = False
        self.scanningChanged.emit()
        self._refresh_albums()
        self._restore_state()
        self._after_scan(info or {})

    def _refresh_albums(self):
        """Folder albums (from tags) + your own albums, sorted together.
        Your edits (titles, artists, album names) are applied on top of the file tags."""
        library.ensure_tracks(self._tracks, self._user)          # files of your albums that live outside the folder
        library.apply_overrides(self._tracks, self._user.get("tracks_meta", {}))
        tag_albums = library.build_albums(self._tracks[:self._n_scanned], "album", self._auto)
        overrides = self._user.get("tag_albums", {})
        by_path = {t["path"]: i for i, t in enumerate(self._tracks)}
        for a in tag_albums:
            o = overrides.get(a["id"])
            if o:
                a["name"] = o.get("name") or a["name"]
                if o.get("artist") == "-":
                    a["artist"] = ""                    # "-" means: show no artist
                else:
                    a["artist"] = o.get("artist") or a["artist"]
                a["year"] = o.get("year") or a["year"]
                library.apply_album_edits(a, o, self._tracks, by_path)
        self._hidden = self._user.get("hidden_albums", {})
        self._all_tag_albums = tag_albums
        tag_albums = library.filter_hidden(tag_albums, self._hidden)
        mine = library.merge_user(self._tracks, self._user)
        self._albums = library.sort_albums(tag_albums + mine, SORTS[self._sort], self._user.get("album_order"))
        self._rev += 1
        self.albumsChanged.emit()

    @Slot(str)
    def setFolder(self, url):
        path = QUrl(url).toLocalFile() if url.startswith("file:") else url
        if not path or not os.path.isdir(path):
            return
        self.player.stop()
        self._queue = library.PlayQueue()
        self._current = -1
        self.currentChanged.emit()
        self._folder = path
        self.settings.setValue("folder", path)
        self.folderChanged.emit()
        self.rescan()

    @Slot()
    def toggleSort(self):
        self._sort = (self._sort + 1) % len(SORTS)
        self.settings.setValue("sort", self._sort)
        self.sortChanged.emit()
        self._refresh_albums()

    # ----- your own albums -----
    @staticmethod
    def _hex(aid):
        return aid[2:] if aid.startswith("u:") else aid

    def _user_changed(self):
        library.user_save(str(USERFILE), self._user)
        self._refresh_albums()

    @Slot(str, str, int, result=str)
    def createAlbum(self, name, artist, year):
        aid = library.user_create(self._user, name.strip() or "New album", artist.strip(), year)
        self._user_changed()
        return "u:" + aid

    @Slot(str, str, str, int)
    def editAlbum(self, aid, name, artist, year):
        name, artist = name.strip(), artist.strip()
        year = year if 0 < year <= 9999 else 0
        if aid.startswith("t:"):                       # a folder album: remember your edit, empty = original
            ov = self._user.setdefault("tag_albums", {})
            o = ov.setdefault(aid, {})
            o["name"], o["artist"], o["year"] = name, artist, year
            if not (name or artist or year or o.get("tracks") or o.get("removed")):
                ov.pop(aid, None)                      # nothing left to remember: back to the original
            self._user_changed()
        elif library.user_update(self._user, self._hex(aid), name or "New album", artist, year):
            self._user_changed()

    @Slot(str, int)
    def moveAlbum(self, aid, to):
        """Drag an album to a new place: from now on the albums are shown in your own order."""
        ids = [a["id"] for a in self._albums]
        if aid not in ids:
            return
        ids.remove(aid)
        ids.insert(max(0, min(int(to), len(ids))), aid)
        self._user["album_order"] = ids
        self._sort = SORTS.index("manual")
        self.settings.setValue("sort", self._sort)
        self.sortChanged.emit()
        self._user_changed()

    @Slot(str, int, result="QVariantList")
    def librarySongs(self, query, rev):
        """All songs of your music folder (for the LIBRARY tab), filtered by the search text."""
        q = query.strip().lower()
        out = []
        for i, t in enumerate(self._tracks[:self._n_scanned]):
            if q and q not in (t["title"] + " " + t["artist"] + " " + t["album"]).lower():
                continue
            out.append({"idx": i, "title": t["title"], "artist": t["artist"], "album": t["album"], "length": t["length"]})
        out.sort(key=lambda d: (d["artist"].lower(), d["album"].lower(), d["title"].lower()))
        return out

    @Slot("QVariantList", int)
    def playSongs(self, idxs, pos):
        idxs = [int(i) for i in idxs if 0 <= int(i) < len(self._tracks)]
        if idxs:
            self._ctx_cover_path = ""
            self._load(self._queue.set(idxs, max(0, min(int(pos), len(idxs) - 1)), self._shuffle))

    @Slot(str)
    def hideAlbum(self, aid):
        """Hide a folder album from the library (the files stay untouched). Can be undone."""
        for a in self._all_tag_albums:
            if a["id"] == aid:
                self._user.setdefault("hidden_albums", {})[aid] = {"name": a["name"], "artist": a["artist"]}
                self._user_changed()
                return

    @Slot()
    def unhideAll(self):
        if self._user.get("hidden_albums"):
            self._user["hidden_albums"] = {}
            self._user_changed()

    @Slot(str)
    def unhideAlbum(self, aid):
        if self._user.setdefault("hidden_albums", {}).pop(aid, None) is not None:
            self._user_changed()

    @Slot(int, str, str)
    def editTrack(self, idx, title, artist):
        """Change a song's title/artist inside the player. The music file is not modified;
        an empty field means 'use the original tag'."""
        if not (0 <= idx < len(self._tracks)):
            return
        t = self._tracks[idx]
        title, artist = title.strip(), artist.strip()
        m = {}
        if title and title != t.get("tag_title", t["title"]):
            m["title"] = title
        if artist and artist != t.get("tag_artist", t["artist"]):
            m["artist"] = artist
        meta = self._user.setdefault("tracks_meta", {})
        if m:
            meta[t["path"]] = m
        else:
            meta.pop(t["path"], None)
        self._user_changed()
        if idx == self._current:
            self.currentChanged.emit()

    @Slot(int)
    def resetTrack(self, idx):
        if 0 <= idx < len(self._tracks):
            self._user.setdefault("tracks_meta", {}).pop(self._tracks[idx]["path"], None)
            self._user_changed()
            if idx == self._current:
                self.currentChanged.emit()

    @Slot(str)
    def deleteAlbum(self, aid):
        a = library.user_delete(self._user, self._hex(aid))
        if a is not None:
            if a.get("cover"):
                try:
                    os.remove(a["cover"])
                except OSError:
                    pass
            self._user_changed()

    # ---- songs of an album: add by hand, remove, reorder (works for folder albums and your own) ----
    def _paths(self, aid):
        for a in self._albums:
            if a["id"] == aid:
                return [self._tracks[t["idx"]]["path"] for t in a["tracks"]]
        return []

    def _tag_edit(self, aid):
        return self._user.setdefault("tag_albums", {}).setdefault(aid, {})

    def _album_add(self, aid, paths):
        cur = self._paths(aid)
        new = [p for p in paths if p not in cur]
        if not new:
            return
        if aid.startswith("u:"):
            library.user_add(self._user, self._hex(aid), new)
        else:
            ov = self._tag_edit(aid)
            ov["tracks"] = cur + new
            ov["removed"] = [p for p in ov.get("removed", []) if p not in new]
        self._user_changed()

    @Slot(str, int)
    def addTrack(self, aid, idx):
        if 0 <= idx < len(self._tracks):
            self._album_add(aid, [self._tracks[idx]["path"]])

    @staticmethod
    def _local(u):
        u = str(u)
        return QUrl(u).toLocalFile() if u.startswith("file:") else u

    @Slot(str, "QVariantList")
    def addFiles(self, aid, urls):
        self._album_add(aid, library.expand_paths([self._local(u) for u in urls]))

    @Slot(str, "QVariantList", result=int)
    def addDropped(self, aid, urls):
        """Files and folders dragged into the window. No album selected -> the album 'Playlist' (made if needed).
        Returns how many songs were new."""
        paths = library.expand_paths([self._local(u) for u in urls])
        if not paths:
            self._set_note("Nothing to add: no supported audio files in what you dropped")
            return 0
        if not aid:
            for a in self._user["albums"]:
                if a["name"].strip().lower() == "playlist":
                    aid = "u:" + a["id"]
                    break
            else:
                aid = "u:" + library.user_create(self._user, "Playlist")
        before = len(self._paths(aid))
        self._album_add(aid, paths)
        n = max(0, len(self._paths(aid)) - before)
        self._set_note("Added %d song%s" % (n, "" if n == 1 else "s") if n else "Those songs are already in the album")
        QTimer.singleShot(4000, lambda: self._set_note(self._cda_note))
        return n

    # ---- M3U playlists ----
    @Slot(str, str, result=bool)
    def exportM3U(self, aid, url):
        path = self._local(url)
        if not path:
            return False
        if not path.lower().endswith((".m3u", ".m3u8")):
            path += ".m3u8"
        for a in self._albums:
            if a["id"] == aid:
                entries = []
                for t in a["tracks"]:
                    g = self._tracks[t["idx"]]
                    entries.append((g["path"], g["title"], g["artist"], g.get("length") or 0))
                try:
                    with open(path, "w", encoding="utf-8") as f:
                        f.write(library.m3u_write(entries))
                except OSError as e:
                    self._set_note("Could not save playlist: %s" % e)
                    return False
                self._set_note("Saved %d songs to %s" % (len(entries), os.path.basename(path)))
                QTimer.singleShot(4000, lambda: self._set_note(self._cda_note))
                return True
        return False

    @Slot(str, result=str)
    def importM3U(self, url):
        """Playlist file -> a new album of your own. Returns its id ('' on failure)."""
        path = self._local(url)
        try:
            raw = open(path, "rb").read()
        except OSError as e:
            self._set_note("Could not read playlist: %s" % e)
            return ""
        found, missing = library.m3u_parse(library.decode_text(raw), os.path.dirname(path))
        if not found:
            self._set_note("No playable songs found in %s" % os.path.basename(path))
            return ""
        name = Path(path).stem or "Playlist"
        aid = library.user_create(self._user, name)
        library.user_add(self._user, aid, found)
        self._user_changed()
        msg = "Imported %d songs as album \"%s\"" % (len(found), name)
        if missing:
            msg += " (%d missing files skipped)" % missing
        self._set_note(msg)
        QTimer.singleShot(6000, lambda: self._set_note(self._cda_note))
        return "u:" + aid

    # ---- remember what was playing ----
    def save_state(self):
        if not (0 <= self._current < len(self._tracks)) or not self._queue.items:
            return
        try:
            items = [self._tracks[i]["path"] for i in self._queue.items if 0 <= i < len(self._tracks)]
            self.settings.setValue("state_queue", json.dumps(items))
            self.settings.setValue("state_current", self._tracks[self._current]["path"])
            self.settings.setValue("state_ms", self.positionMs)
            self.settings.setValue("state_cover", self._ctx_cover_path)
        except Exception:
            pass

    def _restore_state(self):
        """After the first scan: put back the song and the second where you stopped (paused, nothing starts by itself)."""
        if self._restored:
            return
        self._restored = True
        try:
            cur = str(self.settings.value("state_current", ""))
            items = json.loads(str(self.settings.value("state_queue", "[]")))
            ms = int(self.settings.value("state_ms", 0))
        except (ValueError, TypeError):
            return
        by_path = {t["path"]: i for i, t in enumerate(self._tracks)}
        idxs = [by_path[p] for p in items if p in by_path]
        if cur not in by_path or by_path[cur] not in idxs:
            return
        self._ctx_cover_path = str(self.settings.value("state_cover", ""))
        self._queue.set(idxs, idxs.index(by_path[cur]), self._shuffle)
        if self._shuffle:                     # keep the saved song as the current one
            self._queue.set_shuffle(self._shuffle)
        self._load(by_path[cur], autoplay=False, resume_ms=max(0, ms))

    @Slot(str, int)
    def removeTrack(self, aid, idx):
        if not (0 <= idx < len(self._tracks)):
            return
        path = self._tracks[idx]["path"]
        if aid.startswith("u:"):
            if library.user_remove(self._user, self._hex(aid), path):
                self._user_changed()
        else:                                           # folder album: only removed from this player's view
            ov = self._tag_edit(aid)
            ov["tracks"] = [p for p in self._paths(aid) if p != path]
            rem = ov.setdefault("removed", [])
            if path not in rem:
                rem.append(path)
            self._user_changed()

    @Slot(str, int, int)
    def moveTrack(self, aid, idx, number):
        """Put a song at position `number` (typed or dragged); the others shift."""
        if not (0 <= idx < len(self._tracks)):
            return
        path = self._tracks[idx]["path"]
        if aid.startswith("u:"):
            if library.user_move(self._user, self._hex(aid), path, number):
                self._user_changed()
        else:
            cur = self._paths(aid)
            if path in cur:
                self._tag_edit(aid)["tracks"] = library.move_in_list(cur, path, number)
                self._user_changed()

    @Slot(str, str)
    def setCover(self, aid, url):
        src = QUrl(url).toLocalFile() if url.startswith("file:") else url
        a = library.user_find(self._user, self._hex(aid))
        if a is None or not src or not os.path.isfile(src):
            return
        try:
            a["cover"] = library.store_cover(src, str(COVERS), a["id"])
        except OSError:
            return
        self._user_changed()

    # ----- playback -----
    def _load(self, gidx, autoplay=True, resume_ms=0):
        if gidx is None or not (0 <= gidx < len(self._tracks)):
            return
        t = self._tracks[gidx]
        real = t.get("file") or t["path"]                  # cue tracks: the big disc image they live in
        start = int(t.get("start_ms") or 0)
        target = start + int(resume_ms)
        self._current = gidx
        self._cur_start, self._cur_end = start, t.get("end_ms")
        M = QMediaPlayer.MediaStatus
        if real == self._loaded_file and self.player.mediaStatus() in (
                M.LoadedMedia, M.BufferedMedia, M.BufferingMedia, M.EndOfMedia):
            if abs(int(self.player.position()) - target) > 250:       # same file: just jump, no reload
                self.player.setPosition(target)
            if autoplay:
                self.player.play()
        else:
            self._loaded_file = real
            self._pending_seek = target if target > 0 else None
            self._play_after_load = autoplay
            self.player.setSource(QUrl.fromLocalFile(real))
            if autoplay and target == 0:
                self.player.play()
        self.currentChanged.emit()
        self.durationChanged.emit()
        if autoplay:
            self.songStarted.emit(gidx)
        self.save_state()

    @Slot(int, int)
    def playAlbum(self, album, pos):
        if not (0 <= album < len(self._albums)):
            return
        a = self._albums[album]
        idxs = [t["idx"] for t in a["tracks"]]
        if not idxs:
            return
        self._ctx_cover_path = QUrl(a["coverUrl"]).toLocalFile() if a.get("coverUrl") else ""
        self._load(self._queue.set(idxs, pos, self._shuffle))

    @Slot()
    def playLibrary(self):
        idxs = [t["idx"] for a in self._albums for t in a["tracks"]]
        if idxs:
            self._ctx_cover_path = ""
            self._load(self._queue.set(idxs, 0, self._shuffle))

    @Slot()
    def togglePlay(self):
        if self._current < 0:
            self.playLibrary()
        elif self.playing:
            self.player.pause()
        else:
            self.player.play()

    @Slot()
    def play(self):
        if self._current < 0:
            self.playLibrary()
        else:
            self.player.play()

    @Slot()
    def pause(self):
        self.player.pause()

    @Slot()
    def next(self):
        self._load(self._queue.go(1, repeat_all=True))

    @Slot()
    def prev(self):
        if self.positionMs > 3000:
            self.player.setPosition(self._cur_start)
        else:
            self._load(self._queue.go(-1))

    @Slot(int)
    def seek(self, ms):
        ms = max(0, int(ms))
        dur = self.durationMs
        if dur > 0:
            ms = min(ms, max(0, dur - 200))              # never jump past the end (it would skip to the next song)
        target = self._cur_start + ms
        if abs(int(self.player.position()) - target) > 40:   # ignore no-op jumps
            self.player.setPosition(target)
            self.positionChanged.emit()

    @Slot()
    def toggleShuffle(self):
        self._shuffle = not self._shuffle
        self.settings.setValue("shuffle", "true" if self._shuffle else "false")
        self._queue.set_shuffle(self._shuffle)
        self.shuffleChanged.emit()

    @Slot()
    def cycleRepeat(self):
        self._repeat = (self._repeat + 1) % 3       # 0 off, 1 all, 2 one
        self.settings.setValue("repeat", self._repeat)
        self.repeatChanged.emit()

    def _on_position(self, pos):
        self.positionChanged.emit()
        if self._cur_end is not None and pos >= self._cur_end - 10 and self.playing:
            self._track_finished()                         # a cue track ends inside the file

    def _track_finished(self):
        now = time.monotonic()
        if now - self._last_end < 0.3:                     # position updates may repeat while we jump
            return
        self._last_end = now
        if self._repeat == 2:
            self.player.setPosition(self._cur_start)
            self.player.play()
            return
        nxt = self._queue.go(1, auto=True, repeat_all=(self._repeat == 1))
        if nxt is None:
            self.player.stop()
        else:
            self._load(nxt)

    def _on_status(self, status):
        M = QMediaPlayer.MediaStatus
        if status in (M.LoadedMedia, M.BufferedMedia) and self._pending_seek is not None:
            self.player.setPosition(self._pending_seek)
            self._pending_seek = None
            if self._play_after_load:
                self.player.play()
        elif status == M.EndOfMedia:
            self._track_finished()

    # ----- covers -----
    @staticmethod
    def _placeholder():
        img = QImage(256, 256, QImage.Format.Format_ARGB32)
        img.fill(QColor("#1C1030"))
        p = QPainter(img)
        p.setPen(QPen(QColor("#B04CFF"), 6))
        p.drawRect(3, 3, 250, 250)
        p.setPen(QPen(QColor("#FF2BD6"), 10))
        p.drawLine(95, 175, 95, 90)
        p.drawLine(95, 90, 175, 78)
        p.drawLine(175, 78, 175, 160)
        p.end()
        return img

    @Slot(int, str, result="QVariantList")
    def coverColors(self, idx, url):
        """Four main colours of an album cover (custom picture if the album has one) for the album page."""
        key = "%s|%s|%d" % (url, idx if not url else "", self._version)
        hit = self._palette_cache.get(key)
        if hit is not None:
            return hit
        img = QImage(QUrl(url).toLocalFile()) if url else QImage()
        if img.isNull():
            img = self.cover_image(idx)
        small = img.scaled(28, 28, Qt.AspectRatioMode.IgnoreAspectRatio, Qt.TransformationMode.FastTransformation)
        pixels = []
        for y in range(small.height()):
            for x in range(small.width()):
                c = small.pixelColor(x, y)
                if c.alpha() > 128:
                    pixels.append((c.red(), c.green(), c.blue()))
        colors = library.palette_from_pixels(pixels)
        self._palette_cache[key] = colors
        return colors

    def cover_image(self, idx):
        if not (0 <= idx < len(self._tracks)):
            return self._placeholder()
        t = self._tracks[idx]
        key = os.path.dirname(t["path"]) + "|" + t["album"]
        img = self._cover_cache.get(key)
        if img is None:
            data = library.cover_bytes(t.get("file") or t["path"], t["path"])
            img = QImage()
            if data:
                img.loadFromData(data)
            if img.isNull():
                img = self._placeholder()
            else:
                img = img.scaled(512, 512, Qt.AspectRatioMode.KeepAspectRatio,
                                 Qt.TransformationMode.SmoothTransformation)
            self._cover_cache[key] = img
            while len(self._cover_cache) > COVER_CACHE_MAX:        # keep memory flat on big libraries
                self._cover_cache.pop(next(iter(self._cover_cache)))
        return img


class Visualizer(QObject):
    """Feeds the neon bars. Tries real analysis of the audio being played
    (QAudioBufferOutput, Qt 6.8+) and falls back to a simulated animation."""
    barsChanged = Signal()
    modeChanged = Signal()

    _KINDS = {}

    def __init__(self, backend):
        super().__init__(backend)
        self.b = backend
        self._active = False
        self._widget_until = 0.0
        self._sm = viz.Smoother(viz.BARS)
        self._bars = [0.0] * viz.BARS
        self._peaks = [0.0] * viz.BARS
        self._mode = "sim"
        self._buffers = collections.deque(maxlen=300)
        self._last_data = 0.0
        self._t0 = time.monotonic()
        self._warned = False
        self._analyzer = viz.Analyzer() if viz.available() else None
        self._abo = None
        if self._analyzer is not None:
            try:
                from PySide6.QtMultimedia import QAudioBufferOutput, QAudioFormat
                self._KINDS = {QAudioFormat.SampleFormat.UInt8: "u8", QAudioFormat.SampleFormat.Int16: "s16",
                               QAudioFormat.SampleFormat.Int32: "s32", QAudioFormat.SampleFormat.Float: "f32"}
                self._abo = QAudioBufferOutput(self)
                backend.player.setAudioBufferOutput(self._abo)
                self._abo.audioBufferReceived.connect(self._on_buffer)
            except Exception as e:
                print("visualizer: live audio analysis unavailable (%s); using simulated bars" % e, file=sys.stderr)
                self._abo = None
        elif not viz.available():
            print("visualizer: numpy not installed; using simulated bars (sudo pacman -S python-numpy)", file=sys.stderr)

        self._timer = QTimer(self)
        self._timer.setInterval(33)
        self._timer.timeout.connect(self._tick)
        self._timer.start()

    @Property("QVariantList", notify=barsChanged)
    def bars(self):
        return self._bars

    @Property("QVariantList", notify=barsChanged)
    def peaks(self):
        return self._peaks

    @Property(str, notify=modeChanged)
    def mode(self):
        return self._mode

    @Slot(bool)
    def setActive(self, on):
        """Only analyse while the window is visible (or the widget is watching): no CPU use otherwise."""
        self._active = bool(on)
        if not self._is_active():
            self._buffers.clear()

    def touch(self):
        """Called when the widget asks for the state: keep analysing for the next two seconds."""
        self._widget_until = time.monotonic() + 2.0

    def _is_active(self):
        return self._active or time.monotonic() < self._widget_until

    @staticmethod
    def _raw_bytes(buf):
        n = buf.byteCount()
        d = buf.constData() if hasattr(buf, "constData") else buf.data()
        raw = None
        if isinstance(d, int):
            raw = ctypes.string_at(d, n)
        else:
            try:
                raw = bytes(d)
            except Exception:
                raw = None
            if raw is None or len(raw) < n:
                raw = ctypes.string_at(int(d), n)
        return raw[:n]

    def _on_buffer(self, buf):
        if not self._is_active() or self._analyzer is None:
            return
        try:
            fmt = buf.format()
            kind = self._KINDS.get(fmt.sampleFormat())
            if kind is None:
                return
            arr = viz.to_mono(self._raw_bytes(buf), kind, fmt.channelCount())
            self._buffers.append((int(buf.startTime()), arr, int(fmt.sampleRate())))
            self._last_data = time.monotonic()
        except Exception as e:
            if not self._warned:
                self._warned = True
                print("visualizer: could not read audio buffer (%s); using simulated bars" % e, file=sys.stderr)

    def _live_target(self, now):
        if self._analyzer is None or not self._buffers or now - self._last_data > 1.2:
            return None
        pos = int(self.b.player.position()) * 1000
        near = [b for b in self._buffers if pos - 300000 <= b[0] <= pos + 100000]
        recent = near[-6:] if near else list(self._buffers)[-6:]
        arr = recent[0][1] if len(recent) == 1 else viz.np.concatenate([b[1] for b in recent])
        return self._analyzer.levels(arr, recent[-1][2])

    def _tick(self):
        if not self._is_active():
            return
        now = time.monotonic()
        if not self.b.playing:
            target, mode = [0.0] * viz.BARS, self._mode
        else:
            target = self._live_target(now)
            mode = "live"
            if target is None:
                target, mode = viz.simulated(now - self._t0), "sim"
        bars, peaks = self._sm.update(target)
        self._bars, self._peaks = list(bars), list(peaks)
        self.barsChanged.emit()
        if mode != self._mode:
            self._mode = mode
            self.modeChanged.emit()


class Control(QObject):
    showRequested = Signal()
    """Lets the Plasma widget talk to the player.
    - listens on a local socket for one-line commands (see cyberneon-ctl)
    - writes the current state to ~/.cache/cyberneon-player/state.json every second"""

    def __init__(self, backend, visualizer):
        super().__init__(backend)
        self.b = backend
        self.viz = visualizer
        self._bufs = {}
        CACHE.mkdir(parents=True, exist_ok=True)
        self._cover_key = None
        self._cover_path = ""
        self._cover_n = 0

        self.server = QLocalServer(self)
        QLocalServer.removeServer(SOCKET)
        self.server.listen(SOCKET)
        self.server.newConnection.connect(self._on_connection)

        # tiny read-only HTTP endpoint (127.0.0.1 only) so the widget can poll ~12 times per second
        self.http = QTcpServer(self)
        if self.http.listen(QHostAddress("127.0.0.1"), HTTP_PORT):
            self.http.newConnection.connect(self._on_http)
        else:
            print("widget feed: port %d is busy; the widget falls back to the slow state file" % HTTP_PORT,
                  file=sys.stderr)

        self.timer = QTimer(self)
        self.timer.setInterval(1000)
        self.timer.timeout.connect(self.write_state)
        self.timer.start()
        backend.currentChanged.connect(self.write_state)
        self.write_state()

    def _on_connection(self):
        while self.server.hasPendingConnections():
            sock = self.server.nextPendingConnection()
            sock.readyRead.connect(lambda s=sock: self._read(s))
            sock.disconnected.connect(sock.deleteLater)

    def _read(self, sock):
        while sock.canReadLine():
            line = bytes(sock.readLine()).decode("utf-8", "ignore").strip()
            try:
                self.handle(line)
                sock.write(b"ok\n")
            except Exception as e:  # never let a bad command kill the player
                sock.write(("error " + str(e) + "\n").encode())
        sock.flush()
        sock.disconnectFromServer()

    def handle(self, line):
        parts = line.split()
        if not parts:
            return
        cmd, arg = parts[0], (parts[1] if len(parts) > 1 else None)
        b = self.b
        if cmd == "playpause":
            b.togglePlay()
        elif cmd == "play":
            b.play()
        elif cmd == "pause":
            b.pause()
        elif cmd == "next":
            b.next()
        elif cmd == "prev":
            b.prev()
        elif cmd == "seek" and arg is not None:
            b.seek(int(float(arg)))
        elif cmd == "volume" and arg is not None:
            b.volume = float(arg)
        elif cmd == "shuffle":
            b.toggleShuffle()
        elif cmd == "repeat":
            b.cycleRepeat()
        elif cmd == "show":
            self.showRequested.emit()
        elif cmd == "state":
            pass
        else:
            raise ValueError("unknown command: " + line)
        QTimer.singleShot(150, self.write_state)

    def _ensure_cover(self, idx):
        t = self.b._tracks[idx] if 0 <= idx < len(self.b._tracks) else None
        if t is None:
            return ""
        custom = self.b._ctx_cover_path
        key = ("custom|" + custom) if custom else (os.path.dirname(t["path"]) + "|" + t["album"])
        if key != self._cover_key:
            old = self._cover_path
            self._cover_n += 1
            path = CACHE / ("cover-%d.png" % self._cover_n)
            img = QImage(custom) if custom else QImage()
            if img.isNull():
                img = self.b.cover_image(idx)
            img = img.scaled(256, 256, Qt.AspectRatioMode.KeepAspectRatio,
                             Qt.TransformationMode.SmoothTransformation)
            if img.save(str(path), "PNG"):
                self._cover_key, self._cover_path = key, str(path)
                if old:
                    try:
                        os.remove(old)
                    except OSError:
                        pass
        return self._cover_path

    def snapshot(self):
        b = self.b
        return {"running": True, "ts": time.time(), "playing": bool(b.playing),
                "title": b.currentTitle, "artist": b.currentArtist, "album": b.currentAlbum,
                "position": b.positionMs, "duration": b.durationMs, "volume": b.volume,
                "shuffle": b.shuffle, "repeat": b.repeatMode,
                "cover": self._ensure_cover(b._current) if b._current >= 0 else "",
                "bars": [round(x, 2) for x in self.viz._bars],
                "peaks": [round(x, 2) for x in self.viz._peaks]}

    def write_state(self):
        self._dump(self.snapshot())

    # ----- HTTP feed for the widget -----
    def _on_http(self):
        while self.http.hasPendingConnections():
            sock = self.http.nextPendingConnection()
            self._bufs[sock] = b""
            sock.readyRead.connect(lambda s=sock: self._http_read(s))
            sock.disconnected.connect(lambda s=sock: self._bufs.pop(s, None))
            sock.disconnected.connect(sock.deleteLater)

    def _http_read(self, sock):
        buf = self._bufs.get(sock, b"") + bytes(sock.readAll())
        self._bufs[sock] = buf
        if b"\r\n\r\n" not in buf and len(buf) < 8192:
            return                                         # request not complete yet
        lines = buf.decode("latin1").split("\r\n")
        headers = {}
        for h in lines[1:]:
            if ":" in h:
                k, v = h.split(":", 1)
                headers[k.strip().lower()] = v.strip()
        if headers.get("host", "").split(":")[0] not in ("127.0.0.1", "localhost"):
            return self._http_reply(sock, 403, b"forbidden")
        if lines[0].startswith("GET /state"):
            self.viz.touch()
            return self._http_reply(sock, 200, json.dumps(self.snapshot()).encode(), "application/json")
        self._http_reply(sock, 404, b"not found")

    @staticmethod
    def _http_reply(sock, code, body, ctype="text/plain"):
        reason = {200: "OK", 403: "Forbidden", 404: "Not Found"}[code]
        head = ("HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\n"
                "Cache-Control: no-store\r\nConnection: close\r\n\r\n" % (code, reason, ctype, len(body))).encode()
        sock.write(head + body)
        sock.flush()
        sock.disconnectFromHost()

    def _dump(self, state):
        try:
            tmp = CACHE / "state.json.tmp"
            tmp.write_text(json.dumps(state))
            os.replace(tmp, CACHE / "state.json")
        except OSError:
            pass

    def shutdown(self):
        self._dump({"running": False, "ts": time.time()})
        self.server.close()


class CoverProvider(QQuickImageProvider):
    def __init__(self, backend):
        super().__init__(QQuickImageProvider.ImageType.Image)
        self.backend = backend

    def requestImage(self, id, size, requestedSize):
        try:
            idx = int(str(id).split("?")[0])
        except ValueError:
            idx = -1
        return self.backend.cover_image(idx)


def make_icon():
    pm = QPixmap(64, 64)
    pm.fill(Qt.GlobalColor.transparent)
    p = QPainter(pm)
    p.setRenderHint(QPainter.RenderHint.Antialiasing)
    tile = QPolygonF([QPointF(14, 3), QPointF(61, 3), QPointF(61, 50),
                      QPointF(50, 61), QPointF(3, 61), QPointF(3, 14)])
    p.setPen(QPen(QColor("#B04CFF"), 4))
    p.setBrush(QColor("#14091F"))
    p.drawPolygon(tile)
    p.setPen(Qt.PenStyle.NoPen)
    p.setBrush(QColor("#FF2BD6"))
    p.drawPolygon(QPolygonF([QPointF(26, 19), QPointF(26, 45), QPointF(46, 32)]))
    p.end()
    return QIcon(pm)


def already_running(show):
    """If another instance is alive, ask it to show its window and report True."""
    if IS_WIN:
        from PySide6.QtNetwork import QLocalSocket
        c = QLocalSocket()
        c.connectToServer(SOCKET)
        if not c.waitForConnected(1000):
            return False
        c.write(b"show\n" if show else b"state\n")
        c.waitForBytesWritten(1000)
        c.waitForReadyRead(1000)
        c.disconnectFromServer()
        return True
    import socket
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(1)
    try:
        s.connect(SOCKET)
        s.sendall(b"show\n" if show else b"state\n")
        s.recv(64)
        return True
    except OSError:
        return False
    finally:
        s.close()


def main():
    background = "--background" in sys.argv
    if not IS_WIN and already_running(show=not background):
        return

    app = QApplication(sys.argv)
    if IS_WIN and already_running(show=not background):      # (the named pipe needs the Qt application to exist)
        return
    app.setApplicationName("cyberneon-player")
    app.setApplicationDisplayName("CyberNeon Player")
    app.setDesktopFileName("cyberneon-player")     # matches cyberneon-player.desktop, so the panel can pin it
    app.setOrganizationName("CyberNeon")
    app.setQuitOnLastWindowClosed(False)      # closing the window keeps the music going
    icon = make_icon()
    app.setWindowIcon(icon)
    QQuickStyle.setStyle("Basic")

    engine = QQmlApplicationEngine()
    backend = Backend()
    provider = CoverProvider(backend)
    engine.addImageProvider("cover", provider)
    visualizer = Visualizer(backend)
    engine.rootContext().setContextProperty("backend", backend)
    engine.rootContext().setContextProperty("viz", visualizer)
    engine.setInitialProperties({"startVisible": not background})
    engine.load(QUrl.fromLocalFile(str(HERE / "Main.qml")))
    if not engine.rootObjects():
        sys.exit(1)
    window = engine.rootObjects()[0]

    def show_window(*_):
        window.show()
        window.raise_()
        window.requestActivate()

    def toggle_window(*_):
        if window.isVisible():
            window.hide()
        else:
            show_window()

    app.aboutToQuit.connect(backend.save_state)

    def notify_now_playing(idx):
        """Desktop pop-up "Now playing" for every new song."""
        if not backend.notifications or not (0 <= idx < len(backend._tracks)):
            return
        t = backend._tracks[idx]
        body = t["title"] + ("\n" + t["artist"] if t["artist"] else "")
        if t.get("album"):
            body += ("  -  " if t["artist"] else "\n") + t["album"]
        if tray is not None:
            pic = QPixmap.fromImage(backend.cover_image(idx)).scaled(
                128, 128, Qt.AspectRatioMode.KeepAspectRatio, Qt.TransformationMode.SmoothTransformation)
            tray.showMessage("Now playing", body, QIcon(pic), 5000)
        elif shutil.which("notify-send"):
            QProcess.startDetached("notify-send", ["-a", "CyberNeon Player", "-t", "5000", "Now playing", body])

    control = Control(backend, visualizer)
    control.showRequested.connect(show_window)
    app.aboutToQuit.connect(control.shutdown)

    tray, menu = None, None
    if QSystemTrayIcon.isSystemTrayAvailable():
        tray = QSystemTrayIcon(icon, app)
        tray.setToolTip("CyberNeon Player")
        menu = QMenu()
        menu.addAction("Show / Hide").triggered.connect(toggle_window)
        menu.addSeparator()
        menu.addAction("Play / Pause").triggered.connect(lambda *_: backend.togglePlay())
        menu.addAction("Previous").triggered.connect(lambda *_: backend.prev())
        menu.addAction("Next").triggered.connect(lambda *_: backend.next())
        menu.addSeparator()
        menu.addAction("Quit").triggered.connect(app.quit)
        tray.setContextMenu(menu)
        tray.activated.connect(
            lambda reason: toggle_window() if reason == QSystemTrayIcon.ActivationReason.Trigger else None)
        tray.show()
    else:
        app.setQuitOnLastWindowClosed(True)   # no tray: closing the window must quit

    backend.songStarted.connect(notify_now_playing)
    backend.start()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()

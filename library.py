"""Pure-Python part of CyberNeon Player: scanning, tags, albums, covers, play queue.
No Qt imports here, so it can be tested on its own."""
import colorsys
import hashlib
import json
import os
import random
import re
import shutil
import urllib.parse
import uuid
from pathlib import Path

try:
    import mutagen
except Exception:  # mutagen missing -> fall back to file names
    mutagen = None

AUDIO_EXTS = {".mp3", ".flac", ".ogg", ".opus", ".m4a", ".wav", ".ape", ".wv"}
BIN_CACHE_DIR = None        # where converted .bin disc images are kept (set by the player)
COVER_NAMES = ("cover", "folder", "front", "album", "artwork")
COVER_EXTS = (".jpg", ".jpeg", ".png", ".webp")
VARIOUS = "Various Artists"


# ---------- tags ----------
def _first(tags, key, default=""):
    try:
        v = tags.get(key) if tags is not None else None
    except Exception:
        v = None
    if not v:
        return default
    if isinstance(v, (list, tuple)):
        return str(v[0]).strip()
    return str(v).strip()


def _num(s):
    m = re.match(r"\s*(\d+)", s or "")
    return int(m.group(1)) if m else 0


def _year_from_date(s):
    m = re.match(r"\s*(\d{4})", s or "")
    return int(m.group(1)) if m else 0


def read_tags(path):
    p = Path(path)
    t = {"path": str(p), "title": p.stem, "artist": "", "albumartist": "",
         "album": "", "year": 0, "no": 0, "disc": 1, "length": 0.0}
    if mutagen is None:
        return t
    try:
        f = mutagen.File(str(p), easy=True)
        if f is None:
            return t
        tags = f.tags
        t["title"] = _first(tags, "title", p.stem) or p.stem
        t["artist"] = _first(tags, "artist")
        t["albumartist"] = _first(tags, "albumartist")
        t["album"] = _first(tags, "album")
        t["year"] = _year_from_date(_first(tags, "date"))
        t["no"] = _num(_first(tags, "tracknumber"))
        t["disc"] = _num(_first(tags, "discnumber")) or 1
        length = getattr(getattr(f, "info", None), "length", None)
        if length:
            t["length"] = float(length)
    except Exception:
        pass
    return t


# ---------- audio CD images: .cue (+ .wav / .flac / .ape / .wv / .bin) ----------
_TOKEN = re.compile(r'"([^"]*)"|(\S+)')
CUE_STEMS_EXTS = (".flac", ".wav", ".ape", ".wv", ".mp3", ".m4a", ".ogg", ".opus", ".bin")


def decode_text(raw):
    """cue sheets come in UTF-8, or Windows code pages (Cyrillic ones are common)."""
    for enc in ("utf-8-sig", "cp1251"):
        try:
            return raw.decode(enc)
        except UnicodeDecodeError:
            continue
    return raw.decode("latin-1")


def _tokens(line):
    return [m.group(1) if m.group(1) is not None else m.group(2) for m in _TOKEN.finditer(line)]


def _msf(s):
    """mm:ss:ff (75 frames per second) -> milliseconds"""
    m = re.match(r"\s*(\d+):(\d+):(\d+)", s or "")
    if not m:
        return None
    mm, ss, ff = (int(x) for x in m.groups())
    return int(round((mm * 60 + ss) * 1000 + ff * 1000.0 / 75))


def parse_cue(text):
    cue = {"title": "", "performer": "", "year": 0, "files": []}
    cur_file = cur_track = None
    for raw in text.splitlines():
        tok = _tokens(raw.strip())
        if len(tok) < 2:
            continue
        key = tok[0].upper()
        if key == "REM" and len(tok) >= 3 and tok[1].upper() == "DATE":
            cue["year"] = _year_from_date(tok[2])
        elif key == "PERFORMER":
            (cur_track if cur_track is not None else cue)["performer"] = tok[1]
        elif key == "TITLE":
            (cur_track if cur_track is not None else cue)["title"] = tok[1]
        elif key == "FILE":
            cur_file, cur_track = {"name": tok[1], "tracks": []}, None
            cue["files"].append(cur_file)
        elif key == "TRACK" and cur_file is not None and tok[1].isdigit():
            cur_track = {"no": int(tok[1]), "type": (tok[2].upper() if len(tok) > 2 else "AUDIO"),
                         "title": "", "performer": "", "start": None}
            cur_file["tracks"].append(cur_track)
        elif key == "INDEX" and cur_track is not None and len(tok) >= 3 and tok[1] == "01":
            cur_track["start"] = _msf(tok[2])
    return cue


def _resolve_audio(folder, name):
    """Find the file a cue sheet points to (any letter case, or the same name with another extension)."""
    base = os.path.basename(name.replace("\\", "/"))
    try:
        names = {n.lower(): n for n in os.listdir(folder)}
    except OSError:
        return None
    hit = names.get(base.lower())
    if hit:
        return os.path.join(folder, hit)
    stem = os.path.splitext(base)[0].lower()
    for ext in CUE_STEMS_EXTS:
        hit = names.get(stem + ext)
        if hit:
            return os.path.join(folder, hit)
    return None


def bin_cache_path(src, cache_dir):
    """Raw CD images (.bin) are converted once to FLAC; this is where the result is kept."""
    try:
        st = os.stat(src)
        key = "%s|%d|%d" % (os.path.abspath(src), st.st_size, int(st.st_mtime))
    except OSError:
        key = os.path.abspath(src)
    return os.path.join(cache_dir, hashlib.sha1(key.encode("utf-8")).hexdigest()[:16] + ".flac")


def cue_tracks(cue_path, bin_cache_dir=None, info=None):
    """Tracks of a cue sheet as virtual tracks: path 'x.cue#03', 'file' = the real audio, start/end in ms.
    Returns (tracks, claimed): `claimed` = image files that must not be listed as songs themselves."""
    bin_cache_dir = bin_cache_dir or BIN_CACHE_DIR
    try:
        with open(cue_path, "rb") as f:
            cue = parse_cue(decode_text(f.read()))
    except OSError:
        return [], set()
    folder = os.path.dirname(cue_path)
    album = cue["title"] or os.path.splitext(os.path.basename(cue_path))[0]
    out, claimed = [], set()
    for fb in cue["files"]:
        real = _resolve_audio(folder, fb["name"])
        if real is None:
            continue
        claimed.add(real)
        playable = real
        if real.lower().endswith(".bin"):
            cached = bin_cache_path(real, bin_cache_dir) if bin_cache_dir else None
            if cached and os.path.isfile(cached):
                playable = cached
            else:                                              # needs a one-time conversion
                if info is not None:
                    info.setdefault("bins", []).append(real)
                continue
        tracks = [t for t in fb["tracks"] if t["type"] == "AUDIO" and t["start"] is not None]
        if not tracks:
            continue
        total = read_tags(playable)["length"]
        for n, t in enumerate(tracks):
            end = tracks[n + 1]["start"] if n + 1 < len(tracks) else None
            length = (end - t["start"]) / 1000.0 if end is not None else max(0.0, total - t["start"] / 1000.0)
            out.append({"path": "%s#%02d" % (cue_path, t["no"]), "file": playable,
                        "start_ms": t["start"], "end_ms": end,
                        "title": t["title"] or "Track %02d" % t["no"],
                        "artist": t["performer"] or cue["performer"], "albumartist": cue["performer"],
                        "album": album, "year": cue["year"], "no": t["no"], "disc": 1, "length": length})
    return out, claimed


def virtual_track(p):
    """Rebuild a cue track from its virtual path 'x.cue#03' (used for songs added to albums by hand)."""
    cue_path, sep, _ = p.rpartition("#")
    if not sep or not cue_path.lower().endswith(".cue") or not os.path.isfile(cue_path):
        return None
    for t in cue_tracks(cue_path)[0]:
        if t["path"] == p:
            return t
    return None


def cue_track_paths(cue_path):
    return [t["path"] for t in cue_tracks(cue_path)[0]]


def scan_folder(folder, info=None, bin_cache_dir=None):
    """All songs below `folder`. `info` (a dict) collects notes: .cda files skipped, .bin images to convert."""
    tracks = []
    for root, dirs, files in os.walk(folder):
        dirs[:] = sorted(d for d in dirs if not d.startswith("."))
        claimed = set()
        for name in sorted(files):
            low = name.lower()
            if name.startswith("."):
                continue
            if low.endswith(".cue"):
                ts, used = cue_tracks(os.path.join(root, name), bin_cache_dir, info)
                tracks.extend(ts)
                claimed |= used
            elif low.endswith(".cda") and info is not None:
                info["cda"] = info.get("cda", 0) + 1
        for name in sorted(files):
            path = os.path.join(root, name)
            if Path(name).suffix.lower() in AUDIO_EXTS and not name.startswith(".") and path not in claimed:
                tracks.append(read_tags(path))
    return tracks


# ---------- albums ----------
NO_ALBUM = "No album"      # with AUTO ALBUMS on, files without an album tag are collected here


def _album_key(t, auto=True):
    """Which album a song belongs to by its tags. None = not in any folder album (AUTO ALBUMS off);
    disc images (.cue tracks, they have a 'file') always keep their own album."""
    if not auto and "file" not in t:
        return None
    if t["album"]:
        return (t["albumartist"] or "", t["album"])
    return ("", "\0" + NO_ALBUM)


def sort_albums(albums, sort="album", order=None):
    """sort: album | artist | year | manual (your own order: `order` = list of album ids; new albums go last)."""
    if sort == "manual":
        pos = {aid: i for i, aid in enumerate(order or [])}
        albums.sort(key=lambda a: (pos.get(a["id"], len(pos)), a["name"].lower()))
    elif sort == "artist":
        albums.sort(key=lambda a: (a["artist"].lower(), a["name"].lower()))
    elif sort == "year":
        albums.sort(key=lambda a: (a["year"] or 9999, a["name"].lower()))
    else:
        albums.sort(key=lambda a: a["name"].lower())
    return albums


def build_albums(tracks, sort="album", auto=True):
    groups = {}
    for i, t in enumerate(tracks):
        key = _album_key(t, auto)
        if key is not None:
            groups.setdefault(key, []).append(i)

    albums = []
    for key, idxs in groups.items():
        aa, name = key
        ts = [tracks[i] for i in idxs]
        idxs.sort(key=lambda i: (tracks[i]["disc"], tracks[i]["no"] or 9999,
                                 tracks[i]["title"].lower()))
        artists = {t["artist"] for t in ts if t["artist"]}
        if name.startswith("\0"):
            artist = ""                                  # the "Playlist" collection has no artist
        elif aa:
            artist = aa
        elif len(artists) == 1:
            artist = next(iter(artists))
        elif len(artists) > 1:
            artist = VARIOUS
        else:
            artist = ""
        years = [t["year"] for t in ts if t["year"]]
        albums.append({
            "id": "t:" + aa + "|" + name.replace("\0", "#"),
            "custom": False,
            "name": name.lstrip("\0"),
            "artist": artist,
            "year": 0 if name.startswith("\0") else (min(years) if years else 0),
            "cover": idxs[0],
            "coverUrl": "",
            "tracks": [{"idx": i, "title": tracks[i]["title"], "artist": tracks[i]["artist"],
                        "length": tracks[i]["length"], "no": tracks[i]["no"]} for i in idxs],
        })
    return sort_albums(albums, sort)


def filter_hidden(albums, hidden):
    """Drop folder albums the user hid (hidden = {album id: {...}}). Own albums are never hidden."""
    return [a for a in albums if a["custom"] or a["id"] not in hidden]


# ---------- user (custom) albums ----------
# Stored as JSON: {"albums": [{"id", "name", "artist", "cover": "/path", "tracks": ["/path/a.mp3", ...]}]}
# The order of "tracks" IS the track numbering (number = position + 1). Audio files are never modified.
def user_load(path):
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        if isinstance(data, dict) and isinstance(data.get("albums"), list):
            return data
    except (OSError, ValueError):
        pass
    return {"albums": []}


def user_save(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
    os.replace(tmp, path)


def user_find(data, aid):
    for a in data["albums"]:
        if a["id"] == aid:
            return a
    return None


def _year(y):
    try:
        y = int(y)
    except (TypeError, ValueError):
        return 0
    return y if 0 < y <= 9999 else 0


def user_create(data, name, artist="", year=0):
    aid = uuid.uuid4().hex[:8]
    data["albums"].append({"id": aid, "name": name, "artist": artist, "year": _year(year),
                           "cover": "", "tracks": []})
    return aid


def user_update(data, aid, name, artist, year=0):
    a = user_find(data, aid)
    if a is not None:
        a["name"], a["artist"], a["year"] = name, artist, _year(year)
    return a is not None


def user_delete(data, aid):
    a = user_find(data, aid)
    if a is not None:
        data["albums"].remove(a)
    return a


def user_add(data, aid, paths):
    a = user_find(data, aid)
    if a is None:
        return 0
    n = 0
    for p in paths:
        if p not in a["tracks"]:
            a["tracks"].append(p)
            n += 1
    return n


def user_remove(data, aid, path):
    a = user_find(data, aid)
    if a is not None and path in a["tracks"]:
        a["tracks"].remove(path)
        return True
    return False


def move_in_list(paths, path, number):
    """Copy of `paths` with `path` put at position `number` (1-based); the others shift."""
    out = [p for p in paths if p != path]
    out.insert(max(0, min(int(number) - 1, len(out))), path)
    return out


def user_move(data, aid, path, number):
    """Put a track at position `number` (1-based); the others shift."""
    a = user_find(data, aid)
    if a is None or path not in a["tracks"]:
        return False
    a["tracks"] = move_in_list(a["tracks"], path, number)
    return True


def apply_album_edits(album, ov, tracks, by_path):
    """Manual changes to a folder album (stored in ov): songs added by hand, your own order, removed songs.
    Without such edits the album keeps the tag order and numbers."""
    manual, removed = ov.get("tracks") or [], set(ov.get("removed") or [])
    if not manual and not removed:
        return album
    ordered, seen = [], set()
    for p in manual:                                   # your order first (added songs included)
        i = by_path.get(p)
        if i is not None and p not in seen:
            ordered.append(i)
            seen.add(p)
    for e in album["tracks"]:                          # then tag songs you did not place yourself
        p = tracks[e["idx"]]["path"]
        if p not in seen and p not in removed:
            ordered.append(e["idx"])
            seen.add(p)
    album["tracks"] = [{"idx": i, "title": tracks[i]["title"], "artist": tracks[i]["artist"],
                        "length": tracks[i]["length"], "no": n + 1} for n, i in enumerate(ordered)]
    if ordered and album["cover"] not in ordered:
        album["cover"] = ordered[0]
    return album


def store_cover(src, dest_dir, aid):
    """Copy a user-chosen image into our data folder (unique name, old one removed)."""
    os.makedirs(dest_dir, exist_ok=True)
    ext = Path(src).suffix.lower() or ".png"
    for old in Path(dest_dir).glob(aid + "-*"):
        try:
            old.unlink()
        except OSError:
            pass
    dest = os.path.join(dest_dir, "%s-%s%s" % (aid, uuid.uuid4().hex[:6], ext))
    shutil.copyfile(src, dest)
    return dest


def ensure_tracks(tracks, data):
    """Append files used by user albums that are not in `tracks` yet (they get a global index)."""
    by_path = {t["path"] for t in tracks}
    lists = [ua["tracks"] for ua in data["albums"]] + [o.get("tracks") or [] for o in data.get("tag_albums", {}).values()]
    for paths in lists:
        for p in paths:
            if p in by_path:
                continue
            t = virtual_track(p) if "#" in p else None
            if t is None and os.path.isfile(p):            # a real file (its name may contain a '#')
                t = read_tags(p)
            if t is not None:
                tracks.append(t)
                by_path.add(p)


def apply_overrides(tracks, meta):
    """Apply your own title/artist edits (data["tracks_meta"]); the file tags are never touched.
    Original tag values are kept in tag_title / tag_artist so an edit can be undone."""
    for t in tracks:
        t.setdefault("tag_title", t["title"])
        t.setdefault("tag_artist", t["artist"])
        m = meta.get(t["path"]) or {}
        t["title"] = m.get("title") or t["tag_title"]
        t["artist"] = m.get("artist") or t["tag_artist"]


def merge_user(tracks, data):
    """Build album dicts for user albums (see ensure_tracks). Missing files are skipped."""
    ensure_tracks(tracks, data)
    by_path = {t["path"]: i for i, t in enumerate(tracks)}
    albums = []
    for ua in data["albums"]:
        entries = []
        for p in ua["tracks"]:
            if p not in by_path:
                continue
            i = by_path[p]
            t = tracks[i]
            entries.append({"idx": i, "title": t["title"], "artist": t["artist"],
                            "length": t["length"], "no": len(entries) + 1})
        cover = ua.get("cover") or ""
        albums.append({
            "id": "u:" + ua["id"],
            "custom": True,
            "name": ua["name"],
            "artist": ua.get("artist", ""),
            "year": _year(ua.get("year", 0)),
            "cover": entries[0]["idx"] if entries else -1,
            "coverUrl": Path(cover).as_uri() if cover and os.path.isfile(cover) else "",
            "tracks": entries,
        })
    return albums


# ---------- covers ----------
def embedded_cover(path):
    if mutagen is None:
        return None
    try:
        f = mutagen.File(path)
        if f is None:
            return None
        tags = getattr(f, "tags", None)
        if tags is not None and hasattr(tags, "getall"):       # MP3 / ID3
            pics = tags.getall("APIC")
            if pics:
                return pics[0].data
        pics = getattr(f, "pictures", None)                     # FLAC
        if pics:
            return pics[0].data
        if tags is not None and "covr" in tags:                 # MP4 / M4A
            return bytes(tags["covr"][0])
    except Exception:
        pass
    return None


def folder_cover(folder):
    try:
        names = {n.lower(): n for n in os.listdir(folder)}
    except OSError:
        return None
    for stem in COVER_NAMES:
        for ext in COVER_EXTS:
            n = names.get(stem + ext)
            if n:
                try:
                    return Path(folder, n).read_bytes()
                except OSError:
                    return None
    return None


def cover_bytes(path, folder_of=None):
    """Embedded picture, else cover.jpg & co. next to `folder_of` (default: next to the file)."""
    return embedded_cover(path) or folder_cover(os.path.dirname(folder_of or path))


# ---------- colours of a cover (for the album page background) ----------
NEON_PALETTE = ["#B04CFF", "#FF2BD6", "#00F0FF", "#8A2BE2"]


def _hex(r, g, b):
    return "#%02x%02x%02x" % (int(round(r)), int(round(g)), int(round(b)))


def palette_from_pixels(pixels, n=4):
    """Main colours of a picture, made vivid, as '#rrggbb' strings.
    pixels: iterable of (r, g, b) 0..255 (a small, downscaled copy of the cover is enough).
    Grey or empty pictures give the neon palette."""
    buckets = {}
    for r, g, b in pixels:
        e = buckets.setdefault((r >> 5, g >> 5, b >> 5), [0, 0, 0, 0])
        e[0] += 1
        e[1] += r
        e[2] += g
        e[3] += b
    cands = []
    for cnt, sr, sg, sb in buckets.values():
        r, g, b = sr / cnt, sg / cnt, sb / cnt
        h, sat, val = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
        cands.append((cnt * (0.25 + sat) * (0.3 + val), (r, g, b), (h, sat, val)))
    if not cands or max(c[2][1] for c in cands) < 0.12:
        return list(NEON_PALETTE)
    cands.sort(key=lambda c: -c[0])
    chosen = []
    for w, rgb, hsv in cands:
        if all(sum((a - b) ** 2 for a, b in zip(rgb, c[1])) ** 0.5 > 70 for c in chosen):
            chosen.append((w, rgb, hsv))
        if len(chosen) == n:
            break
    out = []
    for _, _, (h, sat, val) in chosen:                       # vivid but not blinding
        r, g, b = colorsys.hsv_to_rgb(h, min(1.0, max(sat, 0.45) * 1.1), max(val, 0.55))
        out.append(_hex(r * 255, g * 255, b * 255))
    i = 0
    while len(out) < n:                                      # too few distinct colours: shift the hue of the first ones
        h, sat, val = colorsys.rgb_to_hsv(*(int(out[i % len(chosen)][k:k + 2], 16) / 255.0 for k in (1, 3, 5)))
        r, g, b = colorsys.hsv_to_rgb((h + 0.08 * (i + 1)) % 1.0, sat, val)
        out.append(_hex(r * 255, g * 255, b * 255))
        i += 1
    return out


# ---------- drag & drop and M3U playlists ----------
def natural_key(s):
    """'track 2' < 'track 10'."""
    return [int(x) if x.isdigit() else x.lower() for x in re.split(r"(\d+)", s)]


def expand_paths(paths):
    """Dropped files and folders -> song paths. Folders are scanned (subfolders too, disc images included),
    a .cue file brings all of its tracks. Natural order, no duplicates."""
    out, seen = [], set()

    def add(p):
        if p not in seen:
            seen.add(p)
            out.append(p)

    for p in paths:
        if os.path.isdir(p):
            for t in sorted(scan_folder(p), key=lambda t: natural_key(t["path"])):
                add(t["path"])
        elif os.path.isfile(p):
            ext = Path(p).suffix.lower()
            if ext == ".cue":
                for q in cue_track_paths(p):
                    add(q)
            elif ext in AUDIO_EXTS:
                add(p)
    return out


def m3u_write(entries):
    """entries: [(path, title, artist, seconds)] -> M3U text."""
    lines = ["#EXTM3U"]
    for path, title, artist, secs in entries:
        name = (artist + " - " + title) if artist else title
        lines.append("#EXTINF:%d,%s" % (int(secs or 0), name.replace("\n", " ")))
        lines.append(path)
    return "\n".join(lines) + "\n"


def m3u_parse(text, base_dir):
    """-> (existing song paths, number of missing entries). Handles BOM, relative paths,
    Windows backslashes, file:// URLs and duplicates."""
    found, missing, seen = [], 0, set()
    for raw in text.lstrip("\ufeff").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.lower().startswith("file://"):
            line = urllib.parse.unquote(urllib.parse.urlparse(line).path)
        elif "\\" in line and "/" not in line:
            line = line.replace("\\", "/")
        if not os.path.isabs(line):
            line = os.path.join(base_dir, line)
        line = os.path.normpath(line)
        if Path(line).suffix.lower() not in AUDIO_EXTS or not os.path.isfile(line):
            missing += 1
            continue
        if line not in seen:
            seen.add(line)
            found.append(line)
    return found, missing


# ---------- play queue ----------
class PlayQueue:
    def __init__(self):
        self.items, self.order, self.pos, self.shuffle = [], [], -1, False

    def _rebuild(self, start):
        n = len(self.items)
        if n == 0:
            self.order, self.pos = [], -1
            return
        start = max(0, min(start, n - 1))
        if self.shuffle:
            rest = [i for i in range(n) if i != start]
            random.shuffle(rest)
            self.order, self.pos = [start] + rest, 0
        else:
            self.order, self.pos = list(range(n)), start

    def set(self, items, start, shuffle):
        self.items, self.shuffle = list(items), bool(shuffle)
        self._rebuild(start)
        return self.current()

    def current(self):
        return self.items[self.order[self.pos]] if 0 <= self.pos < len(self.order) else None

    def set_shuffle(self, shuffle):
        self.shuffle = bool(shuffle)
        if self.order:
            self._rebuild(self.order[self.pos])

    def go(self, step, auto=False, repeat_all=False):
        n = len(self.order)
        if n == 0:
            return None
        pos = self.pos + step
        if pos >= n:
            if auto and not repeat_all:
                return None
            if self.shuffle:
                self._rebuild(random.randrange(n))
            pos = 0
        elif pos < 0:
            pos = n - 1
        self.pos = pos
        return self.current()

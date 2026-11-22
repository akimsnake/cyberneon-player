"""System numbers for the drawer (Linux /proc and /sys). No Qt in here, so it can be tested on its own."""
import glob
import os
import re
import shutil
import time

TEMP_PRIORITY = ("k10temp", "zenpower", "coretemp", "cpu_thermal", "acpitz")
SKIP_NET = ("lo", "docker", "veth", "virbr", "br-", "tun", "tap")


def human_rate(b):
    b = float(b)
    for unit in ("B/s", "KB/s", "MB/s", "GB/s"):
        if b < 1000 or unit == "GB/s":
            return ("%d %s" % (b, unit)) if unit == "B/s" else ("%.1f %s" % (b, unit))
        b /= 1024.0


def read_temp():
    """CPU temperature in degrees C, or None."""
    found = {}
    for hw in glob.glob("/sys/class/hwmon/hwmon*"):
        try:
            name = open(hw + "/name").read().strip()
        except OSError:
            continue
        for f in sorted(glob.glob(hw + "/temp*_input")):
            try:
                found.setdefault(name, int(open(f).read()) / 1000.0)
            except (OSError, ValueError):
                pass
    for name in TEMP_PRIORITY:
        if name in found:
            return found[name]
    return next(iter(found.values()), None)


def parse_wpctl(out):
    """'Volume: 0.50 [MUTED]' -> (0.5, True)"""
    m = re.search(r"([\d.]+)", out or "")
    if not m:
        return None
    return min(1.0, float(m.group(1))), "MUTED" in (out or "")


def parse_pactl(out):
    """'Volume: front-left: 32768 /  50% / ...' -> 0.5"""
    m = re.search(r"(\d+)%", out or "")
    return min(1.0, int(m.group(1)) / 100.0) if m else None


class Sampler:
    def __init__(self):
        self._cpu = None
        self._net = None

    @staticmethod
    def _read_cpu():
        with open("/proc/stat") as f:
            v = [int(x) for x in f.readline().split()[1:]]
        return v[3] + (v[4] if len(v) > 4 else 0), sum(v)

    @staticmethod
    def _read_net():
        rx = tx = 0
        with open("/proc/net/dev") as f:
            for line in f.readlines()[2:]:
                name, _, data = line.partition(":")
                name = name.strip()
                if name.startswith(SKIP_NET):
                    continue
                cols = data.split()
                rx += int(cols[0])
                tx += int(cols[8])
        return time.monotonic(), rx, tx

    def sample(self):
        out = {}
        try:
            idle, total = self._read_cpu()
            if self._cpu and total > self._cpu[1]:
                out["cpu"] = max(0.0, min(1.0, 1.0 - (idle - self._cpu[0]) / float(total - self._cpu[1])))
            else:
                out["cpu"] = 0.0
            self._cpu = (idle, total)
        except (OSError, ValueError, IndexError):
            out["cpu"] = 0.0
        try:
            mem = {}
            with open("/proc/meminfo") as f:
                for line in f:
                    k, _, v = line.partition(":")
                    mem[k] = int(v.split()[0])
            used = mem["MemTotal"] - mem["MemAvailable"]
            out["mem"] = used / float(mem["MemTotal"])
            out["memText"] = "%.1f / %.1f GB" % (used / 1048576.0, mem["MemTotal"] / 1048576.0)
        except (OSError, ValueError, KeyError):
            out["mem"], out["memText"] = 0.0, ""
        t = read_temp()
        out["temp"] = t if t is not None else -1
        try:
            du = shutil.disk_usage("/")
            out["disk"] = du.used / float(du.total)
            out["diskText"] = "%.0f / %.0f GB" % (du.used / 1e9, du.total / 1e9)
        except OSError:
            out["disk"], out["diskText"] = 0.0, ""
        down = up = 0.0
        try:
            now, rx, tx = self._read_net()
            if self._net and now > self._net[0]:
                dt = now - self._net[0]
                down, up = max(0, rx - self._net[1]) / dt, max(0, tx - self._net[2]) / dt
            self._net = (now, rx, tx)
        except (OSError, ValueError, IndexError):
            pass
        out["down"], out["up"] = human_rate(down), human_rate(up)
        return out

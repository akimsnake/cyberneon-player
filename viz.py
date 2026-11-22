"""Visualizer math (no Qt): audio samples -> 40 neon bars.
Needs numpy for live analysis; without it the player falls back to a simulated animation."""
import math

try:
    import numpy as np
except Exception:
    np = None

BARS = 40
FFT_N = 2048


def available():
    return np is not None


def to_mono(raw, kind, channels):
    """Raw PCM bytes -> mono float32 array in [-1, 1]. kind: u8 | s16 | s32 | f32."""
    sizes = {"u8": 1, "s16": 2, "s32": 4, "f32": 4}
    if kind not in sizes:
        raise ValueError("unsupported sample format: %r" % (kind,))
    raw = raw[: len(raw) // sizes[kind] * sizes[kind]]
    if kind == "u8":
        a = (np.frombuffer(raw, dtype=np.uint8).astype(np.float32) - 128.0) / 128.0
    elif kind == "s16":
        a = np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768.0
    elif kind == "s32":
        a = np.frombuffer(raw, dtype="<i4").astype(np.float32) / 2147483648.0
    else:
        a = np.frombuffer(raw, dtype="<f4").astype(np.float32)
    ch = max(1, int(channels))
    usable = a.size // ch * ch
    a = a[:usable]
    return a.reshape(-1, ch).mean(axis=1) if ch > 1 else a


class Analyzer:
    """Log-spaced frequency bands, 40 Hz .. ~16 kHz, levels 0..1 (-70 dB .. 0 dB)."""

    def __init__(self, bars=BARS, n=FFT_N):
        self.bars, self.n = bars, n
        self.window = np.hanning(n).astype(np.float32)
        self._rate, self._idx = None, None

    def _prepare(self, rate):
        freqs = np.fft.rfftfreq(self.n, 1.0 / rate)
        hi = min(16000.0, rate * 0.45)
        edges = np.geomspace(40.0, hi, self.bars + 1)
        idx = []
        for lo, up in zip(edges[:-1], edges[1:]):
            sel = np.nonzero((freqs >= lo) & (freqs < up))[0]
            if sel.size == 0:                      # very narrow low band: use the nearest bin
                sel = np.array([int(np.argmin(np.abs(freqs - (lo + up) / 2)))])
            idx.append(sel)
        self._rate, self._idx = rate, idx

    def levels(self, samples, rate):
        if rate != self._rate:
            self._prepare(rate)
        x = samples[-self.n:]
        if x.size < self.n:
            x = np.concatenate([np.zeros(self.n - x.size, dtype=np.float32), x])
        mag = np.abs(np.fft.rfft(x * self.window)) * (4.0 / self.n)   # full-scale sine ~ 1.0
        peak = np.array([mag[sel].max() for sel in self._idx])
        db = 20.0 * np.log10(peak + 1e-9)
        lv = np.clip((db + 70.0) / 70.0, 0.0, 1.0)
        tilt = np.linspace(0.0, 0.18, self.bars)                      # treble has less energy: lift it a bit
        return [float(v) for v in np.clip(lv * (1.0 + tilt), 0.0, 1.0)]


class Smoother:
    """Fast attack, slow fall, plus falling peak caps."""

    def __init__(self, n=BARS):
        self.v = [0.0] * n
        self.p = [0.0] * n

    def update(self, target):
        for i, t in enumerate(target):
            v = self.v[i]
            v = v + (t - v) * 0.55 if t > v else max(t, v - 0.045)
            self.v[i] = v
            self.p[i] = max(self.p[i] - 0.012, v)
        return self.v, self.p


def simulated(t, n=BARS):
    """Animation used when live audio data is not available."""
    beat = (t * 2.1) % 1.0
    pulse = math.exp(-beat * 4.0)
    out = []
    for i in range(n):
        x = i / max(1, n - 1)
        base = 0.28 + 0.22 * math.sin(t * (2.0 + i * 0.37) + i * 1.3) + 0.15 * math.sin(t * (5.1 - i * 0.05) + i * 0.7)
        bass = pulse * (1.0 - x) ** 1.5 * 0.55
        out.append(max(0.03, min(1.0, base * (0.55 + 0.42 * (1.0 - x)) + bass)))
    return out

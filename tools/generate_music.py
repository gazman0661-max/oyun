#!/usr/bin/env python3
"""Arka plan muzik dongusu (telifsiz, sentez). Kullanim: python tools/generate_music.py
Cikti: assets/music/loop.wav (20 sn, kesintisiz dongu, 22050 Hz mono)."""
import numpy as np
from scipy.io import wavfile

SR = 22050
BPM = 96
BEAT = 60.0 / BPM
BARS = 8
N = int(SR * BEAT * 4 * BARS)
buf = np.zeros(N)


def add(start, sig):
    """Sinyali dongu sonunda basa saracak sekilde ekler (kesintisiz loop)."""
    i = int(start * SR) % N
    end = i + len(sig)
    if end <= N:
        buf[i:end] += sig
    else:
        k = N - i
        buf[i:] += sig[:k]
        buf[: end - N] += sig[k:]


def hz(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def tone(f, dur, att, rel, harm=(1.0, 0.25, 0.08)):
    t = np.arange(int(SR * dur)) / SR
    s = sum(a * np.sin(2 * np.pi * f * (k + 1) * t) for k, a in enumerate(harm))
    env = np.minimum(1, t / max(att, 1e-3)) * np.exp(-t / rel)
    return s * env


chords = [(60, [60, 64, 67]), (57, [57, 60, 64]), (53, [53, 57, 60]), (55, [55, 59, 62])]  # C Am F G
penta = [0, 2, 4, 7, 9, 12, 14, 16]
bar_len = BEAT * 4
for b in range(BARS):
    root, notes = chords[(b // 2) % 4]
    t0 = b * bar_len
    for n in notes:  # yumusak pad
        add(t0, 0.12 * tone(hz(n), bar_len + 0.6, 0.35, 3.0, (1.0, 0.1)))
    add(t0, 0.30 * tone(hz(root - 12), bar_len * 0.9, 0.02, 0.9, (1.0, 0.2)))  # bas
    add(t0 + 2 * BEAT, 0.22 * tone(hz(root - 12), bar_len * 0.45, 0.02, 0.5, (1.0, 0.2)))
    rng = np.random.default_rng(b * 3 + 1)
    for e in range(8):  # sekizlik arpej
        if rng.random() < 0.22:
            continue
        scale_note = root + 12 + int(rng.choice(penta[:6]))
        # akora uydur: pentatonik yerine akor sesleri agirlikli
        if rng.random() < 0.6:
            scale_note = int(rng.choice(notes)) + 12
        add(t0 + e * BEAT / 2, 0.16 * tone(hz(scale_note), 0.6, 0.004, 0.16, (1.0, 0.35, 0.12)))

buf /= np.max(np.abs(buf)) * 1.15
wavfile.write("assets/music/loop.wav", SR, (buf * 32767).astype(np.int16))
print("ok", N / SR, "sn")

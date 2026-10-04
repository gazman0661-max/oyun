#!/usr/bin/env python3
"""
Merge Dünyaları - ses efektlerini SIFIRDAN (sentez ile) uretir.

Neden sentez? Telif derdi yok, dosyalar cok kucuk (toplam ~1 MB) ve
her sesin perdesini/suresini buradan kolayca ayarlayabilirsin.
Sesleri begenmezsen: ya bu dosyadaki sayilari degistirip tekrar calistir,
ya da assets/sfx/ altindaki .wav dosyalarini AYNI ISIMLE kendi
seslerinle degistir (kodda hicbir sey degismez).

Kullanim (proje kokunden):
    pip install numpy scipy
    python tools/generate_sfx.py            # -> assets/sfx/*.wav

Tasarim ilkeleri:
  * Sik duyulan sesler (carpma, atis, kucuk merge) KISA ve yumusak -
    kulak yormasin.
  * Merge sesi seviyeye gore pentatonik gamda YUKSELIR (do-re-mi-sol-la-
    do-mi). Zincirleme merge'ler ust uste binince kendiliginden
    melodi olur, hic falso duymazsin.
  * Nadir/onemli sesler (yeni seviye, bolum sonu) daha uzun, parlak ve
    yankili.
"""
import os
import sys
import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 44100
rng = np.random.default_rng(7)  # sabit tohum: her calistirmada ayni sesler


# ---------------------------------------------------------------- yardimcilar
def n_of(dur):
    return int(SR * dur)


def sine_sweep(f0, f1, dur):
    """f0'dan f1'e ustel perde kaymasi olan sinus."""
    n = n_of(dur)
    t = np.arange(n) / SR
    f = f0 * (f1 / f0) ** (t / dur)
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def exp_env(n, tau, attack=0.002):
    t = np.arange(n) / SR
    env = np.exp(-t / tau)
    a = int(attack * SR)
    if a > 0:
        env[:a] *= np.linspace(0, 1, a)
    return env


def butter(x, kind, cutoff, order=2):
    sos = signal.butter(order, cutoff, btype=kind, fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def place(buf, sig, start, gain=1.0):
    """sig'i buf'a start (sn) noktasindan itibaren ekler. Her parcanin
    sonuna yumusak bir kapanis (kosinus fade) uygulanir - boylece kesilen
    nota/kuyruklar 'tik' sesi cikarmaz."""
    i = int(start * SR)
    if i >= len(buf):
        return
    sig = np.array(sig, dtype=float)
    fo = min(len(sig) // 4, int(0.025 * SR))
    if fo > 1:
        sig[-fo:] *= 0.5 * (1 + np.cos(np.pi * np.linspace(0, 1, fo)))
    j = min(len(buf), i + len(sig))
    buf[i:j] += sig[: j - i] * gain


# yumusak "mallet" (marimba/ksilofon benzeri) partial'lari: (oran, genlik, omur carpani)
MALLET = [(1, 1.0, 1.0), (2, 0.30, 0.55), (3, 0.12, 0.35), (4.2, 0.05, 0.2)]
# cubuk/zil benzeri metalik partial'lar (coin, sparkle icin)
BELL = [(1, 1.0, 1.0), (2.756, 0.45, 0.5), (5.404, 0.20, 0.3), (8.933, 0.08, 0.2)]


def tone(freq, dur, partials, tau, attack=0.003):
    n = n_of(dur)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for ratio, amp, life in partials:
        f = freq * ratio
        if f > SR * 0.45:
            continue
        out += amp * np.sin(2 * np.pi * f * t) * np.exp(-t / (tau * life))
    a = int(attack * SR)
    if a > 0:
        out[:a] *= np.linspace(0, 1, a)
    return out


def soft_synth(freq, dur, attack=0.015, release=0.12, harmonics=6, lp=3200, vibrato=0.0):
    """Yumusak pad/pirinc benzeri: harmonikli testere, alcak geciren filtreli."""
    n = n_of(dur)
    t = np.arange(n) / SR
    vib = 1 + vibrato * np.sin(2 * np.pi * 5.2 * t)
    ph = 2 * np.pi * np.cumsum(freq * vib) / SR
    x = np.zeros(n)
    for h in range(1, harmonics + 1):
        x += np.sin(h * ph) / h
    x = butter(x, "lowpass", lp)
    env = np.ones(n)
    a, r = int(attack * SR), int(release * SR)
    env[:a] = np.linspace(0, 1, max(a, 1))
    env[-r:] *= np.linspace(1, 0, r)
    return x * env


def sweep_bandpass_noise(dur, f0, f1, q=1.2):
    """Merkez frekansi f0->f1 kayan bant-geciren gurultu (whoosh)."""
    n = n_of(dur)
    x = rng.standard_normal(n)
    y = np.zeros(n)
    low = band = 0.0
    qd = 1.0 / q
    for i in range(n):
        f = f0 * (f1 / f0) ** (i / n)
        F = 2 * np.sin(np.pi * f / SR)
        low += F * band
        high = x[i] - low - qd * band
        band += F * high
        y[i] = band
    return y


def reverb(x, wet=0.25, decay=0.5, lp=6000):
    """Basit sentetik yankı: ustel sonumlu gurultu ile konvolusyon."""
    ir_n = n_of(decay)
    t = np.arange(ir_n) / SR
    ir = rng.standard_normal(ir_n) * np.exp(-t / (decay * 0.28))
    ir = butter(ir, "lowpass", lp)
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
    tail = signal.fftconvolve(x, ir)
    out = np.zeros(len(tail))
    out[: len(x)] += x
    out += wet * tail
    return out


def finish(x, peak, wet=0.0, decay=0.4, fade_ms=8, trim_db=-42):
    if wet > 0:
        x = reverb(x, wet=wet, decay=decay)
    x = x - np.mean(x)
    # sondaki sessizligi kirp
    amp = np.abs(x)
    thr = np.max(amp) * (10 ** (trim_db / 20))
    idx = np.where(amp > thr)[0]
    if len(idx):
        x = x[: idx[-1] + 1]
    # tiklama olmasin: 1 ms fade-in, sonda fade-out
    fi = int(0.001 * SR)
    x[:fi] *= np.linspace(0, 1, fi)
    fo = min(len(x), int(fade_ms / 1000 * SR))
    x[-fo:] *= np.linspace(1, 0, fo)
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    return x


# ---------------------------------------------------------------- sesler
def make_throw():
    dur = 0.30
    n = n_of(dur)
    t = np.arange(n) / SR
    w = sweep_bandpass_noise(dur, 700, 3800, q=1.1)
    env = np.minimum(1, t / 0.035) * np.exp(-np.maximum(t - 0.035, 0) / 0.085)
    w = w / (np.max(np.abs(w)) + 1e-9) * env
    body = sine_sweep(560, 240, dur) * np.exp(-t / 0.05)
    return finish(w * 0.85 + body * 0.35, 0.55)


def make_hit(f0, f1, tau, noise_hp, noise_tau, click, dur, p2=0.35):
    n = n_of(dur)
    t = np.arange(n) / SR
    body = sine_sweep(f0, f1, dur) * np.exp(-t / tau)
    body2 = sine_sweep(f0 * 2.1, f1 * 2.1, dur) * np.exp(-t / (tau * 0.5)) * p2
    noise = butter(rng.standard_normal(n), "highpass", noise_hp) * np.exp(-t / noise_tau) * click
    return finish(body + body2 + noise, 0.8, fade_ms=6)


def make_wall():
    dur = 0.17
    n = n_of(dur)
    t = np.arange(n) / SR
    body = sine_sweep(200, 105, dur) * np.exp(-t / 0.05)
    noise = butter(rng.standard_normal(n), "lowpass", 1400) * np.exp(-t / 0.02) * 0.6
    return finish(body + noise, 0.6, fade_ms=8)


MERGE_NOTES = [523.25, 587.33, 659.25, 783.99, 880.00, 1046.50, 1318.51]  # C5 D5 E5 G5 A5 C6 E6


def make_merge(level):
    idx = level - 2
    f = MERGE_NOTES[idx]
    dur = 0.36 + 0.07 * idx
    x = np.zeros(n_of(dur) + n_of(0.1))
    # 1) baloncuk "pop" - perde asagi kayan kisa sinus
    pop = sine_sweep(f * 2.4, f, 0.09) * exp_env(n_of(0.09), 0.03)
    place(x, pop, 0.0, 0.55)
    # 2) mallet ile asil nota
    place(x, tone(f, dur, MALLET, 0.10 + 0.03 * idx), 0.012, 0.75)
    # 3) yukseldikce zenginlesen katmanlar
    if idx >= 3:
        place(x, tone(f * 2, dur * 0.7, MALLET, 0.08), 0.045, 0.28)
    if idx >= 5:
        place(x, tone(f * 1.5, dur * 0.8, MALLET, 0.10), 0.03, 0.25)
    return finish(x, 0.85, wet=0.16 + 0.03 * idx, decay=0.30 + 0.06 * idx)


def make_merge_max():
    x = np.zeros(n_of(1.6))
    for k, f in enumerate([1046.5, 1318.51, 1567.98, 2093.0]):
        place(x, tone(f, 1.2, MALLET, 0.35), 0.05 * k, 0.55)
    place(x, sine_sweep(2400, 500, 0.12) * exp_env(n_of(0.12), 0.04), 0.0, 0.5)
    for k, f in enumerate([2637, 3136, 3520, 4186, 3136, 4186]):
        place(x, tone(f, 0.5, BELL, 0.10), 0.30 + 0.09 * k, 0.16)
    return finish(x, 0.95, wet=0.32, decay=0.9)


def make_coin():
    x = np.zeros(n_of(0.6))
    place(x, tone(987.77, 0.35, BELL, 0.16, attack=0.001), 0.0, 0.7)
    place(x, tone(1318.51, 0.5, BELL, 0.28, attack=0.001), 0.075, 0.85)
    place(x, tone(2637.0, 0.3, BELL, 0.10, attack=0.001), 0.075, 0.18)
    return finish(x, 0.8, wet=0.12, decay=0.35)


def make_new_tier():
    x = np.zeros(n_of(1.3))
    w = sweep_bandpass_noise(0.22, 500, 5000, q=1.4)
    w = w / (np.max(np.abs(w)) + 1e-9) * np.minimum(1, np.arange(len(w)) / SR / 0.1) * np.exp(-np.arange(len(w)) / SR / 0.12)
    place(x, w, 0.0, 0.25)
    for k, f in enumerate([523.25, 659.25, 783.99, 1046.5, 1318.51]):
        place(x, tone(f, 0.9, MALLET, 0.22), 0.09 * k + 0.05, 0.5 + 0.06 * k)
    place(x, tone(2093.0, 0.6, BELL, 0.16), 0.5, 0.18)
    return finish(x, 0.9, wet=0.28, decay=0.8)


def make_chapter_complete():
    x = np.zeros(n_of(3.0))
    # kisa fanfar (G4 C5 E5)
    for k, f in enumerate([392.0, 523.25, 659.25]):
        place(x, soft_synth(f, 0.20, attack=0.012, release=0.08, harmonics=7, lp=3600), 0.12 * k, 0.5)
        place(x, tone(f * 2, 0.3, MALLET, 0.10), 0.12 * k, 0.25)
    # uzun akor (C5 E5 G5 C6) + mallet parlaklik
    for f in [523.25, 659.25, 783.99, 1046.5]:
        place(x, soft_synth(f, 1.5, attack=0.03, release=0.9, harmonics=5, lp=2800), 0.40, 0.30)
        place(x, tone(f, 1.3, MALLET, 0.45), 0.40, 0.30)
    # yukselen kivilcimlar
    for k, f in enumerate([1046.5, 1318.51, 1567.98, 2093.0, 2637.0, 3136.0]):
        place(x, tone(f, 0.7, BELL, 0.16), 0.95 + 0.085 * k, 0.16)
    return finish(x, 0.95, wet=0.30, decay=1.1, fade_ms=40)


def make_game_over():
    x = np.zeros(n_of(1.8))
    # yumusak "ahh" - alçalan uc nota, sert degil
    for f, s, d in [(329.63, 0.0, 0.42), (261.63, 0.34, 0.42), (220.0, 0.68, 0.95)]:
        place(x, soft_synth(f, d, attack=0.03, release=d * 0.6, harmonics=4, lp=1700, vibrato=0.004), s, 0.42)
    # basta hafif "tok"
    thud = sine_sweep(170, 70, 0.2) * exp_env(n_of(0.2), 0.07)
    place(x, thud, 0.0, 0.55)
    return finish(x, 0.70, wet=0.16, decay=0.6, fade_ms=40)


def make_tap():
    dur = 0.09
    n = n_of(dur)
    t = np.arange(n) / SR
    body = sine_sweep(1500, 1000, dur) * np.exp(-t / 0.018)
    click = butter(rng.standard_normal(n), "highpass", 3000) * np.exp(-t / 0.004) * 0.3
    return finish(body + click, 0.5, fade_ms=4)


def make_reward():
    x = np.zeros(n_of(1.0))
    for k, f in enumerate([783.99, 987.77, 1174.66, 1567.98, 1975.53]):
        place(x, tone(f, 0.6, BELL, 0.18, attack=0.001), 0.06 * k, 0.5)
        place(x, tone(f * 2, 0.3, MALLET, 0.08), 0.06 * k, 0.12)
    return finish(x, 0.85, wet=0.25, decay=0.6)


def make_denied():
    x = np.zeros(n_of(0.35))
    for s in (0.0, 0.11):
        b = sine_sweep(250, 190, 0.12) * exp_env(n_of(0.12), 0.05)
        b += 0.3 * sine_sweep(500, 380, 0.12) * exp_env(n_of(0.12), 0.03)
        place(x, b, s, 0.6)
    return finish(x, 0.55, fade_ms=10)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sfx")
    os.makedirs(out, exist_ok=True)
    sounds = {
        "throw": make_throw(),
        # seviyeye gore 4 carpma sesi: 1=ince tik ... 4=derin tok
        "hit_1": make_hit(2000, 1500, 0.018, 4000, 0.006, 0.5, 0.10),
        "hit_2": make_hit(1100, 800, 0.035, 3000, 0.008, 0.45, 0.14),
        "hit_3": make_hit(620, 430, 0.055, 2000, 0.010, 0.40, 0.18),
        "hit_4": make_hit(260, 130, 0.090, 1200, 0.012, 0.35, 0.26, p2=0.2),
        "wall": make_wall(),
        "coin": make_coin(),
        "new_tier": make_new_tier(),
        "merge_max": make_merge_max(),
        "chapter_complete": make_chapter_complete(),
        "game_over": make_game_over(),
        "tap": make_tap(),
        "reward": make_reward(),
        "denied": make_denied(),
    }
    for lvl in range(2, 9):
        sounds[f"merge_{lvl}"] = make_merge(lvl)
    for name, x in sounds.items():
        pcm = np.int16(np.clip(x, -1, 1) * 32767)
        path = os.path.join(out, f"{name}.wav")
        wavfile.write(path, SR, pcm)
        print(f"{name:18s} {len(pcm) / SR:5.2f}s  {os.path.getsize(path) // 1024:4d} KB")


if __name__ == "__main__":
    main()

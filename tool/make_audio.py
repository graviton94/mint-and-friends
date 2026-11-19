#!/usr/bin/env python3
"""게임 BGM / 효과음을 직접 작곡·합성해서 assets/audio/*.ogg 로 만든다.

  python3 tool/make_audio.py            # 전부 생성 + 검사 결과 출력
  python3 tool/make_audio.py --check    # 생성하지 않고 기존 파일만 검사

외부 샘플 없이 numpy/scipy 로만 합성한다(결과는 시드 고정이라 재현 가능).
- 악보: 멜로디/코드/베이스/퍼커션을 노트 데이터(박 단위)로 적어 둔다.
- 악기: 가산합성 마림바·칼림바, 셀레스타 벨, 디튠 패드(웨이브테이블), 플럭 베이스,
  브러시/셰이커/소프트 킥(필터 노이즈).
- 이펙트: 합성 IR 컨볼루션 리버브, 핑퐁 딜레이, 로우패스, 부드러운 컴프레서.
- 루프: 선형 처리(악기·필터·리버브·딜레이)는 꼬리까지 렌더한 뒤 꼬리를 앞쪽에 겹쳐
  원형으로 만들고, 비선형 마스터(컴프)는 3번 이어 붙여 가운데만 쓰므로 루프 경계가 매끈하다.
- 음량: BGM -16 LUFS(통합), 효과음은 조금 더 크게, 피크는 -1 dBFS 이하.
인코딩은 ffmpeg(libvorbis), BGM 스테레오 / 효과음 모노, 44.1 kHz.
"""
import os
import subprocess
import sys
import tempfile

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, fftconvolve, lfilter, sosfilt

SR = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "audio")
FFMPEG = "/usr/bin/ffmpeg" if os.path.exists("/usr/bin/ffmpeg") else "ffmpeg"

rng = np.random.default_rng(20261119)

# ---------------------------------------------------------------------------
# 공통 유틸
# ---------------------------------------------------------------------------
NOTE_PC = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def midi(name):
    """'C5', 'Bb4', 'F#3' -> MIDI 번호 (C4 = 60)."""
    pc = NOTE_PC[name[0]]
    i = 1
    while i < len(name) and name[i] in "b#":
        pc += -1 if name[i] == "b" else 1
        i += 1
    return pc + 12 * (int(name[i:]) + 1)


def hz(m):
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


def tvec(dur):
    return np.arange(int(round(dur * SR))) / SR


def db(x):
    return 20 * np.log10(max(x, 1e-12))


def lowpass(x, fc, order=2):
    return sosfilt(butter(order, fc, "low", fs=SR, output="sos"), x, axis=-1)


def highpass(x, fc, order=2):
    return sosfilt(butter(order, fc, "high", fs=SR, output="sos"), x, axis=-1)


def bandpass(x, lo, hi, order=2):
    return sosfilt(butter(order, [lo, hi], "band", fs=SR, output="sos"), x, axis=-1)


def adsr(n, a=0.005, d=0.1, s=0.7, r=0.1, hold=None):
    """샘플 수 n 짜리 ADSR. hold(초)까지 서스테인 후 r 동안 릴리스."""
    t = np.arange(n) / SR
    hold = (n / SR - r) if hold is None else hold
    env = np.where(t < a, t / max(a, 1e-6), s + (1 - s) * np.exp(-(t - a) / max(d, 1e-6)))
    rel = np.clip(1 - (t - hold) / max(r, 1e-6), 0, 1)
    return env * np.where(t > hold, rel, 1.0)


def fade(x, fin=0.002, fout=0.01):
    x = x.copy()
    a, b = int(fin * SR), int(fout * SR)
    if a:
        x[..., :a] *= np.linspace(0, 1, a)
    if b:
        x[..., -b:] *= np.linspace(1, 0, b) ** 2
    return x


def mix_into(buf, sig, start_s, gain=1.0):
    i = int(round(start_s * SR))
    if i < 0:
        sig, i = sig[-i:], 0
    j = min(len(buf), i + len(sig))
    if j > i:
        buf[i:j] += gain * sig[: j - i]


def pan2(mono, p):
    """등파워 팬. p: -1(왼) ~ 1(오)."""
    a = (p + 1) * np.pi / 4
    return np.stack([mono * np.cos(a), mono * np.sin(a)])


# ---------------------------------------------------------------------------
# 악기
# ---------------------------------------------------------------------------
def marimba(f, vel=0.8, dur=1.4, bright=1.0):
    """가산합성 마림바: 기음 + 4배(튜닝 바) + 9.9배 부분음, 고역일수록 빨리 감쇠."""
    t = tvec(dur)
    tau = 0.55 * (330.0 / f) ** 0.35
    partials = [(1.0, 1.0, tau), (3.98, 0.22 * bright, tau * 0.22), (9.85, 0.05 * bright, tau * 0.07)]
    y = np.zeros_like(t)
    for ratio, amp, tt in partials:
        if f * ratio < SR * 0.45:
            y += amp * np.sin(2 * np.pi * f * ratio * t + rng.uniform(0, 0.3)) * np.exp(-t / tt)
    # 말렛 타격음(아주 짧은 필터 노이즈)
    click = lowpass(rng.standard_normal(len(t)), min(4 * f, 6000)) * np.exp(-t / 0.004) * 0.08 * bright
    y = (y + click) * np.clip(t / 0.003, 0, 1)
    return fade(y * vel, 0, 0.05)


def kalimba(f, vel=0.8, dur=1.2):
    """칼림바: 기음 + 약간 비조화 부분음(5.4, 13.9) + 아주 짧은 디튠 비트."""
    t = tvec(dur)
    tau = 0.7 * (440.0 / f) ** 0.3
    y = np.sin(2 * np.pi * f * t) * np.exp(-t / tau)
    y += 0.5 * np.sin(2 * np.pi * f * 1.003 * t) * np.exp(-t / (tau * 0.8))
    y += 0.14 * np.sin(2 * np.pi * f * 5.4 * t) * np.exp(-t / (tau * 0.12))
    if f * 13.9 < SR * 0.45:
        y += 0.03 * np.sin(2 * np.pi * f * 13.9 * t) * np.exp(-t / 0.01)
    y *= np.clip(t / 0.002, 0, 1)
    return fade(y * vel / 1.5, 0, 0.05)


def bell(f, vel=0.6, dur=2.0):
    """셀레스타/글로켄 느낌의 부드러운 벨(가산합성, 부분음 2, 3, 4.16)."""
    t = tvec(dur)
    tau = 0.9 * (660.0 / f) ** 0.4
    y = np.sin(2 * np.pi * f * t) * np.exp(-t / tau)
    y += 0.28 * np.sin(2 * np.pi * f * 2.0 * t + 0.4) * np.exp(-t / (tau * 0.45))
    if f * 3 < SR * 0.45:
        y += 0.09 * np.sin(2 * np.pi * f * 3.0 * t + 1.1) * np.exp(-t / (tau * 0.22))
    if f * 4.16 < SR * 0.45:
        y += 0.05 * np.sin(2 * np.pi * f * 4.16 * t) * np.exp(-t / (tau * 0.1))
    y *= np.clip(t / 0.004, 0, 1)
    return fade(y * vel, 0, 0.08)


_SAW_TABLE = None


def _soft_saw_table():
    """하모닉 1..12, 1/n^1.4 로 깎은 부드러운 톱니 테이블."""
    global _SAW_TABLE
    if _SAW_TABLE is None:
        ph = np.arange(4096) / 4096
        tab = sum(np.sin(2 * np.pi * k * ph) / k ** 1.4 for k in range(1, 13))
        _SAW_TABLE = tab / np.max(np.abs(tab))
    return _SAW_TABLE


def pad_voice(f, dur, attack=0.7, release=1.4, detune_cents=0.0):
    tab = _soft_saw_table()
    n = int((dur + release) * SR)
    t = np.arange(n) / SR
    fr = f * 2 ** (detune_cents / 1200) * (1 + 0.0015 * np.sin(2 * np.pi * 0.21 * t + rng.uniform(0, 6)))
    phase = (np.cumsum(fr) / SR + rng.uniform()) % 1.0
    y = np.interp(phase * 4096, np.arange(4097), np.append(tab, tab[0]))
    env = np.minimum(np.clip(t / attack, 0, 1) ** 1.5, 1.0)
    env *= np.where(t > dur, np.clip(1 - (t - dur) / release, 0, 1) ** 2, 1.0)
    trem = 1 + 0.06 * np.sin(2 * np.pi * 0.33 * t + rng.uniform(0, 6))
    return y * env * trem


def pluck_bass(f, vel=0.8, dur=0.6):
    """둥근 플럭 베이스: 사인 + 2·3배음, 빠른 감쇠 후 짧은 릴리스."""
    rel = 0.09
    t = tvec(dur + rel)
    body = np.exp(-t / 0.55)
    y = np.sin(2 * np.pi * f * t) * body
    y += 0.4 * np.sin(2 * np.pi * 2 * f * t) * np.exp(-t / 0.25)
    y += 0.15 * np.sin(2 * np.pi * 3 * f * t) * np.exp(-t / 0.12)
    y *= np.clip(t / 0.006, 0, 1) * np.where(t > dur, np.clip(1 - (t - dur) / rel, 0, 1), 1.0)
    return y * vel


def shaker(vel=0.5):
    t = tvec(0.12)
    n = bandpass(rng.standard_normal(len(t)), 5000, 11000)
    env = np.clip(t / 0.008, 0, 1) * np.exp(-t / 0.035)
    return fade(n * env * vel, 0, 0.01)


def brush(vel=0.5):
    t = tvec(0.35)
    n = bandpass(rng.standard_normal(len(t)), 900, 5000)
    env = np.clip(t / 0.012, 0, 1) * (0.7 * np.exp(-t / 0.05) + 0.3 * np.exp(-t / 0.16))
    return fade(n * env * vel * 0.8, 0, 0.02)


def soft_kick(vel=0.6):
    t = tvec(0.35)
    f = 52 + 60 * np.exp(-t / 0.03)
    y = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.13) * np.clip(t / 0.003, 0, 1)
    return fade(y * vel, 0, 0.03)


# ---------------------------------------------------------------------------
# 이펙트
# ---------------------------------------------------------------------------
def reverb_ir(seconds=2.4, predelay=0.018, seed=7, damp=0.5):
    """스테레오 합성 IR: 감쇠 노이즈 두 대역(고역은 빨리 사라짐) + 초기 반사."""
    r = np.random.default_rng(seed)
    n = int(seconds * SR)
    t = np.arange(n) / SR
    chans = []
    for _ in range(2):
        noise = r.standard_normal(n)
        lo = lowpass(noise, 2500) * np.exp(-t / (seconds / 6.9 * 1.0))
        hi = highpass(noise, 2500) * np.exp(-t / (seconds / 6.9 * damp))
        ir = lo + 0.5 * hi
        er = np.zeros(n)
        for d in r.uniform(0.005, 0.06, 8):
            er[int(d * SR)] += r.uniform(-0.6, 0.6)
        ir = ir * np.clip(t / 0.02, 0, 1) + er
        ir = np.concatenate([np.zeros(int(predelay * SR)), ir])
        chans.append(ir / np.sqrt(np.sum(ir ** 2)))
    return np.stack(chans)


def apply_reverb(x, ir):
    """x: (2, n) 또는 (n,) -> 같은 길이 + IR 길이의 웻 신호."""
    if x.ndim == 1:
        return fftconvolve(x, ir[0])
    return np.stack([fftconvolve(x[0], ir[0]), fftconvolve(x[1], ir[1])])


def pingpong(x, delay_s, fb=0.35, taps=5, lp=3500):
    """x: (2, n). 좌우 번갈아 울리는 피드백 딜레이(유한 탭, 탭마다 로우패스)."""
    n = x.shape[1]
    d = int(delay_s * SR)
    out = np.zeros((2, n + d * taps))
    mono = x.mean(axis=0)
    sig = mono
    for k in range(1, taps + 1):
        sig = lowpass(sig, lp, 1)
        out[k % 2, d * k: d * k + n] += sig * fb ** k
    return out


def k_weight(x):
    """ITU-R BS.1770 K 가중 필터(임의 샘플레이트 계수)."""
    f0, G, Q = 1681.974450955533, 3.999843853973347, 0.7071752369554196
    K = np.tan(np.pi * f0 / SR)
    Vh, Vb = 10 ** (G / 20), 10 ** (G / 20) ** 0.4996667741545416
    a0 = 1 + K / Q + K * K
    b1 = [(Vh + Vb * K / Q + K * K) / a0, 2 * (K * K - Vh) / a0, (Vh - Vb * K / Q + K * K) / a0]
    a1 = [1, 2 * (K * K - 1) / a0, (1 - K / Q + K * K) / a0]
    f0, Q = 38.13547087602444, 0.5003270373238773
    K = np.tan(np.pi * f0 / SR)
    a0 = 1 + K / Q + K * K
    a2 = [1, 2 * (K * K - 1) / a0, (1 - K / Q + K * K) / a0]
    return lfilter([1, -2, 1], a2, lfilter(b1, a1, x, axis=-1), axis=-1)


def loudness(x, block=0.4):
    """게이트 적용 통합 라우드니스(LUFS). x: (n,) 또는 (ch, n)."""
    x = np.atleast_2d(x)
    y = k_weight(x)
    bl = int(block * SR)
    hop = max(1, bl // 4)
    if y.shape[1] < bl:
        y = np.pad(y, ((0, 0), (0, bl - y.shape[1])))
    starts = range(0, y.shape[1] - bl + 1, hop)
    z = np.array([np.sum(np.mean(y[:, s:s + bl] ** 2, axis=1)) for s in starts])
    lk = -0.691 + 10 * np.log10(z + 1e-20)
    z = z[lk > -70]
    if len(z) == 0:
        return -70.0
    rel = -0.691 + 10 * np.log10(np.mean(z)) - 10
    z = z[(-0.691 + 10 * np.log10(z)) > rel]
    return float(-0.691 + 10 * np.log10(np.mean(z)))


def compress(x, thresh_db=-20, ratio=2.0, win=0.06):
    """RMS 기반의 부드러운 컴프레서(소프트니, 대칭 스무딩)."""
    mono = np.atleast_2d(x).mean(axis=0)
    a = np.exp(-1 / (win * SR))
    ms = lfilter([1 - a], [1, -a], mono ** 2)
    lvl = 10 * np.log10(ms + 1e-12)
    over = np.maximum(lvl - thresh_db, 0)
    knee = 6.0
    over = np.where(over < knee, over ** 2 / (2 * knee), over - knee / 2)
    gain = 10 ** (-over * (1 - 1 / ratio) / 20)
    return x * gain


def normalize(x, target_lufs, peak_db=-1.0, block=0.4):
    g = 10 ** ((target_lufs - loudness(x, block)) / 20)
    x = x * g
    pk = np.max(np.abs(x))
    lim = 10 ** (peak_db / 20)
    if pk > lim:
        x = x * (lim / pk)
    return x


# ---------------------------------------------------------------------------
# BGM 악보 (D 장조, 110 BPM, 4/4, 32마디 ≈ 69.8초) - 밝고 통통 튀는 느낌
# ---------------------------------------------------------------------------
BPM = 110
BEAT = 60.0 / BPM
BAR = 4 * BEAT

CHORDS = {  # 근음 pc, 구성음 간격
    "Dadd9": (2, [0, 4, 7, 14]), "D6": (2, [0, 4, 7, 9]), "Bm7": (11, [0, 3, 7, 10]),
    "Gmaj7": (7, [0, 4, 7, 11]), "A7sus": (9, [0, 5, 7, 10]), "A7": (9, [0, 4, 7, 10]),
    "F#m7": (6, [0, 3, 7, 10]), "Em7": (4, [0, 3, 7, 10]), "A": (9, [0, 4, 7]),
    "Asus": (9, [0, 5, 7]), "Em9": (4, [0, 3, 7, 10, 14]), "G6": (7, [0, 4, 7, 9]),
}

# 마디별 코드: [(이름, 박수)]
A_PROG = [[("Dadd9", 4)], [("Bm7", 4)], [("Gmaj7", 4)], [("A7sus", 2), ("A7", 2)],
          [("D6", 4)], [("F#m7", 4)], [("Gmaj7", 4)], [("Em7", 2), ("A7", 2)]]
B_PROG = [[("Gmaj7", 4)], [("A", 4)], [("F#m7", 4)], [("Bm7", 4)],
          [("Em9", 4)], [("F#m7", 4)], [("G6", 4)], [("Asus", 2), ("A7", 2)]]

# 멜로디(음이름:박). 8분 당김음이 많은 통통 튀는 선율, 마림바는 스타카토로 연주.
MEL_A = [
    "A4:.5 D5:.5 F#5:.5 A5:1 F#5:.5 A5:1",
    "B5:.5 A5:.5 F#5:1 D5:.5 F#5:1 r:.5",
    "G5:.5 F#5:.5 E5:.5 D5:.5 B4:1 D5:1",
    "E5:1.5 D5:.5 C#5:.5 E5:1 r:.5",
    "A4:.5 D5:.5 F#5:.5 A5:1 B5:.5 A5:1",
    "C#6:.5 A5:.5 F#5:1 E5:.5 C#5:1 r:.5",
    "D5:.5 E5:.5 F#5:.5 G5:1 F#5:.5 E5:1",
    "B4:.5 C#5:.5 D5:.5 E5:.5 G5:.5 F#5:.5 E5:1",
]
MEL_A2_TAIL = [  # A' 의 5~8마디 변주
    "F#5:.5 A5:.5 D6:1 A5:.5 F#5:1 r:.5",
    "E5:.5 F#5:.5 A5:1.5 F#5:.5 C#5:1",
    "B4:.5 D5:.5 G5:1 F#5:.5 D5:.5 B4:1",
    "C#5:1 E5:.5 G5:.5 F#5:2",
]
MEL_B = [
    "B5:1.5 A5:.5 G5:1 D5:1",
    "E5:1.5 F#5:.5 E5:1 C#5:1",
    "F#5:.5 A5:1 C#6:.5 A5:1 E5:1",
    "D6:1.5 C#6:.5 B5:1 F#5:1",
    "G5:.5 F#5:.5 E5:1 B4:.5 E5:1 r:.5",
    "F#5:1.5 E5:.5 C#5:1 A4:1",
    "B4:.5 D5:.5 G5:1 F#5:.5 G5:.5 A5:1",
    "A5:1.5 G5:.5 E5:1 C#5:.5 E5:.5",
]


def parse_bar(s):
    out, beat = [], 0.0
    for tok in s.split():
        name, d = tok.split(":")
        d = float(d)
        if name != "r":
            out.append((beat, d, midi(name)))
        beat += d
    assert abs(beat - 4) < 1e-6, (s, beat)
    return out


def chord_notes(name, lo=55):
    root, iv = CHORDS[name]
    notes = sorted({lo + ((root + i - lo) % 12) for i in iv})
    return notes, root


def staccato(y, gate_s, rel=0.05):
    """gate_s 이후 rel 동안 빠르게 줄여 짧게 끊는다(스타카토/피치카토)."""
    t = np.arange(len(y)) / SR
    return y * np.clip(1 - (t - gate_s) / rel, 0, 1)


def render_bgm():
    sections = [("A", A_PROG, MEL_A), ("A2", A_PROG, MEL_A[:4] + MEL_A2_TAIL),
                ("B", B_PROG, MEL_B), ("A3", A_PROG, MEL_A)]
    n_bars = 8 * len(sections)
    loop_len = int(round(n_bars * BAR * SR))
    total = loop_len + int(9 * SR)  # 리버브·딜레이·릴리스 꼬리 여유

    bus = {k: np.zeros(total) for k in ["mar", "kal", "bell", "bass", "shk", "brs", "kick"]}
    pad = np.zeros((2, total))

    def hum():  # 사람 손 느낌의 미세한 타이밍 흔들림
        return rng.normal(0, 0.005)

    swing = 0.04 * BEAT  # 8분 뒷박을 살짝 늦춰 통통 튀게

    def at(t0, b):  # 박 위치 -> 초 (뒷박 8분에 스윙)
        frac = b % 1.0
        return t0 + b * BEAT + (swing if abs(frac - 0.5) < 1e-6 else 0.0)

    bar_i = 0
    for sec, prog, mel in sections:
        for b in range(8):
            t0 = bar_i * BAR
            # --- 코드 / 패드 / 베이스
            beat = 0.0
            for name, nb in prog[b]:
                cs = t0 + beat * BEAT
                notes, root = chord_notes(name)
                dur = nb * BEAT
                for m in notes:
                    for det, p in [(-7, -0.7), (0, 0.0), (7, 0.7)]:
                        y = pad_voice(hz(m), dur + 0.05, attack=0.5, release=1.0,
                                      detune_cents=det + rng.normal(0, 1.5)) * 0.04
                        i = int(round(cs * SR))
                        seg = pan2(y, p)
                        j = min(total, i + seg.shape[1])
                        pad[:, i:j] += seg[:, : j - i]
                # 장난스러운 베이스: 근음 - 옥타브 튕김 - 5도, 당김음
                rb = 36 + ((root - 36) % 12)
                if rb > 43:
                    rb -= 12
                if nb == 4:
                    pat = [(0, .45, rb, .9), (1, .3, rb + 12, .5), (1.5, .4, rb + 7, .6),
                           (2.5, .4, rb, .75), (3, .3, rb + 7, .5), (3.5, .35, rb + 12, .55)]
                else:
                    pat = [(0, .45, rb, .85), (1, .3, rb + 12, .5), (1.5, .4, rb + 7, .55)]
                for bb, d, m, v in pat:
                    mix_into(bus["bass"], pluck_bass(hz(m), v, d * BEAT), at(cs, bb) + hum())
                beat += nb

            # --- 멜로디: A 계열은 스타카토 마림바(+A3 는 벨 옥타브 더블), B 는 벨 리드 + 칼림바
            for nb_, d, m in parse_bar(mel[b]):
                st = at(t0, nb_) + hum()
                acc = 1.0 if nb_ in (0.0, 2.0) else 0.88
                v = acc * rng.uniform(0.85, 1.0)
                gate = min(d, 1.0) * BEAT * 0.6
                if sec == "B":
                    mix_into(bus["bell"], bell(hz(m), 0.5 * v, max(1.2, d * BEAT + 0.8)), st)
                    mix_into(bus["kal"], staccato(kalimba(hz(m - 12), 0.25 * v), gate), st)
                else:
                    mix_into(bus["mar"], staccato(marimba(hz(m), 0.75 * v), gate + 0.05, 0.08), st)
                    if sec == "A3" and nb_ in (0.0, 2.0):
                        mix_into(bus["bell"], bell(hz(m + 12), 0.16 * v, 1.2), st)

            # --- 반주: 뒷박 피치카토 코드(칼림바), B 는 8분 아르페지오, A2/A3 는 벨 반짝이
            notes, _ = chord_notes(prog[b][0][0], lo=62)
            if sec == "B":
                order = [0, 1, 2, 3, 2, 1, 2, 3]
                for k in range(8):
                    src = prog[b][-1][0] if k >= 4 else prog[b][0][0]
                    ns = chord_notes(src, lo=62)[0]
                    m = ns[order[k] % len(ns)]
                    mix_into(bus["kal"], staccato(kalimba(hz(m), 0.3 if k % 2 == 0 else 0.22), 0.12),
                             at(t0, k * 0.5) + hum())
            else:
                for bb in (0.5, 1.5, 2.5, 3.5):  # 뒷박 "칙" 피치카토 화음
                    src = prog[b][-1][0] if bb > 2 else prog[b][0][0]
                    for m in chord_notes(src, lo=62)[0][:3]:
                        mix_into(bus["kal"], staccato(kalimba(hz(m), 0.11), 0.07, 0.04), at(t0, bb) + hum())
                if sec in ("A2", "A3"):
                    hi = [m + 12 for m in notes]
                    for bb, idx in [(1.5, 1), (3.5, 2)]:
                        mix_into(bus["bell"], bell(hz(hi[idx % len(hi)]), 0.1, 1.0), at(t0, bb) + hum())

            # --- 퍼커션: 셰이커 8분(스윙), A2/A3 는 킥(당김음)+브러시, B 는 브러시만
            for k in range(8):
                mix_into(bus["shk"], shaker(0.5 if k % 2 == 0 else 0.34) * rng.uniform(0.85, 1.0), at(t0, k * 0.5))
            if sec != "A" or b % 2 == 1:
                for bb in (1, 3):
                    mix_into(bus["brs"], brush(0.5 if sec != "B" else 0.38), t0 + bb * BEAT + hum())
            if sec in ("A2", "A3"):
                for bb in (0, 1.5, 2.5) if b % 2 else (0, 2.5):
                    mix_into(bus["kick"], soft_kick(0.7), at(t0, bb))
            bar_i += 1

    # --- 버스 처리 + 스테레오 믹스
    mar = lowpass(bus["mar"], 5000)
    kal = lowpass(bus["kal"], 4500)
    bel = lowpass(bus["bell"], 7000)
    bass = lowpass(bus["bass"], 900)
    padf = lowpass(pad, 1700)
    padf = highpass(padf, 120)

    dry = (pan2(mar, -0.18) * 0.9 + pan2(kal, 0.25) * 0.8 + pan2(bel, 0.3) * 0.75
           + pan2(bass, 0.0) * 0.85 + padf * 1.0
           + pan2(bus["shk"], 0.35) * 0.09 + pan2(bus["brs"], -0.2) * 0.12 + pan2(bus["kick"], 0.0) * 0.35)

    send = pan2(mar, -0.18) * 0.35 + pan2(kal, 0.25) * 0.4 + pan2(bel, 0.3) * 0.55 + padf * 0.35
    dly = pingpong(pan2(mar, 0) * 0.5 + pan2(bel, 0) * 0.6, 0.75 * BEAT, fb=0.3, taps=4)
    wet = apply_reverb(send, reverb_ir(2.6))
    n = max(total, dly.shape[1], wet.shape[1])
    mixbuf = np.zeros((2, n))
    mixbuf[:, :total] += dry
    mixbuf[:, : dly.shape[1]] += dly * 0.22
    mixbuf[:, : wet.shape[1]] += wet * 0.32

    # --- 꼬리를 앞쪽으로 겹쳐 원형 루프로
    loop = mixbuf[:, :loop_len].copy()
    tail = mixbuf[:, loop_len:]
    for k in range(0, tail.shape[1], loop_len):
        seg = tail[:, k:k + loop_len]
        loop[:, : seg.shape[1]] += seg

    # --- 비선형 마스터 체인은 3배로 이어 붙여 가운데만(경계 연속)
    tri = np.concatenate([loop, loop, loop], axis=1)
    tri = highpass(tri, 35)
    tri = compress(tri, thresh_db=-22, ratio=2.0)
    out = tri[:, loop_len:2 * loop_len]
    return normalize(out, -16.0, peak_db=-1.5)


# ---------------------------------------------------------------------------
# 효과음 (모노). 자주 나는 소리일수록 짧고 담백하게.
#   상시(tap/spawn/merge): 작은 "뾱" 한 번, 40~110 ms, 잔향 없음, 변주 파일 여러 개
#   잦음(coin/sell/bubble/error/open): 0.35 s 이하, 단순·부드럽게
#   가끔(deliver/merge_big/unlock/place/splash): 2~3음 또는 반짝임, 0.8 s 이하
#   드묾(levelup): 제대로 된 징글 1.2~1.5 s
# 모든 효과음은 6 kHz 위를 깎아 날카롭지 않게 한다.
# ---------------------------------------------------------------------------
def buf(dur):
    return np.zeros(int(dur * SR))


def sweep_sine(f0, f1, dur, curve="exp"):
    t = tvec(dur)
    if curve == "exp":
        f = f0 * (f1 / f0) ** (t / dur)
    else:
        f = f0 + (f1 - f0) * t / dur
    return np.sin(2 * np.pi * np.cumsum(f) / SR), t


def small_room(x, wet=0.15, seconds=0.6):
    ir = reverb_ir(seconds, predelay=0.008, seed=3, damp=0.4)[0]
    y = fftconvolve(x, ir)[: len(x)]
    return x + wet * y


def sparkle(b, start, count, span, vel=0.12, seed=1):
    """D 장조 펜타토닉 고음 벨 알갱이(1.1~2.3 kHz)를 흩뿌림."""
    r = np.random.default_rng(seed)
    pent = [midi(n) for n in ["C#6", "E6", "F#6", "A6", "B6", "D7"]]
    for _ in range(count):
        mix_into(b, bell(hz(r.choice(pent)), vel * r.uniform(0.5, 1.0), 0.45), start + r.uniform(0, span))


def pop(f, dur=0.09, drop=1.5, drop_t=0.018, tau=0.028, h2=0.18, rise=False):
    """둥근 "뾱": 사인 한 방. 시작 음높이에서 f 로 빠르게 떨어지거나(rise=True 면 올라감)."""
    t = tvec(dur)
    ratio = (1 / drop) if rise else drop
    fr = f * (1 + (ratio - 1) * np.exp(-t / drop_t))
    ph = 2 * np.pi * np.cumsum(fr) / SR
    y = np.sin(ph) + h2 * np.sin(2 * ph) * np.exp(-t / (tau * 0.5))
    y *= np.clip(t / 0.0015, 0, 1) * np.exp(-t / tau)
    return fade(lowpass(y, 4000), 0.0005, 0.012)


# --- 상시 ---------------------------------------------------------------
def sfx_tap():
    return pop(720, dur=0.05, drop=1.35, drop_t=0.008, tau=0.012, h2=0.1)


def sfx_spawn(v):
    f = [560, 600, 640][v]
    return pop(f, dur=0.09, drop=1.6, drop_t=0.02, tau=0.026, h2=[0.15, 0.2, 0.12][v], rise=True)


def sfx_merge(v):
    f = [780, 840, 900][v]
    return pop(f, dur=0.1, drop=1.45, drop_t=0.014, tau=0.03, h2=[0.22, 0.16, 0.25][v])


# --- 잦음 ---------------------------------------------------------------
def sfx_coin():
    b = buf(0.3)
    mix_into(b, bell(hz(midi("A5")), 0.4, 0.08), 0)
    mix_into(b, bell(hz(midi("D6")), 0.5, 0.25), 0.06)
    return b


def sfx_sell():
    b = buf(0.3)
    mix_into(b, staccato(marimba(hz(midi("F#5")), 0.5, 0.2), 0.06), 0)
    mix_into(b, marimba(hz(midi("A5")), 0.55, 0.24), 0.07)
    return b


def sfx_bubble():
    b = buf(0.12)
    s, t = sweep_sine(420, 1000, 0.06)
    mix_into(b, s * np.clip(t / 0.003, 0, 1) * np.exp(-t / 0.025), 0, 0.9)
    return b


def sfx_error():
    b = buf(0.26)
    for st, n in [(0, "A3"), (0.12, "F#3")]:
        mix_into(b, pop(hz(midi(n)), dur=0.1, drop=1.12, drop_t=0.015, tau=0.04, h2=0.45), st, 0.7)
    return lowpass(b, 1500)


def sfx_open():
    b = buf(0.18)
    t = tvec(0.16)
    shape = np.sin(np.pi * t / 0.16) ** 2
    whoosh = tv_lowpass(rng.standard_normal(len(t)), 400 + 1600 * shape) * shape * 0.5
    mix_into(b, highpass(whoosh, 150), 0)
    mix_into(b, pop(620, dur=0.07, drop=1.3, drop_t=0.015, tau=0.02), 0.05, 0.25)
    return b


# --- 가끔 ---------------------------------------------------------------
def sfx_deliver():
    b = buf(0.75)
    for k, n in enumerate(["D5", "F#5", "A5"]):
        mix_into(b, marimba(hz(midi(n)), 0.6, 0.55), k * 0.1)
        mix_into(b, kalimba(hz(midi(n) + 12), 0.2, 0.5), k * 0.1)
    return small_room(b, 0.12)


def sfx_merge_big():
    b = buf(0.8)
    for k, n in enumerate(["A5", "D6", "F#6"]):
        mix_into(b, marimba(hz(midi(n) - 12), 0.45, 0.5), k * 0.06)
        mix_into(b, bell(hz(midi(n)), 0.3 + 0.05 * k, 0.6), k * 0.06)
    sparkle(b, 0.18, 5, 0.3, 0.08, seed=5)
    return small_room(b, 0.15)


def sfx_unlock():
    b = buf(0.6)
    t = tvec(0.04)
    for st, f in [(0, 900), (0.06, 1250)]:  # 딸깍-딸깍(나무)
        mix_into(b, np.sin(2 * np.pi * f * t) * np.exp(-t / 0.007), st, 0.45)
    mix_into(b, bell(hz(midi("A5")), 0.4, 0.5), 0.12)
    mix_into(b, bell(hz(midi("E6")), 0.4, 0.45), 0.2)
    return small_room(b, 0.12)


def sfx_place():
    b = buf(0.5)
    s, t = sweep_sine(170, 85, 0.12)
    thunk = s * np.exp(-t / 0.035) * np.clip(t / 0.002, 0, 1)
    knock = bandpass(rng.standard_normal(len(t)), 350, 1400) * np.exp(-t / 0.012) * 0.5
    mix_into(b, fade(thunk + knock, 0, 0.02), 0, 0.9)
    mix_into(b, bell(hz(midi("F#6")), 0.12, 0.35), 0.07)
    mix_into(b, bell(hz(midi("A6")), 0.1, 0.35), 0.12)
    return small_room(b, 0.1)


def tv_lowpass(x, fc):
    """샘플마다 컷오프가 변하는 1차×2 로우패스(짧은 효과음 전용)."""
    y = np.zeros_like(x)
    s1 = s2 = 0.0
    g = 1 - np.exp(-2 * np.pi * fc / SR)
    for i in range(len(x)):
        s1 += g[i] * (x[i] - s1)
        s2 += g[i] * (s1 - s2)
        y[i] = s2
    return y


def sfx_splash():
    b = buf(0.55)
    t = tvec(0.4)
    noise = rng.standard_normal(len(t))
    fc = 800 + 2600 * np.exp(-t / 0.05)
    body = tv_lowpass(noise, fc) * np.clip(t / 0.008, 0, 1) * np.exp(-t / 0.1)
    mix_into(b, highpass(body, 200), 0, 0.9)
    r = np.random.default_rng(17)
    for _ in range(5):  # 물방울
        f0 = r.uniform(700, 1300)
        s, tt = sweep_sine(f0, f0 * 1.7, 0.03)
        mix_into(b, s * np.sin(np.pi * tt / 0.03) * 0.18, r.uniform(0.04, 0.3))
    return small_room(b, 0.1)


# --- 드묾 ---------------------------------------------------------------
def sfx_levelup():
    b = buf(1.4)
    step = 0.1
    for k, n in enumerate(["D5", "F#5", "A5", "D6"]):
        mix_into(b, marimba(hz(midi(n)), 0.6, 0.6), k * step)
        mix_into(b, kalimba(hz(midi(n)), 0.15, 0.5), k * step)
    for n in ["A5", "D6", "F#6"]:
        mix_into(b, bell(hz(midi(n)), 0.28, 1.0), 4 * step + 0.02)
        mix_into(b, marimba(hz(midi(n) - 12), 0.3, 0.9), 4 * step + 0.02)
    swell = sum(pad_voice(hz(midi(n)), 0.55, attack=0.15, release=0.4, detune_cents=c)
                for n in ["D4", "A4", "F#5"] for c in (-7, 7))
    mix_into(b, lowpass(swell, 2200) * 0.06, 4 * step)
    sparkle(b, 0.45, 8, 0.55, 0.09, seed=9)
    return small_room(b, 0.2)


# 이름 -> (생성 함수, 목표 LUFS(짧은 블록, 모노)). 변주는 name_1..3 으로 저장.
SFX = {
    "tap": (sfx_tap, -24), "coin": (sfx_coin, -21), "sell": (sfx_sell, -21),
    "bubble": (sfx_bubble, -21), "error": (sfx_error, -21), "open": (sfx_open, -26),
    "deliver": (sfx_deliver, -18), "merge_big": (sfx_merge_big, -18), "unlock": (sfx_unlock, -19),
    "place": (sfx_place, -19), "splash": (sfx_splash, -20), "levelup": (sfx_levelup, -16),
}
SFX_VARIANTS = {"spawn": (sfx_spawn, -23), "merge": (sfx_merge, -22)}


# ---------------------------------------------------------------------------
# 인코딩 / 검사
# ---------------------------------------------------------------------------
def encode(x, path, quality):
    x = np.asarray(x, dtype=np.float32)
    data = x.T if x.ndim == 2 else x
    with tempfile.TemporaryDirectory() as d:
        wav = os.path.join(d, "a.wav")
        wavfile.write(wav, SR, data)
        subprocess.run([FFMPEG, "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis",
                        "-q:a", str(quality), "-ar", str(SR), "-map_metadata", "-1", path], check=True)


def decode(path):
    out = subprocess.run([FFMPEG, "-loglevel", "error", "-i", path, "-f", "f32le", "-acodec", "pcm_f32le", "-"],
                         check=True, capture_output=True).stdout
    probe = subprocess.run([FFMPEG, "-i", path], capture_output=True, text=True).stderr
    ch = 2 if "stereo" in probe else 1
    return np.frombuffer(out, dtype=np.float32).reshape(-1, ch).T


def check():
    print(f"{'file':<16}{'ch':>3}{'dur s':>8}{'KB':>8}{'peak dB':>9}{'rms dB':>8}{'LUFS':>7}  clip")
    total = 0
    for f in sorted(os.listdir(OUT)):
        if not f.endswith(".ogg"):
            continue
        p = os.path.join(OUT, f)
        x = decode(p)
        size = os.path.getsize(p)
        total += size
        pk = np.max(np.abs(x))
        rms = np.sqrt(np.mean(x ** 2))
        block = 0.4 if f.startswith("bgm") else min(0.1, x.shape[1] / SR)
        print(f"{f:<16}{x.shape[0]:>3}{x.shape[1] / SR:>8.2f}{size / 1024:>8.1f}{db(pk):>9.2f}{db(rms):>8.2f}"
              f"{loudness(x, block):>7.1f}  {'YES' if pk >= 0.999 else 'no'}")
        if f.startswith("bgm"):
            w = int(0.05 * SR)
            head = np.sqrt(np.mean(x[:, :w] ** 2))
            tail = np.sqrt(np.mean(x[:, -w:] ** 2))
            jump = np.max(np.abs(x[:, 0] - x[:, -1]))
            typ = np.percentile(np.abs(np.diff(x, axis=1)), 99)
            print(f"  loop: last50ms {db(tail):.2f} dB / first50ms {db(head):.2f} dB "
                  f"(diff {db(head) - db(tail):+.2f} dB), boundary step {jump:.4f} vs p99 step {typ:.4f}")
            # 비교 기준: 곡 안의 다른 마디 경계(같은 다운비트)에서의 50 ms RMS 차이
            bars = [int(round(k * BAR * SR)) for k in range(1, int(x.shape[1] / SR / BAR))]
            d_in = [db(np.sqrt(np.mean(x[:, i:i + w] ** 2))) - db(np.sqrt(np.mean(x[:, i - w:i] ** 2)))
                    for i in bars]
            print(f"  in-song bar downbeats: diff median {np.median(d_in):+.2f} dB, "
                  f"range {min(d_in):+.2f}..{max(d_in):+.2f} dB")
    print(f"total {total / 1024:.1f} KB")


def render_sfx(fn, lufs):
    x = fade(lowpass(fn(), 6000, 4), 0.0005, 0.012)
    return normalize(x, lufs, peak_db=-1.0, block=min(0.1, len(x) / SR))


def main():
    os.makedirs(OUT, exist_ok=True)
    if "--check" not in sys.argv:
        bgm = render_bgm()
        encode(bgm, os.path.join(OUT, "bgm_garden.ogg"), 3)
        names = {"bgm_garden"}
        for name, (fn, lufs) in SFX.items():
            encode(render_sfx(fn, lufs), os.path.join(OUT, f"{name}.ogg"), 4)
            names.add(name)
        for name, (fn, lufs) in SFX_VARIANTS.items():
            for v in range(3):
                encode(render_sfx(lambda: fn(v), lufs), os.path.join(OUT, f"{name}_{v + 1}.ogg"), 4)
                names.add(f"{name}_{v + 1}")
        for f in os.listdir(OUT):  # 더 이상 만들지 않는 옛 파일 정리
            if f.endswith(".ogg") and f[:-4] not in names:
                os.remove(os.path.join(OUT, f))
    check()


if __name__ == "__main__":
    main()

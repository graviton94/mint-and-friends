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
# BGM 악보 (F 장조, 96 BPM, 4/4, 32마디 = 80초)
# ---------------------------------------------------------------------------
BPM = 96
BEAT = 60.0 / BPM
BAR = 4 * BEAT

CHORDS = {  # 근음 pc, 구성음 간격
    "Fmaj7": (5, [0, 4, 7, 11]), "Dm7": (2, [0, 3, 7, 10]), "Bbmaj7": (10, [0, 4, 7, 11]),
    "C7sus": (0, [0, 5, 7, 10]), "C7": (0, [0, 4, 7, 10]), "Am7": (9, [0, 3, 7, 10]),
    "Gm7": (7, [0, 3, 7, 10]), "C": (0, [0, 4, 7]), "Csus": (0, [0, 5, 7]),
    "Gm9": (7, [0, 3, 7, 10, 14]), "Fadd9": (5, [0, 4, 7, 14]),
}

# 마디별 코드: [(이름, 박수)]
A_PROG = [[("Fmaj7", 4)], [("Dm7", 4)], [("Bbmaj7", 4)], [("C7sus", 2), ("C7", 2)],
          [("Fadd9", 4)], [("Am7", 4)], [("Bbmaj7", 4)], [("Gm7", 2), ("C7", 2)]]
B_PROG = [[("Bbmaj7", 4)], [("C", 4)], [("Am7", 4)], [("Dm7", 4)],
          [("Gm9", 4)], [("Am7", 4)], [("Bbmaj7", 4)], [("Csus", 2), ("C7", 2)]]

MEL_A = [
    "C5:1 A4:.5 C5:.5 F5:1.5 E5:.5",
    "D5:1.5 C5:.5 A4:1 r:1",
    "Bb4:.5 D5:.5 F5:1 A5:1 G5:1",
    "F5:1.5 E5:.5 C5:2",
    "C5:1 A4:.5 C5:.5 F5:1 G5:1",
    "A5:1.5 G5:.5 E5:1 C5:1",
    "D5:1 F5:.5 E5:.5 D5:1 Bb4:1",
    "G4:.5 A4:.5 Bb4:.5 C5:.5 E5:1 r:1",
]
MEL_A2_TAIL = [  # A' 의 5~8마디 변주
    "A5:1 G5:.5 F5:.5 C5:1 F5:1",
    "E5:1.5 G5:.5 C6:1 A5:1",
    "Bb5:1 A5:.5 G5:.5 F5:1 D5:1",
    "D5:1 E5:1 C5:2",
]
MEL_B = [
    "D5:2 F5:1 A5:1",
    "G5:3 E5:1",
    "C5:2 E5:1 G5:1",
    "F5:2 D5:1 A4:1",
    "Bb4:1 D5:1 F5:1 A5:1",
    "G5:2 E5:1 C5:1",
    "D5:1.5 C5:.5 Bb4:1 D5:1",
    "C5:2.5 E5:.5 G5:1",
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


def render_bgm():
    sections = [("A", A_PROG, MEL_A), ("A2", A_PROG, MEL_A[:4] + MEL_A2_TAIL),
                ("B", B_PROG, MEL_B), ("A3", A_PROG, MEL_A)]
    n_bars = 8 * len(sections)
    loop_len = int(round(n_bars * BAR * SR))
    total = loop_len + int(9 * SR)  # 리버브·딜레이·릴리스 꼬리 여유

    bus = {k: np.zeros(total) for k in ["mar", "kal", "bell", "bass", "shk", "brs", "kick"]}
    pad = np.zeros((2, total))

    def hum():  # 사람 손 느낌의 미세한 타이밍 흔들림
        return rng.normal(0, 0.006)

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
                for k, m in enumerate(notes):
                    for v, (det, p) in enumerate([(-7, -0.7), (0, 0.0), (7, 0.7)]):
                        y = pad_voice(hz(m), dur + 0.05, detune_cents=det + rng.normal(0, 1.5)) * 0.055
                        i = int(round(cs * SR))
                        seg = pan2(y, p)
                        j = min(total, i + seg.shape[1])
                        pad[:, i:j] += seg[:, : j - i]
                # 베이스: 근음(1박) - 5도(2.5박) - 근음, 2코드 마디는 각 코드 근음
                rb = 36 + ((root - 36) % 12)
                if rb > 43:
                    rb -= 12
                if nb == 4:
                    pat = [(0, 1.4, rb, 0.9), (1.5, 0.45, rb + 7, 0.55), (2, 1.4, rb, 0.75),
                           (3.5, 0.45, rb + 12, 0.5)]
                else:
                    pat = [(0, 1.4, rb, 0.85), (1.5, 0.45, rb + 7, 0.5)]
                for bb, d, m, v in pat:
                    mix_into(bus["bass"], pluck_bass(hz(m), v, d * BEAT), cs + bb * BEAT + hum())
                beat += nb

            # --- 멜로디: A 계열은 마림바(+A3 는 벨 옥타브 더블), B 는 벨 리드
            for nb_, d, m in parse_bar(mel[b]):
                st = t0 + nb_ * BEAT + hum()
                acc = 1.0 if nb_ in (0.0, 2.0) else 0.85
                v = acc * rng.uniform(0.85, 1.0)
                if sec == "B":
                    mix_into(bus["bell"], bell(hz(m), 0.55 * v, max(1.6, d * BEAT + 1.0)), st)
                    mix_into(bus["kal"], kalimba(hz(m - 12), 0.25 * v), st)
                else:
                    mix_into(bus["mar"], marimba(hz(m), 0.75 * v), st)
                    if sec == "A3" and nb_ in (0.0, 2.0):
                        mix_into(bus["bell"], bell(hz(m + 12), 0.18 * v), st)

            # --- 반주: B 는 칼림바 8분 아르페지오, A2/A3 는 벨 반짝이
            notes, _ = chord_notes(prog[b][0][0], lo=60)
            if sec == "B":
                arp = notes + [notes[-1] + 12 - (notes[-1] - notes[0]) % 12] if len(notes) < 4 else notes
                order = [0, 1, 2, 3, 2, 1, 2, 3]
                for k in range(8):
                    m = arp[order[k] % len(arp)]
                    if b % 8 == 7 and k >= 4:
                        m = chord_notes(prog[b][-1][0], lo=60)[0][order[k] % 3]
                    mix_into(bus["kal"], kalimba(hz(m), 0.32 if k % 2 == 0 else 0.22), t0 + k * 0.5 * BEAT + hum())
            elif sec in ("A2", "A3"):
                hi = [m + 12 for m in notes]
                for bb, idx in [(1.5, 1), (3.0, 2), (3.5, 3)]:
                    mix_into(bus["bell"], bell(hz(hi[idx % len(hi)]), 0.12, 1.4), t0 + bb * BEAT + hum())
            else:  # A: 첫 섹션은 아주 옅은 칼림바 오프비트만
                for bb in (1.0, 3.0):
                    mix_into(bus["kal"], kalimba(hz(notes[1]), 0.16), t0 + bb * BEAT + hum())

            # --- 퍼커션: A 는 셰이커만, A2/A3 는 풀, B 는 킥 빼고 브러시 가볍게
            for k in range(8):
                st = t0 + k * 0.5 * BEAT + (0.03 * BEAT if k % 2 else 0)  # 살짝 스윙
                mix_into(bus["shk"], shaker(0.5 if k % 2 == 0 else 0.32) * rng.uniform(0.85, 1.0), st)
            if sec != "A":
                for bb in (1, 3):
                    mix_into(bus["brs"], brush(0.55 if sec != "B" else 0.4), t0 + bb * BEAT + hum())
            if sec in ("A2", "A3"):
                for bb in (0, 2.5) if b % 2 else (0, 2):
                    mix_into(bus["kick"], soft_kick(0.7), t0 + bb * BEAT)
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
# 효과음 (모노)
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
    """높은 펜타토닉 벨 알갱이를 흩뿌림."""
    r = np.random.default_rng(seed)
    pent = [midi(n) for n in ["C7", "D7", "E7", "G7", "A7", "C8"]]
    for _ in range(count):
        mix_into(b, bell(hz(r.choice(pent)), vel * r.uniform(0.5, 1.0), 0.5), start + r.uniform(0, span))


def sfx_tap():
    b = buf(0.09)
    t = tvec(0.09)
    body = np.sin(2 * np.pi * 620 * t) * np.exp(-t / 0.018)
    tick = np.sin(2 * np.pi * 1750 * t) * np.exp(-t / 0.006) * 0.5
    noise = bandpass(rng.standard_normal(len(t)), 1500, 6000) * np.exp(-t / 0.003) * 0.25
    b += (body + tick + noise) * np.clip(t / 0.001, 0, 1)
    return lowpass(b, 6000)


def sfx_spawn():
    b = buf(0.38)
    s, t = sweep_sine(280, 950, 0.09)
    pop = s * np.sin(np.pi * np.clip(t / 0.09, 0, 1)) ** 1.5
    mix_into(b, pop, 0, 0.8)
    mix_into(b, marimba(hz(midi("G5")), 0.5, 0.3), 0.06)
    mix_into(b, bell(hz(midi("D6")), 0.15, 0.3), 0.07)
    return small_room(b, 0.12)


def sfx_merge():
    b = buf(0.75)
    for k, n in enumerate(["E5", "G5", "C6"]):
        mix_into(b, marimba(hz(midi(n)), 0.55 + 0.1 * k, 0.6), k * 0.065)
        mix_into(b, bell(hz(midi(n) + 12), 0.12 + 0.04 * k, 0.6), k * 0.065)
    # 부드러운 상승 쉬익(노이즈 + 상승 사인 블룹)
    s, t = sweep_sine(400, 1200, 0.18)
    mix_into(b, s * np.sin(np.pi * t / 0.18) ** 2 * 0.25, 0.0)
    return small_room(b, 0.18)


def sfx_merge_big():
    b = buf(1.15)
    for k, n in enumerate(["C5", "E5", "G5", "C6", "E6"]):
        mix_into(b, marimba(hz(midi(n)), 0.45 + 0.06 * k, 0.7), k * 0.055)
        mix_into(b, bell(hz(midi(n) + 12), 0.14 + 0.03 * k, 0.9), k * 0.055)
    for n in ["C6", "E6", "G6"]:
        mix_into(b, bell(hz(midi(n)), 0.22, 0.9), 0.3)
    # 은은한 패드 스웰
    swell = sum(pad_voice(hz(midi(n)), 0.5, attack=0.12, release=0.4, detune_cents=c)
                for n in ["C5", "G5", "E6"] for c in (-6, 6))
    mix_into(b, lowpass(swell, 2500) * 0.05, 0.1)
    sparkle(b, 0.28, 9, 0.5, 0.1, seed=5)
    return small_room(b, 0.22)


def sfx_coin():
    b = buf(0.5)
    mix_into(b, bell(hz(midi("B5")), 0.5, 0.12), 0)
    mix_into(b, bell(hz(midi("E6")), 0.6, 0.45), 0.075)
    mix_into(b, kalimba(hz(midi("E6")), 0.25, 0.45), 0.075)
    return small_room(lowpass(b, 9000), 0.1)


def sfx_deliver():
    b = buf(0.95)
    for k, n in enumerate(["C5", "E5", "G5"]):
        mix_into(b, marimba(hz(midi(n)), 0.6, 0.7), k * 0.11)
        mix_into(b, kalimba(hz(midi(n) + 12), 0.25, 0.7), k * 0.11)
    for n in ["C6", "E6"]:
        mix_into(b, bell(hz(midi(n)), 0.2, 0.6), 0.33)
    return small_room(b, 0.18)


def sfx_levelup():
    b = buf(1.2)
    step = 0.095
    for k, n in enumerate(["C5", "E5", "G5", "C6"]):
        mix_into(b, marimba(hz(midi(n)), 0.6, 0.6), k * step)
    for n in ["G5", "C6", "E6"]:
        mix_into(b, bell(hz(midi(n)), 0.3, 0.85), 4 * step + 0.02)
        mix_into(b, kalimba(hz(midi(n)), 0.2, 0.8), 4 * step + 0.02)
    swell = sum(pad_voice(hz(midi(n)), 0.45, attack=0.15, release=0.35, detune_cents=c)
                for n in ["C4", "G4", "E5"] for c in (-7, 7))
    mix_into(b, lowpass(swell, 2200) * 0.06, 4 * step)
    sparkle(b, 0.45, 8, 0.55, 0.09, seed=9)
    return small_room(b, 0.22)


def sfx_unlock():
    b = buf(0.75)
    t = tvec(0.05)
    for st, f in [(0, 900), (0.06, 1300)]:  # 딸깍-딸깍(나무)
        click = np.sin(2 * np.pi * f * t) * np.exp(-t / 0.008)
        click += bandpass(rng.standard_normal(len(t)), 800, 4000) * np.exp(-t / 0.004) * 0.3
        mix_into(b, click, st, 0.5)
    mix_into(b, bell(hz(midi("G5")), 0.4, 0.6), 0.12)
    mix_into(b, bell(hz(midi("D6")), 0.45, 0.6), 0.2)
    sparkle(b, 0.22, 4, 0.3, 0.08, seed=11)
    return small_room(b, 0.18)


def sfx_sell():
    b = buf(0.55)
    mix_into(b, marimba(hz(midi("G5")), 0.5, 0.4), 0)
    mix_into(b, bell(hz(midi("D6")), 0.4, 0.45), 0.07)
    mix_into(b, bell(hz(midi("G6")), 0.3, 0.45), 0.07)
    t = tvec(0.12)  # 작은 동전 짤랑
    jing = bandpass(rng.standard_normal(len(t)), 5000, 10000) * np.exp(-t / 0.03) * 0.08
    mix_into(b, jing, 0.07)
    return small_room(b, 0.12)


def sfx_error():
    b = buf(0.42)
    for st, n in [(0, "D4"), (0.13, "Bb3")]:
        f = hz(midi(n))
        t = tvec(0.28)
        y = np.sin(2 * np.pi * f * t) + 0.25 * np.sin(2 * np.pi * 2 * f * t) * np.exp(-t / 0.05)
        y *= np.clip(t / 0.006, 0, 1) * np.exp(-t / 0.09)
        mix_into(b, fade(y, 0, 0.03), st, 0.6)
    return small_room(lowpass(b, 1800), 0.1)


def sfx_place():
    b = buf(0.6)
    s, t = sweep_sine(170, 85, 0.12)
    thunk = s * np.exp(-t / 0.035) * np.clip(t / 0.002, 0, 1)
    knock = bandpass(rng.standard_normal(len(t)), 350, 1400) * np.exp(-t / 0.012) * 0.5
    mix_into(b, fade(thunk + knock, 0, 0.02), 0, 0.9)
    mix_into(b, bell(hz(midi("E6")), 0.14, 0.4), 0.07)
    mix_into(b, bell(hz(midi("B6")), 0.11, 0.4), 0.12)
    sparkle(b, 0.12, 3, 0.15, 0.05, seed=13)
    return small_room(b, 0.12)


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
    b = buf(0.7)
    t = tvec(0.45)
    noise = rng.standard_normal(len(t))
    fc = 900 + 3200 * np.exp(-t / 0.06)
    body = tv_lowpass(noise, fc) * np.clip(t / 0.008, 0, 1) * np.exp(-t / 0.11)
    fizz = bandpass(rng.standard_normal(len(t)), 3000, 8000) * np.exp(-t / 0.05) * 0.25
    mix_into(b, highpass(body, 200) + fizz, 0, 0.9)
    r = np.random.default_rng(17)
    for _ in range(6):  # 물방울
        f0 = r.uniform(700, 1400)
        s, tt = sweep_sine(f0, f0 * 1.8, 0.03)
        mix_into(b, s * np.sin(np.pi * tt / 0.03) * 0.18, r.uniform(0.04, 0.35))
    return small_room(b, 0.15)


def sfx_bubble():
    b = buf(0.16)
    s, t = sweep_sine(420, 1150, 0.07)
    y = s * np.clip(t / 0.004, 0, 1) * np.exp(-t / 0.03)
    mix_into(b, y, 0, 0.9)
    s2, t2 = sweep_sine(900, 1600, 0.03)
    mix_into(b, s2 * np.sin(np.pi * t2 / 0.03) * 0.25, 0.055)
    return small_room(b, 0.1, 0.3)


def sfx_open():
    b = buf(0.34)
    t = tvec(0.3)
    noise = rng.standard_normal(len(t))
    shape = np.sin(np.pi * np.clip(t / 0.3, 0, 1)) ** 2
    fc = 500 + 2500 * np.sin(np.pi * np.clip(t / 0.3, 0, 1)) ** 1.5
    whoosh = tv_lowpass(noise, fc) * shape * 0.6
    s, _ = sweep_sine(520, 780, 0.3)
    mix_into(b, highpass(whoosh, 150) + s * shape * 0.08, 0)
    mix_into(b, bell(hz(midi("A6")), 0.05, 0.25), 0.12)
    return small_room(b, 0.1, 0.4)


SFX = {
    "tap": sfx_tap, "spawn": sfx_spawn, "merge": sfx_merge, "merge_big": sfx_merge_big,
    "coin": sfx_coin, "deliver": sfx_deliver, "levelup": sfx_levelup, "unlock": sfx_unlock,
    "sell": sfx_sell, "error": sfx_error, "place": sfx_place, "splash": sfx_splash,
    "bubble": sfx_bubble, "open": sfx_open,
}
# 효과음별 목표 라우드니스(짧은 블록 기준). UI 성 소리는 조금 작게.
SFX_LUFS = {"tap": -20, "open": -21, "bubble": -18, "error": -18}


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
        block = 0.4 if f.startswith("bgm") else 0.1
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


def main():
    os.makedirs(OUT, exist_ok=True)
    if "--check" not in sys.argv:
        bgm = render_bgm()
        encode(bgm, os.path.join(OUT, "bgm_garden.ogg"), 3)
        for name, fn in SFX.items():
            x = fade(fn(), 0.001, 0.015)
            x = normalize(x, SFX_LUFS.get(name, -16.0), peak_db=-1.0, block=0.1)
            encode(x, os.path.join(OUT, f"{name}.ogg"), 4)
    check()


if __name__ == "__main__":
    main()

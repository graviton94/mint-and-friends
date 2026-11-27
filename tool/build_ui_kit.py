#!/usr/bin/env python3
"""UI 부품(회색 몸통 + 갈색 외곽선, 마젠타 배경) → 게임 테두리 그림 (D-092).

design/ui_kit/raw/*.png (발주로 받은 원본) 를 읽어
  1) 마젠타 배경을 부드럽게 지우고 가장자리의 분홍 번짐을 걷어 낸다,
  2) 그림 둘레만 남기고 잘라 낸다,
  3) 회색 몸통에만 기준 색을 입힌다 (밝기 → 색 계단. 외곽선 · 잎사귀처럼 색이 있는 곳은 그대로),
  4) 지금 게임이 쓰는 이름(button_green, capsule_spring, panel ...)으로 assets/art/frames 에 쓴다.

색과 출력 목록은 tool/ui_kit.json. 새 색이 필요하면 거기에 헥스 하나 추가하고 다시 돌리면 된다.

  python3 tool/build_ui_kit.py            # 전부 만들기
  python3 tool/build_ui_kit.py --preview out.png   # 전부를 한 장에 모아 보기
"""
import argparse
import json
import os

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, 'design/ui_kit/raw')
OUT = os.path.join(ROOT, 'assets/art/frames')
CONF = os.path.join(ROOT, 'tool/ui_kit.json')
MAGENTA = np.array([255.0, 0.0, 255.0])


def hex_rgb(h):
    h = h.lstrip('#')
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], np.float32)


def key_magenta(path):
    """마젠타 배경 → 알파. 가장자리 반투명 픽셀은 마젠타를 빼고 원래 색으로 되돌린다."""
    src = Image.open(path)
    if src.mode == 'RGBA' and np.array(src)[..., 3].min() < 10:
        # 이미 투명 배경으로 온 원본은 그 알파를 쓴다
        arr = np.array(src).astype(np.float32)
        return arr[..., :3], arr[..., 3] / 255.0
    im = np.array(src.convert('RGB')).astype(np.float32)
    d = np.sqrt(((im - MAGENTA) ** 2).sum(-1))
    a = np.clip((d - 70) / 110, 0, 1)
    # 마젠타 계열(빨강 · 파랑 높고 초록 낮음)인데 거리가 좀 있는 번짐도 배경 쪽으로
    spill = (im[..., 1] < 90) & (im[..., 0] > 170) & (im[..., 2] > 170)
    a = np.where(spill, np.minimum(a, 0.15), a)
    safe = np.maximum(a, 1e-3)[..., None]
    rgb = np.clip((im - (1 - a[..., None]) * MAGENTA) / safe, 0, 255)
    rgb = np.where(a[..., None] > 0.02, rgb, 0)
    # 떨어진 점 제거
    vis = a > 0.05
    lab, n = ndimage.label(vis)
    if n > 1:
        sizes = ndimage.sum(vis, lab, range(1, n + 1))
        keep = np.zeros(n + 1, bool)
        keep[1:] = sizes >= sizes.max() * 0.01
        a = np.where(keep[lab], a, 0)
    return rgb, a


def trim(rgb, a, pad=4):
    ys, xs = np.where(a > 0.02)
    y0, y1 = max(0, ys.min() - pad), min(a.shape[0], ys.max() + pad + 1)
    x0, x1 = max(0, xs.min() - pad), min(a.shape[1], xs.max() + pad + 1)
    return rgb[y0:y1, x0:x1], a[y0:y1, x0:x1]


def tint(rgb, target):
    """무채색(회색 · 흰색) 픽셀만 색을 입힌다. 기본 회색 200 = 기준 색, 더 밝으면 흰색 쪽, 어두우면 진하게."""
    if target is None:
        return rgb
    mx, mn = rgb.max(-1), rgb.min(-1)
    sat = (mx - mn) / 255.0
    lum = rgb.mean(-1)
    w = np.clip((0.16 - sat) / 0.08, 0, 1) * np.clip((lum - 90) / 40, 0, 1)
    l = lum[..., None]
    dark = target[None, None, :] * (l / 200.0)
    light = target + (255 - target) * np.clip((l - 200) / 55.0, 0, 1)
    col = np.where(l <= 200, dark, light)
    return rgb * (1 - w[..., None]) + col * w[..., None]


def fill_inside(rgb, a, color):
    """속 빈 틀(패널) 안쪽을 한 색으로 채운다."""
    solid = a > 0.5
    inside = ndimage.binary_fill_holes(solid)
    hole = inside & (a < 1)
    k = a[..., None]
    rgb = np.where(hole[..., None], rgb * k + color * (1 - k), rgb)
    a = np.where(hole, 1.0, a)
    return rgb, a


def resize(rgb, a, height=None, width=None):
    h, w = a.shape
    if height:
        W, H = round(w * height / h), height
    else:
        W, H = width, round(h * width / w)
    # 알파를 곱한 색으로 줄여야 가장자리가 어두워지거나 밝아지지 않는다
    pm = Image.fromarray(np.clip(rgb * a[..., None], 0, 255).astype(np.uint8)).resize((W, H), Image.LANCZOS)
    al = Image.fromarray((a * 255).astype(np.uint8)).resize((W, H), Image.LANCZOS)
    A = np.array(al, np.float32) / 255.0
    C = np.array(pm, np.float32) / np.maximum(A, 1e-3)[..., None]
    return np.clip(C, 0, 255), A


def to_image(rgb, a):
    return Image.fromarray(np.dstack([np.clip(rgb, 0, 255), a * 255]).astype(np.uint8), 'RGBA')


def build(conf):
    pal = {k: hex_rgb(v) for k, v in conf['palette'].items()}
    made = {}
    cache = {}
    for out in conf['outputs']:
        src = out['src']
        if src not in cache:
            cache[src] = trim(*key_magenta(os.path.join(RAW, src + '.png')))
        rgb, a = cache[src]
        rgb = tint(rgb.copy(), pal.get(out.get('color')))
        a = a.copy()
        if out.get('fill'):
            rgb, a = fill_inside(rgb, a, pal[out['fill']])
        if out.get('line'):
            # 외곽선 색 바꾸기 (판 칸처럼 테두리가 은은해야 하는 곳): 진하고 색 있는 픽셀만
            mx, mn = rgb.max(-1), rgb.min(-1)
            dark = np.clip((150 - rgb.mean(-1)) / 50, 0, 1) * np.clip(((mx - mn) / 255.0 - 0.08) / 0.08, 0, 1)
            rgb = rgb * (1 - dark[..., None]) + hex_rgb(out['line']) * dark[..., None]
        if out.get('flat') is not None:
            # 무채색 부분을 한 가지 색으로 (말풍선 꼬리: 몸통 아래 그늘 띠와 같은 색이 되게)
            mx, mn = rgb.max(-1), rgb.min(-1)
            w = np.clip((0.16 - (mx - mn) / 255.0) / 0.08, 0, 1) * np.clip((rgb.mean(-1) - 90) / 40, 0, 1)
            col = pal[out['color']] * out['flat']
            rgb = rgb * (1 - w[..., None]) + col * w[..., None]
        if out.get('strip'):
            # 리본 가운데 띠를 꼬리 그림의 오른쪽 끝 몇 줄에서 떠 온다 (이음매가 생기지 않게)
            (y0, y1), (x0, x1) = out['strip']['rows'], out['strip']['cols']
            h, w = a.shape
            rgb, a = rgb[int(h * y0):int(h * y1), int(w * x0):int(w * x1)], a[int(h * y0):int(h * y1), int(w * x0):int(w * x1)]
        if out.get('crop_x'):  # 리본 가운데 띠: 양 끝 둥근 광택을 빼고 가운데만
            x0, x1 = out['crop_x']
            w = a.shape[1]
            rgb, a = rgb[:, int(w * x0):int(w * x1)], a[:, int(w * x0):int(w * x1)]
        rgb, a = resize(rgb, a, height=out.get('height'), width=out.get('width'))
        img = to_image(rgb, a)
        img.save(os.path.join(OUT, out['name'] + '.webp'), quality=92, method=6, alpha_quality=100)
        made[out['name']] = list(img.size)
    # 크기 표 갱신 (9조각 경계 계산에 쓴다)
    fj = os.path.join(OUT, 'frames.json')
    sizes = json.load(open(fj))
    sizes.update(made)
    json.dump(sizes, open(fj, 'w'), indent=1)
    return made


def preview(made, path):
    bg = (205, 232, 200, 255)
    ims = [Image.open(os.path.join(OUT, n + ".webp")).convert("RGBA") for n in made]
    W = 1400
    x = y = 10
    rowh = 0
    pos = []
    for im in ims:
        im.thumbnail((330, 260))
        if x + im.width > W:
            x, y = 10, y + rowh + 10
            rowh = 0
        pos.append((x, y))
        x += im.width + 10
        rowh = max(rowh, im.height)
    out = Image.new('RGBA', (W, y + rowh + 10), bg)
    for im, p in zip(ims, pos):
        out.alpha_composite(im, p)
    out.save(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--preview')
    args = ap.parse_args()
    conf = json.load(open(CONF))
    made = build(conf)
    for k, v in made.items():
        print(k, v)
    if args.preview:
        preview(made, args.preview)


if __name__ == '__main__':
    main()

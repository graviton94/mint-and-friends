#!/usr/bin/env python3
"""UI 테두리 그림 가장자리 정리 (D-089).

문제: 흰 배경을 지우고 남은 밝은 테(흰 헤일로) · 떨어진 점 노이즈 · 작은 원본(384px)이
폰에서 2~3배로 늘어나며 계단 · 번짐.

처리 (그림 내용은 그대로, 가장자리만):
  1) 떨어진 작은 덩어리(점 노이즈) 제거.
  2) 바깥에 닿은 밝은 테두리 픽셀 깎기 (갈색 외곽선 바깥의 흰 찌꺼기).
  3) 2배로 키운 뒤 알파를 4배 촘촘히 다시 계산해 매끈한 안티에일리어싱.
  4) 가장자리 색은 바로 안쪽 외곽선 색으로 채워 흰 번짐 제거.

사용법:
  python3 tool/clean_frames.py <in.webp> <out.webp> [--scale 2]
  python3 tool/clean_frames.py --all [--scale 2]   # assets/art/frames 의 9조각 · 알약 그림
"""
import argparse
import glob
import json
import os

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

# 9조각 · 알약으로 늘려 쓰는 테두리 그림 (가장자리가 화면에 그대로 보이는 것)
TARGETS = [
    'panel', 'ribbon', 'banner_gold', 'banner_green', 'button_gold',
    'button_green', 'button_purple', 'button_white', 'capsule',
    'capsule_spring', 'capsule_summer', 'capsule_autumn', 'capsule_winter',
    'card', 'card_ready', 'tile', 'slot', 'speech', 'toast', 'tab_idle',
    'tab_on', 'tab_body', 'title_plaque', 'sale_badge', 'levelup_burst',
]


def clean(im: Image.Image, scale: int = 2) -> Image.Image:
    a0 = np.array(im.convert('RGBA')).astype(np.float32)
    rgb, alpha = a0[..., :3], a0[..., 3] / 255.0
    vis = alpha > 0.02

    # 1) 점 노이즈: 가장 큰 덩어리 대비 아주 작은 덩어리 제거
    lab, n = ndimage.label(vis, structure=np.ones((3, 3)))
    if n > 1:
        sizes = ndimage.sum(vis, lab, range(1, n + 1))
        keep = np.zeros(n + 1, bool)
        keep[1:] = sizes >= max(40, sizes.max() * 0.002)
        vis &= keep[lab]

    # 2) 바깥 밝은 테: 투명에 닿은 밝은 픽셀을 바깥부터 2겹까지 깎는다
    lum = rgb.mean(-1)
    for _ in range(2):
        outside = ~vis
        touch = ndimage.binary_dilation(outside, np.ones((3, 3))) & vis
        light = touch & (lum > 200)
        if not light.any():
            break
        vis &= ~light

    # 가장자리 색: 바로 안쪽의 진한(외곽선) 색으로 바깥 몇 픽셀을 채움
    solid = vis & (alpha > 0.9) & (lum < 200)
    idx = ndimage.distance_transform_edt(~solid, return_distances=False,
                                         return_indices=True)
    edge_rgb = rgb[idx[0], idx[1]]
    dist_in = ndimage.distance_transform_edt(vis)
    band = vis & (dist_in <= 2.5)
    rgb = np.where(band[..., None], edge_rgb, rgb)
    # 바깥으로도 색을 번져 두면 확대 · 축소할 때 흰 섞임이 없다
    rgb = edge_rgb * (~vis)[..., None] + rgb * vis[..., None]

    # 3) 확대 + 매끈한 알파 (4배 촘촘히 → 블러 → 줄임)
    h, w = vis.shape
    W, H = w * scale, h * scale
    big_rgb = Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8)).resize(
        (W, H), Image.LANCZOS)
    m = Image.fromarray((vis * 255).astype(np.uint8)).resize(
        (W * 4, H * 4), Image.BILINEAR)
    m = m.point(lambda v: 255 if v >= 128 else 0)
    m = m.filter(ImageFilter.GaussianBlur(radius=1.6)).resize((W, H), Image.LANCZOS)
    # 원래 반투명이던 곳(그림자 · 광택)은 원래 알파를 따른다
    orig_a = Image.fromarray((alpha * 255).astype(np.uint8)).resize((W, H), Image.LANCZOS)
    m_arr = np.array(m, np.float32)
    oa = np.array(orig_a, np.float32)
    a_new = np.where(oa > 240, m_arr, np.minimum(m_arr, oa))
    a_new = np.clip(a_new, 0, 255).astype(np.uint8)
    out = np.dstack([np.array(big_rgb), a_new])
    return Image.fromarray(out, 'RGBA')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('src', nargs='?')
    ap.add_argument('dst', nargs='?')
    ap.add_argument('--all', action='store_true')
    ap.add_argument('--scale', type=int, default=2)
    a = ap.parse_args()
    if a.all:
        d = 'assets/art/frames'
        sizes_path = os.path.join(d, 'frames.json')
        sizes = json.load(open(sizes_path))
        for n in TARGETS:
            p = os.path.join(d, f'{n}.webp')
            if not os.path.exists(p):
                continue
            out = clean(Image.open(p), a.scale)
            out.save(p, quality=92, method=6, alpha_quality=100)
            print('cleaned', n, out.size)
        # 크기 표는 원래 크기(논리 크기) 그대로 둔다: 9조각 경계는 비율로 계산
        json.dump(sizes, open(sizes_path, 'w'), indent=1)
        return
    out = clean(Image.open(a.src), a.scale)
    out.save(a.dst, quality=92, method=6, alpha_quality=100)


if __name__ == '__main__':
    main()

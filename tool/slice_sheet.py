#!/usr/bin/env python3
"""스프라이트 시트 → 개별 에셋 PNG.

사용법:
  python3 tool/slice_sheet.py <시트이미지> <열> <행> <출력1.png> [<출력2.png> ...]
  python3 tool/slice_sheet.py sheet.png 5 3 assets/art/items/flower_{01..15}.png

처리:
  1) 흰 배경 제거: 가장자리에서 이어진 밝은 영역만 투명하게 한다 (물체 안의 흰색은 보존).
  2) 그리드 칸으로 나눈 뒤 칸마다 내용물 경계로 자르고,
  3) 정사각형 캔버스(기본 512px) 가운데 아래 정렬 + 6% 여백으로 맞춘다.
배경(1칸, 투명 처리 없음)은 --keep-bg 로 크기만 맞춘다.
"""
import argparse
from collections import deque

from PIL import Image


def remove_white_bg(img: Image.Image, thresh: int = 235) -> Image.Image:
    img = img.convert("RGBA")
    w, h = img.size
    px = img.load()
    seen = bytearray(w * h)
    q = deque()
    for x in range(w):
        q.append((x, 0)); q.append((x, h - 1))
    for y in range(h):
        q.append((0, y)); q.append((w - 1, y))
    while q:
        x, y = q.popleft()
        i = y * w + x
        if seen[i]:
            continue
        seen[i] = 1
        r, g, b, a = px[x, y]
        if a == 0 or (r >= thresh and g >= thresh and b >= thresh):
            px[x, y] = (255, 255, 255, 0)
            if x > 0: q.append((x - 1, y))
            if x < w - 1: q.append((x + 1, y))
            if y > 0: q.append((x, y - 1))
            if y < h - 1: q.append((x, y + 1))
    return img


def fit_square(cell: Image.Image, size: int, margin: float = 0.06) -> Image.Image:
    box = cell.getbbox()
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    if not box:
        return out
    obj = cell.crop(box)
    inner = int(size * (1 - 2 * margin))
    scale = min(inner / obj.width, inner / obj.height)
    obj = obj.resize((max(1, round(obj.width * scale)), max(1, round(obj.height * scale))), Image.LANCZOS)
    x = (size - obj.width) // 2
    y = size - int(size * margin) - obj.height  # 바닥 정렬
    out.paste(obj, (x, y), obj)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("sheet")
    ap.add_argument("cols", type=int)
    ap.add_argument("rows", type=int)
    ap.add_argument("outputs", nargs="+")
    ap.add_argument("--size", type=int, default=512)
    ap.add_argument("--keep-bg", action="store_true", help="배경 이미지: 투명 처리 없이 1080x720 으로")
    a = ap.parse_args()
    src = Image.open(a.sheet)
    if a.keep_bg:
        src.convert("RGB").resize((1080, 720), Image.LANCZOS).save(a.outputs[0])
        print("saved", a.outputs[0])
        return
    img = remove_white_bg(src)
    cw, ch = img.width / a.cols, img.height / a.rows
    for i, out in enumerate(a.outputs):
        r, c = divmod(i, a.cols)
        cell = img.crop((round(c * cw), round(r * ch), round((c + 1) * cw), round((r + 1) * ch)))
        fit_square(cell, a.size).save(out)
        print("saved", out)


if __name__ == "__main__":
    main()

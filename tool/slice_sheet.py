#!/usr/bin/env python3
"""스프라이트 시트 → 개별 에셋 PNG.

사용법:
  python3 tool/slice_sheet.py <시트이미지> <열> <행> <출력1.png> [<출력2.png> ...]
  python3 tool/slice_sheet.py sheet.png 5 3 assets/art/items/flower_{01..15}.png

처리:
  1) 흰 배경 제거: 가장자리에서 이어진 밝은 영역만 투명하게 한다 (물체 안의 흰색은 보존).
  2) 그림 덩어리를 찾아 중심이 속한 칸에 배정하고 덩어리 경계로 자른 뒤 (격자선에 걸친 부분도 보존),
  3) 정사각형 캔버스(기본 512px) 가운데 아래 정렬 + 6% 여백으로 맞춘다.
배경(1칸, 투명 처리 없음)은 --keep-bg 로 크기만 맞춘다.
"""
import argparse
from collections import deque

from PIL import Image


def _kw(path):
    return dict(quality=90, method=6, alpha_quality=100) if path.endswith('.webp') else {}


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


def drop_edge_fragments(cell: Image.Image, keep_ratio: float = 0.3) -> Image.Image:
    """칸 테두리에 닿은 작은 조각(옆 칸 그림이 삐져나온 것)을 지운다.
    가장 큰 덩어리의 keep_ratio 보다 작고 테두리에 닿은 덩어리만 지우므로, 안쪽의 반짝이 같은 장식은 남는다."""
    cell = cell.copy()
    w, h = cell.size
    alpha = cell.getchannel("A").load()
    seen = bytearray(w * h)
    comps = []
    for sy in range(h):
        for sx in range(w):
            if seen[sy * w + sx] or alpha[sx, sy] == 0:
                continue
            stack = [(sx, sy)]
            seen[sy * w + sx] = 1
            pts = []
            edge = False
            while stack:
                x, y = stack.pop()
                pts.append((x, y))
                if x == 0 or y == 0 or x == w - 1 or y == h - 1:
                    edge = True
                for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                    if 0 <= nx < w and 0 <= ny < h and not seen[ny * w + nx] and alpha[nx, ny] > 0:
                        seen[ny * w + nx] = 1
                        stack.append((nx, ny))
            comps.append((pts, edge))
    if not comps:
        return cell
    biggest = max(len(p) for p, _ in comps)
    px = cell.load()
    for pts, edge in comps:
        if edge and len(pts) < biggest * keep_ratio:
            for x, y in pts:
                px[x, y] = (0, 0, 0, 0)
    return cell


def cells_by_blobs(img: Image.Image, cols: int, rows: int) -> list:
    """투명 배경 시트를 그림 덩어리 단위로 나눈다 (격자선에 걸친 발·꼬리가 잘리지 않게).

    시트 전체에서 이어진 덩어리를 찾고, 덩어리 중심이 속한 칸에 배정한다.
    칸마다 배정된 덩어리만 남긴 이미지를 덩어리 경계로 잘라 돌려준다 (행 우선 순서)."""
    import numpy as np
    from scipy import ndimage

    a = np.asarray(img.convert("RGBA"))
    mask = a[:, :, 3] > 8
    lab, n = ndimage.label(mask, structure=np.ones((3, 3), bool))
    cw, ch = img.width / cols, img.height / rows
    idx = np.arange(1, n + 1)
    areas = ndimage.sum(mask, lab, idx)
    cents = ndimage.center_of_mass(mask, lab, idx)
    owner = np.zeros(n + 1, int) - 1
    for k, (area, (cy, cx)) in enumerate(zip(areas, cents), start=1):
        if area < 12:
            continue
        c = min(cols - 1, int(cx // cw)); r = min(rows - 1, int(cy // ch))
        owner[k] = r * cols + c
    out = []
    for cell in range(cols * rows):
        keep = owner[lab] == cell
        if not keep.any():
            out.append(Image.new("RGBA", (1, 1), (0, 0, 0, 0)))
            continue
        ys, xs = np.nonzero(keep)
        y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
        piece = a[y0:y1, x0:x1].copy()
        piece[~keep[y0:y1, x0:x1]] = 0
        out.append(Image.fromarray(piece, "RGBA"))
    return out


def fit_square(cell: Image.Image, size: int, margin: float = 0.06, clean: bool = True) -> Image.Image:
    if clean:
        cell = drop_edge_fragments(cell)
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
        src.convert("RGB").resize((1080, 720), Image.LANCZOS).save(a.outputs[0], **_kw(a.outputs[0]))
        print("saved", a.outputs[0])
        return
    img = remove_white_bg(src)
    cells = cells_by_blobs(img, a.cols, a.rows)
    for out, cell in zip(a.outputs, cells):
        fit_square(cell, a.size, clean=False).save(out, **_kw(out))
        print("saved", out)


if __name__ == "__main__":
    main()

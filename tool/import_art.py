#!/usr/bin/env python3
"""받은 시트 이미지를 게임 파일로 가져온다.

  python3 tool/import_art.py <sheet_id>=<이미지경로> [...]
  예) python3 tool/import_art.py items_flower=~/Downloads/flower.png bg_yard=yard.png

시트 정의는 tool/art_sheets.json. 앱 아이콘은 Android 런처 아이콘(mipmap)과 스토어용 512px 도 만든다.
"""
import json
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from slice_sheet import fit_square, remove_white_bg  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MIPMAPS = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}


def out(path):
    p = os.path.join(ROOT, path)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    return p


def import_sheet(sid, src, spec):
    img = Image.open(src)
    if spec.get("bg"):
        img.convert("RGB").resize((1080, 720), Image.LANCZOS).save(out(spec["files"][0]), optimize=True)
        return [spec["files"][0]]
    if spec.get("icon"):
        sq = img.convert("RGB")
        s = min(sq.size)
        sq = sq.crop(((sq.width - s) // 2, (sq.height - s) // 2, (sq.width + s) // 2, (sq.height + s) // 2))
        sq.resize((1024, 1024), Image.LANCZOS).save(out(spec["files"][0]), optimize=True)
        sq.resize((512, 512), Image.LANCZOS).save(out("docs/store/icon_512.png"), optimize=True)
        for d, px in MIPMAPS.items():
            sq.resize((px, px), Image.LANCZOS).save(out(f"android/app/src/main/res/mipmap-{d}/ic_launcher.png"), optimize=True)
        return [spec["files"][0], "docs/store/icon_512.png", "mipmap-*/ic_launcher.png"]
    clear = remove_white_bg(img)
    cols, rows, size = spec["cols"], spec["rows"], spec["size"]
    cw, ch = clear.width / cols, clear.height / rows
    done = []
    for i, f in enumerate(spec["files"]):
        r, c = divmod(i, cols)
        cell = clear.crop((round(c * cw), round(r * ch), round((c + 1) * cw), round((r + 1) * ch)))
        fit_square(cell, size).save(out(f), optimize=True)
        done.append(f)
    return done


def main():
    sheets = json.load(open(os.path.join(ROOT, "tool/art_sheets.json")))
    for arg in sys.argv[1:]:
        sid, src = arg.split("=", 1)
        files = import_sheet(sid, os.path.expanduser(src), sheets[sid])
        print(f"{sid}: {len(files)} files")


if __name__ == "__main__":
    main()

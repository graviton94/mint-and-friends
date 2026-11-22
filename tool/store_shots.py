"""스토어 스크린샷 합성: 미리보기 원본(raw_dir/<lang>_<n>.png) + 제목 · 부제 + 친구 일러스트 → docs/store/screenshots/<lang>/<n>.jpg
python3 tool/store_shots.py <raw_dir> <store.json> <lang> [<lang> ...]"""
import json
import sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter

raw, store, langs = sys.argv[1].rstrip('/') + '/', json.load(open(sys.argv[2])), sys.argv[3:]
FONT = {'ja': 'assets/fonts/MochiyPopOne-ja.ttf'}
F = 'assets/art/friends/'
PAIRS = {1: ('bori_happy', 'dubu_wave'), 2: ('kwak_summer_wave', 'nabi_summer_happy'), 3: ('mochi_picnic_happy', 'pposong_wave'),
         4: ('dotori_happy', 'kongtteok_wave'), 5: ('bogeul_happy', 'danpung_happy'), 6: ('nabi_wave', 'kwak_happy'),
         7: ('dubu_happy', 'mochi_wave'), 8: ('danpung_wave', 'bogeul_autumn_happy')}
W, H = 1080, 1920


def bg():
    im = Image.new('RGB', (W, H))
    top, bot = (207, 239, 223), (247, 251, 242)
    for y in range(H):
        t = y / H
        im.paste(tuple(int(top[i] * (1 - t) + bot[i] * t) for i in range(3)), (0, y, W, y + 1))
    return im


def friend(name, h):
    a = Image.open(F + name + '.webp').convert('RGBA')
    a = a.crop(a.getbbox())
    return a.resize((round(a.width * h / a.height), h), Image.LANCZOS)


for lang in langs:
    font = FONT.get(lang, 'assets/fonts/Jua.ttf')
    for s in store['shots']:
        t, sub = s[lang]
        i = s['n']
        im = bg().convert('RGBA')
        d = ImageDraw.Draw(im)
        size = 76
        while d.textlength(t, font=ImageFont.truetype(font, size)) >= W - 80:
            size -= 4
        d.text((W / 2, 120), t, font=ImageFont.truetype(font, size), fill=(58, 74, 52), anchor='mm')
        d.text((W / 2, 205), sub, font=ImageFont.truetype(font, 42), fill=(110, 124, 98), anchor='mm')
        shot = Image.open(f'{raw}{lang}_{i}.png').convert('RGB')
        h = 1560
        w = int(shot.width * h / shot.height)
        shot = shot.resize((w, h), Image.LANCZOS)
        x, y = (W - w) // 2, 290
        sh = Image.new('L', (W, H), 0)
        ImageDraw.Draw(sh).rounded_rectangle((x + 6, y + 14, x + w + 6, y + h + 14), 44, fill=90)
        im.paste((60, 80, 60, 255), (0, 0), sh.filter(ImageFilter.GaussianBlur(18)))
        mask = Image.new('L', (w, h), 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, w, h), 40, fill=255)
        fm = Image.new('L', (w + 16, h + 16), 0)
        ImageDraw.Draw(fm).rounded_rectangle((0, 0, w + 16, h + 16), 48, fill=255)
        im.paste(Image.new('RGB', (w + 16, h + 16), (122, 82, 48)), (x - 8, y - 8), fm)
        im.paste(shot, (x, y), mask)
        for name, side in zip(PAIRS[i], 'lr'):
            a = friend(name, 360)
            fx = -20 if side == 'l' else W - a.width + 20
            fy = H - a.height - 18
            shd = Image.new('RGBA', (W, H), (0, 0, 0, 0))
            ImageDraw.Draw(shd).ellipse((fx + a.width * 0.15, H - 52, fx + a.width * 0.85, H - 8), fill=(40, 60, 30, 90))
            im = Image.alpha_composite(im, shd.filter(ImageFilter.GaussianBlur(8)))
            rim = Image.new('RGBA', a.size, (255, 255, 255, 0))
            rim.putalpha(a.split()[3].filter(ImageFilter.MaxFilter(9)))
            im.alpha_composite(rim, (fx, fy))
            im.alpha_composite(a, (fx, fy))
        import os
        os.makedirs(f'docs/store/screenshots/{lang}', exist_ok=True)
        im.convert('RGB').save(f'docs/store/screenshots/{lang}/{i}.jpg', quality=90)
    print(lang, 'done')

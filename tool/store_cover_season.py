# 시즌 스토어 첫 스크린샷(1080×1920, 세로): 그래픽 이미지와 같은 재료로 세로 포스터를 조립한다.
# python3 tool/store_cover_season.py winter ko en ja es → docs/store/season/<시즌>/shot_<언어>.jpg
# 스토어 스크린샷 순서: [시즌 표지] + 기존 1~7 (8번은 뺀다)
import os, random, sys
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont
sys.path.insert(0, os.path.dirname(__file__))
import store_feature as sf
import store_feature_season as fs

W, H, A = 1080, 1920, sf.A
# 친구 자리 (가운데 민트 고정, 뒤 줄 둘 · 앞 줄 둘): (가운데 x, 위 y, 높이)
SLOTS = [(235, 1150, 370), (320, 1300, 420), (560, 1210, 520), (800, 1300, 420), (885, 1150, 370)]


def make(season, lang, out):
    s = fs.SEASON[season]
    random.seed(11)
    bg = Image.open(fs.art(f"areas/{s['bg']}.webp")).convert('RGB')
    k = H / bg.height
    bg = bg.resize((int(bg.width * k), H), Image.LANCZOS)
    x0 = (bg.width - W) // 2
    im = bg.crop((x0, 0, x0 + W, H))
    sat, bri, tint = s['tone']
    im = ImageEnhance.Brightness(ImageEnhance.Color(im).enhance(sat)).enhance(bri).convert('RGBA')
    im = Image.alpha_composite(im, Image.new('RGBA', (W, H), tint))
    # 위쪽 빛 (로고 뒤)
    lg = Image.new('L', (W, H), 0)
    ImageDraw.Draw(lg).ellipse((-200, -260, W + 200, 760), fill=150)
    sun = Image.new('RGBA', (W, H), (255, 250, 228, 0)); sun.putalpha(lg.filter(ImageFilter.GaussianBlur(120)))
    im = Image.alpha_composite(im, sun)
    # 시즌 장식 둘 (양옆 뒤)
    (n1, _, _, _), (n2, _, _, _) = s['props']
    for name, h, cx, top in ((n1, 560, 150, 700), (n2, 320, 960, 980)):
        a = sf.fit_h(sf.load(fs.art(f'decor/{name}.webp')), h)
        x = cx - a.width // 2
        im.alpha_composite(sf.rim(a, 7), (x, top)); im.alpha_composite(a, (x, top))
    # 친구 5명 (민트 가운데 맨 앞)
    for i in [0, 4, 1, 3, 2]:
        fid, pose = fs.LINEUP[season][i]
        cx, top, h = SLOTS[i]
        p = A + f"friends/{fid}_{s['outfit']}_{pose}.webp"
        if not os.path.exists(p):
            p = A + f'friends/{fid}_{pose}.webp'
        a = sf.fit_h(sf.load(p), h)
        x = cx - a.width // 2
        sh = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        ImageDraw.Draw(sh).ellipse((x + a.width * 0.15, top + h - 30, x + a.width * 0.85, top + h + 14), fill=(40, 60, 30, 90))
        im = Image.alpha_composite(im, sh.filter(ImageFilter.GaussianBlur(10)))
        im.alpha_composite(sf.rim(a, 9), (x, top)); im.alpha_composite(a, (x, top))
    # 앞쪽 시즌 덤불 띠
    fg = sf.load(f'docs/store/season/fg/{season}.webp'); fh = 230
    fg = fg.resize((round(fg.width * fh / fg.height), fh), Image.LANCZOS)
    x = -40
    while x < W:
        im.alpha_composite(fg, (x, H - fh + 30)); x += fg.width - 50
    # 떨어지는 효과
    for name, n, sz in s['fx']:
        src = sf.load(A + f'fx/{name}.webp')
        for _ in range(int(n * 1.6)):
            z = int(sz * 1.8 * random.uniform(0.6, 1.2))
            a = sf.fit_h(src, z).rotate(random.uniform(-40, 40), expand=True, resample=Image.BICUBIC)
            im.alpha_composite(a, (random.randint(0, W - z), random.randint(0, 1050)))
    # 로고 + 시즌 문구
    lp = A + f'title/logo_{lang}.webp'
    logo = sf.fit_h(sf.load(lp if os.path.exists(lp) else A + 'title/logo_en.webp'), 330)
    if logo.width > 940:
        logo = logo.resize((940, round(logo.height * 940 / logo.width)), Image.LANCZOS)
    lx, ly = (W - logo.width) // 2, 150
    g, pad = sf.glow(logo, 30, (255, 252, 235), 255)
    im.alpha_composite(g, (lx - pad, ly - pad)); im.alpha_composite(logo, (lx, ly))
    text, font = fs.TAG[season].get(lang, sf.TAG[lang])
    f = ImageFont.truetype(font, 60)
    d = ImageDraw.Draw(im); tw = d.textlength(text, font=f)
    cx = W // 2; bx0 = int(cx - tw / 2 - 50); bx1 = int(cx + tw / 2 + 50); by = ly + logo.height + 40
    ov = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(ov).rounded_rectangle((bx0 + 5, by + 10, bx1 + 5, by + 110), 50, fill=(60, 40, 20, 70))
    im = Image.alpha_composite(im, ov.filter(ImageFilter.GaussianBlur(6)))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((bx0, by, bx1, by + 100), 50, fill=(255, 251, 240), outline=(122, 82, 48), width=6)
    d.text((cx, by + 52), text, font=f, fill=(122, 82, 48), anchor='mm')
    os.makedirs(os.path.dirname(out), exist_ok=True)
    im.convert('RGB').save(out, quality=90)


if __name__ == '__main__':
    season = sys.argv[1]
    for l in sys.argv[2:]:
        make(season, l, f'docs/store/season/{season}/shot_{l}.jpg')

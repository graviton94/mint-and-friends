"""시즌 스토어 스크린샷 2~8번 자리(기존 1~7): 시즌 상태로 다시 찍은 게임 화면 + 시즌 배경색 · 떨어지는 효과 ·
시즌 장식 · 시즌 덤불 띠 + 시즌 의상 친구(크게, 아래가 살짝 잘리게).
python3 tool/store_shots_season.py <raw_dir> <season> <lang> [...] → docs/store/season/<season>/<lang>_<n>.jpg (n = 1~7)
raw_dir/<lang>_<n>.png 는 웹 미리보기 ?season=<season> 으로 찍은 화면."""
import json, os, random, sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter

raw, season, langs = sys.argv[1].rstrip('/') + '/', sys.argv[2], sys.argv[3:]
store = json.load(open('docs/store/store.json'))
W, H = 1080, 1920
A = 'assets/art/'
FONT = {'ja': os.environ.get('JA_FONT', 'assets/fonts/MochiyPopOne-ja.ttf')}
OUTFIT = {'spring': 'picnic', 'summer': 'summer', 'autumn': 'autumn', 'winter': 'winter'}[season]
STYLE = {  # 위 · 아래 색, 제목 · 부제 색, 떨어지는 효과, 위쪽 양옆 장식
    'spring': ((255, 226, 236), (250, 252, 240), (122, 64, 86), (150, 104, 120), ['cherry_petal', 'butterfly_open'], ('big_tree_spring', 'lantern_spring')),
    'summer': ((190, 234, 250), (252, 248, 228), (36, 92, 120), (70, 120, 140), ['sun_sparkle'], ('parasol_summer', 'sandcastle_summer')),
    'autumn': ((255, 222, 180), (252, 244, 226), (122, 70, 30), (150, 100, 60), ['maple_leaf', 'ginkgo_leaf'], ('big_tree_autumn', 'lantern_autumn')),
    'winter': ((206, 226, 248), (244, 248, 253), (52, 78, 120), (96, 116, 150), ['snowflake'], ('big_tree_winter', 'snowman')),
}[season]
# 화면마다 양옆 친구 (기본 자세 이름) — 시즌 의상으로 바꿔 쓴다
PAIRS = {1: ('bori_happy', 'dubu_wave'), 2: ('kwak_wave', 'nabi_happy'), 3: ('mochi_happy', 'pposong_wave'),
         4: ('dotori_happy', 'kongtteok_wave'), 5: ('bogeul_happy', 'danpung_happy'), 6: ('nabi_wave', 'kwak_happy'),
         7: ('dubu_happy', 'mochi_wave')}


def load(p):
    a = Image.open(p).convert('RGBA')
    return a.crop(a.getbbox())


def fit_h(a, h):
    return a.resize((round(a.width * h / a.height), h), Image.LANCZOS)


def friend(name, h):
    fid, pose = name.rsplit('_', 1)
    p = f'{A}friends/{fid}_{OUTFIT}_{pose}.webp'
    return fit_h(load(p if os.path.exists(p) else f'{A}friends/{name}.webp'), h)


def rim(a, px=9):
    r = Image.new('RGBA', a.size, (255, 255, 255, 0)); r.putalpha(a.split()[3].filter(ImageFilter.MaxFilter(px))); return r


top, bot, tcol, scol, fx, (deco_l, deco_r) = STYLE
for lang in langs:
    font = FONT.get(lang, 'assets/fonts/Jua.ttf')
    for s in store['shots'][:7]:
        t, sub = s[lang]; i = s['n']
        random.seed(i * 7 + len(season))
        im = Image.new('RGB', (W, H))
        for y in range(H):
            k = y / H
            im.paste(tuple(int(top[c] * (1 - k) + bot[c] * k) for c in range(3)), (0, y, W, y + 1))
        im = im.convert('RGBA')
        # 떨어지는 효과 (배경)
        for name in fx:
            src = load(f'{A}fx/{name}.webp')
            for _ in range(14 if name != 'butterfly_open' else 3):
                z = random.randint(34, 70)
                a = fit_h(src, z).rotate(random.uniform(-40, 40), expand=True, resample=Image.BICUBIC)
                a.putalpha(a.split()[3].point(lambda v: int(v * 0.85)))
                im.alpha_composite(a, (random.randint(0, W - z), random.randint(0, H - z)))
        # 위쪽 양옆 시즌 장식 (제목 옆)
        for name, x0, h in ((deco_l, -30, 230), (deco_r, W - 170, 180)):
            a = fit_h(load(f'{A}decor/{name}.webp'), h)
            x = x0 if x0 >= 0 else x0
            im.alpha_composite(rim(a, 7), (x, 40)); im.alpha_composite(a, (x, 40))
        d = ImageDraw.Draw(im)
        size = 76
        while d.textlength(t, font=ImageFont.truetype(font, size)) >= W - 380:
            size -= 4
        d.text((W / 2, 120), t, font=ImageFont.truetype(font, size), fill=tcol, anchor='mm')
        fs = 42
        while d.textlength(sub, font=ImageFont.truetype(font, fs)) >= W - 360:
            fs -= 2
        d.text((W / 2, 205), sub, font=ImageFont.truetype(font, fs), fill=scol, anchor='mm')
        # 게임 화면 (기존과 같은 틀)
        shot = Image.open(f'{raw}{lang}_{i}.png').convert('RGB')
        h = 1560; w = int(shot.width * h / shot.height)
        shot = shot.resize((w, h), Image.LANCZOS)
        x, y = (W - w) // 2, 290
        sh = Image.new('L', (W, H), 0)
        ImageDraw.Draw(sh).rounded_rectangle((x + 6, y + 14, x + w + 6, y + h + 14), 44, fill=90)
        im.paste((60, 70, 90, 255), (0, 0), sh.filter(ImageFilter.GaussianBlur(18)))
        mask = Image.new('L', (w, h), 0); ImageDraw.Draw(mask).rounded_rectangle((0, 0, w, h), 40, fill=255)
        fm = Image.new('L', (w + 16, h + 16), 0); ImageDraw.Draw(fm).rounded_rectangle((0, 0, w + 16, h + 16), 48, fill=255)
        im.paste(Image.new('RGB', (w + 16, h + 16), (122, 82, 48)), (x - 8, y - 8), fm)
        im.paste(shot, (x, y), mask)
        # 시즌 덤불 띠 (화면 아래를 덮는다)
        fg = load(f'docs/store/season/fg/{season}.webp'); fh = 190
        fg = fg.resize((round(fg.width * fh / fg.height), fh), Image.LANCZOS)
        xx = -40
        while xx < W:
            im.alpha_composite(fg, (xx, H - fh + 30)); xx += fg.width - 50
        # 친구 둘 (크게, 아래가 화면 밖으로 살짝 잘리게)
        for name, side in zip(PAIRS[i], 'lr'):
            a = friend(name, 560)
            fx_ = -60 if side == 'l' else W - a.width + 60
            fy = H - int(a.height * 0.86)
            im.alpha_composite(rim(a), (fx_, fy)); im.alpha_composite(a, (fx_, fy))
        os.makedirs(f'docs/store/season/{season}', exist_ok=True)
        im.convert('RGB').save(f'docs/store/season/{season}/{lang}_{i}.jpg', quality=90)
    print(lang, season, 'done')

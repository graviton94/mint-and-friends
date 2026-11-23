# 시즌 스토어 그래픽 이미지(1024×500): 이미 있는 그림만 조립 (구역 배경 · 시즌 의상 친구 · 시즌 장식 · 떨어지는 효과).
# python3 tool/store_feature_season.py winter ko en ja es → docs/store/season/winter/{ko,en,ja,es}.png
import os, random, sys
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont
sys.path.insert(0, os.path.dirname(__file__))
import store_feature as sf

W, H, A = sf.W, sf.H, sf.A
SEASON = {
    # 배경, 색 보정(채도, 밝기, 덧칠 RGBA), 의상, 뒤 장식(왼쪽 · 오른쪽), 떨어지는 효과
    'spring': dict(bg='yard_bg', tone=(1.1, 1.03, (255, 225, 235, 30)), outfit='picnic',
                   props=[('big_tree_spring', 230, 540, 120), ('lantern_spring', 120, 1000, 250)],
                   fx=[('cherry_petal', 22, 34), ('butterfly_open', 3, 34)]),
    'summer': dict(bg='seaside_bg', tone=(1.12, 1.04, (255, 240, 200, 18)), outfit='summer',
                   props=[('parasol_summer', 190, 545, 150), ('sandcastle_summer', 110, 1000, 270)],
                   fx=[('sun_sparkle', 9, 30)]),
    # 가을은 다음 업데이트 구역(사과 과수원) 그림을 미리 쓴다 (content/updates/u1_orchard)
    'autumn': dict(bg='@orchard_bg', tone=(1.1, 1.0, (255, 170, 80, 40)), outfit='autumn',
                   props=[('@apple_tree_autumn', 230, 540, 120), ('@scarecrow_autumn', 130, 1000, 245)],
                   fx=[('maple_leaf', 22, 34), ('ginkgo_leaf', 12, 30)]),
    'winter': dict(bg='snow_village_bg', tone=(1.0, 0.95, (120, 140, 210, 35)), outfit='winter',
                   props=[('big_tree_winter', 230, 540, 120), ('snowman', 120, 1000, 255)],
                   fx=[('snowflake', 30, 26)]),
}


ORCHARD = 'content/updates/u1_orchard/art/'

# 친구는 최대 5명: 가운데 민트(bori)는 늘 고정, 나머지 4명과 자세는 시즌마다 바꾼다
# 자리: 뒤 왼쪽 · 앞 왼쪽 · (가운데 민트) · 앞 오른쪽 · 뒤 오른쪽
SLOTS = [(590, 222, 160), (668, 268, 182), (782, 238, 220), (892, 268, 182), (952, 222, 150)]
LINEUP = {
    'spring': [('nabi', 'wave'), ('dubu', 'happy'), ('bori', 'happy'), ('kongtteok', 'idle'), ('danpung', 'wave')],
    'summer': [('pposong', 'happy'), ('bogeul', 'wave'), ('bori', 'wave'), ('kwak', 'happy'), ('dotori', 'idle')],
    'autumn': [('mochi', 'idle'), ('dotori', 'happy'), ('bori', 'idle'), ('danpung', 'happy'), ('nabi', 'wave')],
    'winter': [('kwak', 'wave'), ('pposong', 'idle'), ('bori', 'happy'), ('dubu', 'wave'), ('bogeul', 'happy')],
}


def art(path):
    # '@이름' = 비축 콘텐츠(사과 과수원) 그림
    if '/@' in path:
        d, n = path.split('/@')
        return ORCHARD + d.split('/')[-1] + '/' + n
    return A + path


def make(season, lang, out):
    s = SEASON[season]
    random.seed(7)
    bg = Image.open(art(f"areas/{s['bg']}.webp")).convert('RGB')
    k = max(W / bg.width, H / bg.height) * 1.05
    bg = bg.resize((int(bg.width * k), int(bg.height * k)), Image.LANCZOS)
    y0 = int((bg.height - H) * 0.35)
    im = bg.crop(((bg.width - W) // 2, y0, (bg.width - W) // 2 + W, y0 + H))
    sat, bri, tint = s['tone']
    im = ImageEnhance.Brightness(ImageEnhance.Color(im).enhance(sat)).enhance(bri).convert('RGBA')
    im = Image.alpha_composite(im, Image.new('RGBA', (W, H), tint))
    # 뒤 장식
    for name, h, cx, top in s['props']:
        a = sf.fit_h(sf.load(art(f'decor/{name}.webp')), h)
        x = cx - a.width // 2
        im.alpha_composite(sf.rim(a, 5), (x, top)); im.alpha_composite(a, (x, top))
    # 친구 (시즌 의상, 최대 5명, 가운데 민트 고정)
    order = [0, 4, 1, 3, 2]  # 뒤에서 앞으로, 민트는 맨 앞에
    for i in order:
        fid, pose = LINEUP[season][i]
        cx, top, h = SLOTS[i]
        p = A + f"friends/{fid}_{s['outfit']}_{pose}.webp"
        if not os.path.exists(p):
            p = A + f'friends/{fid}_{pose}.webp'
        a = sf.fit_h(sf.load(p), h)
        x = cx - a.width // 2
        sh = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        ImageDraw.Draw(sh).ellipse((x + a.width * 0.18, top + h - 14, x + a.width * 0.82, top + h + 8), fill=(40, 60, 30, 80))
        im = Image.alpha_composite(im, sh.filter(ImageFilter.GaussianBlur(6)))
        im.alpha_composite(sf.rim(a, 5), (x, top)); im.alpha_composite(a, (x, top))
    # 앞쪽 시즌 덤불 띠 (docs/store/season/fg)
    fg = sf.load(f'docs/store/season/fg/{season}.webp'); fh = 100
    fg = fg.resize((round(fg.width * fh / fg.height), fh), Image.LANCZOS)
    x = -30
    while x < W:
        im.alpha_composite(fg, (x, H - fh + 18)); x += fg.width - 30
    # 떨어지는 효과
    for name, n, sz in s['fx']:
        src = sf.load(A + f'fx/{name}.webp')
        for _ in range(n):
            z = int(sz * random.uniform(0.6, 1.2))
            a = sf.fit_h(src, z).rotate(random.uniform(-40, 40), expand=True, resample=Image.BICUBIC)
            im.alpha_composite(a, (random.randint(0, W - z), random.randint(0, H - z - 60)))
    # 로고 + 태그라인 (기본 그래픽과 같은 자리)
    lp = A + f'title/logo_{lang}.webp'
    logo = sf.fit_h(sf.load(lp if os.path.exists(lp) else A + 'title/logo_en.webp'), 170 if lang != 'ko' else 176)
    if logo.width > 500:
        logo = logo.resize((500, round(logo.height * 500 / logo.width)), Image.LANCZOS)
    lx, ly = 40, 70
    g, pad = sf.glow(logo, 22, (255, 252, 235), 255)
    im.alpha_composite(g, (lx - pad, ly - pad)); im.alpha_composite(logo, (lx, ly))
    text, font = TAG[season].get(lang, sf.TAG[lang])
    f = ImageFont.truetype(font, 32)
    d = ImageDraw.Draw(im); tw = d.textlength(text, font=f)
    cx = lx + logo.width // 2; bx0 = int(cx - tw / 2 - 28); bx1 = int(cx + tw / 2 + 28); by = ly + logo.height + 18
    ov = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(ov).rounded_rectangle((bx0 + 3, by + 6, bx1 + 3, by + 58), 28, fill=(60, 40, 20, 70))
    im = Image.alpha_composite(im, ov.filter(ImageFilter.GaussianBlur(4)))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((bx0, by, bx1, by + 54), 27, fill=(255, 251, 240), outline=(122, 82, 48), width=4)
    d.text((cx, by + 28), text, font=f, fill=(122, 82, 48), anchor='mm')
    os.makedirs(os.path.dirname(out), exist_ok=True)
    im.convert('RGB').save(out, optimize=True)


J, I = sf.JUA, sf.IPA
TAG = {
    'spring': {'ko': ('벚꽃 정원에 봄이 왔어요!', J), 'en': ('Spring blooms in your garden!', J), 'ja': ('桜の庭に春が来たよ!', I), 'es': ('¡La primavera florece!', J)},
    'summer': {'ko': ('바닷가 정원의 여름 휴가!', J), 'en': ('Summer by the seaside!', J), 'ja': ('海辺の庭で夏休み!', I), 'es': ('¡Verano junto al mar!', J)},
    'autumn': {'ko': ('단풍 가득 가을 정원!', J), 'en': ('A cozy autumn garden!', J), 'ja': ('紅葉いっぱいの秋の庭!', I), 'es': ('¡Un jardín de otoño!', J)},
    'winter': {'ko': ('눈 내리는 겨울 정원!', J), 'en': ('A snowy winter garden!', J), 'ja': ('雪ふる冬の庭!', I), 'es': ('¡Un jardín nevado!', J)},
}

if __name__ == '__main__':
    season = sys.argv[1]
    for l in sys.argv[2:]:
        make(season, l, f'docs/store/season/{season}/{l}.png')

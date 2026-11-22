"""Jua 에 스페인어 · 포르투갈어 글자를 넣는다 (Jua 자신의 글리프만으로: ' ~ . , ? ! 를 줄이고 돌려 강세 부호로).
python3 tool/font_latin.py <원본 Jua.ttf> <출력 .ttf>
Jua 는 SIL OFL 1.1 (예약 글꼴 이름 없음) — 수정본 배포 가능."""
import math
import sys
from fontTools.ttLib import TTFont
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.recordingPen import DecomposingRecordingPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.ttGlyphPen import TTGlyphPen

src, dst = sys.argv[1], sys.argv[2]
f = TTFont(src)
gs = f.getGlyphSet()
glyf, hmtx = f['glyf'], f['hmtx']


def rec(name):
    p = DecomposingRecordingPen(gs)
    gs[name].draw(p)
    return p.value


def contours(value):
    out, cur = [], []
    for op, args in value:
        cur.append((op, args))
        if op in ('closePath', 'endPath'):
            out.append(cur)
            cur = []
    return out


def bounds_of(value):
    p = BoundsPen(None)
    for op, args in value:
        getattr(p, op)(*args)
    return p.bounds


def replay(value, pen):
    for op, args in value:
        getattr(pen, op)(*args)


def part(name, scale, rot_deg, cx, cy, flip_x=False):
    """name 글리프를 가운데 기준으로 scale · 회전해서 (cx, cy) 가 가운데가 되게 놓은 기록."""
    v = rec(name)
    x0, y0, x1, y1 = bounds_of(v)
    mx, my = (x0 + x1) / 2, (y0 + y1) / 2
    a = math.radians(rot_deg)
    sx = -scale if flip_x else scale
    c, s = math.cos(a), math.sin(a)
    # (x,y) → 가운데로 옮기고 → 크기 → 회전 → (cx,cy)
    m = (sx * c, sx * s, -scale * s, scale * c, 0, 0)
    out = []
    pen = _Rec(out)
    tp = TransformPen(pen, (m[0], m[1], m[2], m[3], cx - (m[0] * mx + m[2] * my), cy - (m[1] * mx + m[3] * my)))
    replay(v, tp)
    return out


class _Rec:
    def __init__(self, out):
        self.out = out

    def __getattr__(self, op):
        return lambda *args: self.out.append((op, args))


def top_of(name):
    return bounds_of(rec(name))[3]


def center_x(name):
    x0, _, x1, _ = bounds_of(rec(name))
    return (x0 + x1) / 2


def dotless(name):
    cs = contours(rec(name))
    cs.sort(key=lambda c: bounds_of(c)[1])
    return [x for c in cs[:-1] for x in c]  # 가장 위(점) 하나를 뺀다


ACUTE = lambda cx, y: part('quotesingle', 0.6, -38, cx, y)
GRAVE = lambda cx, y: part('quotesingle', 0.6, 38, cx, y)
TILDE = lambda cx, y: part('asciitilde', 0.55, 0, cx, y)
DIER = lambda cx, y: part('period', 0.8, 0, cx - 62, y) + part('period', 0.8, 0, cx + 62, y)
CIRC = lambda cx, y: part('quotesingle', 0.55, -38, cx - 40, y) + part('quotesingle', 0.55, 38, cx + 40, y)
CEDILLA = lambda cx: part('comma', 0.75, 0, cx + 10, -90)

LOW_GAP, CAP_GAP = 125, 150


def accented(base, mark, body=None):
    v = list(body if body is not None else rec(base))
    cx = center_x(base)
    if mark == 'cedilla':
        return v + CEDILLA(cx)
    y = (top_of(base) if body is None else bounds_of(body)[3]) + (CAP_GAP if base.isupper() else LOW_GAP)
    return v + {'acute': ACUTE, 'grave': GRAVE, 'tilde': TILDE, 'dieresis': DIER, 'circumflex': CIRC}[mark](cx, y)


chars = {
    # 스페인어
    0xE1: ('a', 'acute'), 0xE9: ('e', 'acute'), 0xED: ('i', 'acute'), 0xF3: ('o', 'acute'), 0xFA: ('u', 'acute'),
    0xC1: ('A', 'acute'), 0xC9: ('E', 'acute'), 0xCD: ('I', 'acute'), 0xD3: ('O', 'acute'), 0xDA: ('U', 'acute'),
    0xF1: ('n', 'tilde'), 0xD1: ('N', 'tilde'), 0xFC: ('u', 'dieresis'), 0xDC: ('U', 'dieresis'),
    # 포르투갈어 (나중을 위해)
    0xE7: ('c', 'cedilla'), 0xC7: ('C', 'cedilla'), 0xE3: ('a', 'tilde'), 0xF5: ('o', 'tilde'),
    0xC3: ('A', 'tilde'), 0xD5: ('O', 'tilde'), 0xE2: ('a', 'circumflex'), 0xEA: ('e', 'circumflex'),
    0xF4: ('o', 'circumflex'), 0xC2: ('A', 'circumflex'), 0xCA: ('E', 'circumflex'), 0xD4: ('O', 'circumflex'),
    0xE0: ('a', 'grave'), 0xC0: ('A', 'grave'),
}
new = {}
for cp, (base, mark) in chars.items():
    body = dotless(base) if base == 'i' else None
    new[cp] = (f'uni{cp:04X}', accented(base, mark, body), hmtx[base][0])
# ¿ ¡ : ? ! 를 뒤집어 아래로 내린다
for cp, base in ((0xBF, 'question'), (0xA1, 'exclam')):
    x0, y0, x1, y1 = bounds_of(rec(base))
    h = y1 - y0
    new[cp] = (f'uni{cp:04X}', part(base, 1.0, 180, (x0 + x1) / 2, 470 - h / 2), hmtx[base][0])

for cp, (gname, value, adv) in new.items():
    pen = TTGlyphPen(None)
    replay(value, pen)
    glyf[gname] = pen.glyph()
    x0 = bounds_of(value)[0]
    hmtx[gname] = (adv, int(round(x0)))
f.setGlyphOrder(list(glyf.glyphOrder))
for t in f['cmap'].tables:
    if t.isUnicode():
        for cp, (gname, _, _) in new.items():
            t.cmap[cp] = gname
if 'post' in f and f['post'].formatType == 2.0:
    f['post'].extraNames = []
    f['post'].mapping = {}
for rec_ in f['name'].names:
    if rec_.nameID == 5:
        rec_.string = rec_.toUnicode() + '; Mint & Friends Latin (es/pt) additions'
f.save(dst)
print('added', len(new), 'glyphs →', dst)

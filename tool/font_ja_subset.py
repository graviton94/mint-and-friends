"""일본어 글꼴 Mochiy Pop One (OFL) 을 게임 문구에 쓰는 글자만 남겨 줄인다.
ja.json 이 바뀌면 다시 돌린다: python3 tool/font_ja_subset.py <MochiyPopOne-Regular.ttf 원본>
원본: https://github.com/google/fonts/tree/main/ofl/mochiypopone"""
import json
import sys
from fontTools import subset
from fontTools.ttLib import TTFont

src = sys.argv[1]
ja = json.load(open('assets/i18n/ja.json'))
chars = set(''.join(v for v in ja.values() if isinstance(v, str)))
for a, b in [(0x20, 0x7E), (0xA0, 0xFF), (0x3000, 0x303F), (0x3040, 0x309F), (0x30A0, 0x30FF),
             (0xFF00, 0xFFEF), (0x2010, 0x2027), (0x2190, 0x21FF), (0x2600, 0x26FF)]:
    chars |= {chr(c) for c in range(a, b + 1)}
f = TTFont(src)
cmap = f.getBestCmap()
have = [ord(c) for c in chars if ord(c) in cmap]
opt = subset.Options()
opt.layout_features = ['*']
opt.name_IDs = ['*']
opt.notdef_outline = True
s = subset.Subsetter(opt)
s.populate(unicodes=have)
s.subset(f)
f.save('assets/fonts/MochiyPopOne-ja.ttf')
print('glyphs for', len(have), 'characters')

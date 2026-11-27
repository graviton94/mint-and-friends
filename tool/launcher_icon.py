"""홈 화면(런처) 아이콘을 시즌판 또는 기본으로 바꾸고, 앱의 계절 키(lib/game/season_key.dart)도 함께 바꾼다 (D-056 · D-103).
앱 업데이트에 실려야 폰에 반영된다.
python3 tool/launcher_icon.py winter   → docs/store/season/winter/app_icon.png 로
python3 tool/launcher_icon.py default  → assets/art/icon/app_icon.png (기본) 으로"""
import sys
from PIL import Image

MIPMAPS = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}
s = sys.argv[1]
src = 'assets/art/icon/app_icon.png' if s == 'default' else f'docs/store/season/{s}/app_icon.png'
im = Image.open(src).convert('RGB')
for d, px in MIPMAPS.items():
    im.resize((px, px), Image.LANCZOS).save(f'android/app/src/main/res/mipmap-{d}/ic_launcher.png', optimize=True)
print('launcher icon:', s)

if s != 'default':
    import re
    p = 'lib/game/season_key.dart'
    src_k = open(p).read()
    src_k = re.sub(r"const String kSeasonKey = '[a-z]+';", f"const String kSeasonKey = '{s}';", src_k)
    open(p, 'w').write(src_k)
    print('season key:', s)

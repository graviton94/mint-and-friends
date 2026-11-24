"""홈 화면(런처) 아이콘을 시즌판 또는 기본으로 바꾼다. 앱 업데이트에 실려야 폰에 반영된다 (D-056).
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

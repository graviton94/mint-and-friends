# 스토어 그래픽 이미지(1024×500) 만들기: python3 tool/store_feature.py en ko ja → docs/store/feature/{en,ko,ja}.png
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageEnhance
import sys
W,H=1024,500
A='assets/art/'
JUA='assets/fonts/Jua.ttf'; IPA='/usr/share/fonts/opentype/ipafont-gothic/ipagp.ttf'
TAG={'es':('¡Combina, ayuda y decora!',JUA),'en':('Merge, help friends, decorate!',JUA),'ko':('합치고, 돕고, 꾸미는 힐링 정원',JUA),'ja':('合成して、助けて、飾る癒しの庭',IPA)}
def load(p): return Image.open(p).convert('RGBA')
def fit_h(im,h):
    im=im.crop(im.getbbox()); return im.resize((round(im.width*h/im.height),h),Image.LANCZOS)
def rim(a,px=7,col=(255,255,255)):
    al=a.split()[3].filter(ImageFilter.MaxFilter(px)); r=Image.new('RGBA',a.size,col+(0,)); r.putalpha(al); return r
def glow(a,rad=14,col=(255,248,220),alpha=200):
    pad=rad*3; c=Image.new('RGBA',(a.width+pad*2,a.height+pad*2),(0,0,0,0))
    al=Image.new('L',c.size,0); al.paste(a.split()[3],(pad,pad)); al=al.filter(ImageFilter.GaussianBlur(rad)).point(lambda v:min(255,int(v*alpha/255*1.6)))
    g=Image.new('RGBA',c.size,col+(0,)); g.putalpha(al); return g,pad
def make(lang,out):
    # 배경: 앞마당 풍경 + 살짝 밝게, 위쪽 하늘에 빛
    bg=Image.open(A+'areas/yard_bg.webp').convert('RGB')
    s=max(W/bg.width,H/bg.height)*1.05; bg=bg.resize((int(bg.width*s),int(bg.height*s)),Image.LANCZOS)
    y0=int((bg.height-H)*0.35); im=bg.crop(((bg.width-W)//2,y0,(bg.width-W)//2+W,y0+H))
    im=ImageEnhance.Color(im).enhance(1.08).convert('RGBA')
    # 왼쪽 위 부드러운 햇살
    lg=Image.new('L',(W,H),0); ImageDraw.Draw(lg).ellipse((-260,-300,620,330),fill=170); lg=lg.filter(ImageFilter.GaussianBlur(90))
    sun=Image.new('RGBA',(W,H),(255,250,228,0)); sun.putalpha(lg); im=Image.alpha_composite(im,sun)
    # 친구 줄 (오른쪽, 뒤에서 앞으로)
    back=[('kongtteok_wave',150,600,250),('mochi_happy',160,700,232),('nabi_wave',165,806,240),('pposong_happy',150,905,262)]
    front=[('dotori_happy',170,560,300),('dubu_wave',190,655,288),('bori_happy',215,760,272),('kwak_happy',185,875,296),('danpung_wave',170,955,318)]
    for grp in (back,front):
        for name,h,cx,top in grp:
            a=fit_h(load(A+f'friends/{name}.webp'),h)
            x=cx-a.width//2
            sh=Image.new('RGBA',(W,H),(0,0,0,0)); ImageDraw.Draw(sh).ellipse((x+a.width*0.18,top+h-14,x+a.width*0.82,top+h+8),fill=(40,60,30,80))
            im=Image.alpha_composite(im,sh.filter(ImageFilter.GaussianBlur(6)))
            im.alpha_composite(rim(a,5),(x,top)); im.alpha_composite(a,(x,top))
    # 앞쪽 꽃 덤불 (타이틀 화면 전경)
    fg=load(A+'title/fg.webp'); fh=128; fg=fg.resize((round(fg.width*fh/fg.height),fh),Image.LANCZOS)
    x=-60
    while x<W:
        im.alpha_composite(fg,(x,H-fh+30)); x+=fg.width-40
    # 떠 있는 고단계 아이템 + 반짝이
    items=[('flower_18',74,590,40,-8),('snack_16',66,700,70,6),('tea_17',70,805,36,-5),('stardust_20',74,905,70,8)]
    for n,sz,x,y,rot in items:
        p=A+f'items/{n}.webp'
        try: a=load(p)
        except Exception: continue
        a=fit_h(a,sz).rotate(rot,expand=True,resample=Image.BICUBIC)
        g,pad=glow(a,10); im.alpha_composite(g,(x-pad,y-pad)); im.alpha_composite(a,(x,y))
    sp=load(A+'fx/sun_sparkle.webp')
    for x,y,sz in [(585,120,34),(700,30,26),(905,22,30),(1000,150,24),(470,40,28)]:
        a=fit_h(sp,sz); im.alpha_composite(a,(x-sz//2,y))
    # 로고 + 빛
    import os
    lp=A+f'title/logo_{lang}.webp'
    logo=fit_h(load(lp if os.path.exists(lp) else A+'title/logo_en.webp'),170 if lang!='ko' else 176)
    if logo.width>500: logo=logo.resize((500,round(logo.height*500/logo.width)),Image.LANCZOS)
    lx,ly=40,70
    g,pad=glow(logo,22,(255,252,235),255); im.alpha_composite(g,(lx-pad,ly-pad)); im.alpha_composite(logo,(lx,ly))
    # 태그라인 리본
    text,font=TAG[lang]; f=ImageFont.truetype(font,32)
    d=ImageDraw.Draw(im); tw=d.textlength(text,font=f)
    cx=lx+logo.width//2; bx0=int(cx-tw/2-28); bx1=int(cx+tw/2+28); by=ly+logo.height+18
    ov=Image.new('RGBA',(W,H),(0,0,0,0)); od=ImageDraw.Draw(ov)
    od.rounded_rectangle((bx0+3,by+6,bx1+3,by+58),28,fill=(60,40,20,70))
    ov=ov.filter(ImageFilter.GaussianBlur(4)); im=Image.alpha_composite(im,ov)
    d=ImageDraw.Draw(im)
    d.rounded_rectangle((bx0,by,bx1,by+54),27,fill=(255,251,240),outline=(122,82,48),width=4)
    d.text((cx,by+28),text,font=f,fill=(122,82,48),anchor='mm')
    im.convert('RGB').save(out,optimize=True)
if __name__=='__main__':
    for l in sys.argv[1:]:
        make(l,f'docs/store/feature/{l}.png')

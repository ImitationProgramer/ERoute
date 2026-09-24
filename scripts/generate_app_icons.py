#!/usr/bin/env python3
"""Deterministic platform export of the user-approved E artwork. No image generation.

Requires Pillow and numpy. Retains source PNGs; emits only icon resources and an
export manifest. Android uses Light, never drawable-night/aliases/polling.
"""
from pathlib import Path
import hashlib
import json
import math
import re
import numpy as np
from PIL import Image, ImageDraw, ImageChops

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'docs/ui/icon-review-v1'
EXPORT = ROOT / 'docs/ui/icon-platform-v1'
ANDROID = ROOT / 'apps/mobile/android/app/src'
IOS = ROOT / 'apps/mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset'
SIZE = 1254
BADGE = (.70, .51, .88, .69)  # Right hillside; clear of the E and the road.
written = []

def save(image, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format='PNG', optimize=True)
    written.append(path)

def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    written.append(path)

def scaled(image, size):
    return image.resize((size, size), Image.Resampling.LANCZOS)

def badge_layers(size=SIZE):
    """One geometric P master for color and alpha-only monochrome exports."""
    tile = Image.new('L', (size, size))
    inside = Image.new('L', (size, size))
    glyph = Image.new('L', (size, size))
    x0,y0,x1,y1 = [round(v*size) for v in BADGE]
    w=x1-x0
    ImageDraw.Draw(tile).rounded_rectangle((x0,y0,x1,y1), radius=w*.24, fill=255)
    ImageDraw.Draw(inside).rounded_rectangle((x0+w*.055,y0+w*.055,x1-w*.055,y1-w*.055), radius=w*.20, fill=255)
    d=ImageDraw.Draw(glyph)
    def rect(box): return tuple(round((x0 if i%2==0 else y0)+v*w) for i,v in enumerate(box))
    d.rounded_rectangle(rect((.24,.17,.77,.59)), radius=w*.12, fill=255)
    d.rectangle(rect((.24,.30,.41,.84)), fill=255)
    d.rounded_rectangle(rect((.42,.31,.60,.44)), radius=w*.035, fill=0)
    return tile,inside,glyph

def with_badge(color):
    tile,inside,glyph=badge_layers()
    out=color.copy().convert('RGBA')
    for ink,mask in [('#142a48',tile),('#fff1ad',inside),('#142a48',glyph)]:
        out.paste(Image.new('RGBA',out.size,ink),(0,0),mask)
    return out

def alpha_mono(source):
    # White background and white E become actual alpha=0, not opaque white.
    gray=np.asarray(source.convert('L')).astype(float)
    alpha=np.clip((220-gray)*255/190,0,255).round().astype('uint8')
    out=Image.new('RGBA',source.size,(255,255,255,0))
    out.putalpha(Image.fromarray(alpha))
    return out

def split_e(source):
    """Separate only the E into foreground; road/horizon remain the backdrop.

    The tiny hidden area beneath the opaque E uses the adjacent disk's row color.
    Exact original pixels reconstruct the image at rest. No invented scenery.
    """
    rgb=np.array(source.convert('RGB'))
    yy,xx=np.indices(rgb.shape[:2])
    mask=(xx>SIZE*.40)&(xx<SIZE*.60)&(yy>SIZE*.29)&(yy<SIZE*.50)&(rgb[:,:,0]<210)
    assert mask.sum()>10000
    bg=rgb.copy()
    for y in np.where(mask.any(axis=1))[0]:
        xs=np.where(mask[y])[0]
        left,right=xs[0]-2,xs[-1]+2
        for x in xs:
            t=(x-left)/(right-left)
            bg[y,x]=np.rint(rgb[y,left]*(1-t)+rgb[y,right]*t)
    fg=Image.fromarray(rgb).convert('RGBA')
    fg.putalpha(Image.fromarray(mask.astype('uint8')*255))
    backdrop=Image.fromarray(bg).convert('RGBA')
    assert ImageChops.difference(Image.alpha_composite(backdrop,fg).convert('RGB'),source.convert('RGB')).getbbox() is None
    return backdrop,fg

def adaptive(image, opaque=False):
    # 108dp layer, central 72dp viewport; extend background edges into overscan.
    center=np.array(scaled(image.convert('RGBA'),288))
    arr=np.pad(center,((72,72),(72,72),(0,0)),mode='edge') if opaque else np.zeros((432,432,4),dtype=np.uint8)
    if not opaque: arr[72:360,72:360]=center
    return Image.fromarray(arr)

def check_safe(image):
    a=np.array(image.getchannel('A'))
    y,x=np.where(a>127)
    radius=np.sqrt((x-215.5)**2+(y-215.5)**2)
    maximum=float(radius.max()/4)
    assert maximum<=33, f'Silhouette exceeds 66dp safe circle: {maximum}'
    return round(maximum,3)

def main():
    metadata=json.loads((SOURCE/'generation.json').read_text())
    sources={}
    for name,a in metadata['assets'].items():
        path=SOURCE/a['filename']
        assert hashlib.sha256(path.read_bytes()).hexdigest()==a['sha256'], 'Approved original changed'
        sources[name]=Image.open(path).convert('RGB')
        assert sources[name].size==(SIZE,SIZE)
    EXPORT.mkdir(parents=True,exist_ok=True)
    light,dark=sources['light'],sources['dark']
    mono=alpha_mono(sources['mono'])
    # Transparent outside and in the E's stem, bars and open inner counters.
    alpha=mono.getchannel('A')
    assert alpha.getpixel((0,0))==0
    assert alpha.getpixel((550,320))==0  # White E stem is negative space.
    assert alpha.getpixel((640,365))==255  # Black gap between white E bars.
    tile,inside,glyph=badge_layers()
    # Neither source silhouette nor E/road color regions are covered by the P.
    assert ImageChops.multiply(alpha,tile).getbbox() is None
    preview_alpha=ImageChops.lighter(alpha,ImageChops.subtract(tile,glyph))
    preview_mono=mono.copy(); preview_mono.putalpha(preview_alpha)
    backdrop,foreground=split_e(light)
    preview_foreground=foreground.copy()
    for ink,mask in [('#142a48',tile),('#fff1ad',inside),('#142a48',glyph)]:
        preview_foreground.paste(Image.new('RGBA',foreground.size,ink),(0,0),mask)
    # Restrict new decoration to dark hillside pixels; no E / luminous road overlap.
    rgb=np.asarray(light)
    bright=(rgb[:,:,0]>170)&(rgb[:,:,1]>170)&(rgb[:,:,2]<250)
    assert not np.any(bright & (np.array(tile)>0)), 'Badge overlaps bright E disk or road'
    safe={}
    for name,img in [('light',light),('dark',dark),('light-preview',with_badge(light)),('dark-preview',with_badge(dark)),('monochrome',mono),('monochrome-preview',preview_mono)]:
        save(img,EXPORT/(name+'.png'))
    for flavor,fg,mm,col in [('main',foreground,mono,light),('preview',preview_foreground,preview_mono,with_badge(light))]:
        res=ANDROID/flavor/'res'
        save(adaptive(backdrop,True),res/'drawable-nodpi/eroute_icon_background.png')
        af=adaptive(fg); am=adaptive(mm)
        safe[flavor]={'foreground_max_radius_dp':check_safe(af),'monochrome_max_radius_dp':check_safe(am)}
        save(af,res/'drawable-nodpi/eroute_icon_foreground.png')
        save(am,res/'drawable-nodpi/eroute_icon_monochrome.png')
        for api in (26,33):
            xml='<?xml version="1.0" encoding="utf-8"?>\n<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n    <background android:drawable="@drawable/eroute_icon_background"/>\n    <foreground android:drawable="@drawable/eroute_icon_foreground"/>\n'
            if api>=33:xml+='    <monochrome android:drawable="@drawable/eroute_icon_monochrome"/>\n'
            xml+='</adaptive-icon>\n'
            for filename in ('ic_launcher.xml','ic_launcher_round.xml'):
                write(res/f'mipmap-anydpi-v{api}'/filename,xml)
        for density,pixels in [('mdpi',48),('hdpi',72),('xhdpi',96),('xxhdpi',144),('xxxhdpi',192)]:
            icon=scaled(col,pixels)
            save(icon,res/f'mipmap-{density}/ic_launcher.png')
            mask=Image.new('L',(pixels*4,pixels*4));ImageDraw.Draw(mask).ellipse((0,0,pixels*4-1,pixels*4-1),fill=255)
            rounded=icon.convert('RGBA');rounded.putalpha(scaled(mask,pixels))
            save(rounded,res/f'mipmap-{density}/ic_launcher_round.png')
    # Xcode single-size iOS catalog, iOS 15 deployment unchanged. Keep legacy
    # filenames populated with approved Light as useful exports, not deleted.
    for path in IOS.glob('Icon-App-*.png'):
        match=re.match(r'Icon-App-([\d.]+)x[\d.]+@(\d)x.png',path.name)
        if match:save(scaled(light,round(float(match[1])*int(match[2]))).convert('RGB'),path)
    entries=[]
    for appearance,img in [('any',light),('dark',dark),('tinted',ImageChops.invert(mono.getchannel('A')).convert('RGB'))]:
        filename=f'ERoute-{appearance}-1024.png'
        save(scaled(img,1024).convert('RGB'),IOS/filename)
        item={'filename':filename,'idiom':'universal','platform':'ios','size':'1024x1024'}
        if appearance!='any':item['appearances']=[{'appearance':'luminosity','value':appearance}]
        entries.append(item)
    write(IOS/'Contents.json',json.dumps({'images':entries,'info':{'author':'xcode','version':1}},indent=2)+'\n')
    manifest={'approved_source_sha256':{n:a['sha256'] for n,a in metadata['assets'].items()},'generator':'scripts/generate_app_icons.py','pillow':__import__('PIL').__version__,'numpy':np.__version__,'badge_normalized_bounds':BADGE,'android_layer_dp':108,'android_viewport_dp':72,'safe_circle_diameter_dp':66,'safe_checks':safe,'mono_white_is_transparent':True,'color_reconstruction_exact_at_source':True,'files':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in written}}
    (EXPORT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(json.dumps({'written':len(written),'safe_checks':safe,'E_negative_space':'PASS','P_does_not_cover_E_or_road':'PASS'},indent=2))

if __name__=='__main__':main()

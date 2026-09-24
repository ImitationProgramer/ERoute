#!/usr/bin/env python3
"""Validate exported files and the actually packaged APK icon pixels read-only."""
from pathlib import Path
from io import BytesIO
from zipfile import ZipFile
import json, hashlib
import numpy as np
from PIL import Image

root=Path(__file__).resolve().parents[1]
SIZE=1254
manifest=json.loads((root/'docs/ui/icon-platform-v1/manifest.json').read_text())
for name,digest in manifest['files'].items():
    assert hashlib.sha256((root/name).read_bytes()).hexdigest()==digest, name
results={}
for flavor,source in [('dev','main'),('preview','preview')]:
    apk=root/f'apps/mobile/build/app/outputs/flutter-apk/app-{flavor}-debug.apk'
    with ZipFile(apk) as z:
        for layer in ('background','foreground','monochrome'):
            name=f'eroute_icon_{layer}.png'
            packaged=Image.open(BytesIO(z.read('res/drawable-nodpi-v4/'+name))).convert('RGBA')
            original=Image.open(root/f'apps/mobile/android/app/src/{source}/res/drawable-nodpi/{name}').convert('RGBA')
            assert np.array_equal(np.asarray(packaged),np.asarray(original)),(flavor,layer)
            if layer=='monochrome':
                a=np.asarray(packaged)[:,:,3]
                assert a[0,0]==0 and a.max()==255
                y,x=np.where(a>127)
                assert np.sqrt((x-215.5)**2+(y-215.5)**2).max()<=132
                # Actual packaged transparent E stem vs opaque gap.
                assert a[round(72+320/SIZE*288),round(72+550/SIZE*288)]==0
        for api in (26,33):
            assert f'res/mipmap-anydpi-v{api}/ic_launcher.xml' in z.namelist()
            assert f'res/mipmap-anydpi-v{api}/ic_launcher_round.xml' in z.namelist()
        for density in ('mdpi','hdpi','xhdpi','xxhdpi','xxxhdpi'):
            assert f'res/mipmap-{density}-v4/ic_launcher.png' in z.namelist()
            assert f'res/mipmap-{density}-v4/ic_launcher_round.png' in z.namelist()
    results[flavor]={'packaged_layers_match_exports':True,'monochrome_alpha_and_safe_zone':True,'legacy_and_adaptive_present':True}
catalog=root/'apps/mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset'
items=json.loads((catalog/'Contents.json').read_text())['images']
assert len(items)==3
assert {e.get('appearances',[{'value':'any'}])[0]['value'] for e in items}=={'any','dark','tinted'}
for e in items:
    image=Image.open(catalog/e['filename'])
    assert image.size==(1024,1024) and image.mode=='RGB'
results['ios']={'catalog_static_check':True,'opaque_1024_images':3,'build_and_device_verified':False}
print(json.dumps(results,indent=2))

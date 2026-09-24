from pathlib import Path
import json, html

root = Path(__file__).resolve().parent
meta = json.loads((root / 'generation.json').read_text())
def icon(name, size, preview=False, shape=''):
    badge = '<span class="badge">P</span>' if preview else ''
    return f'<span class="art {shape} {name}" style="--s:{size}px"><img alt="{name} {"Preview" if preview else "일반"}" src="{meta["assets"][name]["filename"]}">{badge}</span>'
names = [('light','Light'), ('dark','Dark'), ('mono','단색')]
hero = ''.join(f'<div><div class="label">{label} · 일반</div><a href="{meta["assets"][name]["filename"]}">{icon(name,260)}</a><div class="caption">새로 제작한 고해상도 래스터 원본<br>클릭하면 원본 크기로 확인</div></div>' for name,label in names)
preview = ''.join(f'<div class="previewcell {name}">{icon(name,104,True,"squircle")}<div><b>{label} Preview</b><div class="caption">P 배지로 형태 구분</div></div></div>' for name,label in names)
rows = ''
for prev in (False,True):
    for name,label in names:
        cells = ''.join('<td>'+icon(name,s,prev)+'</td>' for s in (24,32,48,64))
        cells += '<td>'+icon(name,64,prev,'round')+'</td><td>'+icon(name,64,prev,'squircle')+'</td><td><span class="sampledark">'+icon(name,48,prev,'round')+'</span></td>'
        rows += f'<tr><td>{label} {"Preview" if prev else "일반"}</td>{cells}</tr>'
from urllib.parse import quote
import os
reference_path = root.parents[2] / meta['reference']['path']
reference = quote(os.path.relpath(reference_path,root))
template=(root/'review-template.html').read_text()
(root/'index.html').write_text(template.replace('REFERENCE',reference).replace('HERO',hero).replace('PREVIEW',preview).replace('ROWS',rows))
print('Built review page using unchanged source PNGs and CSS masks/badges.')

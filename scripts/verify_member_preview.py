#!/usr/bin/env python3
"""Read-only member preview isolation checks; never runs a device or service."""
import argparse
import re
from pathlib import Path
from zipfile import ZipFile

root = Path(__file__).resolve().parents[1]
lib = root / 'apps/mobile/lib'
p = argparse.ArgumentParser()
p.add_argument('--apk', type=Path)
a = p.parse_args()
seen = set()

def walk(path):
    path = path.resolve()
    if path in seen:
        return
    seen.add(path)
    if lib / 'preview' in path.parents or path.name == 'main_ui_preview.dart':
        raise SystemExit(f'Preview imported from normal entrypoint: {path.relative_to(root)}')
    for match in re.finditer(r"(?:import|export)\s+['\"]([^'\"]+)['\"]", path.read_text()):
        value = match.group(1)
        if value.startswith('package:eroute_mobile/'):
            walk(lib / value.split('package:eroute_mobile/', 1)[1])
        elif ':' not in value:
            walk(path.parent / value)

for entry in ('main.dart', 'main_production.dart'):
    walk(lib / entry)
print(f'Normal entrypoint closure: {len(seen)} Dart files; no preview imports')
if a.apk:
    markers = ['preview-pass', 'ui-preview-member', 'member-ui-v1', 'member-ui-v2', 'member-ui-v3', 'preview-product-long-name', 'UI Preview forbids HTTP clients.', 'UI_PREVIEW_PRODUCTS', 'preview-product-100-tablet', 'UI 미리보기 · 가상 데이터']
    with ZipFile(a.apk) as apk:
        payloads = [name for name in apk.namelist() if name.endswith('libapp.so') or name.endswith('kernel_blob.bin')]
        if not payloads:
            raise SystemExit('No Dart payload found')
        for name in payloads:
            data = apk.read(name)
            for marker in markers:
                if any(marker.encode(enc) in data for enc in ('utf-8', 'utf-16-le', 'utf-16-be')):
                    raise SystemExit(f'Preview fixture found in normal APK: {name}')
    print(f'APK payloads checked: {len(payloads)}; no preview markers')

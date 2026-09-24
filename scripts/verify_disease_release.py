#!/usr/bin/env python3
"""v1 release boundary: production flag OFF; no synthetic relation fixtures in app payloads."""
import argparse
import json
import re
from pathlib import Path
from zipfile import ZipFile

root = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--apk', type=Path)
p.add_argument('--jar', type=Path)
a = p.parse_args()
source = (root / 'apps/mobile/lib/features/disease_personalization/disease_reference.dart').read_text()
if not re.search(r'const publicDiseaseMapEnabled\s*=\s*false;', source):
    raise SystemExit('v1 production personalization flag must remain OFF')
markers = ['TEST_DISEASE', 'TEST_DEPARTMENT', 'SYNTHETIC_OVERLAY_NATIVE_PRIVACY_READY']
preview_markers = ['DEVELOPMENT_REVIEW_PREVIEW', 'disease-departments-review-preview', '검수 중 매핑 미리보기', 'ReviewPreviewCandidates']
report = {'publicMapFlag': False, 'syntheticFixturesPackaged': False, 'apkPayloads': 0, 'developmentReviewPreviewPackaged': False}
for path in [a.apk, a.jar]:
    if path is None:
        continue
    with ZipFile(path) as archive:
        for name in archive.namelist():
            relevant = (name.endswith(('libapp.so', 'kernel_blob.bin')) if path == a.apk
                        else name.startswith('BOOT-INF/classes/'))
            if not relevant:
                continue
            if path == a.apk:
                report['apkPayloads'] += 1
            data = archive.read(name)
            if path == a.apk and any(marker.encode(enc) in data for marker in preview_markers for enc in ['utf-8', 'utf-16-le', 'utf-16-be']):
                raise SystemExit('Development review preview found in production app payload')
            if any(marker.encode(enc) in data for marker in markers for enc in ['utf-8', 'utf-16-le', 'utf-16-be']):
                raise SystemExit('Synthetic relationship fixture found in distributable artifact')
        if path == a.jar and any('DiseaseReviewPreviewController' in n or 'review-classes-v0.4.json' in n or 'StoredHospitalQaConfiguration' in n for n in archive.namelist()):
            raise SystemExit('Development review route/resources found in production JAR')
        if path == a.apk and any('/reference/disease-departments/' in n for n in archive.namelist()):
            raise SystemExit('Backend reference must not be copied into mobile assets')
if a.apk and report['apkPayloads'] == 0:
    raise SystemExit('No app payload found')
print(json.dumps(report, indent=2))

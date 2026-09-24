#!/usr/bin/env python3
"""Validate canonical offline drafts and generate their Markdown mirror. Never grants approval."""
import argparse
import copy
import json
import re
from collections import Counter
from datetime import date
from pathlib import Path
from urllib.parse import urlsplit
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]
CONTENT = ROOT / 'apps/mobile/assets/content/emergency-guides/v1'
MIRROR = ROOT / 'docs/content/emergency-guides-v1.md'
ACTION_IDS = ['EMERGENCY_CALL_INFO', 'EMERGENCY_LOCATION_HELP', 'EMERGENCY_BEFORE_AMBULANCE', 'EMERGENCY_HANDOFF_INFO']
AID_DATES = dict(zip([
    'FIRST_AID_CPR_ADULT', 'FIRST_AID_AED', 'FIRST_AID_CHOKING_ADULT_CHILD',
    'FIRST_AID_CHOKING_INFANT', 'FIRST_AID_BLEEDING', 'FIRST_AID_BURN',
    'FIRST_AID_AMPUTATION', 'FIRST_AID_BEE_STING', 'FIRST_AID_SNAKE_BITE',
    'FIRST_AID_NOSEBLEED', 'FIRST_AID_HEAT_INJURY', 'FIRST_AID_COLD_INJURY', 'FIRST_AID_SEIZURE'],
    ['2022-11-03', '2022-11-03', '2022-11-09', '2024-10-25', '2022-11-10', '2022-11-10',
     '2022-11-09', '2022-11-10', '2022-11-10', '2022-11-10', '2024-08-20', '2024-08-20', '2024-10-25']))
LATEST = {'FIRST_AID_CPR_ADULT', 'FIRST_AID_AED', 'FIRST_AID_CHOKING_ADULT_CHILD',
          'FIRST_AID_CHOKING_INFANT', 'FIRST_AID_BEE_STING', 'FIRST_AID_SEIZURE'}


def require(ok, message):
    if not ok:
        raise ValueError(message)


def nonempty(value):
    return isinstance(value, str) and bool(value.strip())


def valid_date(value):
    require(isinstance(value, str) and re.fullmatch(r'\d{4}-\d{2}-\d{2}', value), 'Missing/invalid date')
    require(date.fromisoformat(value).isoformat() == value, 'Invalid date')


def https(value):
    require(nonempty(value), 'Missing URL')
    uri = urlsplit(value)
    require(uri.scheme == 'https' and uri.hostname in {'www.nfa.go.kr', 'www.kdca.go.kr'}
            and not uri.username and not uri.password and uri.port in (None, 443)
            and not re.search(r'\s', value), 'Invalid official HTTPS URL')


def load():
    manifest = json.loads((CONTENT / 'manifest.json').read_text())
    require(manifest['schemaVersion'] == 1, 'Schema version')
    require(manifest['files'] == ['emergency-actions.json', 'first-aid.json'], 'Unsafe content path')
    require(manifest['expectedCounts'] == {'EMERGENCY_ACTION': 4, 'FIRST_AID': 13}, 'Manifest counts')
    require(nonempty(manifest['commonDisclaimer']), 'Missing common disclaimer')
    return manifest, [g for name in manifest['files'] for g in json.loads((CONTENT / name).read_text())]


def validate(guides):
    ids = [g['id'] for g in guides]
    require(len(ids) == len(set(ids)) == 17, 'Duplicate/missing guide IDs')
    require(set(ids) == set(ACTION_IDS) | set(AID_DATES), 'Unexpected guide IDs')
    require(Counter(g['category'] for g in guides) == {'EMERGENCY_ACTION': 4, 'FIRST_AID': 13}, 'Category counts')
    routes = []
    for g in guides:
        prefix = g['id'] + ': '
        for key in ['title', 'summary', 'sourceOrganization', 'sourceTitle', 'sourceUrl', 'sourceCheckedAt', 'license']:
            require(nonempty(g.get(key)), prefix + 'missing ' + key)
        require(g['category'] == ('FIRST_AID' if g['id'] in AID_DATES else 'EMERGENCY_ACTION'), prefix + 'category')
        https(g['sourceUrl'])
        valid_date(g['sourceCheckedAt'])
        require(g.get('contentStatus') == 'SOURCE_GROUNDED_DRAFT', prefix + 'status')
        require('humanReviewedAtUtc' in g and g['humanReviewedAtUtc'] is None, prefix + 'fabricated/missing review')
        require(g['license'] in {'UNCONFIRMED', 'KOGL_TYPE_1'}, prefix + 'license')
        require('publicationDate' in g, prefix + 'missing publicationDate')
        if g['id'] in AID_DATES:
            require(g['publicationDate'] == AID_DATES[g['id']], prefix + 'publication date')
        elif g['publicationDate'] is not None:
            valid_date(g['publicationDate'])
        require('latestValidation' in g, prefix + 'missing latestValidation')
        latest = g['latestValidation']
        require(bool(latest) == (g['id'] in LATEST), prefix + 'latest source scope')
        if latest:
            require(latest['organization'] == '질병관리청' and nonempty(latest['title']), prefix + 'validation source')
            https(latest['sourceUrl'])
            require(latest['license'] == 'KOGL_TYPE_4', prefix + 'KDCA license')
            require(latest['publicationDate'] == '2026-01-29' and latest['finalModifiedDate'] == '2026-02-09', prefix + 'KDCA dates')
            valid_date(latest['sourceCheckedAt'])
        routes += [g['id'], *g['aliases']]
        require(all(re.fullmatch(r'[a-z][a-z0-9-]{0,63}', a) for a in g['aliases']), prefix + 'unsafe alias')
        if g['thumbnailAsset']:
            require(re.fullmatch(r'assets/illustrations/guides/[a-z0-9-]+\.webp', g['thumbnailAsset']), prefix + 'unsafe artwork')
            require((ROOT / 'apps/mobile' / g['thumbnailAsset']).is_file(), prefix + 'missing artwork')
        sections = g['sections']
        require(isinstance(sections, list) and sections, prefix + 'missing sections')
        require(any(s['type'] == 'ACTION_STEPS' for s in sections), prefix + 'missing action steps')
        for section in sections:
            require(section['type'] in {'WHEN', 'ACTION_STEPS', 'WARNING', 'EMERGENCY'}, prefix + 'unknown section type')
            require(nonempty(section['title']), prefix + 'section title')
            key = 'steps' if section['type'] == 'ACTION_STEPS' else 'items'
            lines = section.get(key)
            require(isinstance(lines, list) and lines and all(nonempty(s) for s in lines), prefix + 'empty section')
            require(set(section) <= {'type', 'title', key, 'intro'}, prefix + 'unknown section fields')
            if 'intro' in section:
                require(nonempty(section['intro']), prefix + 'empty intro')
            require(not any('준비 중' in s for s in lines), prefix + 'placeholder')
    require(len(routes) == len(set(routes)), 'Duplicate route alias')


def render(manifest, guides):
    lines = ['# ERoute 응급 가이드 v1', '', '<!-- GENERATED: python3 scripts/verify_emergency_guides.py --write-markdown -->', '',
             'Canonical: `apps/mobile/assets/content/emergency-guides/v1/`. 이 문서는 생성 결과이며 직접 편집하지 않습니다.', '',
             '상태: SOURCE_GROUNDED_DRAFT · humanReviewedAtUtc: null · production 의료승인 없음.', '',
             '최신 기준 확인은 출처 대조 기록이며 의료전문가 승인이나 모든 절차의 완전성 보증이 아닙니다.', '',
             '공통 안내: ' + manifest['commonDisclaimer'], '',
             '| ID | 제목 | 게시일 | 확인일 | 이용조건 |', '|---|---|---|---|---|']
    for g in guides:
        lines.append(f"| {g['id']} | {g['title']} | {g['publicationDate'] or '미표시 (null)'} | {g['sourceCheckedAt']} | {g['license']} |")
    for g in guides:
        lines += ['', f"## {g['title']}", '', f"`{g['id']}` · {g['category']}", '', g['summary'], '']
        for s in g['sections']:
            lines += [f"### {s['title']}", '']
            if s.get('intro'):
                lines += [s['intro'], '']
            ordered = s['type'] == 'ACTION_STEPS'
            lines += [f"{i + 1}. {v}" if ordered else f'- {v}' for i, v in enumerate(s['steps' if ordered else 'items'])]
            lines.append('')
        lines += [f"출처: [{g['sourceOrganization']} · {g['sourceTitle']}]({g['sourceUrl']})", '',
                  f"게시일: {g['publicationDate'] or 'null'} · 확인일: {g['sourceCheckedAt']} · 이용조건: {g['license']}", '']
        if g['latestValidation']:
            v = g['latestValidation']
            lines += [f"최신 기준 확인: [{v['organization']} · {v['title']}]({v['sourceUrl']})", '',
                      f"작성: {v['publicationDate']} · 최종수정: {v['finalModifiedDate']} · 확인일: {v['sourceCheckedAt']} · {v['license']}", '']
    return '\n'.join(lines).rstrip() + '\n'


def self_test(guides):
    mutations = [lambda gs: gs.pop(), lambda gs: gs.append(copy.deepcopy(gs[0])),
        lambda gs: gs[0].update(title=''), lambda gs: gs[0].pop('sourceOrganization'),
        lambda gs: gs[0].update(sourceUrl='http://www.nfa.go.kr/'),
        lambda gs: gs[0].update(sourceUrl='https://evil.example/'),
        lambda gs: gs[0].pop('sourceCheckedAt'), lambda gs: gs[0].update(contentStatus='OTHER'),
        lambda gs: gs[0].update(humanReviewedAtUtc='2026-09-22T00:00:00Z'),
        lambda gs: gs[0].pop('humanReviewedAtUtc'), lambda gs: gs[4].update(publicationDate=None),
        lambda gs: gs[0]['sections'][0].update(type='UNKNOWN'),
        lambda gs: gs[0]['sections'][0].update(steps=[]), lambda gs: gs[0].pop('license')]
    for mutate in mutations:
        changed = copy.deepcopy(guides)
        mutate(changed)
        try:
            validate(changed)
        except (ValueError, KeyError, TypeError):
            continue
        raise AssertionError('Invalid resource accepted')
    unknown = copy.deepcopy(guides)
    unknown[4]['license'] = 'UNCONFIRMED'
    validate(unknown)
    return len(mutations)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--write-markdown', action='store_true')
    parser.add_argument('--self-test', action='store_true')
    parser.add_argument('--apk', type=Path)
    args = parser.parse_args()
    manifest, guides = load()
    validate(guides)
    markdown = render(manifest, guides)
    if args.write_markdown:
        MIRROR.write_text(markdown)
    require(MIRROR.exists() and MIRROR.read_text() == markdown, 'Generated Markdown drift; use --write-markdown')
    result = {'emergencyActions': 4, 'firstAid': 13, 'status': 'SOURCE_GROUNDED_DRAFT',
              'humanReviewedAtUtc': None, 'unconfirmedLicenses': ACTION_IDS, 'markdown': 'MATCH'}
    if args.self_test:
        result['rejectedInvalidFixtures'] = self_test(guides)
    if args.apk:
        prefix = 'assets/flutter_assets/assets/content/emergency-guides/v1/'
        with ZipFile(args.apk) as apk:
            names = {n for n in apk.namelist() if n.startswith(prefix)}
            require(names == {prefix + n for n in ['manifest.json', *manifest['files']]}, 'APK content manifest mismatch')
            for name in names:
                require(apk.read(name) == (CONTENT / name.removeprefix(prefix)).read_bytes(), 'APK content drift')
            require(not any('/assets/guide_review/' in n or '/assets/guides/ko/' in n for n in apk.namelist()), 'Legacy guides still bundled')
        result['apk'] = 'MATCH'
    print(json.dumps(result, ensure_ascii=False, indent=2))

if __name__ == '__main__':
    main()

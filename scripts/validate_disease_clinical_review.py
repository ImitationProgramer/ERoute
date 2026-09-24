#!/usr/bin/env python3
"""Offline clinical worksheet validation. Never supplies a medical decision."""
import argparse
import hashlib
import html
import json
import re
import sys
from collections import Counter
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REVIEW_DIR = ROOT / 'docs/review/disease-department-clinical-review-v1'
DEFAULT_REVIEW = REVIEW_DIR / 'review.json'
BASE = Path('services/backend/src/main/resources/reference/disease-departments')
V05 = BASE / 'v0.5.json'
MATRIX = Path('docs/qa/disease-evidence-v05-2026-09-19/source-matrix')
CLASSES = Path('services/backend/src/development/resources/reference/review-classes-v0.5.json')
# Input pins, not reviewer-editable metadata. Change of baseline needs a new workflow version.
LOCKED_INPUTS = {
    BASE / 'v0.4.json': '32a5f98da61178b882a940ea061a55e981febb0900d995ec88356d31b8dadd84',
    V05: 'bd5014127bf2db7bb315efd50411811ca2ce172c2fb9148dfe4884d7d158cf12',
    MATRIX / 'eroute-disease-source-matrix-v05.json': '309eacdbb321c63883ee88ef589a35e78fdd80454c87ff3f66874ed41a874eee',
    MATRIX / 'eroute-disease-source-matrix-v05-reviewed.json': '2418fcfccdb2bd3d462463f769eb3a782aa997b07b984226dc141f2a8b41fee4',
    CLASSES: '90d3bcb043e22471a850b68d355681894cd510480c099ce1debb78211c4e946f',
}
DECISIONS = ('PENDING', 'APPROVED', 'HOLD', 'REJECTED')
SCOPES = ('EXACT_CANONICAL', 'BROAD_PARENT')
BREADTHS = ('NARROW', 'MODERATE', 'VERY_BROAD')
RISKS = ('LOW', 'MEDIUM', 'HIGH')
REQUIRED_REVIEW_FIELDS = {
    'reviewer', 'reviewerRole', 'reviewedAtUtc', 'matchingBreadth',
    'userMisinterpretationRisk', 'decision', 'reason',
}


class ReviewError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise ReviewError(message)


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, f'Duplicate JSON key: {key}')
        result[key] = value
    return result


def read_json(path):
    return json.loads(Path(path).read_text(encoding='utf-8'), object_pairs_hook=unique_object)


def json_text(value):
    return json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + '\n'


def locked_reference(root=ROOT):
    for path, expected in LOCKED_INPUTS.items():
        actual = hashlib.sha256((root / path).read_bytes()).hexdigest()
        require(actual == expected, f'Immutable input SHA-256 mismatch: {path}')
    return read_json(root / V05), read_json(root / CLASSES)


def identity_rows(reference, classes):
    diseases = {d['id']: d['displayName'] for d in reference['diseases']}
    departments = {d['id']: d['canonicalName'] for d in reference['departments']}
    review_classes = {m['mappingId']: m['reviewClass'] for m in classes['mappings']}
    rows = {}
    for mapping in reference['mappings']:
        evidence = mapping['evidence'][0]
        parent = mapping['evidence'][1] if mapping['mappingScope'] == 'BROAD_PARENT' else None
        rows[mapping['id']] = {
            'mappingId': mapping['id'],
            'diseaseId': mapping['diseaseId'],
            'diseaseName': diseases[mapping['diseaseId']],
            'departmentId': mapping['departmentId'],
            'departmentName': departments[mapping['departmentId']],
            'mappingScope': mapping['mappingScope'],
            'reviewClass': review_classes[mapping['id']],
            'sourceUrl': evidence['sourceUrl'],
            'rawDepartmentText': evidence['rawDepartmentText'],
            'checkedAt': evidence['checkedAt'],
            'parentEvidence': {k: parent[k] for k in ('sourceUrl', 'rawDepartmentText', 'checkedAt')} if parent else None,
        }
    return rows


def nonblank(value):
    return isinstance(value, str) and bool(value.strip())


def validate(document, root=ROOT, initial=False):
    reference, classes = locked_reference(root)
    require(isinstance(document, dict) and set(document) == {'schemaVersion', 'referenceVersion', 'mappings'},
            'Expected schemaVersion, referenceVersion and mappings only')
    require(type(document['schemaVersion']) is int and document['schemaVersion'] == 1, 'Unknown review schemaVersion')
    require(document['referenceVersion'] == reference['datasetVersion'], 'referenceVersion must equal frozen v0.5')
    rows = document['mappings']
    require(isinstance(rows, list) and len(rows) == 61, 'Expected exactly 61 review rows')
    expected = identity_rows(reference, classes)
    seen = set()
    for row in rows:
        require(isinstance(row, dict), 'Each review row must be an object')
        mid = row.get('mappingId')
        require(isinstance(mid, str) and mid in expected, f'Unknown mappingId: {mid}')
        require(mid not in seen, f'Duplicate mappingId: {mid}')
        seen.add(mid)
        require(set(row) == set(expected[mid]) | {'clinicalReview'}, f'{mid}: unexpected/missing row fields')
        for key, value in expected[mid].items():
            require(row[key] == value, f'{mid}: immutable field changed: {key}')
        require(nonblank(row['sourceUrl']) and nonblank(row['rawDepartmentText']), f'{mid}: missing evidence')
        review = row['clinicalReview']
        require(isinstance(review, dict), f'{mid}: clinicalReview must be an object')
        require(REQUIRED_REVIEW_FIELDS <= set(review) <= REQUIRED_REVIEW_FIELDS | {'broadApprovalJustification'},
                f'{mid}: unexpected/missing clinicalReview fields')
        decision = review['decision']
        require(decision in DECISIONS, f'{mid}: unknown decision enum')
        breadth, risk = review['matchingBreadth'], review['userMisinterpretationRisk']
        require(breadth is None or breadth in BREADTHS, f'{mid}: unknown matchingBreadth enum')
        require(risk is None or risk in RISKS, f'{mid}: unknown userMisinterpretationRisk enum')
        for field in ('reviewer', 'reviewerRole', 'reviewedAtUtc', 'reason', 'broadApprovalJustification'):
            require(review.get(field) is None or nonblank(review[field]), f'{mid}: {field} must be null or nonblank text')
        stamp = review['reviewedAtUtc']
        if stamp is not None:
            require(re.fullmatch(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z', stamp) is not None,
                    f'{mid}: reviewedAtUtc must be an ISO-8601 UTC timestamp ending in Z')
            try:
                datetime.fromisoformat(stamp.replace('Z', '+00:00'))
            except ValueError as error:
                raise ReviewError(f'{mid}: invalid reviewedAtUtc') from error
        if decision == 'APPROVED':
            for field in REQUIRED_REVIEW_FIELDS - {'decision'}:
                require(nonblank(review[field]), f'{mid}: APPROVED requires {field}')
            require(risk != 'HIGH', f'{mid}: HIGH risk cannot be APPROVED')
            if row['mappingScope'] == 'BROAD_PARENT':
                require(row['parentEvidence'] is not None, f'{mid}: BROAD_PARENT needs parent evidence')
                require(breadth != 'VERY_BROAD' or nonblank(review.get('broadApprovalJustification')),
                        f'{mid}: VERY_BROAD BROAD_PARENT requires broadApprovalJustification')
        if decision in ('HOLD', 'REJECTED'):
            require(nonblank(review['reason']), f'{mid}: {decision} requires reason')
        if initial:
            require(decision == 'PENDING' and all(v is None for k, v in review.items() if k != 'decision'),
                    f'{mid}: initial review must be PENDING with all judgments/identity fields null')
    require(seen == set(expected), 'Mapping identity set differs from v0.5')
    return reference


def summarize(document):
    rows = document['mappings']
    counts = Counter(row['clinicalReview']['decision'] for row in rows)
    result = {'TOTAL': len(rows), **{key: counts[key] for key in DECISIONS}}
    for scope in SCOPES:
        subset = [row for row in rows if row['mappingScope'] == scope]
        counts = Counter(row['clinicalReview']['decision'] for row in subset)
        result[scope] = {'TOTAL': len(subset), **{key: counts[key] for key in DECISIONS}}
    for label, field, values in (('breadth', 'matchingBreadth', BREADTHS), ('risk', 'userMisinterpretationRisk', RISKS)):
        counts = Counter(row['clinicalReview'][field] for row in rows)
        result[label] = {**{key: counts[key] for key in values}, 'UNASSESSED': counts[None]}
    return result


def ordered_rows(document):
    return sorted(document['mappings'], key=lambda row: (SCOPES.index(row['mappingScope']), row['diseaseId'], row['departmentId']))


def cell(value):
    if value is None:
        return '—'
    return html.escape(str(value), quote=False).replace('|', '&#124;').replace('\r\n', '\n').replace('\n', '<br>')


def worksheet(document):
    lines = [
        '# 질환→진료과 의료 검수표', '',
        '> GENERATED from review.json. 직접 편집하지 않습니다. 수동 owner는 review.json 하나입니다.', '',
        '[검수 안내](GUIDE.md) · [원본](review.json) · [집계](summary.json)', '',
        '질문: ERoute가 이 관계로 **“이 병원에 관련 진료과가 있음”**을 표시해도 되는가?',
        '치료 가능·현재 수용 가능·병원 추천에 대한 승인이 아닙니다. —는 미판정입니다.', '',
        '| # | Mapping ID | 질환 | 진료과 | Scope | 공식 원문 | Source | Breadth | Risk | Decision | Reviewer | Reason |',
        '|---|---|---|---|---|---|---|---|---|---|---|---|',
    ]
    for number, row in enumerate(ordered_rows(document), 1):
        review = row['clinicalReview']
        source = f"[질환 근거](<{row['sourceUrl']}>)"
        if row['parentEvidence']:
            source += f" · [상위 구조](<{row['parentEvidence']['sourceUrl']}>)"
        reason = cell(review['reason'])
        if review.get('broadApprovalJustification'):
            reason += '<br>상위 범위 승인 근거: ' + cell(review['broadApprovalJustification'])
        values = [number, row['mappingId'], row['diseaseName'], row['departmentName'], row['mappingScope'], row['rawDepartmentText']]
        values = [cell(value) for value in values] + [source]
        values += [cell(review[key]) for key in ('matchingBreadth', 'userMisinterpretationRisk', 'decision', 'reviewer')]
        lines.append('| ' + ' | '.join(values + [reason]) + ' |')
    return '\n'.join(lines) + '\n'


def generated_files(document):
    return {'review.md': worksheet(document), 'summary.json': json_text(summarize(document))}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--review', type=Path, default=DEFAULT_REVIEW)
    parser.add_argument('--initial', action='store_true', help='Require 61 untouched PENDING rows (initial delivery only)')
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--write', action='store_true', help='Regenerate review.md and summary.json beside the canonical input')
    mode.add_argument('--check-generated', action='store_true', help='Fail if generated files are stale or missing')
    args = parser.parse_args()
    try:
        document = read_json(args.review)
        validate(document, initial=args.initial)
        for name, content in generated_files(document).items():
            path = args.review.parent / name
            if args.write:
                path.write_text(content, encoding='utf-8')
            elif args.check_generated:
                require(path.exists() and path.read_text(encoding='utf-8') == content, f'Stale generated file: {path}; run --write')
        print(json_text({'status': 'PASS', **summarize(document)}), end='')
        return 0
    except (ReviewError, OSError, ValueError) as error:
        print(f'FAIL: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())

#!/usr/bin/env python3
"""Offline v0.5 source/provenance audit. Does not search, stamp, approve or write."""
import hashlib
import json
from collections import Counter
from datetime import datetime
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
QA = ROOT / 'docs/qa/disease-evidence-v05-2026-09-19'
BASE = ROOT / 'services/backend/src/main/resources/reference/disease-departments'
SOURCE_SHA = '309eacdbb321c63883ee88ef589a35e78fdd80454c87ff3f66874ed41a874eee'
V04_SHA = '32a5f98da61178b882a940ea061a55e981febb0900d995ec88356d31b8dadd84'


def read(path):
    return json.loads(path.read_bytes())


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def audit():
    source_path = QA / 'source-matrix/eroute-disease-source-matrix-v05.json'
    assert digest(source_path) == SOURCE_SHA
    assert digest(BASE / 'v0.4.json') == V04_SHA
    source = read(source_path)
    reviewed = read(source_path.with_name('eroute-disease-source-matrix-v05-reviewed.json'))
    old, new = read(BASE / 'v0.4.json'), read(BASE / 'v0.5.json')
    stamp = reviewed['provenance']['humanCheckedAtUtc']
    assert stamp.endswith('Z') and datetime.fromisoformat(stamp.replace('Z', '+00:00'))
    assert stamp != source['researchVerifiedAtUtc']
    assert reviewed['provenance']['originalSha256'] == SOURCE_SHA
    assert reviewed['humanSignoffStatus'] == 'HUMAN_SOURCE_REVIEW'
    assert reviewed['provenance']['medicalApproval'] is False
    assert reviewed['provenance']['productionApproval'] is False
    assert reviewed['humanCheckedAtUtc'] == reviewed['checkedAt'] == stamp
    assert source['parentStructureSource']['humanCheckedAtUtc'] is None
    assert reviewed['parentStructureSource']['humanCheckedAtUtc'] == stamp
    assert reviewed['parentStructureSource']['checkedAt'] == stamp
    for field in ('sourceName', 'sourceUrl', 'rawDepartmentText'):
        assert source['parentStructureSource'][field] == reviewed['parentStructureSource'][field]
    assert new['datasetVersion'] == 'eroute-disease-departments-v0.5'
    for key in old:
        if key not in ('datasetVersion', 'mappings'):
            assert old[key] == new[key], key
    assert len(new['diseases']) == sum(d['active'] for d in new['diseases']) == 46
    assert len(new['departments']) == 51
    assert len(new['mappings']) == len(source['mappings']) == len(reviewed['mappings']) == 61
    originals = {m['id']: m for m in old['mappings']}
    sources = {m['mappingId']: m for m in source['mappings']}
    stamps = {m['mappingId']: m for m in reviewed['mappings']}
    assert len(sources) == len(stamps) == 61
    assert set(originals) == set(sources) == set(stamps) == {m['id'] for m in new['mappings']}
    departments = {d['id']: d['canonicalName'] for d in new['departments']}
    scopes = Counter(m['mappingScope'] for m in new['mappings'])
    assert scopes == {'EXACT_CANONICAL': 36, 'BROAD_PARENT': 25}
    urls = set()
    for mapping in new['mappings']:
        mid = mapping['id']
        supplied, stamped, previous = sources[mid], stamps[mid], originals[mid]
        assert mapping['reviewStatus'] == supplied['reviewStatus'] == stamped['reviewStatus'] == 'DRAFT'
        assert mapping['approval'] is supplied['approval'] is stamped['approval'] is None
        assert mapping['version'] == previous['version'] + 1
        for key in ('diseaseId', 'departmentId', 'relationType'):
            assert mapping[key] == previous[key] == supplied[key] == stamped[key], (mid, key)
        assert mapping['mappingScope'] == supplied['mappingScope'] == stamped['mappingScope']
        canonical = departments[mapping['departmentId']]
        assert canonical == supplied['departmentCanonicalName']
        roles = ['diseaseEvidence']
        disease = supplied['diseaseEvidence']
        if mapping['mappingScope'] == 'EXACT_CANONICAL':
            assert canonical in [t.strip() for t in disease['rawDepartmentText'].split(',')], mid
        else:
            roles.append('parentStructureEvidence')
            assert canonical == '내과'
            subspecialties = disease['supportingSubspecialties']
            assert subspecialties
            parent = supplied['parentStructureEvidence']
            for term in subspecialties:
                assert term in disease['rawDepartmentText'] and term in parent['rawDepartmentText'], mid
        assert len(mapping['evidence']) == len(roles)
        for role, evidence in zip(roles, mapping['evidence']):
            original, checked = supplied[role], stamped[role]
            assert original['checkedAt'] is original['humanCheckedAtUtc'] is None
            assert evidence['checkedAt'] == checked['checkedAt'] == checked['humanCheckedAtUtc'] == stamp
            for key in original:
                if key not in ('checkedAt', 'humanCheckedAtUtc'):
                    assert original[key] == checked[key], (mid, role, key)
            for key in ('sourceName', 'sourceUrl', 'rawDepartmentText'):
                assert evidence[key] == original[key] and evidence[key].strip(), (mid, role, key)
            url = urlparse(evidence['sourceUrl'])
            assert url.scheme in ('http', 'https') and url.netloc
            assert SOURCE_SHA in evidence['notes'] and mid in evidence['notes']
            assert 'HUMAN_SOURCE_REVIEW' in evidence['notes'] and role in evidence['notes']
            if len(roles) == 2:
                for limitation in ('crosswalk', '진료 가능성을 보장하지 않음', '수용 가능성을 의미하지 않음', '추천/적합성 점수가 아님'):
                    assert limitation in evidence['notes']
            urls.add(evidence['sourceUrl'])
    classes_path = ROOT / 'services/backend/src/development/resources/reference'
    old_classes, new_classes = [read(classes_path / f'review-classes-v0.{v}.json') for v in (4, 5)]
    assert old_classes['mappings'] == new_classes['mappings']
    assert new_classes['referenceVersion'] == new['datasetVersion']
    assert Counter(m['reviewClass'] for m in new_classes['mappings']) == {
        'EXACT_CANONICAL_REVIEW_REQUIRED': 6, 'REVIEW_REQUIRED': 30, 'BROAD_PARENT_REVIEW_REQUIRED': 25}
    return {'status': 'PASS', 'sourceMatrixSha256': SOURCE_SHA, 'humanBatchReviewUtc': stamp,
            'v04Sha256': V04_SHA, 'v05Sha256': digest(BASE / 'v0.5.json'),
            'activeDiseases': 46, 'departments': 51, 'mappings': 61, 'scopeCounts': dict(scopes),
            'evidenceCompleteMappings': 61, 'evidenceIncompleteMappings': [],
            'diseaseEvidenceRecords': 61, 'parentStructureEvidenceRecords': 25,
            'evidenceRecords': 86, 'uniqueSourceUrls': len(urls), 'checkedAtMappings': 61,
            'draftMappings': 61, 'approvedMappings': 0, 'approvalNullMappings': 61,
            'previewClassesUnchanged': True}


if __name__ == '__main__':
    print(json.dumps(audit(), ensure_ascii=False, indent=2))

#!/usr/bin/env python3
"""Validate the editable record catalog against preserved v0.5 identities.
No network, database, inference, or writes. Future catalog-only diseases are valid.
"""
import argparse
import hashlib
import json
from pathlib import Path
import unicodedata

ROOT = Path(__file__).resolve().parents[1]
RESOURCE = ROOT / 'services/backend/src/main/resources/reference/diseases/catalog.json'
REFERENCE = ROOT / 'services/backend/src/main/resources/reference/disease-departments/v0.5.json'

def normalized(value):
    return ''.join(unicodedata.normalize('NFC', value).split()).lower()

def validate(path):
    catalog = json.loads(path.read_text())
    reference = json.loads(REFERENCE.read_text())
    assert catalog['catalogVersion'].strip()
    categories = {c['id']: c for c in catalog['categories']}
    assert len(categories) == len(catalog['categories'])
    for c in categories.values():
        assert c['id'].strip() and c['name'].strip() and type(c['sortOrder']) is int
    diseases = {d['id']: d for d in catalog['diseases']}
    assert len(diseases) == len(catalog['diseases']) and diseases
    index = {}
    for d in diseases.values():
        assert d['id'].strip() and d['canonicalName'].strip()
        assert type(d['active']) is bool and d['categoryId'] in categories
        assert isinstance(d['aliases'], list)
        for name in [d['canonicalName'], *d['aliases']]:
            key = normalized(name)
            assert key and index.get(key, d['id']) == d['id'], ('alias collision', name)
            index[key] = d['id']
    for old in reference['diseases']:
        assert diseases[old['id']]['canonicalName'] == old['displayName'], old['id']
    for mapping in reference['mappings']:
        assert mapping['diseaseId'] in diseases
    quick = catalog['quickPickDiseaseIds']
    assert len(quick) == len(set(quick)) and all(diseases[i]['active'] for i in quick)
    mapped = {m['diseaseId'] for m in reference['mappings']}
    return {'status': 'PASS', 'catalogVersion': catalog['catalogVersion'],
            'diseases': len(diseases), 'categories': len(categories),
            'catalogOnlyDiseaseIds': sorted(set(diseases)-mapped),
            'catalogSha256': hashlib.sha256(path.read_bytes()).hexdigest(),
            'v05Sha256': hashlib.sha256(REFERENCE.read_bytes()).hexdigest()}

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('catalog', nargs='?', type=Path, default=RESOURCE)
    print(json.dumps(validate(parser.parse_args().catalog), ensure_ascii=False, indent=2))

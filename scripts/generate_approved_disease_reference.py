#!/usr/bin/env python3
"""Export only human-APPROVED relations to a new immutable candidate; never enable production."""
import argparse
import copy
import re
import sys
from pathlib import Path

from validate_disease_clinical_review import (
    BASE, DEFAULT_REVIEW, REVIEW_DIR, ROOT, ReviewError, json_text, read_json, require, validate,
)


def approved_reference(document, version):
    reference = validate(document)
    match = re.fullmatch(r'eroute-disease-departments-v(0|[1-9]\d*)\.(0|[1-9]\d*)', version or '')
    require(match is not None and tuple(map(int, match.groups())) > (0, 5),
            'Use a new version after eroute-disease-departments-v0.5, e.g. eroute-disease-departments-v0.6')
    reviews = {row['mappingId']: row['clinicalReview'] for row in document['mappings']}
    result = copy.deepcopy(reference)
    result['datasetVersion'] = version
    result['mappings'] = []
    for mapping in reference['mappings']:
        review = reviews[mapping['id']]
        if review['decision'] != 'APPROVED':
            continue
        approved = copy.deepcopy(mapping)
        approved['reviewStatus'] = 'APPROVED'
        approved['approval'] = {
            'reviewer': review['reviewer'],
            'approvedAt': review['reviewedAtUtc'],
            'version': mapping['version'],
        }
        result['mappings'].append(approved)
    # Catalogs, evidence, mapping versions and publicMapApproved remain unchanged.
    # This is an APPROVED-only projection, not the full authoring transition ledger.
    require(result['mappings'], 'No approved mappings. Nothing generated.')
    return result


def generate(review_path=DEFAULT_REVIEW, version=None, output_dir=None, dry_run=False):
    document = read_json(review_path)
    validate(document)  # Also reject malformed unapproved rows, including with APPROVED=0.
    count = sum(row['clinicalReview']['decision'] == 'APPROVED' for row in document['mappings'])
    print(f'APPROVED={count}')
    if count == 0:
        print('No approved mappings. Nothing generated.')
        print('NO OUTPUT GENERATED')
        return None
    result = approved_reference(document, version)
    filename = version.removeprefix('eroute-disease-departments-') + '.json'
    output_dir = Path(output_dir) if output_dir is not None else REVIEW_DIR / 'releases'
    target = output_dir / filename
    # A version already present in either repository location cannot be reused.
    for existing in {target, ROOT / BASE / filename, REVIEW_DIR / 'releases' / filename}:
        require(not existing.exists() and not existing.is_symlink(), f'Immutable version already exists: {existing}')
    if dry_run:
        print(f'DRY RUN: would write {target} ({count} approved mappings)')
        print('NO OUTPUT GENERATED')
        return None
    output_dir.mkdir(parents=True, exist_ok=True)
    # Exclusive create also prevents overwriting if another process writes first.
    with target.open('x', encoding='utf-8') as stream:
        stream.write(json_text(result))
    print(f'Generated {target}; runtime and Production flag unchanged.')
    return target


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--review', type=Path, default=DEFAULT_REVIEW)
    parser.add_argument('--version', help='Required only when APPROVED > 0; e.g. eroute-disease-departments-v0.6')
    parser.add_argument('--output-dir', type=Path, help='Default: review directory/releases (never auto-installed)')
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    try:
        generate(args.review, args.version, args.output_dir, args.dry_run)
        return 0
    except (ReviewError, OSError, ValueError) as error:
        print(f'FAIL: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())

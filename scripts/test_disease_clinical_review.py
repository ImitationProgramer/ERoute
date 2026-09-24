#!/usr/bin/env python3
"""Synthetic in-memory/temp-directory checks, never approvals of real relations."""
import copy
import io
import json
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

import generate_approved_disease_reference as generator
import validate_disease_clinical_review as review


class ClinicalReviewTests(unittest.TestCase):
    def setUp(self):
        self.document = review.read_json(review.DEFAULT_REVIEW)
        # Reset only this in-memory test copy; tests remain usable after human reviews.
        for row in self.document['mappings']:
            row['clinicalReview'] = {field: None for field in review.REQUIRED_REVIEW_FIELDS}
            row['clinicalReview'].update(decision='PENDING', broadApprovalJustification=None)
        self.row = next(row for row in self.document['mappings'] if row['mappingScope'] == 'BROAD_PARENT')

    @staticmethod
    def synthetic_approval(row):
        # Deliberately fake identity/time for validator tests, never persisted in the canonical owner.
        row['clinicalReview'].update({
            'reviewer': 'TEST_ONLY_NOT_A_REAL_REVIEWER',
            'reviewerRole': 'TEST_ONLY_NOT_A_CLINICIAN',
            'reviewedAtUtc': '2000-01-01T00:00:00Z',
            'matchingBreadth': 'MODERATE',
            'userMisinterpretationRisk': 'LOW',
            'decision': 'APPROVED',
            'reason': 'SYNTHETIC VALIDATOR INPUT ONLY, NOT MEDICAL APPROVAL',
        })

    def test_initial_and_generated_files(self):
        review.validate(self.document, initial=True)
        summary = review.summarize(self.document)
        self.assertEqual([summary[k] for k in ('TOTAL', 'PENDING', 'APPROVED', 'HOLD', 'REJECTED')], [61, 61, 0, 0, 0])
        self.assertEqual(summary['EXACT_CANONICAL']['PENDING'], 36)
        self.assertEqual(summary['BROAD_PARENT']['PENDING'], 25)
        canonical = review.read_json(review.DEFAULT_REVIEW)
        review.validate(canonical)
        for name, content in review.generated_files(canonical).items():
            self.assertEqual((review.REVIEW_DIR / name).read_text(), content)
        scopes = [row['mappingScope'] for row in review.ordered_rows(self.document)]
        self.assertEqual(scopes, ['EXACT_CANONICAL'] * 36 + ['BROAD_PARENT'] * 25)

    def test_negative_fixtures(self):
        cases = review.read_json(review.REVIEW_DIR / 'negative-fixtures.json')['cases']
        for case in cases:
            with self.subTest(case=case['name']):
                document = copy.deepcopy(self.document)
                row = next(row for row in document['mappings'] if row['mappingScope'] == 'BROAD_PARENT')
                if case['base'] == 'TEST_ONLY_APPROVED':
                    self.synthetic_approval(row)
                row['clinicalReview'].update(case.get('review', {}))
                row.update(case.get('row', {}))
                with self.assertRaisesRegex(review.ReviewError, case['error']):
                    review.validate(document)

    def test_immutable_projection_fields(self):
        for field in ('diseaseId', 'departmentId', 'diseaseName', 'departmentName', 'mappingScope', 'reviewClass',
                      'sourceUrl', 'rawDepartmentText', 'checkedAt', 'parentEvidence'):
            with self.subTest(field=field):
                document = copy.deepcopy(self.document)
                document['mappings'][0][field] = 'TEST_ONLY_CHANGED'
                with self.assertRaisesRegex(review.ReviewError, 'immutable field changed'):
                    review.validate(document)

    def test_missing_and_duplicate_rows(self):
        missing = copy.deepcopy(self.document)
        missing['mappings'].pop()
        with self.assertRaisesRegex(review.ReviewError, 'exactly 61'):
            review.validate(missing)
        duplicate = copy.deepcopy(self.document)
        duplicate['mappings'][1] = copy.deepcopy(duplicate['mappings'][0])
        with self.assertRaisesRegex(review.ReviewError, 'Duplicate mappingId'):
            review.validate(duplicate)

    def test_blank_fields_and_invalid_time(self):
        self.synthetic_approval(self.row)
        for field in ('reviewer', 'reviewerRole', 'reason', 'broadApprovalJustification'):
            document = copy.deepcopy(self.document)
            row = next(row for row in document['mappings'] if row['mappingScope'] == 'BROAD_PARENT')
            row['clinicalReview'][field] = '   '
            with self.subTest(field=field), self.assertRaisesRegex(review.ReviewError, 'nonblank'):
                review.validate(document)
        for stamp in ('2026-09-22', '2026-02-30T00:00:00Z', '2026-09-22T10:00:00+09:00'):
            self.row['clinicalReview']['reviewedAtUtc'] = stamp
            with self.subTest(stamp=stamp), self.assertRaises(review.ReviewError):
                review.validate(self.document)

    def test_explicit_broad_justification_and_hold_rejected(self):
        self.synthetic_approval(self.row)
        self.row['clinicalReview'].update(matchingBreadth='VERY_BROAD', broadApprovalJustification='TEST_ONLY_EXPLICIT_JUSTIFICATION')
        review.validate(self.document)
        for decision in ('HOLD', 'REJECTED'):
            document = copy.deepcopy(self.document)
            row = document['mappings'][0]
            row['clinicalReview'].update(decision=decision, reason='TEST_ONLY_REASON')
            review.validate(document)
            self.assertEqual(review.summarize(document)[decision], 1)

    def test_frozen_input_hashes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for path in review.LOCKED_INPUTS:
                (root / path).parent.mkdir(parents=True, exist_ok=True)
                (root / path).write_bytes((review.ROOT / path).read_bytes())
            for path in review.LOCKED_INPUTS:
                original = (root / path).read_bytes()
                (root / path).write_bytes(original + b'\n')
                with self.subTest(path=path), self.assertRaisesRegex(review.ReviewError, 'SHA-256 mismatch'):
                    review.validate(self.document, root=root)
                (root / path).write_bytes(original)

    def test_strict_json_and_cli_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'review.json'
            path.write_text('{"decision":"APPROVED","decision":"PENDING"}')
            with self.assertRaisesRegex(review.ReviewError, 'Duplicate JSON key'):
                review.read_json(path)
            self.row['clinicalReview']['decision'] = 'REJECTED'
            path.write_text(review.json_text(self.document))
            result = subprocess.run([sys.executable, str(review.ROOT / 'scripts/validate_disease_clinical_review.py'),
                                     '--review', str(path)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 1)
            self.assertIn('REJECTED requires reason', result.stderr)

    def test_zero_approved_writes_nothing(self):
        with tempfile.TemporaryDirectory() as directory, redirect_stdout(io.StringIO()) as output:
            target = Path(directory) / 'must-not-exist'
            for dry_run in (False, True):
                self.assertIsNone(generator.generate(output_dir=target, dry_run=dry_run))
                self.assertFalse(target.exists())
            self.assertIn('No approved mappings. Nothing generated.', output.getvalue())

    def test_approved_only_export_and_immutable_version(self):
        self.synthetic_approval(self.row)
        exact = self.document['mappings'][0]
        self.synthetic_approval(exact)
        self.document['mappings'][1]['clinicalReview'].update(decision='HOLD', reason='TEST_ONLY_HOLD')
        self.document['mappings'][2]['clinicalReview'].update(decision='REJECTED', reason='TEST_ONLY_REJECTED')
        with tempfile.TemporaryDirectory() as directory, redirect_stdout(io.StringIO()):
            root = Path(directory)
            canonical = root / 'review.json'
            canonical.write_text(review.json_text(self.document))
            output = root / 'releases'
            version = 'eroute-disease-departments-v0.6'
            generator.generate(canonical, version, output, dry_run=True)
            self.assertFalse(output.exists())
            target = generator.generate(canonical, version, output)
            result = review.read_json(target)
            baseline, _ = review.locked_reference()
            self.assertEqual({m['id'] for m in result['mappings']}, {self.row['mappingId'], exact['mappingId']})
            for field in set(baseline) - {'datasetVersion', 'mappings'}:
                self.assertEqual(result[field], baseline[field])
            originals = {m['id']: m for m in baseline['mappings']}
            for mapping in result['mappings']:
                self.assertEqual(mapping['reviewStatus'], 'APPROVED')
                self.assertEqual(mapping['approval']['version'], mapping['version'])
                for field in set(mapping) - {'reviewStatus', 'approval'}:
                    self.assertEqual(mapping[field], originals[mapping['id']][field])
            before = target.read_bytes()
            with self.assertRaisesRegex(review.ReviewError, 'already exists'):
                generator.generate(canonical, version, output)
            self.assertEqual(target.read_bytes(), before)
            for invalid in ('eroute-disease-departments-v0.5', 'eroute-disease-departments-v0.4', '../v0.6', None):
                with self.subTest(version=invalid), self.assertRaises(review.ReviewError):
                    generator.generate(canonical, invalid, output)

    def test_invalid_review_cannot_generate(self):
        self.row['clinicalReview']['decision'] = 'APPROVED'
        with tempfile.TemporaryDirectory() as directory, redirect_stdout(io.StringIO()):
            path = Path(directory) / 'review.json'
            path.write_text(review.json_text(self.document))
            output = Path(directory) / 'releases'
            with self.assertRaises(review.ReviewError):
                generator.generate(path, 'eroute-disease-departments-v0.6', output)
            self.assertFalse(output.exists())


if __name__ == '__main__':
    unittest.main(verbosity=2)

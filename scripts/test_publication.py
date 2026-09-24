#!/usr/bin/env python3
"""Publication regression checks in disposable repositories, synthetic values only."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import secrets
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('publication', ROOT / 'scripts/check_publication.py')
publication = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publication)


@unittest.skipUnless(shutil.which('gitleaks'), 'Gitleaks must be installed')
class PublicationTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='eroute-publication-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.git('init', '--quiet')
        for name in ('.gitignore', '.gitleaks.toml'):
            shutil.copyfile(ROOT / name, self.root / name)
        self.git('add', '.')

    def git(self, *args):
        return publication.git(self.root, *args)

    def stage(self, name, content):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        self.git('add', '--force', '--', name)

    def check(self, expected, history=False):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            result = publication.scan(self.root, history)
        self.assertEqual(result, expected, output.getvalue())
        return output.getvalue()

    def test_source_and_explicit_public_reference_allowed(self):
        self.stage('docs/qa/disease-evidence-v04-2026-09-18/review-inputs.json', '{}')
        self.stage('.env.example', (ROOT / '.env.example').read_text())
        self.stage('src/example.py', 'print("hello")\n')
        self.check(0)

    def test_force_added_private_paths_rejected(self):
        for name in ('.env', '.env.production', '.runtime/health.json', 'tmp/ui.xml',
                     'output/report.pdf', 'docs/qa/session/capture.png', 'keys.json',
                     'upload.jks', 'backend.log'):
            with self.subTest(name=name):
                self.stage(name, 'synthetic')
                self.check(1)
                self.git('rm', '--cached', '--force', '--', name)

    def test_staged_ignore_rules_used(self):
        self.stage('.env', 'synthetic')
        (self.root / '.gitignore').write_text('')
        self.check(1)

    def test_staged_secret_detected_despite_clean_worktree(self):
        value = secrets.token_urlsafe(32)
        self.stage('accidental.json', json.dumps({'credential': value}))
        (self.root / 'accidental.json').write_text('{}')
        self.assertNotIn(value, self.check(1))

    def test_nmc_url_key_detected(self):
        value = secrets.token_urlsafe(48)
        self.stage('notes.md', 'https://example.invalid/?serviceKey=' + value)
        self.assertNotIn(value, self.check(1))

    def test_actual_local_value_comparison(self):
        value = secrets.token_hex(8)
        (self.root / '.env').write_text('DB_PASSWORD=' + value)
        self.stage('notes.md', value)
        self.assertNotIn(value, self.check(1))

    def test_symlink_rejected(self):
        (self.root / 'link').symlink_to('/tmp')
        self.git('add', 'link')
        self.check(1)

    def test_deleted_secret_remains_detectable_in_history(self):
        value = secrets.token_urlsafe(32)
        self.stage('accidental.json', json.dumps({'credential': value}))
        self.git('-c', 'user.name=Publication Test', '-c', 'user.email=test@example.invalid',
                 'commit', '--quiet', '-m', 'Synthetic fixture')
        self.git('rm', 'accidental.json')
        self.check(0)
        self.assertNotIn(value, self.check(1, history=True))


if __name__ == '__main__':
    unittest.main()

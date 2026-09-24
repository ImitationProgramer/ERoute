#!/usr/bin/env python3
"""Check the entire Git index, not working-tree copies. Never print secret values.

Requires Git, Python 3.9+ and Gitleaks 8.30.1. No network requests or writes to
tracked files. Temporary scan copies/reports are private and removed on exit.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from urllib.parse import unquote


def git(root, *args, **kwargs):
    return subprocess.run(['git', '-C', str(root), *args], check=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs).stdout


def local_secret_values(root):
    """Supplement pattern detection with this machine's actual private values."""
    values = set()
    env = root / '.env'
    if env.is_file():
        for line in env.read_text().splitlines():
            if '=' not in line or line.lstrip().startswith('#'):
                continue
            key, value = line.split('=', 1)
            value = value.strip().strip('\"\'')
            if key.strip() in {'NMC_SERVICE_KEY', 'DB_PASSWORD', 'NAVER_MAP_CLIENT_ID'} and value:
                values.update((value, unquote(value)))

    def collect(data, key=''):
        if isinstance(data, dict):
            for name, value in data.items():
                collect(value, name)
        elif isinstance(data, list):
            for value in data:
                collect(value, key)
        elif isinstance(data, str) and (
                key in {'credential', 'password'} or
                (key.startswith('v') and key[1:].isdigit())):
            if data:
                values.add(data)

    for folder in (root / '.runtime').glob('auth-*'):
        for name in ('keys.json', 'credentials.json'):
            path = folder / name
            if path.is_file():
                collect(json.loads(path.read_text()))
    return {value.encode() for value in values}


def scan(root, history=False):
    scanner = shutil.which('gitleaks')
    if not scanner:
        print('BLOCKED: install Gitleaks 8.30.1 (macOS: brew install gitleaks).')
        return 1
    entries = []
    for record in git(root, 'ls-files', '--stage', '-z').split(b'\0'):
        if record:
            info, name = record.split(b'\t', 1)
            mode, _, stage = info.split()
            if mode not in (b'100644', b'100755') or stage != b'0':
                print('BLOCKED: unresolved, symlink or submodule entry:', os.fsdecode(name))
                return 1
            entries.append(os.fsdecode(name))
    if not entries or '.gitleaks.toml' not in entries or '.gitignore' not in entries:
        print('BLOCKED: stage the source and publication configuration before scanning.')
        return 1
    values = local_secret_values(root)
    with tempfile.TemporaryDirectory(prefix='eroute-publication-') as tmp:
        work = Path(tmp)
        snapshot = work / 'index'
        snapshot.mkdir()
        git(root, 'checkout-index', '--all', '--prefix=' + str(snapshot) + '/')
        # Evaluate the staged ignore rules, independently of unstaged edits.
        git(snapshot, 'init', '--quiet')
        ignored = subprocess.run(
            ['git', '-C', str(snapshot), 'check-ignore', '--no-index', '-z', '--stdin'],
            input=b'\0'.join(os.fsencode(p) for p in entries) + b'\0',
            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if ignored.returncode not in (0, 1):
            print('BLOCKED: could not evaluate staged ignore rules.')
            return 1
        issues = [(os.fsdecode(p), 'ignored/private path')
                  for p in ignored.stdout.split(b'\0') if p]
        for name in entries:
            path = snapshot / name
            if path.stat().st_size > 50 * 1024 * 1024:
                issues.append((name, 'file exceeds 50 MiB publication limit'))
                continue
            content = path.read_bytes()
            if any(value in content for value in values):
                issues.append((name, 'matches a local private configuration value'))
        if issues:
            for name, rule in issues:
                print('BLOCKED:', name, '(' + rule + ')')
            return 1
        config = snapshot / '.gitleaks.toml'
        targets = [('index', ['dir', str(snapshot)])]
        if history:
            targets.append(('history', ['git', str(root), '--log-opts=--all']))
        for label, args in targets:
            report = work / (label + '.json')
            result = subprocess.run([
                scanner, *args, '--config', str(config), '--redact=100',
                '--no-banner', '--no-color', '--ignore-gitleaks-allow',
                '--gitleaks-ignore-path', str(work), '--max-archive-depth=2',
                '--report-format=json', '--report-path', str(report),
            ], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            if result.returncode:
                findings = json.loads(report.read_text()) if report.exists() else []
                for finding in findings:
                    name = finding.get('File', '').replace(str(snapshot) + '/', '')
                    print('BLOCKED:', label, name, 'line', finding.get('StartLine'),
                          '(' + finding.get('RuleID', 'secret') + ')')
                if not findings:
                    print('BLOCKED: Gitleaks failed to complete the', label, 'scan.')
                return 1
    print(f'PASS: {len(entries)} staged files; private paths and secrets excluded.'
          + (' Git history scan passed.' if history else ''))
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--history', action='store_true', help='also scan all local Git refs')
    args = parser.parse_args()
    try:
        root = Path(git(Path.cwd(), 'rev-parse', '--show-toplevel').decode().strip())
        return scan(root, args.history)
    except (OSError, ValueError, subprocess.CalledProcessError):
        print('BLOCKED: publication checks could not complete; no secret details printed.')
        return 1


if __name__ == '__main__':
    raise SystemExit(main())

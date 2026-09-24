#!/usr/bin/env python3
"""Offline reference validation/coverage. Never reads .env, connects to DB, or approves data."""
import argparse
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('reference', type=Path)
p.add_argument('--previous', type=Path, help='Required for review of an update; retained immutable prior version')
p.add_argument('--hospitals', type=Path, help='Public audit fixture only; coverage is not an implementation gate')
args = p.parse_args()
backend = root / 'services/backend'
classpath = backend / 'target/reference-classpath.txt'
subprocess.run(['mvn', '-q', '-DskipTests', 'compile', 'dependency:build-classpath',
                '-Dmdep.outputFile=' + str(classpath)], cwd=backend, check=True)
command = ['java', '-cp', str(backend / 'target/classes') + ':' + classpath.read_text().strip(),
           'com.eroute.personalization.ReferenceTool', str(args.reference.resolve())]
if args.previous or args.hospitals:
    command.append(str(args.previous.resolve()) if args.previous else '-')
if args.hospitals:
    command.append(str(args.hospitals.resolve()))
subprocess.run(command, cwd=root, check=True)

#!/usr/bin/env python3
"""Read-only production artifact/configuration gate. Never prints key material."""
import argparse, os, sys, zipfile
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument('--jar', type=Path, required=True)
p.add_argument('--artifact-only', action='store_true')
a = p.parse_args()
with zipfile.ZipFile(a.jar) as jar:
    names = jar.namelist()
    if any('/auth/development/' in n or n.endswith('/Bootstrap.class') for n in names):
        sys.exit('Rejected: development authentication/bootstrap classes in production artifact')
if not a.artifact_only:
    if os.environ.get('EROUTE_AUTH_ENVIRONMENT') != 'production':
        sys.exit('Rejected: explicit production authentication environment required')
    if os.environ.get('EROUTE_ALLOW_DEVELOPMENT_AUTH', 'false') != 'false':
        sys.exit('Rejected: development authentication enabled')
    if os.environ.get('EROUTE_AUTH_PROVIDER', 'disabled') not in ('disabled', 'password'):
        sys.exit('Rejected: production requires disabled or password authentication; development identity adapters are forbidden')
print('Authentication production artifact/configuration gate passed')

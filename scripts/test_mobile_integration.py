#!/usr/bin/env python3
"""Native-map tests with fixture hospitals and mandatory mock emergency dialing."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import shutil
import re

root = Path(__file__).resolve().parents[1]
values = {}
if (root / '.env').exists():
    for line in (root / '.env').read_text().splitlines():
        if '=' in line and not line.lstrip().startswith('#'):
            key, value = line.split('=', 1)
            values[key.strip()] = value.strip().strip('"').strip("'")
values.update(os.environ)
public = {key: values[key] for key in ['NAVER_MAP_CLIENT_ID', 'API_BASE_URL', 'DETAIL_SMOKE_HPID', 'DETAIL_SMOKE_HPIDS'] if values.get(key)}
public.update(EROUTE_AUTOMATION='true', EROUTE_TEST_HARNESS='true', ENABLE_SYSTEM_EMERGENCY_DIALER='false')
if 'NAVER_MAP_CLIENT_ID' not in public:
    sys.exit('NAVER_MAP_CLIENT_ID is required for native map verification.')
if (public.get('DETAIL_SMOKE_HPID') or public.get('DETAIL_SMOKE_HPIDS')) and not public.get('API_BASE_URL'):
    sys.exit('API_BASE_URL is required for the opt-in stored detail smoke test.')
device = sys.argv[1] if len(sys.argv) == 2 else 'emulator-5554'
with tempfile.NamedTemporaryFile(mode='w', suffix='.json') as config:
    json.dump(public, config)
    config.flush()
    command = [os.environ.get('FLUTTER_BIN', 'flutter'), 'test',
        'integration_test/map_ux_integration_test.dart', '--flavor', 'dev', '-d', device,
        '--dart-define-from-file=' + config.name]
    # Export test-owned screenshots while the integration APK still exists.
    adb = shutil.which('adb') or str(Path.home() / 'Library/Android/sdk/platform-tools/adb')
    process = subprocess.Popen(command, cwd=root / 'apps/mobile', stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, text=True)
    qa_failed = False
    for line in process.stdout:
        print(line, end='', flush=True)
        match = re.search(r'QA_IMAGE (/data/user/0/(com\.eroute\.[\w.]+)/code_cache/(eroute-[\w-]+\.png))', line)
        if match:
            remote, package, filename = match.groups()
            target = root / 'apps/mobile/build/qa/native' / filename
            target.parent.mkdir(parents=True, exist_ok=True)
            with target.open('wb') as output:
                result = subprocess.run([adb, '-s', device, 'exec-out', 'run-as', package, 'cat', remote], stdout=output)
            qa_failed |= result.returncode != 0
    status = process.wait()
    sys.exit(status or (1 if qa_failed else 0))

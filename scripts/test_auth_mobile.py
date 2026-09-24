#!/usr/bin/env python3
"""General-app signup with fresh synthetic credentials and real development HTTP/DB.
The private credential file is never committed or printed. No launcher or external product API.
"""
import argparse, json, os, secrets, subprocess, tempfile
from pathlib import Path
root = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser()
p.add_argument('--device', required=True)
p.add_argument('--api-base-url', required=True)
p.add_argument('--credentials', type=Path, required=True, help='New private output file; refuses overwrite')
p.add_argument('--environment', choices=['local', 'test'], default='local')
a = p.parse_args()
if a.credentials.exists():
    p.error('Use a new private credential output path for each signup run')
account = {'phone': '010' + ''.join(str(secrets.randbelow(10)) for _ in range(8)),
           'password': ' '+secrets.token_urlsafe(24)+' e\u0301 \uac00\ub098\ub2e4 \U0001f600 '}
a.credentials.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
with os.fdopen(os.open(a.credentials, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w') as f:
    json.dump({'environment': a.environment, 'account': account}, f)
values={}
if (root/'.env').exists():
    for line in (root/'.env').read_text().splitlines():
        if '=' in line and not line.lstrip().startswith('#'):
            k,v=line.split('=',1);values[k.strip()]=v.strip().strip('\"\'')
values.update(os.environ)
if not values.get('NAVER_MAP_CLIENT_ID'): p.error('Existing map Client ID is required')
config = {'API_BASE_URL': a.api_base_url, 'NAVER_MAP_CLIENT_ID': values['NAVER_MAP_CLIENT_ID'],
          'AUTH_ENVIRONMENT': a.environment, 'ENABLE_DEVELOPMENT_AUTH': 'false',
          'EROUTE_AUTOMATION': 'true','ENABLE_SYSTEM_EMERGENCY_DIALER': 'false',
          'MEMBER_TEST_ACCOUNT': json.dumps(account)}
flutter = os.environ.get('FLUTTER_BIN', str(Path.home() / 'development/flutter/bin/flutter'))
with tempfile.NamedTemporaryFile('w', suffix='.json') as f:
    json.dump(config, f); f.flush()
    subprocess.run([flutter, 'test', 'integration_test/auth_health_integration_test.dart', '-d', a.device,
                    '--flavor=dev', '--dart-define-from-file=' + f.name], cwd=root / 'apps/mobile', check=True)
print('General app signup/health integration passed. Private account file:',a.credentials)

#!/usr/bin/env python3
"""Explicit synthetic account provisioning; never imports .env or contacts external services."""
import argparse, base64, json, os, secrets, subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser()
p.add_argument('--environment', choices=['local', 'test'], required=True)
p.add_argument('--accounts', default='operator,member-a,member-b', choices=['operator,member-a,member-b'])
p.add_argument('--initialize-local-database', action='store_true')
p.add_argument('--rotate-credentials', action='store_true')
args = p.parse_args()
for required in ('DB_URL', 'DB_USERNAME', 'DB_PASSWORD'):
    if required not in os.environ:
        p.error(f'{required} must be supplied explicitly')
folder = root / '.runtime' / ('auth-' + args.environment)
folder.mkdir(parents=True, exist_ok=True, mode=0o700)
keyfile = folder / 'keys.json'
if not keyfile.exists():
    keys = {'environment': args.environment}
    for purpose in ('health', 'account', 'temporary', 'identity', 'session'):
        value = base64.urlsafe_b64encode(secrets.token_bytes(32)).decode().rstrip('=')
        keys[purpose] = {'active': 'v1', 'keys': {'v1': value}}
    with os.fdopen(os.open(keyfile, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w') as f:
        json.dump(keys, f)
env = os.environ.copy()
env.update(EROUTE_AUTH_ENVIRONMENT=args.environment, EROUTE_AUTH_KEY_FILE=str(keyfile),
           EROUTE_DEV_CREDENTIALS_FILE=str(folder / 'credentials.json'))
java = Path(env.get('JAVA_HOME', '/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home')) / 'bin/java'
command = [str(java) if java.exists() else 'java', '-Dloader.main=com.eroute.auth.development.Bootstrap',
           '-cp', str(root / 'services/backend/target/emergency-api-0.1.0.jar'),
           'org.springframework.boot.loader.launch.PropertiesLauncher']
if args.initialize_local_database:
    command.append('--initialize-local-database')
if args.rotate_credentials:
    command.append('--rotate-credentials')
subprocess.run(command, env=env, check=True)
print(f'Key file: {keyfile}\nPrivate credential file: {folder / "credentials.json"}')

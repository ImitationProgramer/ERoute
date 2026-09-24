#!/usr/bin/env python3
"""Only public mobile configuration is exported; the NMC key never enters Dart defines."""
import json,os,shutil,subprocess,sys,tempfile
from pathlib import Path
root=Path(__file__).resolve().parents[1]
values={}
if (root/'.env').exists():
 for line in (root/'.env').read_text().splitlines():
  if '=' in line and not line.lstrip().startswith('#'):
   k,v=line.split('=',1);values[k.strip()]=v.strip().strip('"').strip("'")
values.update(os.environ)
public={k:values[k] for k in ['API_BASE_URL','NAVER_MAP_CLIENT_ID'] if values.get(k)}
public['AUTH_ENVIRONMENT']=values.get('EROUTE_AUTH_ENVIRONMENT','disabled')
public['ENABLE_DEVELOPMENT_AUTH']='true' if values.get('EROUTE_ALLOW_DEVELOPMENT_AUTH')=='true' and public['AUTH_ENVIRONMENT'] in ('local','test') else 'false'
public['EROUTE_AUTOMATION']='true'
public['ENABLE_SYSTEM_EMERGENCY_DIALER']='false'
build_only='--build-apk' in sys.argv[1:]
mobile_args=[a for a in sys.argv[1:] if a!='--build-apk']
if any(arg.startswith(('--flavor','--target','-t','--dart-define')) or 'main_production' in arg for arg in mobile_args):
 sys.exit('Development launcher does not accept target, flavor or Dart define overrides.')
if 'NAVER_MAP_CLIENT_ID' not in public:sys.exit('Existing NAVER_MAP_CLIENT_ID is required for the general app.')
if 'API_BASE_URL' not in public:sys.exit('Set API_BASE_URL to a backend reachable from your device; no production default is supplied.')
flutter=os.environ.get('FLUTTER_BIN') or shutil.which('flutter')
if not flutter:
 flutter=str(Path.home()/'development/flutter/bin/flutter')
if not shutil.which(flutter):
 sys.exit('Flutter SDK not found: '+flutter+'\nInstall Flutter in ~/development/flutter or set FLUTTER_BIN to its bin/flutter executable.')
with tempfile.NamedTemporaryFile(mode='w',suffix='.json') as f:
 json.dump(public,f);f.flush()
 result=subprocess.run([flutter,*(['build','apk'] if build_only else ['run']),'--flavor=dev','--target=lib/main.dart','--dart-define-from-file='+f.name,*mobile_args],cwd=root/'apps/mobile')
 sys.exit(result.returncode)

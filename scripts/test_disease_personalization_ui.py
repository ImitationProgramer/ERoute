#!/usr/bin/env python3
"""Native review QA against a verified stored-only local server. Mock 119 mandatory."""
import argparse,json,pathlib,re,subprocess,urllib.request,urllib.parse
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--defines',type=pathlib.Path,required=True)
p.add_argument('--output',type=pathlib.Path,required=True)
p.add_argument('--device',default='emulator-5554')
p.add_argument('--target',choices=['review','approved','map'],default='review')
a=p.parse_args();root=pathlib.Path(__file__).resolve().parents[1]
cfg=json.loads(a.defines.read_text());url=urllib.parse.urlsplit(cfg.get('API_BASE_URL',''))
if url.scheme!='http' or url.hostname not in ['10.0.2.2','127.0.0.1','localhost'] or cfg.get('AUTH_ENVIRONMENT') not in ['local','test']:
 p.error('An isolated local/test server is required')
if str(cfg.get('ENABLE_SYSTEM_EMERGENCY_DIALER','')).lower()!='false' or str(cfg.get('EROUTE_AUTOMATION','')).lower()!='true':p.error('Mock 119 and automation are required')
with urllib.request.urlopen(f'http://127.0.0.1:{url.port}/api/v1/map-config',timeout=10) as response:
 if response.headers.get('X-ERoute-Stored-QA')!='true':p.error('Stored-only QA adapter is required')
a.output.mkdir(parents=True,exist_ok=True);(a.output/'screenshots').mkdir(exist_ok=True)
adb=str(pathlib.Path.home()/'Library/Android/sdk/platform-tools/adb')
# Set the baseline input before app launch, including first permission prompts.
subprocess.run([adb,'-s',a.device,'emu','geo','fix','126.9779983','37.5664983'],check=True,stdout=subprocess.DEVNULL)
targets={'review':'disease_review_preview_integration_test.dart','approved':'personalization_overlay_integration_test.dart','map':'map_ux_integration_test.dart'}
command=['flutter','test','integration_test/'+targets[a.target],'--flavor=dev','-d',a.device,'--dart-define-from-file='+str(a.defines.resolve())]
process=subprocess.Popen(command,cwd=root/'apps/mobile',stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
with (a.output/'android.log').open('w') as log:
 for line in process.stdout:
  log.write(line);log.flush()
  if 'actual v0.4' in line:
   for permission in ['android.permission.ACCESS_COARSE_LOCATION','android.permission.ACCESS_FINE_LOCATION']:
    subprocess.run([adb,'-s',a.device,'shell','pm','grant','com.eroute.eroute_mobile',permission],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
  found=re.search(r'QA_(IMAGE|ARTIFACT) (/data/user/0/(com\.eroute\.[\w.]+)/code_cache/(eroute-[\w-]+\.(?:png|json)))',line)
  if found:
   kind,remote,package,name=found.groups();dest=a.output/('screenshots/'+name if kind=='IMAGE' else 'results.json')
   with dest.open('wb') as target:subprocess.run([adb,'-s',a.device,'exec-out','run-as',package,'cat',remote],stdout=target,check=True)
   print('Captured',name,flush=True)
status=process.wait();print('Android QA exit',status)
raise SystemExit(status)

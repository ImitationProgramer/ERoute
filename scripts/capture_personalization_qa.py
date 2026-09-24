#!/usr/bin/env python3
"""Capture stored-only localhost QA responses; never contact NMC/HIRA or real member data.
Use only a synthetic account in an isolated public-data clone. Replays use Dart's matcher.
"""
import argparse, datetime, json, pathlib, urllib.request, urllib.parse
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--base-url',required=True);p.add_argument('--account-file',type=pathlib.Path,required=True)
p.add_argument('--center',type=float,nargs=2,required=True,metavar=('LAT','LON'))
p.add_argument('--radius',type=int,required=True);p.add_argument('--diseases',nargs='+',required=True)
p.add_argument('--output',type=pathlib.Path,required=True)
a=p.parse_args();url=urllib.parse.urlsplit(a.base_url)
if url.scheme!='http' or url.hostname not in ['127.0.0.1','localhost'] or url.username or url.password: p.error('Only a local isolated QA server is allowed')
def request(path,data=None,token=None):
 headers={'Content-Type':'application/json'}
 if token:headers['Authorization']='Bearer '+token
 req=urllib.request.Request(a.base_url.rstrip('/')+path,data=None if data is None else json.dumps(data).encode(),headers=headers)
 with urllib.request.urlopen(req,timeout=30) as response:
  if response.headers.get('X-ERoute-Stored-QA')!='true':raise RuntimeError('Stored-only QA adapter is required; refusing requests')
  return json.load(response)
# This read-only probe happens before login or search.
request('/api/v1/map-config')
account=json.loads(a.account_file.read_text())
login=request('/api/v1/auth/login',{'phone':account['phone'],'password':account['password']})
token=login['tokens']['accessToken'] if 'tokens' in login else login['accessToken']
reference=request('/api/v1/reference/disease-departments')
preview=request('/api/v1/dev/reference/disease-departments-review-preview',token=token)
known={d['id'] for d in json.loads(reference['document'])['diseases'] if d['active']}
if not set(a.diseases)<=known:p.error('Unknown/inactive disease IDs')
center=dict(zip(['latitude','longitude'],a.center))
search=request('/api/v1/emergency-hospitals/search',{'center':center,'centerSource':'MANUAL','radiusMeters':a.radius})
hpids=[h['hpid'] for h in search['hospitals']];departments=[]
for offset in range(0,len(hpids),100):departments+=request('/api/v1/emergency-hospitals/departments/query',{'hpids':hpids[offset:offset+100]})['hospitals']
bundle={'reference':reference,'preview':preview,'search':search,'departments':departments,
 'center':center,'requestedRadius':a.radius,'selectedDiseaseIds':a.diseases,
 'evaluatedAt':datetime.datetime.now(datetime.timezone.utc).isoformat()}
a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(bundle,ensure_ascii=False,indent=2)+'\n')
print('Stored public QA bundle written; no member selections were read.')

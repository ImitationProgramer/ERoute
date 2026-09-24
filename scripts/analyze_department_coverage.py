#!/usr/bin/env python3
"""Read-only published NMC coverage. No API access or member-data reads.
Output is public hospital data; reference comes only from the Backend file.
"""
import argparse, collections, datetime, hashlib, json, os, subprocess, urllib.parse
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--output',type=Path);args=p.parse_args()
cfg={}
for line in (ROOT/'.env').read_text().splitlines():
    if '=' in line and not line.lstrip().startswith('#'):
        k,v=line.split('=',1);cfg[k.strip()]=v.strip().strip('\"\'')
u=urllib.parse.urlsplit(cfg['DB_URL'].removeprefix('jdbc:'))
env=os.environ.copy();env['PGPASSWORD']=cfg.get('DB_PASSWORD','');env['PGOPTIONS']='-c default_transaction_read_only=on -c statement_timeout=30000'
sql="""BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
SELECT json_build_object('observedAt',now(),'readOnly',current_setting('transaction_read_only'),
'datasetVersion',(SELECT current_run_id FROM hospital_basic_info_state),
'nmcAttempts',(SELECT count(*) FROM nmc_call_attempt),
'hospitals',(SELECT json_agg(q) FROM (
 SELECT h.hpid,h.active,h.latitude,h.longitude,m.record_status AS "recordStatus",s.id AS "snapshotId",s.departments_status AS "departmentsStatus",s.normalizer_version AS "normalizerVersion",s.fetched_at AS "fetchedAt",s.raw_department_text AS "rawDepartmentText",
 COALESCE((SELECT json_agg(json_build_object('name',d.department_name,'rawValue',d.raw_value,'source',d.source,'interpretationStatus',d.interpretation_status,'ordinal',d.ordinal) ORDER BY d.ordinal) FROM hospital_department d WHERE d.snapshot_id=s.id),'[]'::json) departments
 FROM hospital h LEFT JOIN hospital_basic_info_state st ON true LEFT JOIN hospital_basic_info_dataset_member m ON m.run_id=st.current_run_id AND m.hpid=h.hpid LEFT JOIN hospital_basic_info_snapshot s ON s.id=m.snapshot_id ORDER BY h.hpid) q)); COMMIT;"""
r=subprocess.run(['psql','-X','-w','-qAt','-v','ON_ERROR_STOP=1','-h',u.hostname,'-p',str(u.port or 5432),'-U',cfg['DB_USERNAME'],'-d',u.path.lstrip('/'),'-c',sql],env=env,capture_output=True,text=True)
if r.returncode:raise SystemExit('Read-only coverage query failed; no output written.')
data=json.loads(r.stdout);hospitals=data['hospitals'];known=lambda h:{t['name'] for t in h['departments'] if t['interpretationStatus']=='KNOWN'}
ref_path=ROOT/'services/backend/src/main/resources/reference/disease-departments/v0.1.json';raw=ref_path.read_bytes();ref=json.loads(raw);departments={d['id']:d['canonicalName'] for d in ref['departments']}
freq=collections.Counter(n for h in hospitals for n in known(h));direct={departments[m['departmentId']] for m in ref['mappings'] if m['relationType']=='DIRECT'}
disease_coverage={d['id']:sum(bool(known(h)&{departments[m['departmentId']] for m in ref['mappings'] if m['diseaseId']==d['id'] and m['relationType']=='DIRECT'}) for h in hospitals if h['active']) for d in ref['diseases']}
data['referenceVersion']=ref['datasetVersion'];data['referenceSha256']=hashlib.sha256(raw).hexdigest()
data['summary']={'masterCount':len(hospitals),'activeCount':sum(h['active'] for h in hospitals),'searchableCount':sum(h['active'] and h['latitude'] is not None and h['longitude'] is not None for h in hospitals),'withDepartments':sum(bool(known(h)) for h in hospitals),'normalizedTokenCount':sum(len(h['departments']) for h in hospitals),'distinctNormalizedCount':len(freq),'normalizedFrequencies':dict(sorted(freq.items())),'directCoverage':{n:freq[n] for n in sorted(direct)},'diseaseCoverage':disease_coverage,'matchableDiseases':sum(n>0 for n in disease_coverage.values()),'broadFrequencies':{n:freq[n] for n in ref['uncertaintyPolicy']['broadDepartmentNames']}}
if args.output:
    args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({k:v for k,v in data.items() if k!='hospitals'},ensure_ascii=False,indent=2))

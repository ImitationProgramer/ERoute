#!/usr/bin/env python3
"""Opt-in real NMC discovery; shares PostgreSQL call ledger with the Java guard."""
import argparse,datetime,hashlib,json,os,sys,time,urllib.request,urllib.parse,xml.etree.ElementTree as ET
from pathlib import Path
import psycopg
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))

def environment():
 values={}
 p=ROOT/'.env'
 if p.exists():
  for line in p.read_text().splitlines():
   if '=' in line and not line.lstrip().startswith('#'):
    k,v=line.split('=',1);v=v.strip();values[k.strip()]=v[1:-1] if len(v)>1 and v[0]==v[-1] and v[0] in '\"\'' else v
 values.update(os.environ)
 return values

def run():
 import subprocess
 subprocess.run([sys.executable,str(ROOT/'scripts/verify_sources.py')],check=True)
 args=argparse.ArgumentParser(description=__doc__);args.add_argument('--regional',action='store_true');options=args.parse_args()
 e=environment();key=e.get('NMC_SERVICE_KEY','')
 if e.get('NMC_SERVICE_KEY_ENCODING','decoded')=='encoded':key=urllib.parse.unquote(key)
 if not key:sys.exit('NMC_SERVICE_KEY missing. No requests sent.')
 db=e.get('DB_URL','jdbc:postgresql://localhost:5432/eroute').removeprefix('jdbc:')
 conn=psycopg.connect(db,user=e.get('DB_USERNAME','eroute'),password=e.get('DB_PASSWORD',''),autocommit=True)
 endpoint='getEgytListInfoInqire';alias=e.get('NMC_KEY_ALIAS','development');budget=int(e.get('NMC_ENDPOINT_CALL_BUDGET','900'))
 report={'status':'PENDING','calls':[],'testedPageSizes':[],'timezone':'UNVERIFIED','maximumNumOfRows':'UNVERIFIED'}
 requests=0
 def page(no,size,filters=None,scope="NATIONWIDE"):
  nonlocal requests
  if requests>=(budget if options.regional else 20):raise RuntimeError('DISCOVERY_RUN_BUDGET_REACHED')
  with conn.transaction():
   conn.execute('SELECT pg_advisory_xact_lock(hashtext(%s))',(alias+':'+endpoint,))
   blocked=conn.execute('SELECT 1 FROM nmc_budget_block WHERE key_alias=%s AND endpoint=%s AND blocked_until>clock_timestamp()',(alias,endpoint)).fetchone()
   used=conn.execute("SELECT count(*) FROM nmc_call_attempt WHERE key_alias=%s AND endpoint=%s AND requested_at>clock_timestamp()-interval '24 hours'",(alias,endpoint)).fetchone()[0]
   if blocked or used>=budget:raise RuntimeError('CALL_BUDGET_LIMIT')
   call_id=conn.execute('INSERT INTO nmc_call_attempt(key_alias,endpoint) VALUES(%s,%s) RETURNING id',(alias,endpoint)).fetchone()[0]
  requests+=1
  query=urllib.parse.urlencode({'ServiceKey':key,'pageNo':no,'numOfRows':size,**(filters or {})})
  url=e['NMC_BASE_URL'].rstrip('/')+'/'+endpoint+'?'+query
  now=datetime.datetime.now(datetime.timezone.utc)
  try:
   with urllib.request.urlopen(url,timeout=10) as response:
    body=response.read(8388609)
    if len(body)>8388608:raise RuntimeError('RESPONSE_TOO_LARGE')
    xml=body.decode('utf-8-sig')
   xml=xml.replace(key,'[REDACTED]').replace(urllib.parse.quote_plus(key),'[REDACTED]')
   if '<!DOCTYPE' in xml.upper() or '<!ENTITY' in xml.upper():raise RuntimeError('UNSAFE_XML')
   doc=ET.fromstring(xml);code=doc.findtext('.//resultCode')
   conn.execute('INSERT INTO provider_response(endpoint,scope,page_no,fetched_at,raw_xml,outcome) VALUES(%s,%s,%s,%s,%s,%s)',(endpoint,'DISCOVERY:'+scope,no,now,xml,'SUCCESS' if code=='00' else 'NMC_RESULT_ERROR'))
   if code!='00':
    if code in ('22','23'):
     conn.execute("INSERT INTO nmc_budget_block VALUES(%s,%s,clock_timestamp()+interval '24 hours') ON CONFLICT(key_alias,endpoint) DO UPDATE SET blocked_until=excluded.blocked_until",(alias,endpoint))
    raise RuntimeError('NMC_RESULT_ERROR_'+str(code))
   items=[{c.tag:c.text or '' for c in row} for row in doc.findall('.//item')]
   data={'scope':scope,'requestedPage':no,'requestedSize':size,'pageNo':int(doc.findtext('.//pageNo')),'numOfRows':int(doc.findtext('.//numOfRows')),'totalCount':int(doc.findtext('.//totalCount')),'actualCount':len(items),'fetchedAt':now.isoformat()}
   report['calls'].append(data)
   conn.execute("UPDATE nmc_call_attempt SET outcome='SUCCESS' WHERE id=%s",(call_id,))
   time.sleep(0.6)
   return data,items
  except Exception as ex:
   if hasattr(ex,'read'):
    safe=ex.read(4096).decode('utf-8',errors='replace').replace(key,'[REDACTED]').replace(urllib.parse.quote_plus(key),'[REDACTED]')
    report['gatewayErrorBody']=safe
   conn.execute("UPDATE nmc_call_attempt SET outcome='ERROR' WHERE id=%s",(call_id,))
   # Never expose urllib's exception: it can contain the service key URL.
   if isinstance(ex,RuntimeError):raise
   raise RuntimeError('DISCOVERY_'+type(ex).__name__+(('_HTTP_'+str(ex.code)) if hasattr(ex,'code') else '')+(('_'+type(ex.reason).__name__) if hasattr(ex,'reason') else '')) from None
 passed=False;size=None
 try:
  if not options.regional:
   first,small=page(1,10)
   for requested in [100,500,1000]:
    meta,rows=page(1,requested);report['testedPageSizes'].append({'requested':requested,'returned':meta['numOfRows'],'actualCount':len(rows)})
    if meta['pageNo']!=1 or meta['numOfRows']<1 or meta['totalCount']!=first['totalCount']:raise RuntimeError('UNSTABLE_OR_INVALID_PAGINATION')
    if len(rows)!=min(meta['numOfRows'],meta['totalCount']):raise RuntimeError('INCOMPLETE_PAGE')
    if meta['numOfRows']<requested:report['maximumNumOfRows']={'observedClamp':meta['numOfRows']};break
   # Explicitly exercise nonempty later pages, even when a large page fits the whole catalog.
   size=min(meta['numOfRows'],100);meta,rows=page(1,size);total=meta['totalCount'];allrows=list(rows)
   for no in range(2,(total+size-1)//size+1):
    m,rs=page(no,size)
    if m['pageNo']!=no or m['numOfRows']!=size or m['totalCount']!=total or len(rs)!=min(size,total-(no-1)*size):raise RuntimeError('INCOMPLETE_PAGE')
    allrows.extend(rs)
   hpids=[r.get('hpid','').strip() for r in allrows]
   if not total or len(hpids)!=total or len(set(hpids))!=total or '' in hpids:raise RuntimeError('HPID_COVERAGE_MISMATCH')
   if not set(r.get('hpid') for r in small).issubset(set(hpids)):raise RuntimeError('PAGE_SIZE_COVERAGE_MISMATCH')
   out,empty=page((total+size-1)//size+1,size)
   if empty:raise RuntimeError('OUT_OF_RANGE_NONEMPTY')
   prefixes=sorted(set(r.get('dutyAddr','').split(' ')[0] for r in allrows))
   if len(prefixes)<2:raise RuntimeError('NATIONWIDE_SCOPE_NOT_ESTABLISHED')
   report.update(status='PASSED',totalCount=total,uniqueHpidCount=len(set(hpids)),observedAddressPrefixes=prefixes,safePageSize=size,outOfRangeEmpty=True)
   passed=True
  else:
   reference=json.loads((ROOT/'docs/references/administrative-regions.json').read_text())
   active=[r for r in reference['regions'] if r['referenceStatus']=='존재']
   scopes=[r for r in active if not any(other['addressPrefix'].startswith(r['addressPrefix']+' ') for other in active)]
   if not scopes:raise RuntimeError('REGION_REFERENCE_EMPTY')
   report['regionReferenceSha256']=reference['sha256'];report['validatedRegionIds']=[]
   hpids=set();size=100
   for region in scopes:
    filters={'Q0':region['stage1'],'Q1':region['stage2']}
    meta,rows=page(1,size,filters,region['id']);total=meta['totalCount'];actual=meta['numOfRows']
    if actual<1 or meta['pageNo']!=1 or len(rows)!=min(actual,total):raise RuntimeError('INCOMPLETE_PAGE')
    local=list(rows)
    for no in range(2,(total+actual-1)//actual+1):
     m,rs=page(no,actual,filters,region['id'])
     if m['pageNo']!=no or m['numOfRows']!=actual or m['totalCount']!=total or len(rs)!=min(actual,total-(no-1)*actual):raise RuntimeError('INCOMPLETE_PAGE')
     local.extend(rs)
    localids=[r.get('hpid','').strip() for r in local]
    if '' in localids or len(set(localids))!=total:raise RuntimeError('HPID_COVERAGE_MISMATCH')
    hpids.update(localids);report['validatedRegionIds'].append(region['id'])
   if not hpids:raise RuntimeError('EMPTY_REGIONAL_CATALOG')
   report.update(status='PASSED',safePageSize=size,uniqueHpidCount=len(hpids),totalCount=len(hpids));passed=True
 except RuntimeError as ex:report.update(status='INCOMPLETE' if str(ex) in ('CALL_BUDGET_LIMIT','DISCOVERY_RUN_BUDGET_REACHED') else 'FAILED',reason=str(ex))
 book=json.loads((ROOT/'services/backend/src/main/resources/nmc/codebooks/v13/codebook.json').read_text())
 report['completedAt']=datetime.datetime.now(datetime.timezone.utc).isoformat()
 conn.execute('INSERT INTO discovery_result(passed,mode,page_size,report,pdf_sha256,endpoint) VALUES(%s,%s,%s,%s::jsonb,%s,%s)',(passed,'REGIONAL' if options.regional else 'NATIONWIDE',size,json.dumps(report,ensure_ascii=False),book['officialSource']['sha256'],endpoint))
 out=ROOT/('docs/api/nmc-regional-discovery-report.md' if options.regional else 'docs/api/nmc-discovery-report.md')
 out.write_text('# NMC nationwide discovery\n\nReal authenticated requests, all counted in the PostgreSQL endpoint budget ledger.\n\n```json\n'+json.dumps(report,ensure_ascii=False,indent=2)+'\n```\n\nA PASSED result validates only the observed request scope and safe page size, not a guaranteed global maximum or timestamp timezone.\n')
 print(json.dumps({'status':report['status'],'calls':requests,'totalCount':report.get('totalCount'),'reason':report.get('reason')},ensure_ascii=False))
 return 0 if passed else 2
if __name__=='__main__':sys.exit(run())

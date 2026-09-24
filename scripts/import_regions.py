#!/usr/bin/env python3
"""Import official nationwide legal district reference; NMC filter compatibility remains unverified."""
import csv,datetime,hashlib,io,json,urllib.request,urllib.parse,zipfile
from pathlib import Path
import psycopg
from discover_nmc import environment,ROOT

def main():
 e=environment();url='https://www.code.go.kr/etc/codeFullDown.do'
 req=urllib.request.Request(url,data=urllib.parse.urlencode({'codeseId':'법정동코드'}).encode())
 with urllib.request.urlopen(req,timeout=30) as r:content=r.read()
 with zipfile.ZipFile(io.BytesIO(content)) as z:raw=z.read(z.namelist()[0])
 text=raw.decode('cp949');rows=[]
 for line in csv.DictReader(io.StringIO(text),delimiter='\t'):
  code=line['법정동코드'];name=line['법정동명'];parts=name.split()
  if not code.endswith('00000') or code.endswith('00000000'):continue
  # Both extant and abolished prefixes remain explicit reference data. No regional constants.
  rows.append({'id':code,'addressPrefix':name,'stage1':parts[0],'stage2':' '.join(parts[1:]),'referenceStatus':line['폐지여부']})
 unique={}
 for r in sorted(rows,key=lambda r:(r['referenceStatus']=='존재',r['id'])):unique[r['addressPrefix']]=r
 rows=list(unique.values())
 artifact={'source':url,'retrievedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'sha256':hashlib.sha256(raw).hexdigest(),'nmcFilterCompatibility':'UNVERIFIED_UNTIL_QUERIED','regions':rows}
 p=ROOT/'docs/references/administrative-regions.json';p.write_text(json.dumps(artifact,ensure_ascii=False,indent=2)+'\n')
 with psycopg.connect(e.get('DB_URL','jdbc:postgresql://localhost:5432/eroute').removeprefix('jdbc:'),user=e.get('DB_USERNAME','eroute'),password=e.get('DB_PASSWORD','')) as conn:
  for r in rows:
   conn.execute('''INSERT INTO nmc_region_mapping(id,address_prefix,stage1,stage2,source_version,verified) VALUES(%s,%s,%s,%s,%s,false)
    ON CONFLICT(id) DO UPDATE SET address_prefix=excluded.address_prefix,stage1=excluded.stage1,stage2=excluded.stage2,
    source_version=excluded.source_version,verified=CASE WHEN nmc_region_mapping.stage1=excluded.stage1 AND nmc_region_mapping.stage2=excluded.stage2 THEN nmc_region_mapping.verified ELSE false END''',(r['id'],r['addressPrefix'],r['stage1'],r['stage2'],artifact['sha256']))
  mappings=json.loads((ROOT/'services/backend/src/main/resources/nmc/region-query-mappings.json').read_text())
  for mapping in mappings['mappings']:
   conn.execute('''UPDATE nmc_region_mapping SET verified=false WHERE id=%s AND NOT EXISTS(
    SELECT 1 FROM nmc_region_query_mapping WHERE region_id=%s AND endpoint=%s AND request_region_id=%s)''',
    (mapping['regionId'],mapping['regionId'],mappings['endpoint'],mapping['requestRegionId']))
   conn.execute('''INSERT INTO nmc_region_query_mapping(region_id,endpoint,request_region_id,source_version)
    SELECT %s,%s,%s,%s WHERE EXISTS(SELECT 1 FROM nmc_region_mapping WHERE id=%s) AND EXISTS(SELECT 1 FROM nmc_region_mapping WHERE id=%s)
    ON CONFLICT(region_id,endpoint) DO UPDATE SET request_region_id=excluded.request_region_id,source_version=excluded.source_version''',
    (mapping['regionId'],mappings['endpoint'],mapping['requestRegionId'],mappings['version'],mapping['regionId'],mapping['requestRegionId']))
 print('Imported' ,len(rows),'official reference records; NMC compatibility is checked on demand.')
if __name__=='__main__':main()

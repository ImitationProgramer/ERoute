#!/usr/bin/env python3
"""Offline source gate: does not require PDF parsing dependencies or an API key."""
import hashlib,json,os,sys
from pathlib import Path
root=Path(__file__).resolve().parents[1]
book=json.loads((root/'services/backend/src/main/resources/nmc/codebooks/v13/codebook.json').read_text())
pdf=Path(os.environ.get('NMC_V13_PDF',str(root/book['officialSource']['path'])))
if not pdf.is_file() or not pdf.read_bytes().startswith(b'%PDF-'):
 sys.exit('NMC V13 PDF missing/unreadable. Place the original in docs/references or set NMC_V13_PDF.')
if hashlib.sha256(pdf.read_bytes()).hexdigest()!=book['officialSource']['sha256']:
 sys.exit('NMC V13 PDF hash differs: review source and codebook before implementation.')
if not (root/book['observationSource']['path']).is_file():sys.exit('Empirical observation source missing.')
for endpoint,data in book['endpoints'].items():
 seen=set()
 for field in data['fields']:
  assert field['pdfPages'] and field['semanticStatus'] in ('VERIFIED','UNVERIFIED')
  for name in [field['name']]+field['aliases']:
   assert name not in seen,(endpoint,name)
   seen.add(name)
basic=book['endpoints']['getEgytBassInfoInqire']
assert basic['request']['HPID']=='OPTIONAL'
basic_fields={field['name']:field for field in basic['fields']}
required={'hpid','dutyName','dutyAddr','dutyTel1','dutyTel3','dgidIdName'}
required.update(f'dutyTime{day}{suffix}' for day in range(1,9) for suffix in ('s','c'))
assert required.issubset(basic_fields),'Basic Info field definitions are incomplete'
for name in required:
 field=basic_fields[name]
 assert field['dataType']=='XML_TEXT'
 assert field['officialLabel'] and field['semanticCategory'] and field['normalizationPolicy']
 assert field['interpretationStatus'] in ('VERIFIED','UNVERIFIED')
 assert (root/field['evidenceReference']).is_file()
 if name.startswith('dutyTime'):
  assert field['semanticCategory']=='HOSPITAL_CLINIC_HOURS'
  assert field['normalizationPolicy']=='STRICT_HHMM_PAIR'
print('PASS: V13 PDF hash, observation source and endpoint-aware codebook verified.')

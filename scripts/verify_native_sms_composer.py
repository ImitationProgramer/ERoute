#!/usr/bin/env python3
"""Synthetic Android composer QA: inspect, capture, clear the test draft, then Back.
Never taps Send. Real-account data is deliberately rejected by this artifact helper.
"""
import hashlib, json, os, re, subprocess, sys, time, xml.etree.ElementTree as ET
from pathlib import Path
adb = str(Path(os.environ.get('ANDROID_HOME', str(Path.home() / 'Library/Android/sdk'))) / 'platform-tools/adb')
output = Path(sys.argv[1])
output.parent.mkdir(parents=True, exist_ok=True)
def run(*args):
    return subprocess.check_output([adb, *args])
def nodes():
    run('shell','uiautomator','dump','/data/local/tmp/eroute-sms-qa.xml')
    return list(ET.fromstring(run('shell','cat','/data/local/tmp/eroute-sms-qa.xml')).iter('node'))
n = nodes()
if any(v.get('package')=='com.eroute.eroute_mobile.preview' for v in n):
    button=next(v for v in n if v.get('content-desc')=='문자 앱에서 확인하고 보내기')
    assert button.get('enabled')=='true'
    x1,y1,x2,y2=map(int,re.findall(r'\d+',button.get('bounds')))
    run('shell','input','tap',str((x1+x2)//2),str((y1+y2)//2))
    time.sleep(1)
    n=nodes()
editor=next(v for v in n if v.get('resource-id','').endswith('/compose_message_text'))
expected=editor.get('text','')
assert '합성' in expected and expected.startswith('[ERoute 응급정보]')
values = [v.get(k,'') for v in n for k in ['text','content-desc']]
result = {'synthetic':True, 'nativePackage': 'com.google.android.apps.messaging',
          'recipient119': any(v=='119' or v.startswith('119,') for v in values),
          'bodySha256': hashlib.sha256(expected.encode()).hexdigest(),
          'excludedMemoAbsent': not any('QA 합성 메모' in v for v in values),
          'locationIncluded': '현재 위치:' in expected,
          'koreanAndLineBreaks': '기저질환:' in expected and '\n' in expected,
          'actualSend': 0}
assert any(v.get('package')==result['nativePackage'] for v in n), 'Messages not foreground'
assert result['recipient119'] and result['excludedMemoAbsent'], 'Composer mismatch (body redacted)'
output.write_bytes(run('exec-out','screencap','-p'))
editor=next(v for v in n if v.get('resource-id','').endswith('/compose_message_text'))
x1,y1,x2,y2=map(int,re.findall(r'\d+',editor.get('bounds')))
run('shell','input','tap',str((x1+x2)//2),str((y1+y2)//2))
run('shell','input','keycombination','113','29')
run('shell','input','keyevent','67')
result['testDraftCleared']=all('ERoute 응급정보' not in v.get('text','') for v in nodes())
assert result['testDraftCleared']
for _ in range(5):
    current=run('shell','dumpsys','activity','activities').decode()
    if re.search(r'topResumedActivity=.*com\.eroute\.eroute_mobile\.preview/',current):
        result['returnedToPreviewApp']=True
        break
    run('shell','input','keyevent','4')
    time.sleep(.4)
assert result.get('returnedToPreviewApp'), 'Back did not return to ERoute preview'
run('shell','rm','/data/local/tmp/eroute-sms-qa.xml')
output.with_suffix('.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(result,ensure_ascii=False))

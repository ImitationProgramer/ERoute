#!/usr/bin/env python3
"""Run from repository root alongside the synthetic Android integration driver.
Waits for two explicit preview handoffs; never sends an SMS.
"""
import subprocess,time,re,os,shutil
from pathlib import Path
android_sdk=Path(os.environ.get('ANDROID_SDK_ROOT') or os.environ.get('ANDROID_HOME') or Path.home()/'Library/Android/sdk')
adb=shutil.which('adb') or str(android_sdk/'platform-tools/adb')
for name in ['android-sms-composer','android-sms-composer-no-location']:
 deadline=time.monotonic()+120
 while time.monotonic()<deadline:
  x=subprocess.check_output([adb,'shell','dumpsys','activity','activities'],text=True)
  if re.search(r'topResumedActivity=.*com.google.android.apps.messaging/.main.MainActivity',x):break
  time.sleep(.4)
 else: raise RuntimeError('Native composer not reached')
 subprocess.run(['python3','scripts/verify_native_sms_composer.py','docs/qa/emergency-personalization-ios-2026-09-22/'+name+'.png'],check=True)
 print(name,'inspected and returned',flush=True)

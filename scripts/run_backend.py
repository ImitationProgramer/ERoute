#!/usr/bin/env python3
"""Read local .env without evaluating shell code; inherited environment takes precedence."""
import os,sys,subprocess,hashlib,shutil
from pathlib import Path
root=Path(__file__).resolve().parents[1]
env={}
p=root/'.env'
if p.exists():
 for line in p.read_text().splitlines():
  if '=' in line and not line.lstrip().startswith('#'):
   k,v=line.split('=',1);v=v.strip();env[k.strip()]=v[1:-1] if len(v)>1 and v[0]==v[-1] and v[0] in '\"\'' else v
os_env=os.environ.copy();env.update(os_env)
subprocess.run([sys.executable,str(root/'scripts/verify_sources.py')],check=True,env=env)
java=Path(env.get('JAVA_HOME','/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home'))/'bin/java'
source=root/'services/backend/target/emergency-api-0.1.0.jar'
digest=hashlib.sha256(source.read_bytes()).hexdigest()
folder=root/'.runtime/backend-artifacts';folder.mkdir(parents=True,exist_ok=True)
artifact=folder/(digest+'.jar')
if not artifact.exists():shutil.copy2(source,artifact)
args=[str(java) if java.exists() else 'java','-jar',str(artifact),*sys.argv[1:]]
os.execvpe(args[0],args,env)

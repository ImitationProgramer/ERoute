#!/usr/bin/env python3
"""Apply external deletion ledger to an ISOLATED restored database before serving it.

Requires psql, an explicitly marked restore target, and a trusted export produced
after all relevant deletions. Input contains IDs/epochs only, never health text.
"""
import argparse, json, os, subprocess, uuid
from pathlib import Path
p = argparse.ArgumentParser()
p.add_argument('--ledger', type=Path, required=True)
p.add_argument('--isolated-restore', action='store_true', required=True)
a = p.parse_args()
if os.environ.get('EROUTE_RESTORE_TARGET') != 'isolated':
    p.error('EROUTE_RESTORE_TARGET=isolated is required; do not run on a serving database')
rows = json.loads(a.ledger.read_text())
sql = ['BEGIN;', 'LOCK TABLE health_consent,member_health_profile,member_medication IN EXCLUSIVE MODE;']
for row in rows:
    user = str(uuid.UUID(row['userId']))
    epoch = row['consentEpoch']
    if not isinstance(epoch, int) or epoch < 0:
        p.error('Invalid consent epoch')
    resource = row.get('resourceId')
    if resource:
        resource = str(uuid.UUID(resource))
        if resource == user:
            sql.append(f"DELETE FROM member_health_profile WHERE user_id='{user}' AND consent_epoch<={epoch};")
        else:
            sql.append(f"DELETE FROM member_medication WHERE user_id='{user}' AND id='{resource}' AND consent_epoch<={epoch};")
    else:
        for table in ('member_health_profile', 'member_medication'):
            sql.append(f"DELETE FROM {table} WHERE user_id='{user}' AND consent_epoch<={epoch};")
        sql.append(f"UPDATE health_consent SET state='REVOKED',epoch={epoch+1} WHERE user_id='{user}' AND epoch<={epoch};")
# Never restore old sessions. New encryption material is required before writes resume.
sql += ['UPDATE auth_session SET revoked_at=COALESCE(revoked_at,clock_timestamp());', 'COMMIT;']
subprocess.run(['psql', '-X', '-v', 'ON_ERROR_STOP=1'], input='\n'.join(sql), text=True, check=True, stdout=subprocess.DEVNULL)
print('Restore exclusions applied. Keep isolated until key rotation and backup/ledger verification complete.')

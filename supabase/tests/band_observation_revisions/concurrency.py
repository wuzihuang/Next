#!/usr/bin/env python3
"""Prove delayed concurrent uploads do not overwrite later device reads."""
import concurrent.futures
import json
import subprocess
import sys

container = sys.argv[1]
command = ['docker', 'exec', '-i', container, 'psql', '-U', 'postgres', '-d', 'nb', '-Atq', '-v', 'ON_ERROR_STOP=1']
owner = '66666666-6666-4666-8666-666666666603'
def query(sql):
    result = subprocess.run(command, input=sql, text=True, capture_output=True, check=True)
    return result.stdout.strip()
def upload(value, minute):
    samples = json.dumps([{'ts': '2026-09-01T12:00Z', 'heart': value, 'step': value}])
    return f"select public.ingest_band_domain('band-A','origin','2026-09-01','UTC','2026-09-01T04:00Z','2026-09-02T04:00Z','{samples}','complete','veepoo-rmssd-v2','2026-09-02T12:{minute:02d}Z');"
auth = f"select set_config('request.jwt.claim.sub','{owner}',true); set local role authenticated;"
query(f"insert into auth.users(id) values('{owner}'); insert into profiles(user_id,timezone) values('{owner}','UTC'); insert into consents(user_id,consent_version,choice,text_sha256,locale) values('{owner}','test','granted','test','en');")
newer = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
newer.stdin.write('begin;'+auth+upload(90,30)+"\n\\echo LOCKED\nselect pg_sleep(0.5); commit;\n")
newer.stdin.close()
for line in newer.stdout:
    if line.strip() == 'LOCKED':
        break
else:
    raise AssertionError('Newer transaction failed before acquiring the ingestion lock: ' + newer.stderr.read())
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    calls = [pool.submit(query, 'begin;'+auth+upload(70,10)+'commit;') for _ in range(4)]
    for call in calls:
        output = call.result()
        assert '"unchanged": 1' in output, output
assert newer.wait(timeout=10) == 0, newer.stderr.read()
row = query(f"select jsonb_build_object('heart',heart,'step',step,'count',count(*) over()) from raw_samples where user_id='{owner}';")
assert json.loads(row) == {'heart': 90, 'step': 90, 'count': 1}, row
revision = query(f"select input_revision from nb.calculation_work where user_id='{owner}'")
assert revision == '1', revision
print('PASS: concurrent older uploads preserved the later reading; duplicate retries did not advance revision')

#!/usr/bin/env python3
"""Two committed authenticated sessions, against the named disposable DB only."""
import json
import subprocess
import uuid

CONTAINER = 'nextbody-calculation-test'
COMMAND = ['docker', 'exec', '-i', CONTAINER, 'psql', '-X', '-q', '-A', '-t', '-U', 'supabase_admin', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1']
owner, turn, lease_a, lease_b = [str(uuid.uuid4()) for _ in range(4)]
def execute(sql):
    result = subprocess.run(COMMAND, input=sql, text=True, capture_output=True, check=True)
    return result.stdout

setup = f"""
insert into auth.users(id) values('{owner}');
insert into public.profiles(user_id) values('{owner}');
insert into public.consents(user_id,consent_version,choice,text_sha256,locale) values('{owner}','concurrency-test','granted','test','en');
"""
def attempt(lease, hold=False):
    return f"""
begin;
set local role authenticated;
set local request.jwt.claim.sub='{owner}';
select public.claim_ai_turn('{turn}','concurrent same question',null,'{lease}');
{'select pg_sleep(0.6);' if hold else ''}
commit;
"""
first = None
try:
    execute(setup)
    first = subprocess.Popen(COMMAND, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    first.stdin.write(attempt(lease_a, hold=True))
    first.stdin.close()
    # The first claim has returned but its transaction deliberately holds the lock.
    first_result = json.loads(first.stdout.readline())
    second_result = json.loads(execute(attempt(lease_b)).strip())
    first.wait(timeout=10)
    if first.returncode:
        raise RuntimeError(first.stderr.read())
    assert first_result['status'] == 'claimed', first_result
    assert second_result['status'] == 'busy', second_result
    assert 1 <= second_result['retry_after'] <= 90, second_result
    print('PASS: two authenticated overlapping transactions produce one claimed and one busy')
finally:
    if first is not None and first.poll() is None:
        first.kill()
        first.wait()
    execute(f"delete from auth.users where id='{owner}';")

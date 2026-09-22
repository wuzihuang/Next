#!/usr/bin/env python3
"""Verify committed photo/consent/deletion races in a named disposable Docker DB."""
import os
import subprocess
import time
import uuid

container = os.environ.get("NEXTBODY_TEST_CONTAINER", "")
if not (container.startswith("nb-schema-") or
        (container.startswith("nextbody-") and "test" in container)):
    raise SystemExit("Set NEXTBODY_TEST_CONTAINER to a disposable nb-schema-* or nextbody-*test* DB")
command = ["docker", "exec", "-i", container, "psql", "-X", "-q", "-A", "-t",
           "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1"]


def sql(statement):
    return subprocess.run(command, input=statement, text=True, capture_output=True, check=True).stdout.strip()


def race(first_statement, second_statement, owner, expected_error=None):
    first = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE, text=True)
    second = None
    marker = "meal-race-" + uuid.uuid4().hex
    try:
        first.stdin.write("begin;\n" + first_statement + "\nselect 'locked';\n")
        first.stdin.flush()
        assert first.stdout.readline().strip() == "locked"
        second = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  stderr=subprocess.PIPE, text=True)
        second.stdin.write(f"set application_name='{marker}'; set statement_timeout='10s';\n" + second_statement)
        second.stdin.close()
        for _ in range(100):
            waiting = sql(f"select exists(select 1 from pg_stat_activity where application_name='{marker}' and wait_event_type='Lock');")
            if waiting == "t":
                break
            if second.poll() is not None:
                raise AssertionError("competing statement did not wait on the owner's lifecycle lock: " + second.stderr.read())
            time.sleep(0.02)
        else:
            raise AssertionError("competing statement never reached the lifecycle lock")
        first.stdin.write("commit;\n")
        first.stdin.close()
        first.wait(timeout=10)
        assert first.returncode == 0, first.stderr.read()
        second.wait(timeout=10)
        error = second.stderr.read()
        if expected_error:
            assert second.returncode != 0 and expected_error in error, error
            assert sql(f"select count(*) from storage.objects where bucket_id='meal-photos' and name='{owner}/race.jpg';") == "0"
        else:
            assert second.returncode == 0, error
    finally:
        for process in [first, second]:
            if process is not None and process.poll() is None:
                process.kill()
                process.wait()


for scenario in ["tombstone", "withdrawal", "upload-first"]:
    owner = str(uuid.uuid4())
    sql(f"insert into auth.users(id) values('{owner}'); "
        f"insert into public.profiles(user_id) values('{owner}') on conflict do nothing; "
        "insert into public.consents(user_id,consent_version,choice,text_sha256,locale) "
        f"values('{owner}','race','granted','test','en');")
    upload = f"insert into storage.objects(bucket_id,name) values('meal-photos','{owner}/race.jpg');"
    withdrawal = ("insert into public.consents(user_id,consent_version,choice,text_sha256,locale,decided_at) "
                  f"values('{owner}','race','withdrawn','test','en',clock_timestamp());")
    try:
        if scenario == "tombstone":
            race(f"update public.profiles set deletion_requested_at=now() where user_id='{owner}';",
                 upload, owner, "ACCOUNT_UNAVAILABLE")
        elif scenario == "withdrawal":
            race(withdrawal, upload, owner, "CONSENT_WITHDRAWN")
        else:
            race(upload, withdrawal, owner)
            denied = subprocess.run(command, input=upload.replace("race.jpg", "late.jpg"), text=True, capture_output=True)
            assert denied.returncode != 0 and "CONSENT_WITHDRAWN" in denied.stderr
        print("PASS:", scenario, "serialized across committed sessions")
    finally:
        sql(f"delete from storage.objects where bucket_id='meal-photos' and name like '{owner}/%'; "
            f"delete from auth.users where id='{owner}';")

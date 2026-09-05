"""Run only against an explicitly named disposable NextBody Docker test DB."""
import concurrent.futures
import os
import subprocess
import uuid

container = os.environ.get("NEXTBODY_TEST_CONTAINER", "")
if not container.startswith("nextbody-") or "test" not in container:
    raise SystemExit("Set NEXTBODY_TEST_CONTAINER to a disposable nextbody-*test* container")
owner = str(uuid.uuid4())

def sql(statement):
    return subprocess.check_output([
        "docker", "exec", "-i", container, "psql", "-U", "supabase_admin",
        "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-Atq",
    ], input=statement.encode()).decode().strip()

sql(f"insert into auth.users(id) values('{owner}');")
try:
    def request(_):
        return sql(f"begin; set local role authenticated; "
                   f"set local request.jwt.claim.sub='{owner}'; "
                   "select public.consume_request_budget('archive-data')->>'allowed'; commit;")
    with concurrent.futures.ThreadPoolExecutor(max_workers=16) as pool:
        outcomes = list(pool.map(request, range(16)))
    assert outcomes.count("true") == 6, outcomes
    assert outcomes.count("false") == 10, outcomes
    assert sql(f"select used from nb.request_budgets where user_id='{owner}';") == "6"
    print("PASS: 16 concurrent authenticated requests admitted exactly 6; counter stayed at 6")
finally:
    sql(f"delete from auth.users where id='{owner}';")

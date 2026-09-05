"""Opt-in isolated Supabase HTTP test. No production URLs or credential output.
Run: python3 supabase/tests/http_storage_integration.py /path/to/isolated/workdir
The isolated stack must use API port 57421 and have functions serve running.
"""
import datetime
import gzip
import hashlib
import json
import secrets
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid

workdir = sys.argv[1]
status = subprocess.run(["supabase", "status", "--workdir", workdir, "-o", "json"], capture_output=True, text=True, check=True)
config = json.loads(status.stdout)
base = config["API_URL"]
assert base in ("http://127.0.0.1:57421", "http://localhost:57421"), "Only the isolated test API is allowed"
admin = config["SERVICE_ROLE_KEY"]
users = []
objects = []
checks = 0

def http(path, token, method="GET", body=None, expected=200, raw=False):
    global checks
    payload = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(base + path, data=payload, method=method, headers={
        "apikey": config["ANON_KEY"], "Authorization": "Bearer " + token,
        "Content-Type": "application/json", "Prefer": "return=representation",
    })
    try:
        response = urllib.request.urlopen(req, timeout=90)
        code, data = response.status, response.read()
    except urllib.error.HTTPError as error:
        code, data = error.code, error.read()
    assert code == expected, f"{method} {path.split('?')[0]} expected {expected}, got {code}: {data[:400]!r}"
    checks += 1
    return data if raw else (json.loads(data) if data else None)

def account():
    email = f"integration-{uuid.uuid4().hex}@example.test"
    password = secrets.token_urlsafe(32)
    user = http("/auth/v1/admin/users", admin, "POST", {"email": email, "password": password, "email_confirm": True})
    users.append(user["id"])
    session = http("/auth/v1/token?grant_type=password", config["ANON_KEY"], "POST", {"email": email, "password": password})
    http("/rest/v1/profiles", admin, "POST", {"user_id": user["id"], "timezone": "UTC"}, 201)
    http("/rest/v1/consents", admin, "POST", {"user_id": user["id"], "consent_version": "test", "choice": "granted", "text_sha256": "test", "locale": "en"}, 201)
    return user["id"], session["access_token"]

try:
    alice, token_a = account()
    bob, token_b = account()
    op, meal = str(uuid.uuid4()), str(uuid.uuid4())
    day = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=4)).date().isoformat()
    payload = {"draft_id": op, "id": meal, "user_day": day, "slot": "LUNCH", "name": "Test rice", "kcal": 500,
               "protein_g": 20, "carb_g": 80, "fat_g": 10, "model_version": "integration-v1"}
    first = http("/functions/v1/meal-commit", token_a, "POST", payload)
    assert first["id"] == meal and first["client_op_id"] == op
    retry = http("/functions/v1/meal-commit", token_a, "POST", payload)
    assert retry["replay"] is True
    http("/functions/v1/meal-commit", token_a, "POST", dict(payload, kcal=600), 409)
    assert http("/rest/v1/meals?select=id,kcal", token_b) == []
    assert http("/rest/v1/meal_operations?select=operation_id", token_b) == []
    replacement = str(uuid.uuid4())
    fields = {k: v for k, v in payload.items() if k not in ("draft_id", "id")}
    edit = {"operation_id": str(uuid.uuid4()), "kind": "amend", "meal_id": meal,
            "replacement": dict(fields, id=replacement, kcal=600)}
    http("/functions/v1/meal-operation", token_a, "POST", edit)
    visible = http("/rest/v1/meals?select=id,kcal&deleted_at=is.null", token_a)
    assert visible == [{"id": replacement, "kcal": 600}]
    delete = {"operation_id": str(uuid.uuid4()), "kind": "delete", "meal_id": replacement}
    http("/functions/v1/meal-operation", token_b, "POST", delete, 404)
    http("/functions/v1/meal-operation", token_a, "POST", delete)
    assert http("/rest/v1/meals?select=id&deleted_at=is.null", token_a) == []
    # Exercise the persisted request/answer seam without contacting a model provider.
    conversation, turn, lease = str(uuid.uuid4()), str(uuid.uuid4()), str(uuid.uuid4())
    claim = {"p_turn": turn, "p_text": "最近睡眠如何？", "p_conversation": conversation, "p_lease": lease}
    assert http("/rest/v1/rpc/claim_ai_turn", token_a, "POST", claim)["status"] == "claimed"
    assert http("/rest/v1/rpc/claim_ai_turn", token_a, "POST", dict(claim, p_lease=str(uuid.uuid4())))["status"] == "busy"
    query = {"dayKey": day, "from": day, "to": day, "queryText": "睡眠" * 2500, "explicitRange": True}
    saved = {**claim, "p_envelope": {"type": "text", "sentence": "没有足够数据作出结论。", "ttl_min": 20},
             "p_trace": [], "p_latency": 10, "p_model": "deterministic-http-fixture", "p_query_context": query}
    receipt = http("/rest/v1/rpc/record_claimed_ai_turn", token_a, "POST", saved)
    assert receipt["replay"] is False
    assert http("/rest/v1/rpc/record_claimed_ai_turn", token_a, "POST", saved)["frame_id"] == receipt["frame_id"]
    assert http("/rest/v1/rpc/claim_ai_turn", token_a, "POST", claim)["status"] == "replay"
    context = http("/rest/v1/rpc/conversation_context", token_a, "POST", {"p_conversation": conversation})
    assert [row["role"] for row in context] == ["user", "assistant"]
    summary = http("/rest/v1/rpc/conversation_summary", token_a, "POST", {"p_conversation": conversation})
    assert summary["lastQueryContext"] == query
    assert http("/rest/v1/rpc/conversation_context", token_b, "POST", {"p_conversation": conversation}) == []
    assert http("/rest/v1/conversation_messages?select=id", token_b) == []
    http("/rest/v1/rpc/claim_ai_turn", token_b, "POST", dict(claim, p_turn=str(uuid.uuid4())), 403)
    assert http("/rest/v1/rpc/release_ai_turn", token_a, "POST", {"p_turn": turn, "p_lease": lease}) is True
    print("PASS authenticated conversation HTTP: claim/busy, fenced persistence, replay, Unicode query context, two-account isolation")

    for owner, token, weight in [(alice, token_a, 70), (bob, token_b, 90)]:
        http("/rest/v1/weigh_ins", token, "POST", {"user_id": owner, "measured_at": day + "T12:00:00Z",
             "weight_kg": weight, "source": "manual", "client_op_id": str(uuid.uuid4())}, 201)
    metric_request = {"metrics": ["weight", "bloodPressure"], "from": day, "to": day, "timezone": "UTC"}
    for token, expected_weight in [(token_a, 70), (token_b, 90)]:
        reading = http("/functions/v1/metric-read", token, "POST", metric_request)
        assert reading["ok"] is True
        weight_reading, unsupported = reading["data"]
        assert weight_reading["stats"]["latest"] == expected_weight
        assert weight_reading["evidence"]["unit"] == "kg"
        assert unsupported["evidence"]["status"] == "unsupported"
    print("PASS authenticated metric-read HTTP: actual measured weight, exact units, unsupported domain, account isolation")

    withdrawn_at = (datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(seconds=1)).isoformat()
    http("/rest/v1/consents", admin, "POST", {"user_id": alice, "consent_version": "test", "choice": "withdrawn",
         "text_sha256": "test", "locale": "en", "decided_at": withdrawn_at}, 201)
    http("/functions/v1/meal", token_a, "POST", {"text": "rice", "slot": "LUNCH"}, 403)
    http("/functions/v1/meal-commit", token_a, "POST", dict(payload, id=str(uuid.uuid4()), draft_id=str(uuid.uuid4())), 403)
    http("/functions/v1/meal-operation", token_a, "POST", dict(delete, operation_id=str(uuid.uuid4())))
    print("PASS latest-consent HTTP gate: estimation and creation blocked; explicit deletion still allowed")
    print("PASS authenticated HTTP meals: create, lost-response retry, conflict, amend, delete, two-account RLS")

    http("/rest/v1/raw_samples", admin, "POST", {"user_id": alice, "ts": "2020-01-01T12:00:00Z", "src": "band", "sampled_tz": "UTC", "heart": 65}, 201)
    result = http("/functions/v1/archive-data", token_a, "POST", {"domain": "raw_samples"})
    assert result["state"] == "verified" and result["archived"] == 1 and result["pruned"] == 1
    manifests = http("/rest/v1/sample_archives?select=*", token_a)
    assert len(manifests) == 1
    manifest = manifests[0]
    path = manifest["object_path"]
    objects.append(path)
    assert http("/rest/v1/sample_archives?select=id", token_b) == []
    blob = http("/storage/v1/object/authenticated/sample-history/" + path, token_a, raw=True)
    assert hashlib.sha256(blob).hexdigest() == manifest["checksum"]
    restored = json.loads(gzip.decompress(blob))
    assert restored["rows"][0]["heart"] == 65 and restored["rows"][0]["user_id"] == alice
    http("/storage/v1/object/authenticated/sample-history/" + path, token_b, expected=400)
    assert http("/rest/v1/raw_samples?select=ts", token_a) == []
    print("PASS authenticated Storage archive: upload, verified readback, checksum/gzip roundtrip, hot pruning, owner isolation")
finally:
    if objects:
        http("/storage/v1/object/sample-history", admin, "DELETE", {"prefixes": objects})
    for user in users:
        http("/auth/v1/admin/users/" + user, admin, "DELETE")

print(f"PASS final isolated integration: {checks} expected HTTP outcomes across meals, consent, conversations, metrics and Storage")

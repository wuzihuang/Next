#!/usr/bin/env bash
# Set the hosted project's auth config through the Management API — only the fields named
# here, nothing else is touched (unlike `supabase config push`, which replaces the lot).
#
#   set -a; source supabase/.env; set +a
#   bash supabase/scripts/auth-config.sh
#
# Needs: SUPABASE_ACCESS_TOKEN (personal access token), SUPABASE_AUTH_SMTP_PASS (Resend API key).
# The six mail templates come from supabase/templates/*.html (regenerate with build.py).
set -euo pipefail

REF="${SUPABASE_PROJECT_REF:-gkgzwcxivnffsecshvfs}"
: "${SUPABASE_ACCESS_TOKEN:?set SUPABASE_ACCESS_TOKEN}"
: "${SUPABASE_AUTH_SMTP_PASS:?set SUPABASE_AUTH_SMTP_PASS (the Resend API key)}"

HERE="$(cd "$(dirname "$0")" && pwd)"

BODY=$(python3 - "$HERE/../templates" <<'PY'
import json, sys
from pathlib import Path
t = Path(sys.argv[1])
subjects = {
    "magic_link": "Your NEXTBODY code",
    "confirmation": "Your NEXTBODY code",
    "email_change": "Confirm your new email",
    "recovery": "Your NEXTBODY code",
    "reauthentication": "Confirm it's you",
    "invite": "You're invited to NEXTBODY",
}
body = {
    "smtp_host": "smtp.resend.com",
    "smtp_port": "465",
    "smtp_user": "resend",
    "smtp_pass": __import__("os").environ["SUPABASE_AUTH_SMTP_PASS"],
    "smtp_admin_email": "no-reply@nextbody.ai",
    "smtp_sender_name": "NEXTBODY",
    "smtp_max_frequency": 1,
    "rate_limit_email_sent": 200,
    "mailer_otp_exp": 600,
    "mailer_otp_length": 6,
    # A first-time address would otherwise get a confirmation *link*; the code is the check.
    "mailer_autoconfirm": True,
    "external_apple_enabled": True,
    "external_apple_client_id": "com.nextbody.hoop",
}
for name, subject in subjects.items():
    body[f"mailer_subjects_{name}"] = subject
    body[f"mailer_templates_{name}_content"] = (t / f"{name}.html").read_text()
print(json.dumps(body))
PY
)

curl -sS -X PATCH "https://api.supabase.com/v1/projects/${REF}/config/auth" \
  -H "Authorization: Bearer ${SUPABASE_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  --data "${BODY}" \
| python3 -c '
import json, sys
d = json.load(sys.stdin)
if "smtp_host" not in d: print(d); sys.exit(1)
for k in ["smtp_host","smtp_admin_email","mailer_otp_exp","mailer_autoconfirm","external_apple_enabled"]:
    print(f"{k:24s} {d.get(k)}")
for n in ["magic_link","confirmation","email_change","recovery","reauthentication","invite"]:
    c = d.get("mailer_templates_%s_content" % n) or ""
    subj = d.get("mailer_subjects_%s" % n)
    print("%-24s %-32r NEXTBODY frame: %s" % (n, subj, "NEXTBODY" in c))
'

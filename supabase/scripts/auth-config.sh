#!/usr/bin/env bash
# Set the hosted project's auth config through the Management API — only the fields named
# here, nothing else is touched (unlike `supabase config push`, which replaces the lot).
#
#   set -a; source supabase/.env; set +a
#   bash supabase/scripts/auth-config.sh
#
# Needs: SUPABASE_ACCESS_TOKEN (personal access token), SUPABASE_AUTH_SMTP_PASS (Resend API key).
set -euo pipefail

REF="${SUPABASE_PROJECT_REF:-gkgzwcxivnffsecshvfs}"
: "${SUPABASE_ACCESS_TOKEN:?set SUPABASE_ACCESS_TOKEN}"
: "${SUPABASE_AUTH_SMTP_PASS:?set SUPABASE_AUTH_SMTP_PASS (the Resend API key)}"

HERE="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE="$(python3 -c 'import json,sys; print(json.dumps(open(sys.argv[1]).read()))' "$HERE/../templates/magic_link.html")"

BODY=$(cat <<JSON
{
  "smtp_host": "smtp.resend.com",
  "smtp_port": "465",
  "smtp_user": "resend",
  "smtp_pass": "${SUPABASE_AUTH_SMTP_PASS}",
  "smtp_admin_email": "no-reply@nextbody.ai",
  "smtp_sender_name": "NEXTBODY",
  "smtp_max_frequency": 1,
  "rate_limit_email_sent": 200,
  "mailer_otp_exp": 600,
  "mailer_otp_length": 6,
  "mailer_subjects_magic_link": "Your NEXTBODY code",
  "mailer_templates_magic_link_content": ${TEMPLATE},
  "mailer_subjects_confirmation": "Your NEXTBODY code",
  "mailer_templates_confirmation_content": ${TEMPLATE},
  "external_apple_enabled": true,
  "external_apple_client_id": "com.nextbody.hoop"
}
JSON
)

curl -sS -X PATCH "https://api.supabase.com/v1/projects/${REF}/config/auth" \
  -H "Authorization: Bearer ${SUPABASE_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  --data "${BODY}" \
| python3 -c 'import json,sys; d=json.load(sys.stdin); print({k:d.get(k) for k in ["smtp_host","smtp_user","smtp_admin_email","mailer_otp_exp","rate_limit_email_sent","external_apple_enabled","external_apple_client_id"]})'

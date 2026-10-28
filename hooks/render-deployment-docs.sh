#!/usr/bin/env bash
# Render the product's LIVE-DEPLOYMENT documentation from verified state.
# Called by phase 02-docs as a `run:` hook (and safe to run by hand, from the
# product's checkout). Idempotent: the generated file and the README section
# are fully re-rendered on every run, so re-running after a redeploy, a custom
# domain or connecting Stripe or email refreshes them.
#
#   hooks/render-deployment-docs.sh <out> <workspace> <baseline-dir>
#
# What it writes (in <out>):
#   ai/context/deployment.md   — REGENERATED: URLs with live probe results
#                                (the app, its health check, whether Stripe and
#                                email are connected yet), identity, and the secrets
#                                the deployment uses BY NAME
#   ai/context/operations.md   — healed from the baseline's copy if absent
#                                (the static operating contract; never rewritten)
#   README.md                  — the section between <!-- 02-docs:begin/end -->
#                                is replaced (appended after the title if the
#                                README predates the markers)
#
# No secret VALUE is ever read or written here — secrets are named, not read.
#
# IT ASKS THE PLATFORM NOTHING. The record used to carry the workspace's slug,
# its secrets listed per rung and its integrations — five CLI calls, one after
# another, from the build box — and all of it is what the console shows live
# and this file could only show as it was the day it was written. The record
# keeps what the repository is the right place for: the identity the code
# names, what answered at the URLs, and where to look for the rest.
set -euo pipefail

out="${1:?usage: render-deployment-docs.sh <out> <workspace> <baseline-dir>}"
ws="${2:-}"
L="${3:?usage: render-deployment-docs.sh <out> <workspace> <baseline-dir>}"

cd "$out"
vals=".rebrand/values.json"
[ -f "$vals" ] || { echo "render-docs: $vals missing — is this a bootstrapped product?" >&2; exit 1; }
val() { python3 -c "import json,sys;print(json.load(open('$vals')).get(sys.argv[1],'') or '')" "$1"; }

repo="$(val reponame)"
brand="$(val brandSlug)"; [ -n "$brand" ] || brand="$repo"
sub="$(val subdomain)"; [ -n "$sub" ] || sub="your-workers-subdomain"
[ -n "$ws" ] || ws="$(sed -n 's/^[[:space:]]*workspace:[[:space:]]*\([^[:space:]#]*\).*/\1/p' intent.yaml | head -1)"
[ -n "$ws" ] || ws="?"

# CI lane pin (what version the deploy lanes run).
lanepin="$(sed -n 's/^ *version: *\(v[0-9.]*\) *$/\1/p' .github/workflows/ci.yml 2>/dev/null | head -1)"
[ -n "$lanepin" ] || lanepin="?"

# curl emits the -w format even on connection failure (000) — capture, don't
# append, or a failed probe reads "000000".
probe() { local c; c="$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "$1" 2>/dev/null)" || true; printf '%s' "${c:-000}"; }
badge() { case "$1" in 2*|3*) echo "LIVE ($1)" ;; 000) echo "unreachable" ;; *) echo "answering $1" ;; esac; }

stage_url="https://${brand}-web-stage.${sub}.workers.dev"
prod_url="https://${brand}-web-prod.${sub}.workers.dev"

# Whether Stripe and email are connected yet: /api/health reports both
# (`"stripe":true|false`, `"email":true|false`) — true once the environment's
# Worker has the key (the README's "Stripe", "Email"). Read only from an
# answer that came back 200: anything else says nothing about either.
connected_state() { # URL FIELD WHAT
  local body code
  body="$(mktemp)"
  code="$(curl -s -o "$body" -w '%{http_code}' --max-time 20 "$1/api/health" 2>/dev/null)" || true
  code="${code:-000}"
  if [ "$code" != 200 ]; then echo "unknown (/api/health $(badge "$code"))"
  elif grep -q "\"$2\":true" "$body"; then echo "connected"
  else echo "not connected — $3"; fi
  rm -f "$body"
}

rows=""
for pair in "stage|$stage_url" "prod|$prod_url"; do
  env="${pair%%|*}"; url="${pair#*|}"
  rows+="| app (${env}) | ${url} | $(badge "$(probe "$url/")") |"$'\n'
  rows+="| health check (${env}) | ${url}/api/health | $(badge "$(probe "$url/api/health")") |"$'\n'
done
stripe_stage="$(connected_state "$stage_url" stripe "the billing page says to connect it; see README, Stripe")"
stripe_prod="$(connected_state "$prod_url" stripe "the billing page says to connect it; see README, Stripe")"
email_stage="$(connected_state "$stage_url" email "no email is sent; see README, Email")"
email_prod="$(connected_state "$prod_url" email "no email is sent; see README, Email")"

now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Heal the static operating contract when the product predates it.
mkdir -p ai/context
if [ ! -f ai/context/operations.md ] && [ -f "$L/ai/context/operations.md" ]; then
  cp "$L/ai/context/operations.md" ai/context/operations.md
  git add ai/context/operations.md 2>/dev/null || true
  node "$L/tooling/rebrand/rebrand.mjs" --values "$vals" --allow-dirty >/dev/null 2>&1 || true
  echo "render-docs: healed ai/context/operations.md"
fi

cat > ai/context/deployment.md <<EOF
# ${repo} — live deployment manifest

> GENERATED by the \`02-docs\` phase on ${now}; re-run it to refresh
> (idempotent; see [operations.md](operations.md)). Hand-edits here are
> overwritten. No secret values appear in this file — secrets are named only.

## Identity

| | |
|---|---|
| repository / project slug | \`${repo}\` |
| Orun workspace | \`${ws}\` |
| declared in | \`intent.yaml\` → \`execution.state.workspace\` |
| Workers | \`${brand}-web-stage\`, \`${brand}-web-prod\` on \`${sub}.workers.dev\` |
| CI lane CLI pin | orun \`${lanepin}\` (\`.github/workflows/ci.yml\`) |

## Public URLs (probed ${now})

| surface | URL | status |
|---|---|---|
${rows}
\`/api/health\` answers 200 only when the Worker reaches its Supabase project
with the service-role key and finds the migrated schema. The \`dev\`
environment is verify-only by design — no deployed URL.

## Stripe and email

| environment | billing (Stripe) | email (Resend) |
|---|---|---|
| stage | ${stripe_stage} | ${email_stage} |
| prod | ${stripe_prod} | ${email_prod} |

Neither is a provider the platform brokers: their keys are orun secrets the
owner adds per environment, which the deploy hands the Worker as secrets
(README, "Stripe", "Email"). Everything else — the marketing site, sign-up,
sign-in, the account dashboard — works without them.

## Secrets (names only)

| secret | where | what it is |
|---|---|---|
| \`CLOUDFLARE_API_TOKEN\` | the workspace | BROKERED from its Cloudflare connection (\`workers-deploy\`): deploys the app's Worker and sets its secrets |
| \`CLOUDFLARE_ACCOUNT_ID\` | the workspace | the Cloudflare connection's account id — a fact, not a credential |
| \`SUPABASE_ACCESS_TOKEN\` | the workspace | BROKERED from its Supabase connection (\`management-access\`): creates the project and runs the migrations |
| \`SUPABASE_ORG_ID\` | the workspace | the Supabase connection's organization id — a fact, not a credential |
| \`SUPABASE_PROJECT_REF\`, \`SUPABASE_DB_PASSWORD\`, \`SUPABASE_DB_URL\` | \`${repo}\` on stage and on prod | written by the Supabase root's apply: the project's ref, its database password and its connection URL, read by the migrations |
| \`WIRING_SUPABASE\` | \`${repo}\` on stage and on prod | written by the Supabase root's apply: the project's URL and anon key, rendered into the Worker's config |
| \`SUPABASE_SERVICE_ROLE_KEY\` | \`${repo}\` on stage and on prod | written by the Supabase root's apply: the project's service-role key, a Worker secret |
| \`STRIPE_API_KEY\`, \`RESEND_API_KEY\`, \`ADMIN_EMAIL\`, \`FROM_ADMIN_EMAIL\` | \`${repo}\`, per environment, once you add them | optional: Stripe's secret key and Resend's settings, Worker secrets |

Brokered secrets are minted per run, so no long-lived value is at rest.
The project's and the owner's keys reach the Worker as Worker secrets. What the
workspace holds right now (every secret by name, and its integrations and
their health) is on the console's Secrets and Integrations pages for
\`${ws}\`.

## How this deployment changes

Merges to \`main\` converge automatically: CI plans the changed components and
runs each lane with \`orun run --remote-state\` against the workspace above.
See [operations.md](operations.md) for the full operating contract.
EOF
echo "render-docs: wrote ai/context/deployment.md"

python3 - <<'PY'
import re
begin, end = "<!-- 02-docs:begin -->", "<!-- 02-docs:end -->"
body = f"""{begin}
This product is **live**. Verified URLs, identity, whether Stripe and email are
connected and the secrets it uses are recorded in
[ai/context/deployment.md](ai/context/deployment.md) (re-rendered by the
`02-docs` phase); how it deploys and how to operate it:
[ai/context/operations.md](ai/context/operations.md).
{end}"""
s = open("README.md").read()
if begin in s and end in s:
    s = re.sub(re.escape(begin) + r".*?" + re.escape(end), lambda _m: body, s, count=1, flags=re.S)
else:
    lines = s.splitlines(keepends=True)
    at = 1
    while at < len(lines) and lines[at].strip() == "":
        at += 1
    lines.insert(at, f"\n## Live deployment\n\n{body}\n")
    s = "".join(lines)
open("README.md", "w").write(s)
print("render-docs: README live-deployment section rendered")
PY
echo "render-docs: done"

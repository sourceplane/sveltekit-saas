#!/usr/bin/env bash
# TIER 2 — the product a bootstrap produces builds, migrates, deploys (dry),
# serves, and takes a user from sign-up to a deleted account through Supabase
# Auth and the Data API, with no Stripe key and no email key.
#
# placement.test.sh proves the tree a bootstrap ends with is the right tree,
# and that its own plan converges in the right order. This proves it WORKS,
# by doing to it what its own pipelines will:
#
#   1. at the 01-product landing (the commit its PR merges), install with the
#      lockfile the product ships, render the wrangler fixture (which must
#      change nothing: the render is committed), typecheck, lint, test, build.
#      The landing itself is checked in the build box with `orun validate`
#      and `orun plan` alone (`checks: local`), and its PR runs `plan` alone
#      (an `orun/BASE-*` branch), so THIS is where a product those steps
#      refuse is caught: before the tag, not after a build has merged it.
#      Then the Supabase root: formatted and valid, when terraform is on PATH;
#   2. a Supabase project of its own, stood in for: a Postgres on a random
#      port with Supabase's roles (testing/lib/local-postgres.sh) and what a
#      project has and answers (testing/lib/fake-supabase-api.py) — the
#      `auth` and `storage` schemas Supabase creates before any migration,
#      Auth (GoTrue, its admin API included), the Data API (PostgREST, the
#      calls the app's supabase-js makes) and the Management API's query
#      endpoint the migration runner calls, connected as `postgres`;
#   3. the db-migrate lane's own steps, rendered by `orun plan` for a push to
#      main and run IN THE TREE THE RUNNER STAGES for the job: install, build
#      @saas/db, apply — the template's own migrations, verbatim: a trigger
#      on auth.users, row-level security on every table, the avatars bucket
#      and its policies — then apply again, which must apply nothing, and the
#      pull-request profile's offline plan;
#   4. the web lane's own steps for stage, rendered for a pull request (the
#      verify profile carries deploy-dry-run; the deploy profile does not) and
#      run in its staged job tree: install, `verify-app-structure` (the
#      committed wrangler.jsonc must exist BEFORE the build, in a tree with no
#      build output), `build-app` — which re-renders the config from the
#      stage wiring document it is handed, inlines that project into the
#      bundles, and pushes the service-role key to the Worker only from a job
#      that can deploy — then `verify-build-output` and `deploy-dry-run`;
#   5. the built Worker under `wrangler dev`: first with NO .dev.vars — the
#      public pages serve, `/api/health` says the service-role key is missing
#      and the component's OWN `smokeCommand` refuses the deploy — then with
#      the key as the Worker's secret (`.dev.vars`, written by the same
#      tooling/wire/worker-secrets.mjs the build pushes it with), the smoke
#      passes, and every route the product promises answers: the pages carry
#      the product's name and its origin, the account pages are guarded;
#   6. the user flow: a visitor signs up (the call the sign-up page makes),
#      the migration's trigger has written their profile, the Worker sends
#      them to create it, the profile form's action writes it under
#      row-level security, the dashboard, billing (Stripe not connected —
#      not a 500), the Stripe routes degrade, settings, the email opt-out;
#      the contact form writes through the service role; a second user; a
#      wrong password refused, a sign-in, a sign-out; and the account
#      deleted through the admin API, after which the user cannot sign in;
#   7. the Data API's roles against the same database: every table in
#      `public` has row-level security and is owned by `postgres`, which is
#      neither a superuser nor BYPASSRLS; each user reads exactly their own
#      profile, `anon` reads nothing and writes nothing, nobody writes a row
#      as somebody else, and only the service role sees every row.
#
# WHAT IS ONLY OFFLINE HERE. The browser is not driven: the login pages
# render in the browser (`ssr = false`), and what they call — supabase-js,
# from the product's own installed @supabase/ssr, with the same arguments,
# keeping the session in the same cookies — is called from Node
# (testing/lib/browser-auth.mjs); the forms the Worker serves are posted as
# SvelteKit's `enhance` posts them. Supabase is a stand-in, faithful to the
# requests the app makes and no further. The platform's half — create the
# repository, mint the brokered tokens, create a real Supabase project, read
# its keys, set its Auth, deploy for real and probe workers.dev — is a
# bootstrap against a workspace (BOOTSTRAP.md).
#
# Needs: orun, node, pnpm, python3 (+PyYAML), git, curl, psql and a
# PostgreSQL server install (initdb, pg_ctl), and the network for
# `pnpm install` (or a warm store). A few minutes: three installs, two builds.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
# shellcheck source=lib/bootstrap.sh
source "$here/lib/bootstrap.sh"
# shellcheck source=lib/local-postgres.sh
source "$here/lib/local-postgres.sh"

for bin in orun node pnpm python3 git curl psql; do
  command -v "$bin" >/dev/null || { echo "e2e.test.sh needs $bin on PATH" >&2; exit 1; }
done
pg_bin >/dev/null || { echo "e2e.test.sh needs a PostgreSQL server install (initdb, pg_ctl)" >&2; exit 1; }

scratch="$(mktemp -d)"
pgdir="$(mktemp -d)"
dev_pid=""
api_pid=""
# wrangler dev runs under pnpm, node and two workerd processes; a TERM to the
# first does not reach the rest, and waiting on it then never returns. So each
# server is started as its own process group (setsid) and the group stopped.
stop_group() {
  local pid="$1"
  [ -n "$pid" ] || return 0
  kill -TERM -- "-$pid" 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 -- "-$pid" 2>/dev/null || break; sleep 0.5; done
  kill -KILL -- "-$pid" 2>/dev/null || true
}
cleanup() {
  stop_group "$dev_pid"
  stop_group "$api_pid"
  pg_down "$pgdir"
  [ -n "$pgdir" ] && [ -d "$pgdir" ] && rm -rf "$pgdir"
  [ -n "$scratch" ] && [ -d "$scratch" ] && rm -rf "$scratch"
}
trap cleanup EXIT
free_port() { python3 -c "import socket;s=socket.socket();s.bind(('127.0.0.1',0));print(s.getsockname()[1]);s.close()"; }
values="$here/fixtures/acme.json"
repo="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['reponame'])" "$values")"
export CI=1 WRANGLER_SEND_METRICS=false TURBO_TELEMETRY_DISABLED=1

# The landing's own checks, step for step — what the product's Checks
# workflow ran on a pull request before the product carried ci.yml alone —
# run here at once on the whole tree.
LANDING_CHECKS=(
  "pnpm install --frozen-lockfile"
  "pnpm run wire:fixture"
  "pnpm typecheck"
  "pnpm lint"
  "pnpm test"
  "pnpm build"
)
checks() { # DIR LOG
  local dir="$1" log="$2" cmd
  for cmd in "${LANDING_CHECKS[@]}"; do
    echo "   \$ $cmd" | tee -a "$log"
    if ! (cd "$dir" && bash -c "$cmd") >> "$log" 2>&1; then
      echo "FAIL: \`$cmd\` failed in $dir" >&2; tail -40 "$log" >&2; return 1
    fi
  done
}

# One job of a plan, written out as the runner would run it: each `run:` step
# (the `use:` actions are setup-node and setup-pnpm, which this machine has)
# as a numbered script, the job's env, and the component path the steps run
# in. Steps are picked BY ID when given, else every `run:` step in order.
extract_job() { # PLAN JOB-ID OUT-DIR [STEP-ID…]
  python3 - "$@" <<'PY'
import json, pathlib, sys
plan, jid, out, *want = sys.argv[1:]
job = next((j for j in json.load(open(plan))["jobs"] if j["id"] == jid), None)
if job is None:
    sys.exit(f"the plan has no job {jid}")
out = pathlib.Path(out); out.mkdir(parents=True)
steps = [s for s in job["steps"] if s.get("run")]
if want:
    by = {s["id"]: s for s in steps}
    missing = [w for w in want if w not in by]
    if missing:
        sys.exit(f"{jid} has no step(s) {missing}")
    steps = [by[w] for w in want]
for i, s in enumerate(steps):
    (out / f"{i:02d}.sh").write_text(s["run"])
    (out / f"{i:02d}.id").write_text(s["id"])
(out / "path").write_text(job.get("path") or ".")
with (out / "env").open("w") as f:
    for k, v in (job.get("env") or {}).items():
        f.write(f"export {k}={json.dumps(v)}\n")
PY
}
run_job() { # STEPS-DIR WORK-TREE ENV LOG-PREFIX
  local steps="$1" work="$2" envname="$3" logp="$4" s id
  for s in "$steps"/[0-9][0-9].sh; do
    id="$(cat "${s%.sh}.id")"
    echo "   ▸ $id"
    if ! (cd "$work/$(cat "$steps/path")" && source "$steps/env" && export ORUN_ENVIRONMENT="$envname" \
          && bash -e "$s") > "$logp-$id.log" 2>&1; then
      echo "FAIL: the lane's $id step" >&2; tail -40 "$logp-$id.log" >&2; return 1
    fi
  done
}
# `wrangler dev` over the staged, built Worker; sets dev_pid and url.
serve() { # APP-DIR LOG
  local app="$1" log="$2" port
  port="$(free_port)"
  (cd "$app" && exec setsid pnpm exec wrangler dev --config wrangler.jsonc --ip 127.0.0.1 --port "$port" \
     --name "$repo-web-stage" --show-interactive-dev-session=false) > "$log" 2>&1 < /dev/null &
  dev_pid=$!
  url="http://127.0.0.1:$port"
  for _ in $(seq 1 90); do
    curl -s -o /dev/null "$url/" && return 0
    kill -0 "$dev_pid" 2>/dev/null || { echo "FAIL: wrangler dev exited" >&2; tail -30 "$log" >&2; return 1; }
    sleep 1
  done
  curl -s -o /dev/null "$url/" || { echo "FAIL: wrangler dev never answered" >&2; tail -30 "$log" >&2; return 1; }
}

echo "── the offline bootstrap (testing/lib/bootstrap.sh)"
tree="$scratch/$repo"
bootstrap_offline "$root" "$tree" "$values" "$scratch/logs" > "$scratch/bootstrap.log" 2>&1 || {
  echo "FAIL: the offline bootstrap stopped" >&2; tail -40 "$scratch/bootstrap.log" >&2; exit 1; }
echo "   2 phases placed and landed"

# ── 1. the product's own pull request ──────────────────────────────────────
echo "── 01-product's landing: install, the fixture render, typecheck, lint, test, build"
s01="$(git -C "$tree" rev-parse HEAD~1)"
at01="$scratch/at-01/$repo"
git -C "$tree" worktree add -q "$at01" "$s01"
checks "$at01" "$scratch/checks.log"
dirty="$(git -C "$at01" status --porcelain)"
[ -z "$dirty" ] || { echo "FAIL: the checks changed tracked files — the committed wrangler.jsonc is not the fixture render:" >&2; echo "$dirty" >&2; exit 1; }
echo "   the checks left the tree as committed (wire:fixture rendered the committed wrangler.jsonc)"

# The Supabase root, as far as it goes without a cloud: formatted, and valid
# against the pinned providers its lock file names.
if command -v terraform >/dev/null; then
  echo "── the product's supabase root: terraform fmt, init -backend=false, validate"
  tfdir="$scratch/tf"
  cp -r "$tree/infra/terraform/supabase/terraform" "$tfdir"
  (cd "$tfdir" && terraform fmt -check -diff . && terraform init -backend=false -input=false \
     && terraform validate) > "$scratch/terraform.log" 2>&1 \
    || { echo "FAIL: the product's supabase root" >&2; tail -30 "$scratch/terraform.log" >&2; exit 1; }
  cmp -s "$tfdir/.terraform.lock.hcl" "$tree/infra/terraform/supabase/terraform/.terraform.lock.hcl" \
    || { echo "FAIL: terraform init changed the committed lock file" >&2; exit 1; }
  echo "   formatted and valid; the committed lock file is what init resolves"
else
  echo "── the product's supabase root: SKIPPED (no terraform on PATH)"
fi

# ── 2. a Supabase project, stood in for ────────────────────────────────────
echo "── a local Postgres with Supabase's roles, and the Supabase stand-in"
pgport="$(free_port)"
pgurl="$(pg_up "$pgdir" "$pgport")" || { echo "FAIL: Postgres did not start" >&2; exit 1; }
admin="postgres://supabase_admin@127.0.0.1:$pgport/postgres"
api_port="$(free_port)"
ref="localproject"
setsid python3 "$here/lib/fake-supabase-api.py" "$api_port" "$pgurl" --ref "$ref" --auth "$admin" \
  > "$scratch/api.log" 2>&1 < /dev/null &
api_pid=$!
for _ in $(seq 1 30); do grep -q '^service-role-key ' "$scratch/api.log" 2>/dev/null && curl -s -o /dev/null "http://127.0.0.1:$api_port/" && break; sleep 0.3; done
anon="$(sed -n 's/^anon-key //p' "$scratch/api.log")"
service="$(sed -n 's/^service-role-key //p' "$scratch/api.log")"
[ -n "$anon" ] && [ -n "$service" ] || { echo "FAIL: the Supabase stand-in did not start" >&2; cat "$scratch/api.log" >&2; exit 1; }
supabase_url="http://127.0.0.1:$api_port"
echo "   $pgurl; the project on $supabase_url (auth and storage schemas in place, no migration yet)"

# The two plans the lanes below run from, each in the product's own tree: a
# push to main at the 01-product commit (the db-migrate lane's APPLY profile),
# and a pull request over the finished product against an empty base (the web
# lane's VERIFY profile, which carries deploy-dry-run, and db-migrate's PLAN).
(cd "$at01" && orun plan --intent intent.yaml --trigger github-push-main --env stage --output "$scratch/plan-main.json") > "$scratch/plan-main.log" 2>&1 \
  || { echo "FAIL: orun plan (push to main)" >&2; tail -15 "$scratch/plan-main.log" >&2; exit 1; }
git -C "$tree" worktree remove --force "$at01"
mkdir -p "$scratch/pr"
git clone -q "$tree" "$scratch/pr/$repo"
prtree="$scratch/pr/$repo"
git -C "$prtree" checkout -q --orphan empty
git -C "$prtree" rm -rqf .
git -C "$prtree" -c user.email=t@example.invalid -c user.name=t commit -qm empty --allow-empty
git -C "$prtree" checkout -q main
(cd "$prtree" && orun plan --intent intent.yaml --trigger github-pull-request --base empty --head HEAD --env stage \
   --output "$scratch/plan-pr.json") > "$scratch/plan-pr.log" 2>&1 \
  || { echo "FAIL: orun plan (pull request)" >&2; tail -15 "$scratch/plan-pr.log" >&2; exit 1; }
# This tier runs the bootstrap floor, newer than the orun the product's CI
# pins, and both read the per-edge `modeRules`: on a pull request — which
# applies and deploys nothing — the infrastructure edges that order a push to
# main are advisory, so no lane waits on another. (placement.test.sh checks
# the push to main's order.)
python3 - "$scratch/plan-pr.json" <<'PY'
import json, sys
jobs = {j["component"]: j for j in json.load(open(sys.argv[1]))["jobs"] if j["environment"] == "stage"}
chain = ["supabase", "db-migrate", "web"]
for a, b in zip(chain, chain[1:]):
    ja, jb = jobs[a], jobs[b]
    if ja["id"] in (jb.get("dependsOn") or []) or ja["id"] not in (jb.get("advisoryDependsOn") or []):
        sys.exit(f"FAIL: on a pull request {b}@stage must name {a}@stage as advisory, not wait on it")
print("   pull request: " + " → ".join(chain) + ", every edge advisory")
PY

# ── 3. the db-migrate lane, in its staged job tree ─────────────────────────
echo "── the stage db-migrate lane: install, build @saas/db, apply — then apply again, and the PR's plan"
extract_job "$scratch/plan-main.json" db-migrate.stage.migrate "$scratch/steps-migrate" \
  install-dependencies build-db-package "Migration Apply"
extract_job "$scratch/plan-main.json" db-migrate.stage.migrate "$scratch/steps-migrate-again" "Migration Apply"
extract_job "$scratch/plan-pr.json" db-migrate.stage.migrate "$scratch/steps-migrate-plan" "Migration Plan"
# Staged from the fresh clone (a CI checkout: no build output, no
# node_modules); its migrations are the 01-product commit's, byte for byte.
mwork="$prtree/.orun/runs/e2e/db-migrate.stage.migrate/work"
python3 "$here/lib/stage-job.py" "$prtree" "$mwork"
# The component's secretEnv, as the lane resolves it: the supabase apply's
# published credentials and the brokered access token. SUPABASE_API_URL is
# the one value no lane has — it points the runner at the stand-in.
export SUPABASE_ACCESS_TOKEN=e2e-token SUPABASE_PROJECT_REF="$ref" SUPABASE_DB_PASSWORD=postgres \
       SUPABASE_DB_URL="$pgurl" SUPABASE_API_URL="$supabase_url"
run_job "$scratch/steps-migrate" "$mwork" stage "$scratch/migrate"
applied() { python3 -c "import json,sys;t=open(sys.argv[1]).read();print(' '.join(json.loads(t[t.index('{'):t.rindex('}')+1])['applied']))" "$1"; }
want="000_control_baseline 010_initial 020_add_unsubscribed_to_profiles"
[ "$(applied "$scratch/migrate-Migration Apply.log")" = "$want" ] \
  || { echo "FAIL: the first apply applied '$(applied "$scratch/migrate-Migration Apply.log")', not '$want'" >&2; exit 1; }
echo "   applied $want"
run_job "$scratch/steps-migrate-again" "$mwork" stage "$scratch/migrate-again"
[ -z "$(applied "$scratch/migrate-again-Migration Apply.log")" ] \
  || { echo "FAIL: a second apply applied '$(applied "$scratch/migrate-again-Migration Apply.log")'" >&2; exit 1; }
echo "   a second apply applied nothing (the ledger holds $(psql "$pgurl" -XAtc 'select count(*) from _migrations.applied') migrations)"
schema="$(psql "$pgurl" -XAtc "select string_agg(tgname, ',') from pg_trigger where tgrelid = 'auth.users'::regclass and not tgisinternal")|$(psql "$pgurl" -XAtc "select string_agg(id, ',') from storage.buckets")|$(psql "$pgurl" -XAtc "select count(*) from pg_policies where schemaname = 'storage' and tablename = 'objects'")"
[ "$schema" = "on_auth_user_created|avatars|2" ] \
  || { echo "FAIL: the template's trigger, bucket and storage policies are not in place (got '$schema')" >&2; exit 1; }
echo "   the template's trigger on auth.users, the avatars bucket and its two storage policies are in place"
run_job "$scratch/steps-migrate-plan" "$mwork" stage "$scratch/migrate-plan"
[ "$(applied "$scratch/migrate-plan-Migration Plan.log")" = "$want" ] \
  || { echo "FAIL: the pull request's offline plan did not verify every migration" >&2; exit 1; }
echo "   the pull request's plan step verifies every migration's checksum offline"
unset SUPABASE_ACCESS_TOKEN SUPABASE_PROJECT_REF SUPABASE_DB_PASSWORD SUPABASE_DB_URL SUPABASE_API_URL
rm -rf "$mwork"

# ── 4. the web lane's steps, for stage ─────────────────────────────────────
echo "── the stage web lane: install, verify-app-structure, build-app, verify-build-output, deploy-dry-run"
extract_job "$scratch/plan-pr.json" web.stage.verify-deploy "$scratch/steps-web" \
  install-workspace-dependencies verify-app-structure build-app verify-build-output deploy-dry-run
work="$prtree/.orun/runs/e2e/web.stage.verify-deploy/work"
# The job's private tree, staged as orun stages it — no build output, no
# node_modules: under stack-tectonic 0.19.0 the job installs inside it.
python3 "$here/lib/stage-job.py" "$prtree" "$work"
[ ! -e "$work/apps/web/.svelte-kit" ] && [ -f "$work/apps/web/wrangler.jsonc" ] \
  || { echo "FAIL: the staged tree is not a fresh checkout with the committed wrangler.jsonc" >&2; exit 1; }
echo "   staged: $(realpath --relative-to="$prtree" "$work") — no build output, the committed wrangler.jsonc"
# The stage wiring document, as the supabase apply publishes it and the lane
# resolves it (secretEnv WIRING_SUPABASE_STAGE): the stand-in's URL and its
# anon key. And the service-role key, as the lane's optionalSecretEnv hands
# it over: a verify lane has no Cloudflare credential, so build-app must
# leave it out of every bundle and push it nowhere.
export WIRING_SUPABASE_STAGE="{\"supabase_url\":\"$supabase_url\",\"supabase_anon_key\":\"$anon\"}"
export PRIVATE_SUPABASE_SERVICE_ROLE="$service"
run_job "$scratch/steps-web" "$work" stage "$scratch/web"
unset WIRING_SUPABASE_STAGE PRIVATE_SUPABASE_SERVICE_ROLE
grep -q "\"PUBLIC_SUPABASE_URL\": \"$supabase_url\"" "$work/apps/web/wrangler.jsonc" \
  && grep -q "\"PUBLIC_SUPABASE_ANON_KEY\": \"$anon\"" "$work/apps/web/wrangler.jsonc" \
  || { echo "FAIL: build-app did not re-render wrangler.jsonc from the stage wiring document" >&2; exit 1; }
[ "$(node -e 'const fs=require("fs");process.stdout.write(String(fs.readdirSync(process.argv[1]).length))' "$work/node_modules")" -gt 0 ] && [ ! -L "$work/node_modules" ] \
  || { echo "FAIL: the job's install did not land inside its own tree" >&2; exit 1; }
# `vite build` inlined the SAME project ($env/static/public) into the browser
# bundle — not the committed fixture's — and the service-role key into none.
grep -rqF "$supabase_url" "$work/apps/web/.svelte-kit/cloudflare/_app" \
  && ! grep -rqF "stage-project-ref.supabase.co" "$work/apps/web/.svelte-kit/cloudflare" "$work/apps/web/.svelte-kit/output" \
  || { echo "FAIL: the browser bundle does not carry the project the stage wiring names" >&2; exit 1; }
! grep -rqF "$service" "$work/apps/web/.svelte-kit" \
  || { echo "FAIL: the service-role key is in the build output" >&2; exit 1; }
grep -q "worker-secrets: no Cloudflare credential in this job" "$scratch/web-build-app.log" \
  || { echo "FAIL: build-app did not hand the service-role key to the deploy lane" >&2; tail -5 "$scratch/web-build-app.log" >&2; exit 1; }
echo "   the staged build ran inside its own tree; the Worker's vars and the browser bundle name the stage project it was handed; the service-role key is in no bundle and was pushed nowhere (a verify lane)"

# ── 5. serve it: first without the service-role key, then with it ──────────
echo "── wrangler dev over the built Worker, with no .dev.vars"
[ ! -e "$work/apps/web/.dev.vars" ] || { echo "FAIL: the staged tree carries a .dev.vars" >&2; exit 1; }
smoke="$(python3 -c "import yaml,sys;print(yaml.safe_load(open(sys.argv[1]))['spec']['parameters']['smokeCommand'])" "$tree/apps/web/component.yaml")"
serve "$work/apps/web" "$scratch/dev-nokey.log"
home_status="$(curl -s -o /dev/null -w '%{http_code}' "$url/")"
health="$(curl -s -w ' %{http_code}' "$url/api/health")"
case "$home_status|$health" in
  "200|"*'"ok":false'*'PRIVATE_SUPABASE_SERVICE_ROLE is not set'*' 503') ;;
  *) echo "FAIL: without the key, / answered $home_status and /api/health $health" >&2; exit 1 ;;
esac
if DEPLOYED_URL="$url" bash -c "$smoke" > /dev/null 2>&1; then
  echo "FAIL: the deploy's smoke passed a Worker that has no service-role key" >&2; exit 1
fi
echo "   / serves; /api/health answers 503 naming PRIVATE_SUPABASE_SERVICE_ROLE; the smoke refuses it"
stop_group "$dev_pid"; dev_pid=""

echo "── wrangler dev with the service-role key as the Worker's secret"
(cd "$work/apps/web" && PRIVATE_SUPABASE_SERVICE_ROLE="$service" \
   node ../../tooling/wire/worker-secrets.mjs --dev-vars .dev.vars --secret PRIVATE_SUPABASE_SERVICE_ROLE) > "$scratch/dev-vars.log" 2>&1 \
  || { echo "FAIL: worker-secrets.mjs --dev-vars" >&2; cat "$scratch/dev-vars.log" >&2; exit 1; }
serve "$work/apps/web" "$scratch/dev.log"
echo "   ▸ the component's own smokeCommand, DEPLOYED_URL=$url"
DEPLOYED_URL="$url" bash -c "$smoke" || { echo "FAIL: the deploy's smoke refused the product" >&2; tail -20 "$scratch/dev.log" >&2; exit 1; }

echo "   ▸ every route the product promises; a user from sign-up to a deleted account"
python3 - "$url" "$values" "$supabase_url" "$anon" "$work/apps/web" "$here/lib/browser-auth.mjs" "$pgurl" <<'PY' \
  || { echo "FAIL: the routes; wrangler dev said:" >&2; tail -40 "$scratch/dev.log" >&2; exit 1; }
import html, http.client, json, re, subprocess, sys, time, urllib.error, urllib.parse, urllib.request
base, values, supabase, anon, app, browser, pgurl = sys.argv[1], json.load(open(sys.argv[2])), *sys.argv[3:]
name = values["productname"]
origin = f"https://{values['reponame']}-web-stage.{values['subdomain']}.workers.dev"
problems = []
def bad(m): problems.append(m)

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a, **k): return None
opener = urllib.request.build_opener(NoRedirect)
def req(path, data=None, headers=None, method=None):
    # A GET whose CONNECTION drops (not one that answers an error) is asked
    # again, twice at most, and says so: `wrangler dev` on a loaded machine
    # has dropped one. A POST is never repeated — it would submit twice.
    for attempt in range(3):
        r = urllib.request.Request(base + path, data=data, headers=headers or {}, method=method)
        try:
            with opener.open(r, timeout=60) as resp:
                return resp.status, resp.headers, resp.read().decode("utf-8", "replace")
        except urllib.error.HTTPError as e:
            return e.code, e.headers, e.read().decode("utf-8", "replace")
        except (http.client.RemoteDisconnected, ConnectionResetError) as e:
            if data is not None or attempt == 2:
                raise
            print(f"   (GET {path}: the connection dropped ({e.__class__.__name__}) — asking again)")
            time.sleep(1)
def location(h):
    return urllib.parse.urlparse(h.get("location", "")).path
def text(page):
    # Svelte separates adjacent text with `<!---->` markers: drop those, then tags.
    return html.unescape(re.sub(r"<[^>]+>", " ", re.sub(r"<!--.*?-->", "", page, flags=re.S)))
def title(page):
    m = re.search(r"<title>(.*?)</title>", page, re.S)
    return m and html.unescape(m.group(1)).strip()
def guarded(path, cookie=None, want="/login"):
    s, h, _ = req(path, headers={"cookie": cookie} if cookie else {})
    if s not in (302, 303, 307) or location(h) != want:
        bad(f"{path} answered {s} → {h.get('location')}, not a redirect to {want}")
# A form, as SvelteKit's `use:enhance` posts it: the action's URL, the page's
# own origin (SvelteKit refuses a cross-site form post), and the headers that
# make the Worker answer the action's result as JSON.
def action(path, fields, cookie=None):
    h = {"content-type": "application/x-www-form-urlencoded", "origin": base,
         "accept": "application/json", "x-sveltekit-action": "true"}
    if cookie:
        h["cookie"] = cookie
    s, _, body = req(path, urllib.parse.urlencode(fields).encode(), h, "POST")
    try:
        return s, json.loads(body)
    except ValueError:
        return s, {"type": "unparsed", "body": body[:200]}
def browser_call(*args):
    out = subprocess.run(["node", browser, app, supabase, anon, *args], capture_output=True, text=True)
    if out.returncode != 0:
        raise SystemExit(f"browser-auth {args[0]} failed: {out.stderr.strip()[-400:]}")
    return json.loads(out.stdout)
def sql(query):
    return subprocess.run(["psql", pgurl, "-XAtc", query], capture_output=True, text=True, check=True).stdout.strip()

# ── the public pages, under the product's own name and origin ─────────────
s, _, home = req("/")
if s != 200:
    bad(f"/ answered {s}")
if title(home) != name:
    bad(f"the home page's <title> is {title(home)!r}, not {name!r}")
if name not in [html.unescape(m).strip() for m in re.findall(r'<a class="btn btn-ghost normal-case text-xl" href="/">(.*?)</a>', home, re.S)]:
    bad(f"the header's home link does not read {name!r}")
if f'"url":"{origin}"' not in home:
    bad(f"the home page's JSON-LD does not name the product's origin {origin}")
for leftover in ("sveltekit-saas", "your-workers-subdomain", "localhost:5173"):
    if leftover in home:
        bad(f"the home page still carries {leftover!r}")
if 'href="https://github.com/CriticalMoments/CMSaasStarter"' not in home:
    bad("the marketing layout's link to the upstream template is gone")
s, _, pricing = req("/pricing")
if s != 200 or f"Pricing - {name}" not in html.unescape(pricing):
    bad(f"/pricing answered {s} without the product's name")
# The sitemap is pre-rendered, so its links are the build's origin (the
# environment's SITE_URL, else its workers.dev URL); the feed is rendered per
# request from the origin it is asked on, as upstream's is.
s, _, body = req("/sitemap.xml")
if s != 200 or f"<loc>{origin}/" not in body or "localhost" in body:
    bad(f"/sitemap.xml answered {s} without links on {origin}")
s, _, body = req("/blog/rss.xml")
if s != 200 or f"<link>{base}/blog</link>" not in body or "<item>" not in body:
    bad(f"/blog/rss.xml answered {s} without its posts on {base}")
s, _, body = req("/search/api.json")
try:
    if s != 200 or not json.loads(body):
        bad(f"/search/api.json answered {s} with no index")
except ValueError:
    bad(f"/search/api.json is not JSON ({s})")
for path in ("/blog", "/login", "/login/sign_in", "/login/sign_up", "/login/forgot_password", "/contact_us"):
    s, _, _ = req(path)
    if s != 200:
        bad(f"{path} answered {s}")
s, _, _ = req("/no-such-page")
if s != 404:
    bad(f"/no-such-page answered {s}, not 404")
for path in ("/account", "/account/billing", "/account/settings", "/account/create_profile"):
    guarded(path)
guarded("/auth/callback", want="/account")

# ── what only the Worker answers ──────────────────────────────────────────
s, h, body = req("/api/health")
if s != 200 or json.loads(body) != {"ok": True, "database": "ok", "stripe": False, "email": False} \
        or h.get("cache-control") != "no-store":
    bad(f"/api/health answered {s} {body} ({h.get('cache-control')})")

# ── a visitor signs up, and the migration's trigger has written a profile ─
password = "correct horse battery"
sam = "sam@seats.example"
up = browser_call("signup", sam, password, base)
if not up["ok"] or not up["session"] or "sb-127-auth-token" not in up["cookie"]:
    raise SystemExit(f"sign-up did not sign the user in: {up}")
cookie, sam_id = up["cookie"], up["id"]
if sql(f"select coalesce(full_name, '<null>') from profiles where id = '{sam_id}'") != "<null>":
    bad("the trigger on auth.users did not write an empty profile for the new user")
guarded("/account", cookie, "/account/create_profile")
s, _, page = req("/account/create_profile", headers={"cookie": cookie})
if s != 200 or 'action="/account/api?/updateProfile"' not in page:
    bad(f"/account/create_profile answered {s} without the profile form")
s, r = action("/account/api?/updateProfile", {"fullName": "", "companyName": "Seats", "website": "https://seats.example"}, cookie)
if r.get("type") != "failure" or r.get("status") != 400:
    bad(f"a profile with no name was not refused: {s} {r}")
s, r = action("/account/api?/updateProfile",
              {"fullName": "Sam Seats", "companyName": "Seats & Co", "website": "https://seats.example"}, cookie)
if r.get("type") != "success":
    bad(f"the profile form's action answered {s} {r}")
row = sql(f"select full_name || '|' || company_name || '|' || website || '|' || (updated_at is not null) from profiles where id = '{sam_id}'")
if row != "Sam Seats|Seats & Co|https://seats.example|true":
    bad(f"the profile the form wrote reads {row!r}")
guarded("/account/create_profile", cookie, "/account/select_plan")
s, _, dash = req("/account", headers={"cookie": cookie})
if s != 200 or "Dashboard" not in text(dash) or name not in text(dash):
    bad(f"/account signed in answered {s} without the dashboard under {name!r}")

# ── billing, with no Stripe key ───────────────────────────────────────────
s, _, billing = req("/account/billing", headers={"cookie": cookie})
if s != 200 or 'data-stripe="not-connected"' not in billing or "STRIPE_API_KEY" not in billing:
    bad(f"/account/billing answered {s} without saying Stripe is not connected")
guarded("/account/billing/manage", cookie, "/account/billing")
guarded("/account/subscribe/price_1NkdZCHMjzZ8mGZnRSjUm4yA", cookie, "/account/billing")
guarded("/account/subscribe/free_plan", cookie, "/account")

# ── settings, and the email opt-out ───────────────────────────────────────
s, _, settings = req("/account/settings", headers={"cookie": cookie})
if s != 200 or sam not in settings:
    bad(f"/account/settings answered {s} without the user's email")
s, r = action("/account/api?/toggleEmailSubscription", {}, cookie)
if r.get("type") != "success" or sql(f"select unsubscribed from profiles where id = '{sam_id}'") != "t":
    bad(f"the email opt-out answered {s} {r} and did not write it")

# ── the contact form writes through the service role ──────────────────────
s, r = action("/contact_us?/submitContactUs", {"first_name": "A", "last_name": "Visitor", "email": "a@visitor.example"})
if r.get("type") != "failure" or r.get("status") != 400:
    bad(f"a contact request with a one-letter name was not refused: {s} {r}")
s, r = action("/contact_us?/submitContactUs", {"first_name": "Avery", "last_name": "Visitor", "email": "avery@visitor.example",
                                               "company": "Visitors", "phone": "", "message": "Hello"})
if r.get("type") != "success" or sql("select string_agg(email, ',') from contact_requests") != "avery@visitor.example":
    bad(f"the contact form answered {s} {r} and did not write the request")

# ── a second user; each reads their own profile through the Data API ──────
kim = "kim@seats.example"
up = browser_call("signup", kim, password, base)
if not up["ok"] or not up["session"]:
    raise SystemExit(f"the second sign-up failed: {up}")
kim_cookie, kim_id = up["cookie"], up["id"]
mine = browser_call("select", "profiles", sam, password)
if [r["id"] for r in mine["rows"] or []] != [sam_id]:
    bad(f"sam reads {mine['rows']} through the Data API, not his own profile alone")
theirs = browser_call("select", "profiles", kim, password)
if [r["id"] for r in theirs["rows"] or []] != [kim_id]:
    bad(f"kim reads {theirs['rows']}, not her own profile alone")
for table in ("profiles", "contact_requests", "stripe_customers"):
    nobody = browser_call("select", table)
    if not nobody["ok"] or nobody["rows"] != []:
        bad(f"anon reads {nobody['rows']} from {table} through the Data API")
contact = browser_call("select", "contact_requests", sam, password)
if contact["rows"] != []:
    bad(f"a signed-in user reads the contact requests: {contact['rows']}")

# ── a wrong password, a sign-in, a sign-out ───────────────────────────────
wrong = browser_call("signin", sam, "not the password")
if wrong["ok"] or wrong["code"] != "invalid_credentials":
    bad(f"a wrong password was not refused: {wrong}")
again = browser_call("signin", sam, password)
s, _, _ = req("/account", headers={"cookie": again["cookie"]})
if not again["session"] or s != 200:
    bad(f"sign-in answered {again['code']} and /account {s}")
s, r = action("/account/api?/signout", {}, again["cookie"])
if r.get("type") != "redirect" or r.get("location") != "/":
    bad(f"sign-out answered {s} {r}")

# ── kim deletes her account, through the admin API and the service role ───
s, r = action("/account/api?/deleteAccount", {"currentPassword": ""}, kim_cookie)
if r.get("type") != "failure" or r.get("status") != 400:
    bad(f"deleting an account with no password was not refused: {s} {r}")
s, r = action("/account/api?/deleteAccount", {"currentPassword": password}, kim_cookie)
if r.get("type") != "redirect" or r.get("location") != "/":
    bad(f"deleting the account answered {s} {r}")
if sql(f"select deleted_at is not null from auth.users where id = '{kim_id}'") != "t":
    bad("the account was not deleted in Auth")
gone = browser_call("signin", kim, password)
if gone["ok"] or gone["code"] != "invalid_credentials":
    bad(f"a deleted user signed in again: {gone}")
guarded("/account", kim_cookie)

if problems:
    for p in problems:
        print(f"  ✕ {p}", file=sys.stderr)
    sys.exit(1)
print(f"   /, /pricing, /blog, the sitemap on {origin}, the RSS feed, the search index, the login and "
      f"contact pages, a 404, the account pages guarded, /api/health; a sign-up, the profile the trigger "
      f"wrote completed through the form's action under RLS, the dashboard, billing without Stripe, the "
      f"Stripe routes degraded, settings, the email opt-out, the contact form through the service role, "
      f"a second user, a wrong password, a sign-in and a sign-out, an account deleted and unable to "
      f"sign in — as {name!r}")
PY

# ── 7. what Supabase's Data API roles see ──────────────────────────────────
echo "── the Data API's roles (anon, authenticated, service_role) against the same database"
sam_id="$(psql "$pgurl" -XAtc "select id from auth.users where email = 'sam@seats.example'")"
psql "$pgurl" -X -q -v ON_ERROR_STOP=1 -At -v sam="$sam_id" > "$scratch/rls.out" 2> "$scratch/rls.err" <<'SQL' \
  || { echo "FAIL: the row-level security checks" >&2; cat "$scratch/rls.err" >&2; exit 1; }
SELECT 'app role: superuser=' || rolsuper || ' bypassrls=' || rolbypassrls FROM pg_roles WHERE rolname = current_user;
SELECT 'public tables without RLS: ' || count(*) FILTER (WHERE NOT c.relrowsecurity) || ' of ' || count(*)
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p');
SELECT 'not owned by the app: ' || count(*) FILTER (WHERE pg_get_userbyid(c.relowner) <> current_user)
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p');
SELECT 'app sees profiles: ' || count(*) FROM profiles;
SET ROLE anon;
SELECT 'anon sees profiles: ' || count(*) FROM profiles;
SELECT 'anon sees contact_requests: ' || count(*) FROM contact_requests;
RESET ROLE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'sam', 'role', 'authenticated')::text, false) \g /dev/null
SELECT 'sam sees profiles: ' || count(*) FROM profiles;
SELECT 'sam sees contact_requests: ' || count(*) FROM contact_requests;
WITH u AS (UPDATE profiles SET full_name = 'written by sam' WHERE id <> :'sam' RETURNING 1)
SELECT 'sam updates others: ' || count(*) FROM u;
RESET ROLE;
SET ROLE service_role;
SELECT 'service_role sees profiles: ' || count(*) FROM profiles;
SELECT 'service_role sees contact_requests: ' || count(*) FROM contact_requests;
RESET ROLE;
SQL
sed 's/^/   /' "$scratch/rls.out"
grep -qx "app role: superuser=false bypassrls=false" "$scratch/rls.out" \
  && grep -qx "public tables without RLS: 0 of 3" "$scratch/rls.out" \
  && grep -qx "not owned by the app: 0" "$scratch/rls.out" \
  || { echo "FAIL: the app's role, the tables' owner or their row-level security is not what Supabase's would be" >&2; exit 1; }
for line in "app sees profiles: 2" "anon sees profiles: 0" "anon sees contact_requests: 0" "sam sees profiles: 1" \
            "sam sees contact_requests: 0" "sam updates others: 0" "service_role sees profiles: 2" \
            "service_role sees contact_requests: 1"; do
  grep -qx "$line" "$scratch/rls.out" || { echo "FAIL: expected '$line'" >&2; exit 1; }
done
# A write through the Data API's roles is refused by row-level security: anon
# writes nothing, and a signed-in user cannot create a profile for anyone else.
psql_as() { psql "$pgurl" -X -q -At -v ON_ERROR_STOP=1 -c "$1" > "$scratch/rls-write.log" 2>&1; }
claims="SELECT set_config('request.jwt.claims', '{\"sub\":\"$sam_id\",\"role\":\"authenticated\"}', false);"
for attempt in "SET ROLE anon; INSERT INTO contact_requests (email) VALUES ('anon@example.invalid')" \
               "SET ROLE anon; INSERT INTO profiles (id) VALUES ('$sam_id')" \
               "SET ROLE authenticated; $claims INSERT INTO profiles (id) VALUES (gen_random_uuid())" \
               "SET ROLE authenticated; $claims INSERT INTO stripe_customers (user_id, stripe_customer_id) VALUES ('$sam_id', 'cus_forged')"; do
  if psql_as "$attempt"; then
    echo "FAIL: a write went through row-level security: $attempt" >&2; exit 1
  fi
  grep -q "row-level security" "$scratch/rls-write.log" \
    || { echo "FAIL: '$attempt' was refused for another reason:" >&2; cat "$scratch/rls-write.log" >&2; exit 1; }
done
echo "   anon reads nothing and writes nothing; sam reads his own profile only, updates no one else's and cannot forge a profile or a Stripe customer; only the service role sees every row"

echo "e2e.test.sh: ok"

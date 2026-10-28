# BOOTSTRAP — a new SaaS product from this baseline, in one landing

How to go from **nothing** to **a SaaS product live on stage and prod —
its own Supabase project per environment for its Auth and its data, the
schema applied, the app deployed — documented**, with two provider consents.

There is one artifact: **`repo-blueprint.yaml`**. It declares what to place,
in what order, what each phase needs first, and what to say while it runs.
`orun new` is the whole runtime — the phases below are its `--phase` names,
not separate workflows. The console card the platform renders is
**`blueprint.yaml`**; it names the build document and states the inputs, the
brokered secrets and the programme, and `testing/manifest.test.sh` holds it
to what the build document does.

Target wall-clock: **about fourteen minutes** — an estimate summed from the
phases (13 + 1) until a bootstrap measures it. The shape: the task set-up in
the background while ONE landing is placed, branded and checked in the box
(`orun validate` and `orun plan`, no runner waited for), then one convergence
per environment (stage and prod side by side until `02-docs` restores the
promotion gate) that creates the Supabase project (five to seven minutes),
applies the migrations and builds and deploys the app, in that order, then a
short docs landing.

## 0. What you need

- GitHub org access (repository creation) and a machine with `git`, `node`
  (≥ 22), `pnpm` (10.12.1), `python3` with PyYAML, `curl`, and the `orun`
  CLI **≥ v2.88.0** — the floor for RUNNING the bootstrap (the phase overlay,
  `githubOwner` on the doctor probe, `from: workspace`, the deploy
  credentials minted in one `secrets` reconcile per provider, the task set-up
  run in the background (`background: true`), and landings checked in the box
  before they merge (`checks: local`)). The product's own `ci.yml` pins its
  lanes separately (v2.78.4), and that pin — or anything newer, as the floor
  is — is what reads the per-edge `mode` rules the convergence order relies
  on.
- A **Cloudflare** account (the free plan is enough for one Worker with
  static assets per environment) and its Account API token with the
  permission groups the console's Connect recipe lists — Workers Scripts
  among them.
- A **Supabase** organization the platform can create projects in, connected
  to the workspace (console → Integrations → Supabase). Each environment gets
  its own project — mind your plan's project limit.
- An Orun Cloud workspace for the product — `orunWorkspace`, or the workspace
  the build runs in (ORUN_WORKSPACE) when that is unset — with an
  **admin-role API key** for headless runs (secret writes below admin are
  masked as `not_found`).
- **The repository allow-listed in the workspace** (console → Settings → Git
  repos), unless the credential can write links. `01-product`'s `link` step
  stops and names the fix if it is not.
- **Not Stripe, not Resend.** No platform brokers them: the product deploys
  without their keys and its owner adds them afterwards (§3).

## 1. One command: `--resume`

The whole bootstrap, unattended. `--resume` places every phase not already
derived as done, in order, honouring each phase's barrier:

```bash
git clone --depth 1 --branch <baseline-tag> https://github.com/sourceplane/sveltekit-saas
cd sveltekit-saas

orun new --blueprint repo-blueprint.yaml \
  --out ~/products/acme-saas --run-hooks --resume \
  --set reponame=acme-saas --set productname="Acme Cloud" \
  --set githuborg=acme-inc \
  --set orunWorkspace=ws_XXXXXXXX \
  --set subdomain=<workers-dev-subdomain>
```

`subdomain` is the workers.dev subdomain of the Cloudflare account you deploy
into (Workers & Pages → your subdomain). A build started from the console, or
with `orun baseline new --from bst_…`, never asks for it: the platform reads
it from the workspace's Cloudflare connection, the same one the deploy tokens
mint from. Only a hand-run build like this one passes it.

**`--run-hooks` is the difference between placing files and bootstrapping a
product.** Without it `orun new` writes the tree and stops: no repository, no
landing, no convergence watch, no probe. That is deliberate — it is what
makes the offline bootstrap in `testing/` possible with no workspace and no
provider.

`--resume` is safe to re-run from anywhere, a fresh container with a fresh
`--out` included: **phase state is derived from the tree, never stored.** A
phase whose files are present but branded derives as `drifted`, and
`--resume` leaves it placed rather than reverting the product's identity.

## 1b. Or phase by phase

| phase | what it lands | verified by |
|---|---|---|
| `01-product` | the repository, created and linked; the four brokered credentials; then the whole product in one PR — intent, CI, tooling, identity, the Supabase Terraform root, the migrations, the app and its tests | its commit validated and planned in the box (as the PR and as the merge), then merged; the convergence green (supabase → db-migrate → web, per environment — each resolving what the apply before it published); `/` and `/api/health` answering on both workers.dev URLs |
| `02-docs` | `ai/context/deployment.md` from probed facts (whether Stripe and email are connected included); prod's promotion gate and dev's push lanes restored | the render's own probes, recorded; the commit checked in the box and merged |

```bash
orun new --blueprint repo-blueprint.yaml --out ~/products/acme-saas --run-hooks \
  --phase 01-product --values ~/acme-saas.values.yaml
# … then 02-docs
```

`02-docs` reads the identity back from `.rebrand/values.json` in the placed
tree, but the blueprint's **required** inputs — `reponame`, `productname`,
`githuborg` — are validated before anything runs, so pass them every time (a
`--values` file is easier). The domain is not one of them: the app goes live
on workers.dev, and `productdomain` defaults to empty, which brands the
reserved placeholder `<reponame>.example.com` into `BASE_DOMAIN` for an owner
to replace when they attach a domain (README, "Custom domain"). Pass
`--set productdomain=` only for a product that already has its domain.
The full guide, one page per phase: [docs/phases/README.md](docs/phases/README.md).

| flag | what it does |
|---|---|
| `--status` | derives and prints every phase's state and writes nothing. It parses the document, validates each hook against the action registry and compiles every template; it needs no credential and no network |
| `--phase <name>` | places exactly that phase; its `requires.phases` still gates |
| `--until <name>` | places every phase through that one and stops |

What lands in the product is PRODUCT-ONLY: the app, the Terraform root, the
migrations and their runner, the tests, its CI, its tooling, its README and
its two context pages. None of this repository's machinery (`.baseline/`, the
blueprints, `tooling/rebrand`, `tooling/bootstrap`, `hooks/`, `testing/`,
`docs/phases/`, `specs/`, `tasks/`, this file) ships, and no shipped file
names any of it. That promise is a test: `testing/leak.test.sh` derives what
every phase would place and gates the set and every file's text, and
`testing/placement.test.sh` gates the same rules over a placed, branded tree.

## 2. Headless / container mode

The blueprint's source is this repository (`sources: [{kind: dir, path: .}]`),
so the container contract is a shallow clone at a pinned tag plus two
tokens:

```bash
export ORUN_TOKEN=…          # orun auth, headless
export GITHUB_TOKEN=…        # fine-grained PAT (below)

git clone --depth 1 --branch <baseline-tag> https://github.com/sourceplane/sveltekit-saas
cd sveltekit-saas
orun new --blueprint repo-blueprint.yaml \
  --out /work/acme-saas --run-hooks --resume --progress json \
  --values /work/acme-saas.values.yaml
```

| requirement | detail |
|---|---|
| `GITHUB_TOKEN` | fine-grained PAT: **read** on this repository; on the PRODUCT's repository **contents write**, **pull-requests write**, **actions read+write** (`orun.run/watch@v1` resumes runs with `gh run rerun`), **checks read**; **repository create** on the owner if `01-product` creates it (or pre-create it — supported) |
| classic token caveat | a classic PAT or gh OAuth token also needs the `workflow` scope to push `.github/workflows/` |
| pinning | the clone's `--branch <tag>` pins everything: the blueprint, its modules and its hooks' scripts all come from that one commit |

## 3. After the product is live

- **Connect Stripe** (per environment): put your Stripe price ids in
  `apps/web/src/routes/(marketing)/pricing/pricing_plans.ts`, store the
  secret key as the product's orun secret `STRIPE_API_KEY`
  (`orun secrets set STRIPE_API_KEY --env <env>`) and redeploy `web` — the
  build hands it to the Worker as a secret. Until then the billing page says
  Stripe is not connected and checkout and the portal send visitors there;
  sign-up, sign-in and the account pages work either way. The product's
  README, "Stripe", is the owner's copy of this.
- **Turn on email** the same way: `RESEND_API_KEY`, `ADMIN_EMAIL` and
  `FROM_ADMIN_EMAIL` (a sender on a domain verified in Resend), then
  redeploy. Supabase Auth's own email needs the project's own SMTP before
  confirmation is turned on (README, "Email").
- **Custom domain**: attach it to the Worker in Cloudflare, then set
  `SITE_URL` under the environment's `env:` in the product's `intent.yaml`
  (its README, "Custom domain"): the next apply points the project's Auth at
  it and the next deploy builds on it. There is no domain phase: attaching a
  domain needs zone permissions the brokered `workers-deploy` token does not
  carry.
- **Refresh the record**: re-run `--phase 02-docs`; it is idempotent, and it
  records whether Stripe and email are connected.

## 4. Testing this baseline

`.github/workflows/baseline.yml` runs three tiers on every pull request, and
each runs locally the same way:

```bash
for t in manifest phases coverage rebrand retouch bootstrap-defer; do bash testing/$t.test.sh; done
bash testing/leak.test.sh        # needs orun
bash testing/placement.test.sh   # needs orun, node, pnpm: the offline bootstrap and the product's own plans
bash testing/e2e.test.sh         # + network for pnpm, psql and a PostgreSQL server install
```

The offline bootstrap (`testing/lib/bootstrap.sh`) places both phases in
order and finishes each with the blueprint's OWN `run:` hooks — read out of
`repo-blueprint.yaml`, not transcribed — so the retouch marker, the rebrand,
the re-tenant, the deferrals and their restore and the deployment record
all run exactly as a real bootstrap runs them. Only the platform's typed
actions (task, repo, reconcile, land, watch, probe) and the `link` step are
stood in for, a landing becoming a commit.

What no test here can do is the clouds' half: create a Supabase project,
mint a token, deploy for real. The Terraform root is held to `fmt`,
`init -backend=false` and `validate` (a real `plan` reads Supabase's API and
the platform's state backend); the convergence ORDER is proven on the
product's own `orun plan`; and the migrations are applied by the product's
own runner to a local Postgres with Supabase's roles through a stand-in for
the Management API endpoint it calls (`testing/lib/fake-supabase-api.py`,
which also stands in for the project's Auth and Data API), before the built
Worker signs a user up over that database and takes them through the
profile step to the account pages.

## 5. Cutting a baseline tag (maintainers)

Every product built from this repository resolves a `baseline-vN` tag, so the
tag is cut by a workflow rather than by hand:

```bash
gh workflow run tag.yml -f version=baseline-v1          # from main
gh workflow run tag.yml -f version=baseline-v1 -f ref=<sha>
```

It refuses a version that is not `baseline-v<N>` and a tag that already
exists: a baseline tag is never moved. Then add (or move) the registry row in
orun-cloud's `infra/baselines-registry/baselines.yaml` by pull request —
after the tag exists, because the registry's sync fetches `blueprint.yaml`
at the tag and refuses the whole catalogue if it 404s.

## Troubleshooting

| Symptom | Cause → fix |
|---|---|
| `01-product` parks: `waiting for github for <org>` | the workspace's GitHub connection is to another account. Connect the App installation on `<org>` (console → Integrations → GitHub), then `--resume` |
| `01-product` parks on the `providers` probe for cloudflare or supabase | that connection is missing. Connect it (console → Integrations); the probe is a wait, not a failure |
| `01-product` stops at `link` | the repository is not linked to the workspace and the credential cannot link it. Allow-list it (console → Settings → Git repos) and re-run the phase |
| Secret WRITE fails `not_found` while listings work | the API key's role is below admin; re-mint it with the admin role |
| supabase apply: `does not support oauth access` | a supabase provider ≥ 1.6 reads billing endpoints the brokered OAuth token cannot; the root pins `~> 1.5.1` — keep it |
| supabase apply: project limit reached | the Supabase org's plan allows fewer projects than stage + prod need; free one or upgrade, then re-run `01-product` |
| web build: `wrangler secret bulk` Authentication error (10000) | the connection's token cannot mint `workers-deploy`; reconnect Cloudflare with the recipe's permission groups and re-run the phase — the reconcile re-mints only what is missing |
| db-migrate: `secret resolution failed … SUPABASE_*` | the supabase apply for that environment did not publish; its lane's log says why. db-migrate waits on it, enforced |
| web: `secret resolution failed … WIRING_SUPABASE_*` | a supabase apply published no wiring: the root lost its `secretOutputs`, or its lane was not in the plan. Re-run the phase; its retouch marker re-plans the root |
| `land` stops: `the landing's own check failed — orun plan for …` | the product's tree does not plan — the line after it is orun's own error (an unknown component type, a composition that does not resolve). Nothing was pushed. Fix the tree (or the baseline) and re-run the phase |
| `land` waits on CI after all | the product's repository requires a status check on `main` (branch protection or a ruleset), so GitHub refused the early merge; the landing waits for the check as a `checks: ci` landing would, then merges |
| db-migrate: `permission denied for table users` or `must be owner of table objects` | the project's query role may not create upstream's `auth.users` trigger or Storage policies (risk SV-A). Apply the rest of `010_initial` in the project's SQL editor, then re-run `01-product`: the ledger skips what is recorded |
| web smoke: `/api/health` 503 | its `database` field says why: the service-role key did not reach the Worker (read the build's `worker-secrets` line), or `relation … does not exist` — db-migrate did not run for that environment |
| `verify-app-structure` fails: `test -f "wrangler.jsonc"` | the product's `apps/web/wrangler.jsonc` is not committed. It must be — the check runs before the build in a fresh checkout (`pnpm run wire:fixture` renders it) |
| Convergence failed AFTER the PR merged; re-running lands nothing | expected on its own — the files are on main. Re-run the phase (`--phase 01-product`, `--redo 01-product`, or the console's Retry): its `retouch` hook gives the landing a diff and the components re-plan; the project is adopted, not recreated |
| The convergence reported green, then `verify` got 404 | a second workflow ran on the push to main and the watch took its run. Only `ci.yml` may run on a push to main |
| The product's `intent.yaml` says `workspace: ws_SET_ME` | `orunWorkspace` was empty and the build ran outside a workspace; set it and re-run `01-product` |
| A bootstrap stopped before `02-docs`; prod no longer waits on stage | the gate is deferred, not dropped: run `02-docs`, or `node tooling/bootstrap/promotion.mjs --restore --file <product>/intent.yaml` |
| `✕ input "productname" is required` | all three required inputs (`reponame`, `productname`, `githuborg`) must be set on every invocation, single-phase ones included |
| `unknown flag: --phase`, `has no parameter "checks"`, `has no parameter "secrets"` or another parse error in the blueprint | the CLI is below the v2.88.0 floor |

# 01-product — the product, in one landing

The whole product lands as ONE pull request, and ONE convergence on main
provisions and deploys it on stage and prod: the Supabase project, the
migrations, and the app — in that order, per environment.

**Places** every module `repo-blueprint.yaml` declares: the root manifests,
CI, tooling and identity; `infra/terraform/supabase` and
`infra/db-migrate`;
`packages/db` (the migrations and their runner); `apps/web`; and
`tests/web`, `tests/db`. `testing/phases.test.sh` holds the set.

**Requires** three live connections, probed and waited for (up to ten
minutes, so a consent can be clicked while it waits): the GitHub App on the
account that OWNS the repository — the platform sees a PR only through that
installation — and Cloudflare and Supabase, which every credential below is
minted from.

## How one convergence keeps the order

| what has to come first | how the plan holds it |
|---|---|
| the migrations after the project | `db-migrate` reads `SUPABASE_PROJECT_REF`, `SUPABASE_DB_PASSWORD` and `SUPABASE_DB_URL`, which the `supabase` apply lease-publishes, and declares `dependsOn: supabase`, `mode: enforced` on main. A job resolves its secrets when it STARTS, so the values are there |
| the app last | `web` renders the project's URL and anon key (`WIRING_SUPABASE_<ENV>`) into `wrangler.jsonc` before the build, hands the Worker the service-role key (`SUPABASE_SERVICE_ROLE_KEY`), and reads the migrated schema, so it declares `dependsOn` on `supabase` and `db-migrate`, enforced on main |
| stage before prod | deferred during the bootstrap (below), so both environments run their chains side by side |

Every one of these edges is **advisory on a pull request**, which applies and
deploys nothing. `testing/placement.test.sh` plans the placed product's own
push to main and reads the order off it:
`supabase → db-migrate → web`.

## What runs

The run's task set-up — the epic, both milestones, both tasks — runs in the
background from the start (`background: true`), so every hook up to `task`
runs beside it; `task` is the first that waits for it.

| hook | what it does |
|---|---|
| `retouch` | one trailing `# orun: redeploy 01-product <stamp>` line in each component `.baseline/tasks/01-product.TaskContract.yaml` names (supabase, db, db-migrate, web), so a RE-RUN has a diff to land |
| `git-init`, `stage` | the tree becomes a git repository with a populated index (the rebrand enumerates `git ls-files`) |
| `rebrand` | renames the baseline's identity to the product's: the slug (intent, worker, secret project, the `repo` the Supabase projects are named after), the name seam (`WebsiteName` in `apps/web/src/config.ts`), the domain, the workers.dev subdomain. The upstream template's own links and every migration are left alone |
| `orun-workspace` | writes the product's workspace into `intent.yaml` |
| `work-tree` | strips this repository's `work:` block from the product's intent |
| `promotion`, `dev-lanes` | defer prod's wait on stage and dev's push lanes until `02-docs` |
| `restage`, `rebrand-verify` | the sweep: no baseline identity left |
| `repo` | `orun.repo/ensure@v1`: creates (or finds) `<githuborg>/<reponame>` |
| `link` | the repository becomes the workspace's (`orun cloud link`, best effort; `orun cloud check` is the gate). Every convergence lane authenticates over GitHub OIDC through that link |
| `secrets-cloudflare` | `orun.integrations/reconcile@v1`, Cloudflare's two keys in one hook, each under its own scope, created side by side: `CLOUDFLARE_API_TOKEN` (workers-deploy, the app's deploy and its Worker secrets), `CLOUDFLARE_ACCOUNT_ID` (account-id). Keys that exist are kept |
| `secrets-supabase` | the same for Supabase's two: `SUPABASE_ACCESS_TOKEN` (management-access, the project and the migrations), `SUPABASE_ORG_ID` (org-id) |
| `task` | finds the phase's task and yields its key — waiting, if it must, for the background set-up |
| `land` | one PR bound to the task, its commit checked in the box first (`checks: local`: `orun validate`, then `orun plan` as the PR and as the merge would plan it, under a second); merged without waiting for the PR's CI (`plan` alone on a bootstrap branch) |
| `converge` (await) | `orun.run/watch@v1` on the merge commit's run, read every 5 s; resumes it up to three times |
| `verify` (await) | `orun.http/probe@v1`: `/` and `/api/health` on both workers.dev URLs |

## What the convergence does, per environment

1. **supabase** — `terraform apply`: one project, `<reponame>-<env>`, in the
   org `SUPABASE_ORG_ID` names, with a generated database password, waited
   on until it is healthy, its Auth pointed at the app's Worker (Site URL,
   redirect allow-list, email confirmation off until it has SMTP). Its
   outputs are lease-published as `SUPABASE_PROJECT_REF`,
   `SUPABASE_DB_PASSWORD`, `SUPABASE_DB_URL`, `WIRING_SUPABASE` (the URL and
   anon key) and `SUPABASE_SERVICE_ROLE_KEY`. A new project takes five to
   seven minutes to come up.
2. **db-migrate** — builds `@saas/db` and applies every migration the
   project's `_migrations.applied` ledger does not have, through Supabase's
   Management API: upstream's schema — `profiles`, `stripe_customers` and
   `contact_requests` under row-level security, the trigger that gives each
   new user a profile, the `avatars` bucket — then `profiles.unsubscribed`.
3. **web** — installs, re-renders `wrangler.jsonc` from this environment's
   wiring document, builds with adapter-cloudflare (the project inlined),
   hands the Worker its secrets, deploys `<reponame>-web-<env>`, and
   smoke-tests it: the home page, and `/api/health`, which answers only when
   the Worker reaches its project with the service-role key and finds the
   schema.

Stripe and Resend are not in it: no connection brokers them. The app deploys
without their keys; its billing page says Stripe is not connected and no
email is sent until the owner adds them (the product's README, "Stripe",
"Email").

## Verify / done means

- The convergence for the merge commit is green on stage and prod — in it,
  db-migrate resolved the Supabase project's `SUPABASE_PROJECT_REF`,
  `SUPABASE_DB_PASSWORD` and `SUPABASE_DB_URL`, and the app's deploy
  `WIRING_SUPABASE`, from stage and prod, where every later run reads them;
  a missing one fails its lane. The deploy's smoke proves the service-role
  key arrived: `/api/health` answers ok only with it. So there is no
  separate check that they exist.
- `/` and `/api/health` answer on both workers.dev URLs.

## Failure modes

| symptom | meaning → fix |
|---|---|
| parks on the `providers` probe | a connection is missing — GitHub on the repository's owner, Cloudflare, or Supabase. Connect it (console → Integrations); the probe is a wait, not a failure |
| supabase apply: `does not support oauth access` | the provider is above 1.5.x, which reads billing endpoints an OAuth token cannot — `~> 1.5.1` is pinned for this reason |
| supabase apply: project name already exists | `adopt.tf` looks the project up by name and imports it — if you removed that file, restore it |
| db-migrate lane: secret resolution failed (`SUPABASE_*`) | the supabase apply for that environment did not publish — read its log; db-migrate waits on it, so it shows as not run |
| web lane: secret resolution failed (`WIRING_SUPABASE_*`) | a supabase apply did not publish its wiring (the root lost its `secretOutputs`, or its lane was not in the plan) — read the supabase lane; re-run the phase and its retouch marker re-plans it |
| `land`: `the landing's own check failed — orun plan for …` | the placed tree does not plan; the next line is orun's own error. Nothing was pushed. Fix it (or the baseline) and re-run the phase |
| `land` waits on CI after all | the product's repository requires a status check on `main` (branch protection or a ruleset), so GitHub refused the early merge; the landing waits for the check as a `checks: ci` landing would, then merges |
| web build: `wrangler secret bulk` Authentication error (10000) | the connection's token cannot mint `workers-deploy`; re-issue it with Workers Scripts write, re-connect, re-run the phase |
| db-migrate: checksum mismatch | an applied migration's file changed. Never edit one; add a new migration |
| db-migrate: `permission denied for table users` or `must be owner of table objects` | the project's query role may not create the `auth.users` trigger or the Storage policies of `010_initial` (risk SV-A): nothing after the failing statement ran and the app did not deploy. Apply that migration's remaining statements in the project's SQL editor, then re-run the phase — the ledger skips what is recorded |
| web smoke: `/api/health` 503 | its `database` field says why: `PRIVATE_SUPABASE_SERVICE_ROLE is not set` (the key did not reach the Worker — read the build's `worker-secrets` line), or `relation … does not exist` (the migrations did not run — read the db-migrate lane) |
| `verify-app-structure` fails: `test -f wrangler.jsonc` | `apps/web/wrangler.jsonc` is not committed. It must be: the check runs before the build, in a fresh checkout (`pnpm run wire:fixture` renders it) |
| the watch says green, the probe says 404 | another workflow ran on the push and the watch took its run. Only `ci.yml` may run on a push to main |
| re-run lands nothing | the hooks did not run (`--run-hooks`), or the contract names no component — `node tooling/bootstrap/retouch.mjs --check --affects .baseline/tasks/01-product.TaskContract.yaml` in the product's tree says which |

## Re-running

Idempotent: placement is additive, the rebrand is a no-op on branded files,
`git init` and the repo step are guarded, the Supabase project is adopted
rather than recreated, and the migration ledger lives in the database, so only missing migrations apply. A re-run of
a phase whose PR already merged lands the retouch markers alone, which
re-plans exactly the components they name. Once the tree is branded the
phase derives as `drifted`, so `--resume` leaves it alone; re-run it
deliberately with `--phase 01-product` (or `--redo 01-product`).

## What one convergence will run, before running it

From a placed product's tree:

```bash
node <baseline>/tooling/bootstrap/promotion.mjs --defer && node <baseline>/tooling/bootstrap/dev-lanes.mjs --defer
orun plan --intent intent.yaml --trigger github-push-main -v lanes
git checkout intent.yaml
```

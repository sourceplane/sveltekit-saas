# sveltekit-saas — operating contract (for humans and agents)

This is the standing guide to how this product is deployed and operated.
Instance facts (live URLs, workspace, whether Stripe and email are connected,
the secrets it uses) live in [deployment.md](deployment.md), rendered from
probed reality by the bootstrap's `02-docs` phase; this file is the contract
that stays true between deployments. It is written to give an agent with
repository read access enough context to reason about and operate the product
without any other source.

## What this system is

CMSaasStarter — a SvelteKit SaaS: a pre-rendered marketing site, a blog,
search, pricing, Supabase Auth, an account dashboard, Stripe billing and
Resend email — on Cloudflare Workers, with a Supabase project per environment
for its Auth and its data, expressed as an Orun component-native
desired-state repo. Six components:

- **`infra/terraform/supabase`** (`supabase`) — one Supabase project per
  environment, its Auth pointed at the app (Site URL, redirect allow-list,
  email confirmation). Its apply publishes `SUPABASE_PROJECT_REF`,
  `SUPABASE_DB_PASSWORD`, `SUPABASE_DB_URL`, `WIRING_SUPABASE` (the project's
  URL and anon key) and `SUPABASE_SERVICE_ROLE_KEY` onto the environment's
  secret rung.
- **`infra/db-migrate`** (`db-migrate`) — applies `packages/db`'s migrations
  to the environment's project through Supabase's Management API. Each
  migration is recorded with its checksum in `_migrations.applied`; only the
  missing ones apply.
- **`packages/db`** (`db`) — the migrations and their runner.
- **`apps/web`** (`web`) — the app: SvelteKit built by
  `@sveltejs/adapter-cloudflare` into one Worker plus Static Assets. The
  project's URL and anon key are vars in its config and inlined into its
  build; the service-role key and the owner's Stripe and Resend keys are
  Worker secrets, read at request time (`$env/dynamic/private`).
- **`tests/web`**, **`tests/db`** — vitest suites, verified on the `dev` rung.

Environments: **`stage`** and **`prod`** are deployed; **`dev` is
verify-only by design** — lanes build and test, nothing deploys.

## Identity and tenancy

Every remote operation runs against ONE Orun workspace, declared in
`intent.yaml` under `execution.state.workspace` — committed, enforced, and
what CI uses. Do not remove it; headless credentials depend on it. If it
reads `ws_SET_ME`, the bootstrap had no workspace to write: set the real one
before anything else.

## How deployment works

1. Merge (or push) to `main`.
2. CI (`.github/workflows/ci.yml`) runs `orun plan --changed` — only
   components whose files changed are planned — then runs each planned lane
   with `orun run --remote-state`, authenticated by GitHub OIDC (the
   exchange resolves this repository's linked workspace server-side).
3. Per environment, in this order — each edge `mode: enforced` on a push to
   main, advisory on a pull request (which deploys nothing):
   **`supabase` → `db-migrate` → `web`.** A job resolves its secrets when it
   starts, so each one reads what the apply before it published. The app's
   deploy re-renders `apps/web/wrangler.jsonc` from `WIRING_SUPABASE` before
   it builds, hands the Worker its secrets (`tooling/wire/worker-secrets.mjs`,
   over stdin), deploys `sveltekit-saas-web-<env>`, and smoke-tests it: the
   home page, and `/api/health`, which answers 200 only when the Worker
   reaches its project with the service-role key and finds the schema.
4. `prod` deploys after `stage` has converged on the same commit
   (`environments.prod.promotion` in intent.yaml).
5. **The convergence run is the deployment.** A green run means every
   planned lane applied. Failed lanes are retried with
   `gh run rerun --failed`, which resumes the same execution.

Caveats that matter:

- A push that touches no component files plans zero lanes — that run is
  green and deployed nothing. Never treat "latest run green" as "product
  converged"; probe the URLs instead.
- `apps/web/wrangler.jsonc` is committed as the render of
  `wrangler.template.jsonc` from `wiring.fixture.json` (a placeholder
  project): edit the template and run `pnpm run wire:fixture`. The deploy
  lanes render the real one in their own job tree; never commit a real
  project's key.
- Row-level security guards every table in `public`: a user reads and writes
  only their own `profiles` row, and `stripe_customers` and
  `contact_requests` answer no API role at all — the server reaches them with
  the service-role key. Give a new table row-level security and the policies
  it needs in the same migration.
- A migration is immutable once applied: its checksum is in
  `packages/db/src/manifest.ts` and in the project's ledger. Change the
  schema with a NEW migration in `packages/db/src/migrations`, and update
  `apps/web/src/DatabaseDefinitions.ts` to match.
- Never read a secret through `$env/static/private`: it is inlined into the
  Worker's bundle at build time. `tests/web` fails if anything does.

## Secrets model

- **Brokered provider secrets**, minted per run from the workspace's
  connections — no long-lived values at rest, nothing to rotate by hand:
  `CLOUDFLARE_API_TOKEN` (the Worker's deploy and its secrets),
  `CLOUDFLARE_ACCOUNT_ID`, `SUPABASE_ACCESS_TOKEN` (the project, its Auth,
  the migrations) and `SUPABASE_ORG_ID`.
- **Published by the apply** onto the stage and prod rungs:
  `SUPABASE_PROJECT_REF`, `SUPABASE_DB_PASSWORD`, `SUPABASE_DB_URL`,
  `WIRING_SUPABASE`, `SUPABASE_SERVICE_ROLE_KEY`. The service-role key
  bypasses row-level security: only the environment's own deploy lane reads
  it, and it reaches the Worker as a secret, never a var or a bundle.
- **Optional, the owner's**: `STRIPE_API_KEY` (billing), `RESEND_API_KEY`,
  `ADMIN_EMAIL`, `FROM_ADMIN_EMAIL` (email), stored per environment as
  orun secrets and handed to the Worker as secrets by the next deploy. Until
  they exist the billing page says Stripe is not connected and no email is
  sent.
- Inspect by NAME only: `orun secrets list --org <ws> --project` and
  `--env stage|prod`. No tooling in this repository prints a secret value,
  and no document in `ai/context/` may contain one.

## Verifying the system

```bash
# the app and its project on each environment (also recorded, probed, in deployment.md)
curl -s -o /dev/null -w '%{http_code}\n' https://sveltekit-saas-web-stage.your-workers-subdomain.workers.dev/
curl -s https://sveltekit-saas-web-prod.your-workers-subdomain.workers.dev/api/health

# workspace readiness (integrations + repository link)
orun integrations list --org <ws> --json && orun cloud check --org <ws>
```

## Common operations

| task | how |
|---|---|
| deploy a change | merge to `main`; watch the run; failed lanes → `gh run rerun --failed` |
| deploy by hand | Orunbase's Deploy button, or `gh workflow run ci.yml --ref main -f environment=<env> [-f component=<a,b>]` — the named components (blank: every one) run in that environment as a merge runs them; started off `main` it is refused |
| connect Stripe | put your price ids in `apps/web/src/routes/(marketing)/pricing/pricing_plans.ts`, `orun secrets set STRIPE_API_KEY --env <env>`, then redeploy `web` (README, "Stripe") |
| turn on email | `orun secrets set RESEND_API_KEY --env <env>` and `ADMIN_EMAIL`, `FROM_ADMIN_EMAIL` likewise, then redeploy `web` (README, "Email") |
| change the schema | a new `packages/db/src/migrations/<nnn>_<name>/up.sql`, listed in the manifest (`pnpm --filter @saas/db run manifest:fix` for its checksum); merge — db-migrate applies it before the app deploys |
| require email confirmation | give the project SMTP of its own (Supabase → Authentication → SMTP), set `authEmailConfirmation: "true"` in `infra/terraform/supabase/component.yaml`, merge |
| add GitHub sign-in | README, "OAuth providers" |
| redeploy without a change | the Deploy button with no component, or edit the last line of the component's `component.yaml` (`# orun: redeploy <reason> <stamp>`) and merge — it is a deploy trigger, nothing reads it |
| remove a Worker secret | delete the orun secret, then `wrangler secret delete <NAME> --name sveltekit-saas-web-<env>`: the Worker keeps its copy until then |
| serve a custom domain | attach it to the Worker in Cloudflare, then set `SITE_URL` under the environment's `env:` in `intent.yaml` and replace the placeholder `sveltekit-saas.example.com` in its `BASE_DOMAIN` (README, "Custom domain") |
| headless credentials | `ORUN_TOKEN` (workspace-scoped) + `GITHUB_TOKEN` |

The deployment record is the bootstrap's `02-docs` phase. Re-running it (the
Orun console's Retry on that phase, or `orun new … --phase 02-docs`)
re-probes the URLs and re-renders [deployment.md](deployment.md); it is
idempotent.

## Evolution

Structural changes (a second Worker, a queue, another data store) follow the
same contract that deployed the product: add a component under `apps/`,
`infra/` or `packages/` with a `component.yaml` — declaring `dependsOn` on
any infrastructure whose published secrets it reads, enforced on main — land
it as a pull request, and the convergence run applies it.

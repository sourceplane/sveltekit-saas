# sveltekit-saas

Steve Cosman's [CMSaasStarter](https://github.com/scosman/CMSaasStarter) — a
SvelteKit SaaS template: a pre-rendered marketing site, a blog with an RSS
feed and search, a pricing page, sign-up and sign-in with Supabase Auth, an
account dashboard with profile, email, password and subscription settings,
Stripe Checkout and the billing portal, a contact form, and welcome and admin
email through Resend — running on **Cloudflare Workers + Static Assets**
through [`@sveltejs/adapter-cloudflare`](https://svelte.dev/docs/kit/adapter-cloudflare),
with a **Supabase** project per environment provisioned by Terraform through
[Orun](https://github.com/sourceplane/orun) and its schema applied by Orun's
`db-migrate` — and packaged as an **Orun baseline**: one command takes a new
product from nothing to live on stage and prod, in its own repository, under
its own name, in ONE landing.

The app is upstream's, page for page. What changed is where it runs and where
its settings come from: one Worker serves the pages SvelteKit pre-renders
from its static assets and renders the rest; the Supabase project's URL and
anon key are rendered into the Worker's config per environment and inlined
into its build; every secret — the service-role key, Stripe's and Resend's —
is a Worker secret, read at request time. Stripe and Resend are optional: the
site goes live without them and says what to connect. What the baseline adds
is everything needed to make a copy of it somebody else's — built the way
[cirrus-baseline](https://github.com/sourceplane/cirrus-baseline) builds a
product, in one landing. See [`specs/epics/sveltekit-saas`](specs/epics/sveltekit-saas/README.md)
for the design, the milestones and the as-built status, including every
departure.

## Instantiating a product

```bash
git clone --depth 1 --branch <baseline-tag> https://github.com/sourceplane/sveltekit-saas
cd sveltekit-saas
orun new --blueprint repo-blueprint.yaml --out ~/products/acme-saas --run-hooks --resume \
  --set reponame=acme-saas --set productname="Acme SaaS" \
  --set githuborg=acme-inc --set subdomain=<workers-dev-subdomain>
```

Or, once the platform's registry lists it, from the Orun console (Baselines →
`sveltekit-saas` → Build). Two phases: **`01-product`** creates the
repository, mints the four brokered credentials (Cloudflare and Supabase) and
lands the whole product as one pull request, whose convergence on `main`
provisions and deploys it per environment in a fixed order —

```
supabase ──▶ db-migrate ──▶ web
```

— each edge `mode: enforced` on a push to main and advisory on a pull
request; then **`02-docs`** records the live deployment from probed facts.
**[BOOTSTRAP.md](BOOTSTRAP.md)** is the operator guide;
[docs/phases/](docs/phases/README.md) has a page per phase.

The new repository receives the **product only** — the app, the Terraform
root, the migrations, the tests, its CI, its tooling, a README of its own and
its operating contract — renamed throughout to the product's name,
repository, Worker and Supabase project. None of this repository's machinery
ships. **Stripe and email are the owner's to connect afterwards** (the
product's README, "Stripe" and "Email"): no platform brokers them, so the
card asks for no Stripe or Resend key, and the site says what is missing.

| What makes it a baseline | Where |
|---|---|
| The console card (inputs, secrets, programme) | `blueprint.yaml` |
| The build document (modules, phases, hooks) | `repo-blueprint.yaml` |
| This tree's identity, the product's README and the bootstrap's task contracts | `.baseline/` |
| The rename engine (product-name seam: `apps/web/src/config.ts`) | `tooling/rebrand/rebrand.mjs` |
| The bootstrap's helpers (deferrals, redeploy marker, work-tree strip) | `tooling/bootstrap/` |
| The deployment-record renderer | `hooks/render-deployment-docs.sh` |
| The product's context pack | `ai/context/` |
| The baseline's tests: contract, leak, offline bootstrap and plans, end to end | `testing/`, `.github/workflows/baseline.yml` |
| Cutting a `baseline-vN` tag | `.github/workflows/tag.yml` |

## What is here

| Surface | Where |
|---|---|
| The marketing pages, the blog, pricing, search, contact | `apps/web/src/routes/(marketing)` |
| Sign-up, sign-in, password reset, the OAuth callback | `apps/web/src/routes/(marketing)/login`, `…/auth/callback` |
| The account dashboard and its settings, the profile step, billing | `apps/web/src/routes/(admin)/account` |
| The site's name, origin and description | `apps/web/src/config.ts` |
| The pricing plans (with their Stripe price ids) | `apps/web/src/routes/(marketing)/pricing/pricing_plans.ts` |
| Email (Resend) and its templates, precompiled at build | `apps/web/src/lib/mailer.ts`, `apps/web/src/lib/emails/` |
| Stripe, connected or not | `apps/web/src/lib/server/stripe.ts` |
| The health route the deploy's smoke reads | `apps/web/src/routes/api/health/+server.ts` |
| Workers build, bindings and deploy contract | `apps/web/svelte.config.js`, `vite.config.ts`, `wrangler.template.jsonc` + `wiring.fixture.json` (→ the committed `wrangler.jsonc`), `component.yaml` |
| The Supabase project and its Auth (stage, prod) | `infra/terraform/supabase` |
| The schema (upstream's migrations) and the runner that applies them | `packages/db`, run by `infra/db-migrate` |
| The wrangler renderer, the build's vars, the Worker-secrets helper | `tooling/wire` |
| Tests | `tests/web` (the Worker's config and secrets, then the app's own suite), `tests/db` (the migrations on a Supabase-shaped Postgres) |

## Getting started

```bash
pnpm install
pnpm run wire:fixture   # render apps/web/wrangler.jsonc from the offline fixture
pnpm typecheck
pnpm lint
pnpm test
pnpm build              # vite build → apps/web/.svelte-kit/cloudflare (the Worker and its assets)
```

To run it against a Supabase project of your own (a free one, or the stage
project a bootstrap created):

```bash
cd apps/web
cp .env.example .env              # PUBLIC_SUPABASE_URL and PUBLIC_SUPABASE_ANON_KEY
cp .dev.vars.example .dev.vars    # PRIVATE_SUPABASE_SERVICE_ROLE (and Stripe, Resend: optional)
pnpm dev                          # http://localhost:5173
```

`pnpm build` and `pnpm preview` (wrangler dev over the build) read the project
from `wrangler.jsonc` instead, so render it with your project for a local
build of your own, or leave the fixture for the offline checks. A project of
your own needs the schema: run the migrations in `packages/db/src/migrations`
in order in its SQL editor, or let a bootstrap's db-migrate apply them.

## Stripe

Billing is off until an environment has a Stripe secret key:

1. Create the products and prices in Stripe and put their ids in
   `apps/web/src/routes/(marketing)/pricing/pricing_plans.ts`
   (`stripe_price_id`, `stripe_product_id`), as upstream's README describes.
2. Store the secret key as the product's Orun secret `STRIPE_API_KEY` for the
   environment (`orun secrets set STRIPE_API_KEY --env stage`, or the
   console's Secrets) and redeploy it (Orunbase's Deploy button, or Run
   workflow on `main`).

The build hands the key to the Worker as a secret (`tooling/wire/worker-secrets.mjs`,
the value over stdin, never in a bundle); the billing page then opens Stripe
Checkout and the billing portal. Until then it says Stripe is not connected,
and checkout and the portal send visitors there. Removing the Orun secret
does not remove the Worker's copy: `wrangler secret delete
PRIVATE_STRIPE_API_KEY --name <worker>` too.

## Email

Welcome and admin emails go through [Resend](https://resend.com) once an
environment has `RESEND_API_KEY`, `ADMIN_EMAIL` (where admin notices go) and
`FROM_ADMIN_EMAIL` (a sender on a domain verified in Resend) as Orun secrets;
redeploy after setting them. Without them no email is sent, as upstream
behaves.

Supabase Auth's own email (confirmation, password reset) is the project's: a
new project's built-in SMTP mails only its organization's members, so the
Terraform root turns email confirmation off (`authEmailConfirmation:
"false"` in `infra/terraform/supabase/component.yaml`) and sign-up signs the
user straight in. Give the project SMTP of its own (Supabase → Authentication
→ SMTP), then set it to `"true"`; the next apply turns confirmation on.

## OAuth providers

The sign-in page offers email and password. To add GitHub (upstream's
default), create a GitHub OAuth app whose callback is
`https://<project-ref>.supabase.co/auth/v1/callback`, turn the provider on in
the environment's Supabase project (Authentication → Providers), and add
`"github"` to `oauthProviders` in `apps/web/src/routes/(marketing)/login/login_config.ts`.

## Custom domain

Each environment answers on its workers.dev URL. To serve one on a domain of
your own, attach the domain to the Worker in Cloudflare (Workers → the
Worker → Domains & Routes), then set `SITE_URL` under that environment's
`env:` in `intent.yaml` and merge: the next apply points the project's Auth
at it, and the next deploy builds the sitemap, the feed and the emails on it.
`BASE_DOMAIN` in `intent.yaml` holds the placeholder `<repo>.example.com`
until then.

## How it maps to adapter-auto and Vercel

| Upstream | Here |
|---|---|
| `@sveltejs/adapter-auto` | `@sveltejs/adapter-cloudflare` 7: one Worker, the pre-rendered pages and assets beside it, in one `wrangler deploy` |
| A Supabase project made by hand; `supabase db push` | `infra/terraform/supabase` per environment; upstream's two migrations applied by `infra/db-migrate` over the Management API before the Worker deploys |
| `PUBLIC_SUPABASE_URL`, `PUBLIC_SUPABASE_ANON_KEY` in `.env` | rendered into `wrangler.jsonc` from the root's wiring document, and handed to `vite build` from there (`tooling/wire/with-vars.mjs`) |
| `PRIVATE_SUPABASE_SERVICE_ROLE`, `PRIVATE_STRIPE_API_KEY` through `$env/static/private` (inlined at build) | Worker secrets read through `$env/dynamic/private`; the service-role key published by the root, Stripe's and Resend's optional Orun secrets |
| `new Stripe(key)` at module load | created per request with Stripe's fetch client; without a key the billing page says to connect Stripe |
| `handlebars.compile` per email | templates precompiled at build, rendered with the Handlebars runtime (Workers forbid code generation) |
| `WebsiteBaseUrl = "https://saasstarter.work"` | `PUBLIC_SITE_URL`: the environment's `SITE_URL`, or its workers.dev URL |
| The welcome email from `no-reply@saasstarter.work` | from `FROM_ADMIN_EMAIL`, the owner's own verified sender |
| GitHub sign-in on by default | email and password; GitHub once its OAuth app is set up (above) |
| `patch-package` for a SvelteKit 2.55 bug | not needed on SvelteKit 2.70 |
| Deploy on push (Vercel) | Orun applies the project, migrates it and deploys `<repo>-web-{stage,prod}` on merge to `main`, smoke-tested through `/api/health` |

## How the project reaches the Worker

```
infra/terraform/supabase ──apply──► WIRING_SUPABASE (url, anon key) · SUPABASE_SERVICE_ROLE_KEY
                                    · SUPABASE_PROJECT_REF · SUPABASE_DB_PASSWORD · SUPABASE_DB_URL
        ▼
infra/db-migrate  dependsOn supabase (enforced on main)
  apply:  packages/db's runner → POST api.supabase.com/v1/projects/<ref>/database/query, each pending migration once
        ▼
apps/web  dependsOn supabase + db-migrate (enforced on main) · secretEnv WIRING_SUPABASE_<ENV>
  build:  tooling/wire/live.mjs → wrangler.jsonc vars → vite build (the project inlined)
          → worker-secrets.mjs: the service-role key, Stripe and Resend as Worker secrets
  smoke:  / renders to </html>; /api/health counts profiles with the service-role key
```

`wrangler.jsonc` is committed as the fixture render of
`wrangler.template.jsonc`, because the deploy lane's `verify-app-structure`
step checks the config exists before it builds.

## CI

| Workflow | What it runs | Ships to a product |
|---|---|---|
| `ci.yml` | the Orun pipeline, and the only workflow a product carries: `orun plan --changed`, then one job per lane. A pull request runs the verify lanes (the packages type-checked, linted, tested and built, both test suites, the Supabase root planned, the migrations planned offline, the Worker built and dry-deployed per environment), except the bootstrap's own landings (`orun/BASE-*`), where `plan` alone runs and nothing waits for it — the landing was checked in the build box; a merge applies the project, migrates it, then deploys stage → prod. It plans nothing while `intent.yaml` names the placeholder workspace `ws_CHANGE_ME`, as this repository does. A manual run (Orunbase's Deploy button, or Run workflow on `main`) plans the environment and components it names under the push-to-main trigger, so they deploy as a merge deploys them | yes |
| `baseline.yml` | the baseline's own tiers: contract tests; the blueprint read by the pinned orun, the leak gate, the offline bootstrap and the product's own plans; the product built, migrated into a local stand-in for a Supabase project, dry-deployed, served, and taken from sign-up to a deleted account | no |
| `tag.yml` | cuts a `baseline-vN` tag (manual) | no |

## Licence

CMSaasStarter is © 2023 Steve Cosman, under the MIT License
([`apps/web/LICENSE`](apps/web/LICENSE)). The port keeps it.

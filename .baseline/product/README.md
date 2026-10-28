# sveltekit-saas

Steve Cosman's [CMSaasStarter](https://github.com/scosman/CMSaasStarter) — a
SvelteKit SaaS: a pre-rendered marketing site, a blog with an RSS feed and
search, a pricing page, sign-up and sign-in with Supabase Auth, an account
dashboard with profile, email, password and subscription settings, Stripe
Checkout and the billing portal, a contact form, and welcome and admin email
through Resend — on **Cloudflare Workers + Static Assets** through
[`@sveltejs/adapter-cloudflare`](https://svelte.dev/docs/kit/adapter-cloudflare),
with a **Supabase** project per environment for its Auth and its data.
Terraform provisions each project and Orun's `db-migrate` applies the schema,
all on every merge to `main`.

## Live deployment

<!-- 02-docs:begin -->
Not recorded yet. The bootstrap's last phase writes the live URLs, the
workspace, whether Stripe and email are connected and the secrets the
product uses into [ai/context/deployment.md](ai/context/deployment.md); how
the product deploys and how to operate it is in
[ai/context/operations.md](ai/context/operations.md).
<!-- 02-docs:end -->

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

## How it deploys

Merges to `main` converge through [Orun](https://github.com/sourceplane/orun):
`.github/workflows/ci.yml` plans the changed components and runs each lane
against the workspace in `intent.yaml`. Per environment the order is
enforced — **the Supabase project, then the migrations, then the Worker** —
because each reads what the one before it published: the project's ref and
credentials, its URL and keys, the schema the app reads. `stage` deploys
first and `prod` once stage has converged on the same commit; `dev` only
verifies. Every deploy is smoke-tested over HTTP: the home page renders, and
`/api/health` answers only when the Worker reaches its project with the
service-role key and finds the schema.

The pipeline holds one credential, GitHub's own `GITHUB_TOKEN`. The
Cloudflare token and account id and the Supabase access token and org id are
brokered per run from the workspace's connections; the project's credentials,
its URL and anon key and its service-role key are published by the Terraform
apply as orun secrets; Stripe's and Resend's keys are orun secrets you add.
Nothing provider-shaped is stored in the repository or in GitHub.

**Deploy by hand.** Orunbase's **Deploy** button on a component, or **Run
workflow** on the CI workflow in GitHub's Actions tab (on `main`), runs
`ci.yml` for the environment and components you pick, and each one deploys
exactly as a merge would deploy it. Leave the component blank to redeploy
every component in that environment, with nothing changed: after adding a
Stripe key, say. A component with nothing to run in that environment (a test
suite in `prod`) is left out with a notice.

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

## CI

| Workflow | What it runs |
|---|---|
| `ci.yml` | the Orun pipeline, and the only workflow: `orun plan --changed`, then one job per lane. A pull request runs the verify lanes — the app built and dry-deployed for each environment, the packages type-checked and built, both test suites, the Supabase root planned, the migrations planned and their checksums verified — with nothing applied or deployed; a merge applies the project, migrates it and deploys stage → prod. A manual run (Deploy, or Run workflow on `main`) deploys the components you name |

## Licence

CMSaasStarter is © 2023 Steve Cosman, under the MIT License
([`apps/web/LICENSE`](apps/web/LICENSE)). The port keeps it.

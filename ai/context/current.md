# sveltekit-saas — where this repository stands

The entry page for anyone (or any agent) picking this repository up. It is
this repository's own state and does not ship to a product built from it;
the two pages that do are [operations.md](operations.md) and
[deployment.md](deployment.md).

## What it is

Steve Cosman's CMSaasStarter — a SvelteKit SaaS: a pre-rendered marketing
site, a blog with RSS and search, pricing, Supabase Auth, an account
dashboard, Stripe billing and Resend email — on Cloudflare Workers + Static
Assets through `@sveltejs/adapter-cloudflare`, with a Supabase project per
environment from Terraform and its schema (upstream's two migrations)
applied by db-migrate. It is packaged as an Orun baseline: `orun new
--blueprint repo-blueprint.yaml` builds a new product in its own repository
and takes it to live on stage and prod in one landing (`01-product`: the
Supabase project, then the migrations, then the app), then records what went
live (`02-docs`). Stripe and email are the owner's to connect afterwards; the
app deploys, signs users up and serves without them.

## Release

| | |
|---|---|
| Latest tag | `baseline-v1` (SV4, the baseline) |
| Proven live | No. Everything short of the platform is proven offline in Baseline CI: the e2e tier migrates a local Postgres with Supabase's roles through the product's own runner, builds in orun's staged job tree, serves the Worker under `wrangler dev` against a stand-in Supabase, and signs a user up, through the profile step to the account pages, with no Stripe or Resend key. No bootstrap from a tag has run against a workspace: the Supabase root has not been applied, db-migrate has not run against a real project, nothing has deployed, and the card's fourteen minutes is unmeasured (SV-H) |

## Where to read

| Question | Page |
|---|---|
| What shipped, and every departure from upstream | `specs/epics/sveltekit-saas/IMPLEMENTATION-STATUS.md` |
| Why it is built this way | [decisions.md](decisions.md), then `specs/epics/sveltekit-saas/design.md` |
| What could still go wrong | [open-risks.md](open-risks.md), then `specs/epics/sveltekit-saas/risks-and-open-questions.md` |
| How to instantiate it | `BOOTSTRAP.md`, `docs/phases/` |
| What each component is | `<component>/docs/` beside each `component.yaml` — `apps/web`, `packages/db`, `infra/db-migrate`, `infra/terraform/supabase`, `tests/{web,db}` (generated; `python3 tooling/catalog/gen-component-docs.py`) |

## Next

1. Bootstrap one product from `baseline-v1` against a workspace with
   Cloudflare and Supabase connected, and record its timings (closes SV-H;
   settles SV-A — upstream's `auth.users` trigger and Storage policies
   applied through the Management API on a real project).

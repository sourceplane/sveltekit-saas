# Epic: sveltekit-saas (SV)

**CMSaasStarter is a SvelteKit 2 app built for adapter-auto with Supabase behind it. On Cloudflare the adapter is `@sveltejs/adapter-cloudflare`: the build emits one Worker with the pre-rendered marketing pages and the hashed assets beside it in Workers Static Assets. Each environment gets its own Supabase project from Terraform through Orun (supabase-starter's `supabase` root): the project's URL and anon key reach the Worker through the wiring document the root publishes, rendered into `wrangler.jsonc` and inlined into the build, and its service-role key becomes a Worker secret. Upstream's two Supabase migrations become db-migrate migrations applied over the Management API before the Worker deploys.**

The port keeps the marketing site, the blog with its RSS feed, the build-time search index, the pricing page, the sign-up, sign-in, password-reset and OAuth callback flows, the profile step, the account dashboard and its settings, the contact form, the Stripe checkout and billing portal, and the welcome and admin emails. Stripe and Resend become optional Orun secrets: a product goes live without either, and its pages say what to connect.

## Status

| Field | Value |
|-------|-------|
| Status | SV0 in progress |
| Cluster | **SV** (SV0–SV4) |
| Owner(s) | `apps/web` (the SvelteKit app) · `tests/web` · `infra/terraform/supabase` · `packages/db` + `infra/db-migrate` · `tests/db` |
| Builds on | `sveltekit-boilerplate` (a SvelteKit app on adapter-cloudflare, one Worker with Static Assets), `supabase-starter` (the `supabase` root, its Auth settings and wiring, the Supabase stand-in its e2e runs against), `saas-starter` (the migration runner over the Management API and `db-migrate`), `cirrus-baseline` (the `@@wiring(...)@@` deploy-time render) |
| Upstream | [scosman/CMSaasStarter](https://github.com/scosman/CMSaasStarter) (MIT), at `2e61406` (2026-03-21) |
| Changes | adapter-auto → adapter-cloudflare; secrets read at request time (`$env/dynamic/private`) instead of inlined; the Supabase project, its Auth and its schema from Orun; Stripe and Resend optional; email templates precompiled (Workers forbid code generation) |
| Gate | SV1 is the first user-visible rung. SV2 applies only with a linked workspace; verified by `terraform validate` and the migrations run into a real Postgres with Supabase's roles |

## Read order

1. `design.md` — what maps to what, the wiring flow, what is out of scope
2. `implementation-plan.md` — the milestones and what "done" means for each
3. `risks-and-open-questions.md` — what could go wrong and what was decided
4. `IMPLEMENTATION-STATUS.md` — what actually shipped (kept distinct from intent)

## Milestones at a glance

| Milestone | What it lands | Done when |
|---|---|---|
| SV0 — the spec | intent, CI, tooling, the spec index, this doc set and the task contracts | merged on `main` |
| SV1 — the app on Workers | `apps/web` (the template on adapter-cloudflare), the rendered wrangler config, `tests/web` | `wrangler dev` serves the pre-rendered pages, the login pages and `/api/health` from the built Worker |
| SV2 — the Supabase project and its schema | `infra/terraform/supabase`, `packages/db`, `infra/db-migrate`, `tests/db` | the root validates; the migrations apply into a real Postgres and a second apply applies nothing |
| SV3 — ready to instantiate | README, as-built status | a reader can run, test, preview, connect Stripe and Resend, and deploy it |
| SV4 — a baseline | card, build document (`01-product` + `02-docs`), rename, bootstrap tooling, tests | a new SaaS goes from nothing to live in one landing; Baseline CI green |

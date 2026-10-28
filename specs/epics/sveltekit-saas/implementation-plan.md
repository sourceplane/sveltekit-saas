# sveltekit-saas — implementation plan

Milestones land in order; each is one pull request into `main`, squash-merged
once its CI is green.

## SV0 — the spec

Intent (workspace `ws_CHANGE_ME`), `ci.yml` (turso-starter's, carrying the
manual-deploy contract), the shared tooling (TypeScript, ESLint, the wrangler
renderer, the Worker-secrets helper, the migration manifest check), the spec
index, this doc set and the task contracts.

**Done when** the five documents, `epic.yaml` and `tasks/SV-1..SV-5` are on `main`.

## SV1 — the app on Workers

`apps/web`: upstream's `src/`, `static/` and configuration on
adapter-cloudflare; the wrangler template (the Supabase vars) and its fixture;
secrets through `$env/dynamic/private`; Stripe's fetch client; precompiled
email templates; `/api/health`; `tests/web`.

**Done when**
- `pnpm install && pnpm run wire:fixture && pnpm typecheck && pnpm lint && pnpm test && pnpm build` is green
- `wrangler dev` over the build serves `/`, `/blog`, `/pricing`, `/login/sign_in`, `/search/api.json` and `/api/health`

## SV2 — the Supabase project and its schema

`infra/terraform/supabase` (supabase-starter's root, publishing the
service-role key too), `packages/db` (upstream's two migrations and the runner
over the Management API), `infra/db-migrate`, `tests/db`.

**Done when** `terraform validate` passes, and the migrations apply into a
real Postgres carrying Supabase's roles and `auth` and `storage` schemas, a
second apply applying nothing.

## SV3 — ready to instantiate

The README (run, test, preview, connect Stripe and Resend, OAuth, custom
domain, deploy) and the as-built status.

## SV4 — a baseline

`blueprint.yaml`, `repo-blueprint.yaml` (`01-product`, `02-docs`), the rename
engine and the bootstrap helpers, the context pack, the phase cards, the
baseline's tests and its workflows.

**Done when** Baseline CI is green, its e2e signing a user up and taking them
through the profile step to the account pages under `wrangler dev`.

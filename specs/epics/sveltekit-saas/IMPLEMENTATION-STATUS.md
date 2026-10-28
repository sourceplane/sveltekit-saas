# sveltekit-saas — implementation status

As built, kept apart from the plan.

| Milestone | State | Pull request |
|---|---|---|
| SV0 — the spec | ✅ shipped | [#1](https://github.com/sourceplane/sveltekit-saas/pull/1) |
| SV1 — the app on Workers | ✅ shipped | [#2](https://github.com/sourceplane/sveltekit-saas/pull/2) |
| SV2 — the Supabase project and its schema | ✅ shipped | [#3](https://github.com/sourceplane/sveltekit-saas/pull/3) |
| SV3 — ready to instantiate | in progress | — |
| SV4 — a baseline | planned | — |

## Departures from upstream (scosman/CMSaasStarter at `2e61406`)

Everything not listed here is upstream's, file for file.

| Where | Upstream | Here | Why |
|---|---|---|---|
| `svelte.config.js` | `adapter-auto` | `@sveltejs/adapter-cloudflare` 7, `platformProxy` on `wrangler.jsonc` | Workers + Static Assets |
| `package.json` | `adapter-auto`, `patch-package` | `adapter-cloudflare`, `wrangler`; no `patch-package` (the SvelteKit 2.55 bug it patched does not reproduce on 2.70); `fuse.js ~7.0.0` and `prettier ~3.4.2` / `prettier-plugin-svelte ~3.3.2`, the versions upstream's lockfile resolved | newer fuse.js breaks the search page's types; newer prettier reformats upstream's files |
| scripts | `vite build`, `svelte-check`, `vitest` | each run through `tooling/wire/with-vars.mjs`, which hands `wrangler.jsonc`'s vars to the command | `$env/static/public` is inlined at build: the build reads the project it deploys against |
| `hooks.server.ts`, `lib/mailer.ts`, the Stripe routes | `$env/static/private` (inlined at build) | `$env/dynamic/private` (request time) | secrets are Worker secrets, never in a bundle |
| `hooks.server.ts` | `createClient(url, serviceRole)` | the same, or — with no key set — a client whose every use fails naming the key | public pages keep working on a local run without `.dev.vars` |
| Stripe routes | `new Stripe(key)` at module load | `lib/server/stripe.ts`: per request, Stripe's fetch client; no key → the billing page says to connect Stripe, checkout and the portal send the visitor there | Workers have no Node `http`; the site goes live before Stripe is connected |
| `lib/mailer.ts` | `handlebars.compile` per email | `lib/emails/templates.ts`: templates precompiled at build by a Vite plugin (`vite.config.ts`), rendered with `handlebars/runtime` | Workers forbid generating code from strings |
| `config.ts` | `WebsiteBaseUrl = "https://saasstarter.work"` | from `PUBLIC_SITE_URL`: the environment's `SITE_URL` or its workers.dev URL; `http://localhost:5173` locally | the product's own origin, per environment |
| `account/api/+page.server.ts` | welcome email from `no-reply@saasstarter.work`, company name `"SaaS Starter"` | from `PRIVATE_FROM_ADMIN_EMAIL` (or `PRIVATE_ADMIN_EMAIL`), skipped without one; `WebsiteName` | Resend sends only from a verified domain of the owner's |
| `login/login_config.ts` | `oauthProviders = ["github"]` | `[]` | a provider fails until its OAuth app is set up in the project (README, "OAuth providers") |
| `routes/api/health/+server.ts` | — | new: counts `profiles` with the service-role key | the deploy's smoke |
| `routes/(admin)/account/(menu)/billing` | — | `stripeConnected` in the load, a notice on the page | Stripe is optional |
| `supabase/migrations/*.sql` | applied by `supabase db push` | `packages/db/src/migrations/010_initial`, `020_add_unsubscribed_to_profiles`, byte for byte, applied by `infra/db-migrate` | Orun applies the schema per environment |
| `database_migration.sql`, `checks.sh`, `.github/`, the docs pages | — | not ported | the repository's own tooling replaces them |

## Proven offline

- `pnpm install --frozen-lockfile`, `wire:fixture`, `typecheck`, `lint`, `test`, `build` green.
- The built Worker (487 KiB gzipped) under `wrangler dev`: every marketing page, the blog, the feed, the sitemap and the search index; `/account` → `/login`; an unknown path is a 404; `/api/health` 503 without the service-role key.
- The migrations through the runner into PGlite with Supabase's roles, `auth` and `storage` stood in: applied once, a second apply nothing; the profile trigger, row-level security, the bucket.
- `terraform validate` on the Supabase root; `orun plan` for a merge: supabase → db-migrate → web.

## Not proven here

The project's apply, the migrations against a real project (risk SV-A), the
service-role key's publication and the live deploy need a linked workspace
(risk SV-H).

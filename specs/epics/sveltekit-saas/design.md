# sveltekit-saas — design

## What maps to what

| Upstream (Vercel or any adapter-auto host) | Here |
|---|---|
| `@sveltejs/adapter-auto` | `@sveltejs/adapter-cloudflare`: one Worker (`.svelte-kit/cloudflare/_worker.js`) with the pre-rendered pages and `_app/` assets beside it, deployed in one `wrangler deploy` |
| A Supabase project created by hand, `supabase link` + `supabase db push` | `infra/terraform/supabase` creates one project per environment and sets its Auth (Site URL, redirect allow-list, email confirmation); `packages/db` + `infra/db-migrate` apply upstream's `supabase/migrations` over the Management API before the Worker deploys |
| `PUBLIC_SUPABASE_URL`, `PUBLIC_SUPABASE_ANON_KEY` in `.env` | rendered per environment into `wrangler.jsonc` `vars` from the root's wiring document (`WIRING_SUPABASE_<ENV>`), and handed to `vite build` from that render so `$env/static/public` inlines the same project into the browser bundle and the Worker |
| `PRIVATE_SUPABASE_SERVICE_ROLE` in `.env`, read through `$env/static/private` (inlined at build) | published by the root as the Orun secret `SUPABASE_SERVICE_ROLE_KEY`, pushed to the Worker as a secret by the deploy lane (`tooling/wire/worker-secrets.mjs`), read at request time through `$env/dynamic/private` |
| `PRIVATE_STRIPE_API_KEY` | the optional Orun secret `STRIPE_API_KEY` → Worker secret; Stripe's fetch HTTP client; unset, the pricing, checkout and billing pages say to connect Stripe |
| `PRIVATE_RESEND_API_KEY`, `PRIVATE_ADMIN_EMAIL`, `PRIVATE_FROM_ADMIN_EMAIL` | optional Orun secrets → Worker secrets; unset, no email is sent (upstream's behaviour) |
| `handlebars.compile` at request time | templates precompiled at build (a Vite plugin) and rendered with `handlebars/runtime`: Workers forbid generating code from strings |
| The search index written into the client output after the build | the same, inside the Worker's static assets (`/search/api.json`) |
| Deploy on push (Vercel) | Orun applies the project, migrates it and deploys `<repo>-web-{stage,prod}` on merge to `main` |

## The wiring flow

```
infra/terraform/supabase ──apply──► WIRING_SUPABASE (url, anon key) · SUPABASE_SERVICE_ROLE_KEY ·
                                    SUPABASE_PROJECT_REF · SUPABASE_DB_PASSWORD · SUPABASE_DB_URL
        │
        ▼
infra/db-migrate  dependsOn supabase (enforced on main)
  apply: packages/db's runner → POST api.supabase.com/v1/projects/<ref>/database/query
        │
        ▼
apps/web  dependsOn supabase + db-migrate (enforced on main)
  build: tooling/wire/live.mjs → wrangler.jsonc vars (url, anon key) → vite build (inlined)
         → worker-secrets.mjs: SUPABASE_SERVICE_ROLE_KEY, STRIPE_API_KEY, RESEND_API_KEY … as Worker secrets
  deploy: wrangler deploy → smoke: the home page, and /api/health answered by the Worker
```

## Out of scope

- OAuth providers. Upstream offers GitHub sign-in, which needs an OAuth app configured in the project; the port ships email and password only, and the README says how to turn GitHub on.
- Stripe products and prices. The pricing plans keep upstream's shape; an owner puts their own price ids in `pricing_plans.ts`.
- Supabase Storage. Upstream's migration creates an `avatars` bucket the app never reads; it is applied as written.

# apps/web

[CMSaasStarter](https://github.com/scosman/CMSaasStarter) (MIT, © 2023 Steve
Cosman — see [LICENSE](LICENSE)) on Cloudflare Workers + Static Assets through
`@sveltejs/adapter-cloudflare`.

```bash
pnpm install                       # from the repository root
pnpm --filter @app/web wire:fixture   # render wrangler.jsonc from the fixture
cp apps/web/.env.example apps/web/.env            # your project's URL and anon key, for `vite dev`
cp apps/web/.dev.vars.example apps/web/.dev.vars  # its service-role key (and Stripe / Resend, optional)
pnpm --filter @app/web dev         # http://localhost:5173
pnpm --filter @app/web build       # vite build → .svelte-kit/cloudflare (the Worker and its assets)
pnpm --filter @app/web preview     # wrangler dev over the build
```

`pnpm build` reads the Supabase project's URL and anon key from
`wrangler.jsonc` (`tooling/wire/with-vars.mjs`), so the build always inlines
the project the Worker is configured for. Secrets are never inlined: the
Worker reads them at request time (`$env/dynamic/private`).

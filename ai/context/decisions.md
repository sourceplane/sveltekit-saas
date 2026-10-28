# sveltekit-saas — decisions

The choices that shape this repository, one line each, with where the full
reasoning lives. Superseded decisions stay listed, marked, so the history
reads in order.

| # | Decision | Why | Source |
|---|---|---|---|
| 1 | `@sveltejs/adapter-cloudflare` 7 on SvelteKit 2, upstream's dependency ranges otherwise kept (fuse.js and prettier on the versions upstream's lockfile resolved) | Only what Workers needs changes; newer fuse.js breaks the search page's types, newer prettier reformats upstream's files | IMPLEMENTATION-STATUS (departures) |
| 2 | The project's URL and anon key are vars in `wrangler.jsonc`, rendered per environment from `WIRING_SUPABASE`, and handed to `vite build` by `tooling/wire/with-vars.mjs` | `$env/static/public` is inlined at build: the browser bundle and the Worker must name the project the Worker is configured for | design.md, risk SV-C |
| 3 | Every secret through `$env/dynamic/private`, as a Worker secret pushed by the deploy lane (`worker-secrets.mjs`, over stdin) | `$env/static/private` would inline secrets into the bundle | risk SV-C |
| 4 | The Supabase root publishes the service-role key (`SUPABASE_SERVICE_ROLE_KEY`), which only that environment's deploy lane reads | Upstream's server uses it (the contact form, Stripe customers, account deletion); it bypasses row-level security, so it is never a var | risk SV-B |
| 5 | Upstream's two `supabase/migrations` files, byte for byte, applied by the `@saas/db` runner (db-migrate) through Supabase's Management API | The token is already brokered; the SQL is upstream's, and `tests/db` holds the checksums to upstream's files | design.md, risk SV-A |
| 6 | Email templates precompiled at build (a Vite plugin), rendered with `handlebars/runtime` | Workers forbid generating code from strings | risk SV-D |
| 7 | Stripe and Resend optional: no key, the billing page says to connect Stripe and no email is sent | A bootstrapped product is deployed by a convergence nobody attends, and no platform brokers either | README ("Stripe", "Email") |
| 8 | Email confirmation off by default; OAuth providers empty by default | A new project's SMTP mails only its organization; an OAuth provider fails until its app exists | risks SV-E, SV-F |
| 9 | Infra before app on main: supabase → db-migrate → web, enforced; advisory on a pull request | Each component reads what the one before it published; a migration is the one step a re-run cannot take back | `repo-blueprint.yaml`, component manifests |
| 10 | One landing (`01-product`) then the record (`02-docs`); `ci.yml` plans nothing while `intent.yaml` names `ws_CHANGE_ME`; no `checks.yml` | The turso-starter v8 shape on orun v2.88.0 | `repo-blueprint.yaml` |
| 11 | stack-tectonic 0.19.0, not 0.20.0 | Every job installs inside its own tree; the app has one job per lane, so a shared install saves nothing | `intent.yaml` |
| 12 | Component docs are generated from the manifests and checked in CI | A hand-written copy of the dependency graph and bindings drifts silently | `tooling/catalog/gen-component-docs.py` |
| 13 | `subdomain` is read from the Cloudflare connection, never asked; the console asks for no domain | It has one right answer per account; a domain is an owner's step after the bootstrap | `blueprint.yaml`, `tooling/rebrand/rebrand.mjs` |

# sveltekit-saas — risks and open questions

| # | Risk / question | Decision |
|---|---|---|
| SV-A | Upstream's migration creates a trigger on `auth.users` and policies on `storage.objects`; whether the Management API's query role may do both on a new project is Supabase's to decide. | Applied as written, the way `supabase db push` applies it; proven offline against a Postgres with Supabase's roles; a live bootstrap is the proof. |
| SV-B | The service-role key bypasses row-level security. | Published by the root as an Orun secret of its own environment, resolved only by that environment's deploy lane, pushed to the Worker as a secret over stdin; never a var, never in a bundle. |
| SV-C | `$env/static/private` inlines secrets into the server bundle. | Every secret is read through `$env/dynamic/private` at request time. |
| SV-D | Workers forbid code generation, and `handlebars.compile` generates code. | Templates are precompiled at build and rendered with the runtime alone. |
| SV-E | A new project's built-in SMTP mails only its organization's members, so email confirmation would block every other sign-up. | The root turns confirmation off by default (supabase-starter's `authEmailConfirmation`), and the README says when to turn it on. |
| SV-F | Upstream's GitHub sign-in needs an OAuth app no bootstrap can create. | Email and password only by default; the README says how to add GitHub. |
| SV-G | Upstream's last commit is seven months old. | Dependencies stay on upstream's ranges; only what Workers needs is added or changed, and each change is recorded. |
| SV-H | The project apply, the migrations and the live deploy are proven only by a live bootstrap. | Offline: `terraform validate`, the runner against a stand-in Management API over a real Postgres, and the Worker served by `wrangler dev` against a stand-in Supabase. |

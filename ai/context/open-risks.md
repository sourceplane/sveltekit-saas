# sveltekit-saas — open risks

What is not yet proven or not yet decided. The full write-up of every risk,
including the accepted and resolved ones, is
`specs/epics/sveltekit-saas/risks-and-open-questions.md`; this page lists only
what is still live, so it should be short.

| ID | Risk | State | What closes it |
|---|---|---|---|
| SV-A | Upstream's migration creates a trigger on `auth.users` and policies on `storage.objects`; whether the Management API's role may do both on a new project is unobserved here | OPEN | One bootstrap's db-migrate lane against a real project |
| SV-H | No bootstrap has been timed (the card's fourteen minutes is summed from estimates); the Supabase root has not been applied from this repository, and nothing has deployed | OPEN | One bootstrap from a tag against a workspace with Cloudflare and Supabase connected |

Accepted, and worth knowing before you change them: SV-B (the service-role
key is published and becomes a Worker secret), SV-C (no secret through
`$env/static/private`), SV-D (precompiled email templates), SV-E (email
confirmation off until the project has SMTP), SV-F (no OAuth provider by
default), SV-G (upstream's dependency ranges kept).

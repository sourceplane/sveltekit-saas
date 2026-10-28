# supabase

Provisions Supabase projects for stage and prod, points their Auth at the app, and wires the URL and keys into orun secrets

Terraform-managed infrastructure, planned and applied per environment by its CI lane.

|              |                                                                                                      |
| ------------ | ---------------------------------------------------------------------------------------------------- |
| Type         | `terraform`                                                                                          |
| Source       | `infra/terraform/supabase`                                                                           |
| Environments | `stage`: `plan-only`, `apply` on a push to `main` · `prod`: `plan-only`, `apply` on a push to `main` |

## Depends on

- (none)

## Depended on by

- **db-migrate** — Applies the SaaS schema (packages/db's migrations) to the stage and prod Supabase projects
- **web** — The SaaS site (SvelteKit on Cloudflare Workers + Static Assets via @sveltejs/adapter-cloudflare, per environment)

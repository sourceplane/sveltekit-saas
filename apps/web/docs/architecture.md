# web — architecture

Built by the turbo pipeline from `apps/web` and deployed with wrangler.

|                     |                                     |
| ------------------- | ----------------------------------- |
| Worker config       | `apps/web/wrangler.template.jsonc`  |
| Entry               | `.svelte-kit/cloudflare/_worker.js` |
| Compatibility date  | `2026-10-01`                        |
| Compatibility flags | `nodejs_compat`                     |

## Bindings

| Binding  | Kind          | Source                   |
| -------- | ------------- | ------------------------ |
| `ASSETS` | Static assets | `.svelte-kit/cloudflare` |

## Variables

`PUBLIC_SUPABASE_ANON_KEY`, `PUBLIC_SUPABASE_URL`.

## Wiring

Resolved at deploy time from secrets the infrastructure lanes publish (names only):

- `WIRING_SUPABASE_PROD`
- `WIRING_SUPABASE_STAGE`

## Secrets resolved by the lane (names only)

- `PRIVATE_ADMIN_EMAIL` (optional)
- `PRIVATE_FROM_ADMIN_EMAIL` (optional)
- `PRIVATE_RESEND_API_KEY` (optional)
- `PRIVATE_STRIPE_API_KEY` (optional)
- `PRIVATE_SUPABASE_SERVICE_ROLE` (optional)

# Epics

Orun-style work programs. Each epic is a folder carrying `epic.yaml` (the
declaration the platform reads: slug, key prefix, milestones with exit
criteria and task keys) beside its doc set. The pull request that adds the
folder is the adoption; the merge creates the epic in the workspace.

| Epic | Cluster | Status | What it is |
|------|---------|--------|------------|
| [`sveltekit-saas/`](./sveltekit-saas/) | **SV** | Shipped | Steve Cosman's CMSaasStarter — a SvelteKit SaaS with marketing pages, a blog, search, pricing, Supabase Auth, an account dashboard, Stripe billing and Resend email — equivalent in code and function on Cloudflare Workers + Static Assets with a Supabase project per environment, and an Orun baseline that instantiates it in one landing |

As-built ≠ intent: what shipped lives in each epic's `IMPLEMENTATION-STATUS.md`.

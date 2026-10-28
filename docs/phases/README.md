# The phases — one blueprint, two selections, one landing that deploys

`repo-blueprint.yaml` declares two phases that take a SaaS product from
**nothing** to **live on stage and prod, documented**. Run them one at a time
with `--phase <name>`, or both unattended with `--resume`. There is no
umbrella workflow and no per-phase document: a phase is a selection on one
artifact, which is what makes running one alone, months later, from a fresh
container the same operation as running them all.

Each phase follows the same contract:

> **place its modules → brand them → check them in the box and land them as
> one pull request → watch the convergence that merge triggers
> (auto-resumed) → verify the outcome.**

The run's task set-up — the epic, a milestone per phase, a task per landing
— runs in the background from the start; the first hook that needs it, the
phase's `task`, waits for it.

Run from the baseline checkout (the blueprint's source is `path: .`); the
product's repository is wherever `--out` points.

## Execution order

| phase | lands | verified by |
|---|---|---|
| [`01-product`](01-product.md) | **the GitHub repo created**, then the WHOLE product in one PR: intent, CI, tooling, the Supabase Terraform root, the migrations, the app and its tests — one convergence provisions and deploys it in dependency order | convergence green (each component resolving what the apply before it published); `/` and `/api/health` answer on both |
| [`02-docs`](02-docs.md) | the live-deployment record; the promotion gate and dev's lanes put back | committed manifest matches probed reality |

**One landing builds the product.** The order the data plane needs — the
Supabase project before the migrations, both before the app — is not a
sequence of landings. It is the components' own `dependsOn`, every edge
`mode: enforced` on a push to `main` and advisory on a pull request:

```
supabase ──▶ db-migrate ──▶ web        (per environment)
```

A job resolves its secrets when it starts, so each one reads what the apply
before it published: db-migrate the project's ref and credentials, the app's
deploy the project's URL, anon key and service-role key.
`testing/placement.test.sh` reads that order off the product's own
`orun plan --trigger github-push-main`. Each job reads them from the place
every later run looks, and a missing one fails its lane, so a green
convergence already says all of it is there — there is no separate check.

Every landing is a pull request on a branch named for its task
(`orun/BASE-<n>-<phase>`), checked before it is pushed: `orun validate`, then
`orun plan` as the pull request and as the merge would plan it, in the box,
in under a second (`checks: local`). Then it merges; nothing waits for the
PR's CI. On those branches `ci.yml` runs `plan` only and skips the lanes,
because the merge runs them on main a minute later, for real, and that
convergence is what the phase watches. The product carries no other
workflow: the baseline's own CI (Tier 2) installs, renders the fixture,
type-checks, lints, tests and builds this landing before a tag is cut, and
every later pull request in the product runs `ci.yml`'s verify lanes.

There is no custom-domain phase: the app answers on workers.dev. Attaching a
domain needs zone permissions the brokered `workers-deploy` token does not
carry, so it is an owner's step after the bootstrap (the product's README,
"Custom domain").

## Inputs

`01-product` takes the product's identity once and writes it into the repo
(`.rebrand/values.json`); `02-docs` reads it back from the placed tree. But
the blueprint's **required** inputs — `reponame`, `productname`,
`githuborg` — are validated before any phase runs, so they must be supplied
on every invocation, single-phase ones included. A `--values` file is easier
than repeating `--set`.

- `productdomain` — NOT ASKED, default empty. The app goes live on
  workers.dev; empty brands the reserved placeholder `<reponame>.example.com`
  into `BASE_DOMAIN`, for an owner to replace when they attach a domain (the
  product's README, "Custom domain", which also moves `BASE_URL` — where
  Stripe returns the browser — onto it). Pass it only for a product that
  already has its domain.

- `subdomain` — the workers.dev subdomain of the Cloudflare account you
  deploy into. It is in every URL the phases probe and in the `BASE_URL`
  Stripe returns to. A console or `--from bst_…` build reads it from the
  Cloudflare connection; pass it only for a hand-run build.
- `orunWorkspace` — workspace id (`ws_…`). Unset, it is the workspace the
  build runs in (`from: workspace`); with none anywhere, a placeholder that
  fails loudly rather than silently claiming another tenant's workspace.
- `epicSlug` (default `saas-baselining`) — the epic every phase clubs its
  task under. Found by slug, so a fresh run and a resumed run find the same
  work.
- `repoPrivate` (default `true`) — the repository's visibility at creation.

```bash
orun new --blueprint repo-blueprint.yaml \
  --out $HOME/products/acme-saas --run-hooks --phase 01-product \
  --values ~/acme-saas.values.yaml
```

Drop `--run-hooks` (or add `--status`) to preview. Without it a phase places
files and stops: no repo, no landing, no convergence watch, and no probe —
which is exactly what makes a dry instantiation of this baseline possible in
CI with no workspace and no provider (`testing/placement.test.sh`,
`testing/e2e.test.sh`).

## Stripe and email are not phases

Stripe and Resend are third parties the platform does not broker, so nothing
here mints, asks for or waits on their keys. The product deploys, signs users
up and renders the account dashboard without them; the billing page says
Stripe is not connected and no email is sent. The owner stores
`STRIPE_API_KEY` (and Resend's `RESEND_API_KEY`, `ADMIN_EMAIL`,
`FROM_ADMIN_EMAIL`) as orun secrets afterwards and redeploys (the product's
README, "Stripe", "Email"), and re-running `02-docs` records it.

## When a phase fails

- **Before it lands** (a probe that timed out, a rebrand residue, a refused
  link): nothing was merged. Fix what the message names and re-run the phase.
- **After it lands** (the convergence went red): the files are on main.
  `orun.run/watch@v1` has already resumed the run up to three times. Re-run
  the phase (`--phase 01-product`, `--redo 01-product` under `--resume`, or
  the console's Retry): its `retouch` hook gives the landing a diff and the
  components it names re-plan. The Supabase project is adopted rather
  than recreated (`adopt.tf`), and the migration ledger lives in the
  database, so a re-run applies only what is missing.

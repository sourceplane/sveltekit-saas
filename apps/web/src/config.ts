import { PUBLIC_SITE_URL } from "$env/static/public"

export const WebsiteName: string = "SaaS Starter"
// The site's public origin: the environment's SITE_URL, or its workers.dev
// URL, handed to the build by the deploy (apps/web/component.yaml). A local
// build has none and names the dev server.
export const WebsiteBaseUrl: string = (
  PUBLIC_SITE_URL || "http://localhost:5173"
).replace(/\/+$/, "")
export const WebsiteDescription: string =
  "Open source, fast, and free to host SaaS template. Built with SvelteKit, Supabase, Stripe, Tailwind, DaisyUI, and Postgres"
export const CreateProfileStep: boolean = true

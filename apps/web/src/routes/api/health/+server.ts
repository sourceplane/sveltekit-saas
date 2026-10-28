// GET /api/health — what this environment's Worker is connected to.
//
// Only the Worker answers it, and only by reaching its Supabase project with
// the service-role key: it counts the `profiles` table (a HEAD request, no
// rows read), so `ok: true` says the project's URL and key reached the
// Worker, the migrations ran, and the Worker is serving. Stripe and email are
// optional, so they are reported, never required. The deploy's smoke reads
// it (apps/web/component.yaml).
import { json } from "@sveltejs/kit"
import { env } from "$env/dynamic/private"
import { stripeConnected } from "$lib/server/stripe"
import type { RequestHandler } from "./$types"

export const GET: RequestHandler = async ({
  locals: { supabaseServiceRole },
}) => {
  let database: string
  try {
    const { error } = await supabaseServiceRole
      .from("profiles")
      .select("id", { count: "exact", head: true })
    database = error ? `error: ${error.message || error.code}` : "ok"
  } catch (e) {
    database = `error: ${e instanceof Error ? e.message : String(e)}`
  }
  const body = {
    ok: database === "ok",
    database,
    stripe: stripeConnected(),
    email: !!env.PRIVATE_RESEND_API_KEY && !!env.PRIVATE_ADMIN_EMAIL,
  }
  return json(body, {
    status: body.ok ? 200 : 503,
    headers: { "cache-control": "no-store" },
  })
}

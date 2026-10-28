import { describe, it, expect, vi, beforeEach } from "vitest"

vi.mock("$env/dynamic/private", () => ({ env: {} as Record<string, string> }))

import { env } from "$env/dynamic/private"
import { GET } from "./+server"

const event = (
  result: { error: { message?: string; code?: string } | null } | Error,
) => {
  const select = vi.fn(() =>
    result instanceof Error ? Promise.reject(result) : Promise.resolve(result),
  )
  return {
    locals: { supabaseServiceRole: { from: vi.fn(() => ({ select })) } },
    select,
  }
}

describe("GET /api/health", () => {
  beforeEach(() => {
    for (const k of Object.keys(env)) delete (env as Record<string, string>)[k]
  })

  it("is ok when the project's profiles table answers the service-role key", async () => {
    const e = event({ error: null })
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const res = await GET(e as any)
    expect(res.status).toBe(200)
    expect(await res.json()).toEqual({
      ok: true,
      database: "ok",
      stripe: false,
      email: false,
    })
    expect(e.select).toHaveBeenCalledWith("id", { count: "exact", head: true })
  })

  it("reports Stripe and email once both are set", async () => {
    Object.assign(env, {
      PRIVATE_STRIPE_API_KEY: "sk_test_x",
      PRIVATE_RESEND_API_KEY: "re_x",
      PRIVATE_ADMIN_EMAIL: "admin@example.com",
    })
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const res = await GET(event({ error: null }) as any)
    expect(await res.json()).toMatchObject({
      ok: true,
      stripe: true,
      email: true,
    })
  })

  it("is 503 when the table is missing (the migrations did not run)", async () => {
    const res = await GET(
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      event({
        error: { message: 'relation "public.profiles" does not exist' },
      }) as any,
    )
    expect(res.status).toBe(503)
    expect(await res.json()).toMatchObject({
      ok: false,
      database: expect.stringContaining("does not exist"),
    })
  })

  it("is 503 when the service-role key never reached the Worker", async () => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const res = await GET(
      event(new Error("PRIVATE_SUPABASE_SERVICE_ROLE is not set")) as any,
    )
    expect(res.status).toBe(503)
    expect(await res.json()).toMatchObject({
      ok: false,
      database: expect.stringContaining("not set"),
    })
  })
})

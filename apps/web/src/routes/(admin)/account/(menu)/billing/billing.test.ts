import { describe, it, expect, vi } from "vitest"

vi.mock("$env/dynamic/private", () => ({ env: {} as Record<string, string> }))

import { load } from "./+page.server"

describe("the billing page without Stripe", () => {
  it("puts everyone on the free plan and asks for no Stripe call", async () => {
    const supabaseServiceRole = { from: vi.fn() }
    const data = await load({
      locals: {
        safeGetSession: async () => ({
          session: { user: { id: "u1" } },
          user: { id: "u1", email: "a@example.com" },
        }),
        supabaseServiceRole,
      },
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
    } as any)
    expect(data).toEqual({
      stripeConnected: false,
      isActiveCustomer: false,
      hasEverHadSubscription: false,
      currentPlanId: undefined,
    })
    expect(supabaseServiceRole.from).not.toHaveBeenCalled()
  })
})

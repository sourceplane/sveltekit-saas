import { describe, it, expect, vi, beforeEach } from "vitest"

vi.mock("$env/dynamic/private", () => ({ env: {} as Record<string, string> }))

import { env } from "$env/dynamic/private"
import { getStripe, stripeConnected } from "./stripe"

describe("stripe", () => {
  beforeEach(() => {
    delete (env as Record<string, string>).PRIVATE_STRIPE_API_KEY
  })

  it("is not connected until the key is set, and says how to connect it", () => {
    expect(stripeConnected()).toBe(false)
    expect(() => getStripe()).toThrow(/STRIPE_API_KEY/)
  })

  it("talks over fetch once the key is set — Workers have no Node http", () => {
    ;(env as Record<string, string>).PRIVATE_STRIPE_API_KEY = "sk_test_x"
    expect(stripeConnected()).toBe(true)
    const stripe = getStripe()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const client =
      (stripe as any)._api?.httpClient ??
      (stripe as any).getApiField?.("httpClient")
    expect(client?.getClientName?.()).toBe("fetch")
  })
})

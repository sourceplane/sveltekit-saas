// Stripe, connected or not.
//
// The Stripe secret key is an OPTIONAL Orun secret (STRIPE_API_KEY), which the
// deploy lane hands the Worker as the secret PRIVATE_STRIPE_API_KEY. It is read
// at request time ($env/dynamic/private), never inlined into a bundle. A
// product goes live before its owner has a Stripe account: until the key is
// set, the billing page says to connect Stripe and the checkout and portal
// routes send the visitor there.
//
// Workers have no Node `http`: Stripe talks over `fetch`.
import { env } from "$env/dynamic/private"
import Stripe from "stripe"

export const stripeConnected = (): boolean => !!env.PRIVATE_STRIPE_API_KEY

export const getStripe = (): Stripe => {
  const key = env.PRIVATE_STRIPE_API_KEY
  if (!key) {
    throw new Error(
      "Stripe is not connected: store the product's Stripe secret key as the Orun secret STRIPE_API_KEY and redeploy",
    )
  }
  return new Stripe(key, {
    apiVersion: "2023-08-16",
    httpClient: Stripe.createFetchHttpClient(),
  })
}

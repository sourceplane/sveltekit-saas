import { error, redirect } from "@sveltejs/kit"
import { getStripe, stripeConnected } from "$lib/server/stripe"
import { getOrCreateCustomerId } from "../../../subscription_helpers.server"
import type { PageServerLoad } from "./$types"

export const load: PageServerLoad = async ({
  url,
  locals: { safeGetSession, supabaseServiceRole },
}) => {
  const { session, user } = await safeGetSession()
  if (!session) {
    redirect(303, "/login")
  }

  // No Stripe yet: the billing page says how to connect it.
  if (!stripeConnected()) {
    redirect(303, "/account/billing")
  }

  const { error: idError, customerId } = await getOrCreateCustomerId({
    supabaseServiceRole,
    user,
  })
  if (idError || !customerId) {
    console.error("Error creating customer id", idError)
    error(500, {
      message: "Unknown error (PCID). If issue persists, please contact us.",
    })
  }

  let portalLink
  try {
    const portalSession = await getStripe().billingPortal.sessions.create({
      customer: customerId,
      return_url: `${url.origin}/account/billing`,
    })
    portalLink = portalSession?.url
  } catch (e) {
    console.error("Error creating billing portal session", e)
    error(500, "Unknown error (PSE). If issue persists, please contact us.")
  }

  redirect(303, portalLink ?? "/account/billing")
}

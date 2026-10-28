import { error, redirect } from "@sveltejs/kit"
import {
  fetchSubscription,
  getOrCreateCustomerId,
} from "../../subscription_helpers.server"
import { stripeConnected } from "$lib/server/stripe"
import type { PageServerLoad } from "./$types"

export const load: PageServerLoad = async ({
  locals: { safeGetSession, supabaseServiceRole },
}) => {
  const { session, user } = await safeGetSession()
  if (!session || !user?.id) {
    redirect(303, "/login")
  }

  // No Stripe yet: every visitor is on the free plan, and the page says how
  // to connect Stripe.
  if (!stripeConnected()) {
    return {
      stripeConnected: false,
      isActiveCustomer: false,
      hasEverHadSubscription: false,
      currentPlanId: undefined,
    }
  }

  const { error: idError, customerId } = await getOrCreateCustomerId({
    supabaseServiceRole,
    user,
  })
  if (idError || !customerId) {
    console.error("Error creating customer id", idError)
    error(500, {
      message: "Unknown error. If issue persists, please contact us.",
    })
  }

  const {
    primarySubscription,
    hasEverHadSubscription,
    error: fetchErr,
  } = await fetchSubscription({
    customerId,
  })
  if (fetchErr) {
    console.error("Error fetching subscription", fetchErr)
    error(500, {
      message: "Unknown error. If issue persists, please contact us.",
    })
  }

  return {
    stripeConnected: true,
    isActiveCustomer: !!primarySubscription,
    hasEverHadSubscription,
    currentPlanId: primarySubscription?.appSubscription?.id,
  }
}

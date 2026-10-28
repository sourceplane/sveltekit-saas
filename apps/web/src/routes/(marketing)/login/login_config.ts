import { ThemeSupa } from "@supabase/auth-ui-shared"
import type { Provider } from "@supabase/supabase-js"

// OAuth sign-in, beside email and password. Each provider must be turned on in
// the environment's Supabase project first (Authentication → Providers, with
// the provider's OAuth app), or its button fails: so a product starts with
// none. Add "github" here once GitHub is set up (README, "OAuth providers").
export const oauthProviders = [] as Provider[]

// use the css variables from DaisyUI to style Supabase auth template
export const sharedAppearance = {
  theme: ThemeSupa,
  variables: {
    default: {
      colors: {
        brand: "oklch(var(--p))",
        brandAccent: "oklch(var(--ac))",
        inputText: "oklch(var(--n))",
        brandButtonText: "oklch(var(--pc))",
        messageText: "oklch(var(--b))",
        dividerBackground: "oklch(var(--n))",
        inputLabelText: "oklch(var(--n))",
        defaultButtonText: "oklch(var(--n))",
        anchorTextColor: "oklch(var(--p))",
      },
      fontSizes: {
        baseInputSize: "16px",
      },
    },
  },
  className: {
    button: "authBtn",
  },
}

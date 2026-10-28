import { defineConfig } from "vitest/config";

// The port's own checks on the app's configuration, in Node. The app's unit
// tests — upstream's and the port's — run in the app's own Vite config
// (`pnpm --dir ../../apps/web run test:unit`), where SvelteKit resolves $lib
// and $env.
export default defineConfig({
  test: {
    include: ["src/**/*.test.ts"],
    environment: "node",
  },
});
